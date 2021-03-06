#MOI attribute for optimizers to signal how to solve an optigraph
struct OptiGraphOptimizeHook <: MOI.AbstractModelAttribute end

#Get backends
JuMP.backend(graph::OptiGraph) = graph.optimizer
JuMP.backend(node::OptiNode) = JuMP.backend(jump_model(node))
JuMP.backend(edge::OptiEdge) = edge.backend
JuMP.moi_mode(node_optimizer::NodeBackend) = JuMP.moi_mode(node_optimizer.optimizer)

#Extend OptiNode and OptiGraph with MOI interface
MOI.get(node::OptiNode, args...) = MOI.get(jump_model(node), args...)
MOI.set(node::OptiNode, args...) = MOI.set(jump_model(node), args...)
MOI.get(graph::OptiGraph,args...) = MOI.get(JuMP.backend(graph),args...)

#Create an moi backend for an optigraph by aggregating MOI backends of underlying optinodes and optiedges
function _aggregate_backends!(graph::OptiGraph)
    dest = JuMP.backend(graph)
    id = graph.id

    #Set node backends
    for node in all_nodes(graph)
        src = JuMP.backend(node)
        idx_map = append_to_backend!(dest, src, false; filter_constraints=nothing)
        node_pointer = NodePointer(dest,idx_map)
        src.optimizers[id] = node_pointer
        if !(id in src.graph_ids)
            push!(src.graph_ids,id)
        end
    end

    #Set edge backends
    for edge in all_edges(graph)
        edge_pointer = EdgePointer(dest)
        edge.backend.result_location[id] = edge_pointer
        edge.backend.optimizers[id] = edge_pointer
    end
    for linkref in all_linkconstraints(graph)
        constraint_index = _add_link_constraint!(id,dest,JuMP.constraint_object(linkref))
        linkref.optiedge.backend.result_location[id].edge_to_optimizer_map[linkref] = constraint_index
    end

    return nothing
end

#Set the optigraph objective to the sume of the nodes
function _set_graph_objective(graph::OptiGraph)
    if !has_objective(graph) && has_node_objective(graph)
        nodes = all_nodes(graph)
        for node in nodes
            if JuMP.objective_sense(node) == MOI.MAX_SENSE
                JuMP.set_objective_sense(node,MOI.MIN_SENSE)
                JuMP.set_objective_function(node,-1*JuMP.objective_function(node))
            end
        end
        JuMP.set_objective(graph,MOI.MIN_SENSE,sum(objective_function(nodes[i]) for i = 1:length(nodes)))
    end
    return nothing
end

#NOTE: Must hit _aggregate_backends!() first
#Set the backend objective to the graph objective
function _set_backend_objective(graph::OptiGraph)
    obj = objective_function(graph)
    _set_backend_objective(graph,obj)
    return nothing
end

function _set_backend_objective(graph::OptiGraph,obj::JuMP.GenericAffExpr{Float64,VariableRef})
    graph_backend = JuMP.backend(graph)
    moi_obj = moi_function(obj)
    for (i,terms) in enumerate(linear_terms(obj))
        term = terms[2]
        moi_term = index(term)
        node = getnode(term)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx = node_idx_map[moi_term]
        moi_obj = _swap_linear_term!(moi_obj,i,new_moi_idx)
    end
    MOI.set(graph_backend,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    MOI.set(graph_backend,MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),moi_obj)
    return nothing
end

function _set_backend_objective(graph::OptiGraph,obj::JuMP.GenericQuadExpr{Float64,VariableRef})
    graph_backend = JuMP.backend(graph)
    moi_obj = moi_function(obj)
    for (i,terms) in enumerate(quad_terms(obj))
        term1 = terms[2]
        term2 = terms[3]
        node = getnode(term1)
        @assert getnode(term1) == getnode(term2)
        moi_term1 = index(term1)
        moi_term2 = index(term2)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx_1 = node_idx_map[moi_term1]
        new_moi_idx_2 = node_idx_map[moi_term2]
        moi_obj = _swap_quad_term!(moi_obj,i,new_moi_idx_1,new_moi_idx_2)
    end

    for (i,terms) in enumerate(linear_terms(obj))
        term = terms[2]
        moi_term = index(term)
        node = getnode(term)
        node_idx_map = backend(node).optimizers[graph.id].node_to_optimizer_map
        new_moi_idx = node_idx_map[moi_term]
        moi_obj = _swap_linear_term!(moi_obj,i,new_moi_idx)
    end

    MOI.set(graph_backend,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    MOI.set(graph_backend,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),moi_obj)
    return nothing
end

function _swap_linear_term!(moi_obj::MOI.ScalarAffineFunction,idx::Int64,new_moi_idx::MOI.VariableIndex)
    term = moi_obj.terms[idx]
    coeff = term.coefficient
    moi_obj.terms[idx] = MOI.ScalarAffineTerm{Float64}(coeff,new_moi_idx)
    return moi_obj
end

function _swap_linear_term!(moi_obj::MOI.ScalarQuadraticFunction,idx::Int64,new_moi_idx::MOI.VariableIndex)
    term = moi_obj.affine_terms[idx]
    coeff = term.coefficient
    moi_obj.affine_terms[idx] = MOI.ScalarAffineTerm{Float64}(coeff,new_moi_idx)
    return moi_obj
end

function _swap_quad_term!(moi_obj::MOI.ScalarQuadraticFunction,idx::Int64,new_moi_idx1::MOI.VariableIndex,new_moi_idx2::MOI.VariableIndex)
    term = moi_obj.quadratic_terms[idx]
    coeff = term.coefficient
    var_idx1 = term.variable_index_1
    var_idx2 = term.variable_index_2
    moi_obj.quadratic_terms[idx] = MOI.ScalarQuadraticTerm{Float64}(coeff,new_moi_idx1,new_moi_idx2)
    return moi_obj
end

#Add a LinkConstraint to the MOI backend.  This is used as part of _aggregate_backends!
function _add_link_constraint!(id::Symbol,dest::MOI.ModelLike,link::LinkConstraint)
    jump_func = JuMP.jump_function(link)
    moi_func = JuMP.moi_function(link)
    for (i,term) in enumerate(JuMP.linear_terms(jump_func))
        coeff = term[1]
        var = term[2]

        src = JuMP.backend(getnode(var))
        idx_map = src.optimizers[id].node_to_optimizer_map

        var_idx = JuMP.index(var)
        dest_idx = idx_map[var_idx]

        moi_func.terms[i] = MOI.ScalarAffineTerm{Float64}(coeff,dest_idx)
    end
    moi_set = JuMP.moi_set(link)

    constraint_index = MOI.add_constraint(dest,moi_func,moi_set)

    return constraint_index
end

function _set_node_results!(graph::OptiGraph)
    graph_backend = JuMP.backend(graph)
    id = graph.id

    nodes = all_nodes(graph)
    srces = JuMP.backend.(nodes)
    for src in srces
        src.last_solution_id = graph.id
        src.result_location[id] = src.optimizers[id]
    end

    #edges (links)
    #edges also point to Graph MOI model
    for linkref in all_linkconstraints(graph)
        edge = JuMP.owner_model(linkref)
        JuMP.backend(edge).last_solution_id = graph.id
        edge.backend.result_location[id] = edge.backend.optimizers[id]
    end

    #Set NLP dual solution for node
    #Nonlinear duals #TODO: multiple node solutions with nlp duals
    if MOI.NLPBlock() in MOI.get(graph_backend,MOI.ListOfModelAttributesSet())
        nlp_duals = MOI.get(graph_backend,MOI.NLPBlockDual())
        for node in nodes
            if node.nlp_data != nothing
                src = JuMP.backend(node)
                nl_idx_map = src.result_location[id].nl_node_to_optimizer_map #JuMP.backend(node).nl_idx_maps[id]
                nl_duals = node.nlp_duals[id]
                #node.nlp_data.nlconstr_duals = Vector{Float64}(undef,length(node.nlp_data.nlconstr))
                for (src_index,graph_index) in nl_idx_map
                    nl_duals[src_index.value] = nlp_duals[graph_index.value] # node.nlp_data.nlconstr_duals[src_index.value] = nlp_duals[graph_index.value]
                end
            end
        end
    end
    return nothing
end

JuMP.optimize!(graph::OptiGraph,optimizer;kwargs...) = error("The optimizer keyword argument is no longer supported. Use `set_optimizer` first, and then `optimize!`.")

#################################
# Optimizer
#################################
"""
    JuMP.set_optimizer(graph::OptiGraph,optimizer_constructor::Any)

Set an MOI optimizer for the optigraph `graph`.
"""
function JuMP.set_optimizer(graph::OptiGraph, optimizer_constructor, bridge_constraints::Bool = true)
    backend = JuMP.backend(graph)
    if bridge_constraints
        optimizer = MOI.instantiate(optimizer_constructor, with_bridge_type=Float64, with_names=false)
        for bridge_type in graph.bridge_types
            JuMP._moi_add_bridge(optimizer, bridge_type)
        end
    else
        optimizer = MOI.instantiate(optimizer_constructor)
    end
    MOIU.reset_optimizer(backend,optimizer)
    return nothing
end

#Set an optigraph optimizer
#TODO: drop this into a caching optimizer so we can pass attributes into it as needed
# JuMP.set_optimizer(graph::OptiGraph, optimizer::OptiGraphOptimizer) = graph.optimizer=optimizer

function JuMP.optimize!(graph::OptiGraph;kwargs...)
    graph_optimizer = JuMP.backend(graph)
    #NOTE: I think this will always be a MOIU.CachingOptimizer
    if isa(graph_optimizer,MOIU.CachingOptimizer)
        if MOIU.state(graph_optimizer) == MOIU.NO_OPTIMIZER
            error("Please set an optimizer on optigraph before calling `optimize!` using `set_optimizer(graph,optimizer)`")
        end
    end

    #check for optigraph optimize hook
    try
        #We have to attach the optimizer to query attributes
        if !(MOIU.state(graph_optimizer) == MOIU.ATTACHED_OPTIMIZER)
            MOIU.attach_optimizer(backend(graph))
        end
        optimize_func = MOI.get(graph_optimizer,MOIU.AttributeFromOptimizer(OptiGraphOptimizeHook()))
        #TODO: Better checking for the model
        optimize_func(graph,graph_optimizer.optimizer.model)
    catch err
        if !(typeof(err) in [KeyError,ArgumentError])
            rethrow(err)
        else  #otherwise, aggregate and solve with the MOI interface
            _moi_optimize!(graph)
        end
    end
    return nothing
end

#optimize with MOI interfaced optimizer
function _moi_optimize!(graph::OptiGraph)
    #Build the MOI backend if it hasn't already been created
    if MOI.get(JuMP.backend(graph), MOI.TerminationStatus())==MOI.OPTIMIZE_NOT_CALLED
        _aggregate_backends!(graph) #else, changes SHOULD have been captured
    end

    #set the optigraph objective if it is:
    #1) not nonlinear and
    #2) there are node objectives
    has_nl_obj = has_nl_objective(graph)
    if !(has_nl_obj)
        _set_graph_objective(graph)
    end

    #NLP data
    if has_nlp_data(graph)
        MOI.set(graph.optimizer, MOI.NLPBlock(), _create_nlp_block_data(graph))
    end

    if has_nl_obj #set default sense to minimize if there is a nonlinear objective function
        MOI.set(graph.optimizer,MOI.ObjectiveSense(),MOI.MIN_SENSE)
    else
        _set_backend_objective(graph) #sets linear or quadratic objective
    end

    try
        MOI.optimize!(graph.optimizer)
    catch err
        if err isa MOI.UnsupportedAttribute{MOI.NLPBlock}
            error("The solver does not support nonlinear problems " *
                  "(i.e., @NLobjective and @NLconstraint).")
        else
            rethrow(err)
        end
    end
    _set_node_results!(graph)     #populate optimizer solutions onto each node backend
end

function _create_nlp_block_data(graph::OptiGraph)
    @assert has_nlp_data(graph)
    id = graph.id

    bounds = MOI.NLPBoundsPair[]
    has_nl_obj = false
    for node in all_nodes(graph)
        if node.model.nlp_data !== nothing
            src = JuMP.backend(node)
            nl_idx_map = src.optimizers[id].nl_node_to_optimizer_map
            for (i,constr) in enumerate(node.model.nlp_data.nlconstr)
                push!(bounds, MOI.NLPBoundsPair(constr.lb, constr.ub))
                nl_idx_map[JuMP.NonlinearConstraintIndex(i)] = JuMP.NonlinearConstraintIndex(length(bounds))
            end
            if !has_nl_obj && isa(node.model.nlp_data.nlobj, JuMP._NonlinearExprData)
                has_nl_obj = true
            end
        end
    end
    return MOI.NLPBlockData(bounds,OptiGraphNLPEvaluator(graph),has_nl_obj)
end

#######################################################
#OptiGraph Optimizer Attributes
#######################################################
function JuMP.set_optimizer_attribute(graph::OptiGraph, name::String, value)
    return JuMP.set_optimizer_attribute(graph, MOI.RawParameter(name), value)
end

function JuMP.set_optimizer_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute,
    value)
    return MOI.set(graph, attr, value)
end

function JuMP.get_optimizer_attribute(graph::OptiGraph, name::String)
    return JuMP.get_optimizer_attribute(graph, MOI.RawParameter(name))
end

function JuMP.get_optimizer_attribute(
    graph::OptiGraph,
    attr::MOI.AbstractOptimizerAttribute)
    return MOI.get(graph, attr)
end

function MOI.get(graph::OptiGraph, attr::MOI.AbstractOptimizerAttribute)
    return MOI.get(backend(graph), attr)
end

function MOI.get(graph::OptiGraph, attr::MOI.AbstractModelAttribute)
    return MOI.get(backend(graph), attr)
end

function MOI.set(graph::OptiGraph, attr::MOI.AbstractOptimizerAttribute, value)
    return MOI.set(backend(graph), attr, value)
end

function MOI.set(graph::OptiGraph, attr::MOI.AbstractModelAttribute, value)
    return MOI.set(backend(graph), attr, value)
end
#######################################################
#Optinode optimizer interface
#######################################################
#OptiNode optimizer.  Hits MOI.optimize!(backend(node))
function JuMP.set_optimizer(node::OptiNode,optimizer_constructor)
    JuMP.set_optimizer(jump_model(node),optimizer_constructor)
    JuMP.backend(node).last_solution_id = node.id
    JuMP.backend(node).result_location[node.id] = JuMP.backend(node).optimizer
    return nothing
end

function JuMP.optimize!(node::OptiNode;kwargs...)
    JuMP.optimize!(jump_model(node);kwargs...)
    return nothing
end

function set_node_primals(node::OptiNode,vars::Vector{JuMP.VariableRef},values::Vector{Float64})
    node_backend = JuMP.backend(node)
    moi_indices = index.(vars)
    set_backend_primals!(node_backend,moi_indices,values,node.id)
    return nothing
end

function set_node_duals(node::OptiNode,cons::Vector{JuMP.ConstraintRef},values::Vector{Float64})
    node_backend = JuMP.backend(node)
    moi_indices = index.(cons)
    set_backend_duals!(node_backend,moi_indices,values,node.id)
    return nothing
end

function set_node_status(node::OptiNode,status::MOI.TerminationStatusCode)
    node_backend = JuMP.backend(node)
    set_backend_status!(node_backend,status,node.id)
end

# caching_mode = MOIU.AUTOMATIC
# universal_fallback = MOIU.UniversalFallback(MOIU.Model{Float64}())
# backend = MOIU.CachingOptimizer(universal_fallback,caching_mode)
