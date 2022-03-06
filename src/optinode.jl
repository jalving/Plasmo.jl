##############################################################################
# OptiNode
##############################################################################
"""
    OptiNode()

Creates an empty OptiNode.  Does not add it to an optigraph.
"""
mutable struct OptiNode <: JuMP.AbstractModel
    model::JuMP.AbstractModel
    label::String                                               #what gets printed
    partial_linkconstraints::Dict{Int64,AbstractLinkConstraint} #node contribution to link constraint

    #nlp_data is a reference to `model.nlp_data`
    nlp_data::Union{Nothing,JuMP._NLPData}
    nlp_duals::DefaultDict{Symbol,OrderedDict{Int64,Float64}}

    #Extension data
    ext::Dict{Symbol,Any}

    id::Symbol

    function OptiNode()
        model = JuMP.Model()
        id = gensym()
        node_backend = NodeBackend(JuMP.backend(model),id)
        model.moi_backend = node_backend
        node = new(model,
        "node",
        Dict{Int64,AbstractLinkConstraint}(),
        nothing,
        DefaultDict{Symbol,OrderedDict{Int64,Float64}}(OrderedDict()),
        Dict{Symbol,Any}(),
        id)
        node.model.ext[:optinode] = node
        return node
    end
end

#############################################
# OptiNode Management
############################################
"""
    jump_model(node::OptiNode)

Get the underlying `JuMP.Model` from the optinode `node`.
"""
jump_model(node::OptiNode) = node.model
@deprecate getmodel jump_model

"""
    setlabel(node::OptiNode, label::Symbol)

Set the label for optinode `node` to `label`. This is what gets printed.
"""
set_label(node::OptiNode,label::String) = node.label = label
label(node::OptiNode) = node.label

"""
    JuMP.all_variables(node::OptiNode)::Vector{JuMP.VariableRef}

Retrieve all of the variables on the optinode `node`.
"""
JuMP.all_variables(node::OptiNode) = JuMP.all_variables(jump_model(node))

"""
    JuMP.value(node::OptiNode, vref::VariableRef)

Get the variable value of `vref` on the optinode `node`.
"""
JuMP.value(node::OptiNode, vref::VariableRef) =
    MOI.get(
    JuMP.backend(node).result_location[node.id],
    MOI.VariablePrimal(),
    JuMP.index(vref)
    )

"""
    JuMP.dual(c::JuMP.ConstraintRef{OptiNode,NonlinearConstraintIndex})

Get the dual value on a nonlinear constraint that is part of an optinode
"""
function JuMP.dual(c::JuMP.ConstraintRef{OptiNode,NonlinearConstraintIndex})
    node = c.model
    node_backend = JuMP.backend(node)
    return node.nlp_duals[node_backend.last_solution_id][c.index.value]
end

"""
    is_node_variable(node::OptiNode, var::JuMP.AbstractVariableRef)

Checks whether the variable `var` belongs to the optinode `node`.
"""
is_node_variable(node::OptiNode, var::JuMP.AbstractVariableRef) = jump_model(node)==var.model
is_node_variable(var::JuMP.AbstractVariableRef) = haskey(var.model.ext,:optinode)

"""
    is_set_to_node(m::JuMP.AbstractModel)

Checks whether the model `m` is set to an optinode
"""
function is_set_to_node(m::JuMP.AbstractModel)
    if haskey(m.ext,:optinode)
        return isa(m.ext[:optinode],OptiNode)
    else
        return false
    end
end

"""
    set_model(node::OptiNode, m::AbstractModel)

Set the model on a node.  This will delete any link-constraints the node is currently part of
"""
function set_model(node::OptiNode,m::JuMP.AbstractModel;preserve_links = false)
    !(is_set_to_node(m) && jump_model(node) == m) || error("Model $m is already asigned to another node")
    node.model = m
    m.ext[:optinode] = node
    node_backend = NodeBackend(JuMP.backend(m),node.id)
    m.moi_backend = node_backend
end
@deprecate setmodel set_model

#############################################
# JuMP Extension Functions
############################################
"""
    Base.getindex(node::OptiNode, symbol::Symbol)

Support retrieving node attributes via symbol lookup. (e.g. node[:x])
"""
Base.getindex(node::OptiNode, symbol::Symbol) = jump_model(node)[symbol]

"""
    Base.setindex(node::OptiNode, value::Any, symbol::Symbol)

Support retrieving node attributes via symbol lookup. (e.g. node[:x])
"""
Base.setindex!(node::OptiNode,
    value::Any,
    symbol::Symbol) = JuMP.object_dictionary(node)[symbol] = value

"""
    JuMP.object_dictionary(node::OptiNode)

Get the underlying object dictionary of optinode `node`
"""
JuMP.object_dictionary(node::OptiNode) = JuMP.object_dictionary(jump_model(node))

"""
    JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, name::String="")

Add variable `v` to optinode `node`. This function supports use of the `@variable` JuMP macro.
Optionally add a `base_name` to the variable for printing.
"""
function JuMP.add_variable(node::OptiNode, v::JuMP.AbstractVariable, base_name::String="")
    jump_vref = JuMP.add_variable(node.model,v,base_name)
    JuMP.set_name(jump_vref, "$(node.label)[:$(JuMP.name(jump_vref))]")
    return jump_vref
end

"""
    JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")

Add a constraint `con` to optinode `node`. This function supports use of the @constraint JuMP macro.
"""
function JuMP.add_constraint(node::OptiNode, con::JuMP.AbstractConstraint, base_name::String="")
    cref = JuMP.add_constraint(jump_model(node),con,base_name)
    return cref
end

"""
    JuMP.add_NL_constraint(node::OptiNode,expr::Expr)

Add a non-linear constraint to an optinode using a Julia expression.
"""
function JuMP.add_NL_constraint(node::OptiNode,expr::Expr)
    con = JuMP.add_NL_constraint(jump_model(node),expr)
    #re-sync NLP data
    #TODO: think about less hacky nlp_data
    node.nlp_data = node.model.nlp_data
    return con
end

function JuMP.num_constraints(node::OptiNode)
    m = jump_model(node)
    num_cons = 0
    for (func,set) in JuMP.list_of_constraint_types(m)
        if func != JuMP.VariableRef
            num_cons += JuMP.num_constraints(m,func,set)
        end
    end
    num_cons += JuMP.num_nl_constraints(m)
    return num_cons
end

JuMP.num_nl_constraints(node::OptiNode) = JuMP.num_nl_constraints(node.model)

"""
    num_linked_variables(node::OptiNode)

Return the number of node variables on `node` that are linked to other nodes
"""
function num_linked_variables(node::OptiNode)
    partial_link_cons = node.partial_linkconstraints
    num_linked = 0
    vars = []
    for (idx,link) in partial_link_cons
        for var in keys(link.func.terms)
            if !(var in vars)
                push!(vars,var)
                num_linked += 1
            end
        end
    end
    return num_linked
end

"""
    num_link_constraints(node::OptiNode)

Return the number of link-constraints that `node` belongs to
"""
function num_link_constraints(node::OptiNode)
    return length(node.partial_linkconstraints)
end

"""
    has_objective(node::OptiNode)

Check whether optinode `node` has a non-empty objective function
"""
has_objective(node::OptiNode) =
    objective_function(node) != zero(JuMP.AffExpr) &&
    objective_function(node) != zero(JuMP.QuadExpr)

"""
    has_nl_objective(node::OptiNode)

Check whether optinode `node` has a nonlinear objective function
"""
function has_nl_objective(node::OptiNode)
    if node.nlp_data != nothing
        if node.nlp_data.nlobj != nothing
            return true
        end
    end
    return false
end

#TODO: one macro to hit all these extensions
JuMP.objective_function(node::OptiNode) = JuMP.objective_function(jump_model(node))
JuMP.objective_value(node::OptiNode) = JuMP.objective_value(jump_model(node))
JuMP.objective_sense(node::OptiNode) = JuMP.objective_sense(jump_model(node))
JuMP.num_variables(node::OptiNode) = JuMP.num_variables(jump_model(node))
JuMP.NLPEvaluator(node::OptiNode) = JuMP.NLPEvaluator(jump_model(node))
JuMP.set_objective(optinode::OptiNode, sense::MOI.OptimizationSense, func::JuMP.AbstractJuMPScalar) = JuMP.set_objective(jump_model(optinode),sense,func)
JuMP.set_NL_objective(optinode::OptiNode,sense::MOI.OptimizationSense,obj::Any) = JuMP.set_NL_objective(optinode.model,sense,obj)
JuMP.set_objective_function(optinode::OptiNode,func::JuMP.AbstractJuMPScalar) = JuMP.set_objective_function(optinode.model,func)
JuMP.set_objective_function(optinode::OptiNode,real::Real) = JuMP.set_objective_function(optinode.model,real)
JuMP.set_objective_sense(optinode::OptiNode,sense::MOI.OptimizationSense) = JuMP.set_objective_sense(optinode.model,sense)
JuMP.termination_status(node::OptiNode) = JuMP.termination_status(jump_model(node))
JuMP.raw_status(node::OptiNode) = JuMP.raw_status(jump_model(node))
JuMP.primal_status(node::OptiNode) = JuMP.primal_status(jump_model(node))
JuMP.dual_status(node::OptiNode) = JuMP.dual_status(jump_model(node))
JuMP.solver_name(node::OptiNode) = JuMP.solver_name(jump_model(node))
JuMP.mode(node::OptiNode) = JuMP.mode(jump_model(node))
JuMP._moi_mode(node_backend::NodeBackend) = node_backend.optimizer.mode
JuMP.list_of_constraint_types(node::OptiNode) = JuMP.list_of_constraint_types(jump_model(node))
JuMP.all_constraints(node::OptiNode,F::DataType,S::DataType) = JuMP.all_constraints(jump_model(node),F,S)

##############################################
# Get OptiNode
##############################################
getnode(m::JuMP.Model) = m.ext[:optinode]

#Get the corresponding node for a JuMP variable reference
function getnode(var::JuMP.VariableRef)
    if haskey(var.model.ext,:optinode)
        return getnode(var.model)
    else
        error("variable $var does not belong to a optinode.  If you're trying to create a linkconstraint, make sure
        the owning model has been set to a node.")
    end
end

function getnode(con::JuMP.ConstraintRef)
    if haskey(con.model.ext,:optinode)
        return getnode(con.model)
    else
        error("constraint $con does not belong to a node")
    end
end
getnode(m::AbstractModel) = is_set_to_node(m) ? m.ext[:optinode] : throw(error("Only node models have associated graph nodes"))
getnode(var::JuMP.AbstractVariableRef) = JuMP.owner_model(var).ext[:optinode]

###############################################
# Printing
###############################################
function string(node::OptiNode)
    "OptiNode w/ $(JuMP.num_variables(node)) Variable(s)"
end
print(io::IO,node::OptiNode) = print(io, string(node))
show(io::IO,node::OptiNode) = print(io,node)


#DEPRECATED
nodevalue(var::JuMP.VariableRef) = JuMP.value(var)
function nodevalue(expr::JuMP.GenericAffExpr)
    ret_value = 0.0
    for (var,coeff) in expr.terms
        ret_value += coeff*nodevalue(var)
    end
    ret_value += expr.constant
    return ret_value
end
function nodevalue(expr::JuMP.GenericQuadExpr)
    ret_value = 0.0
    for (pair,coeff) in expr.terms
        ret_value += coeff*nodevalue(pair.a)*nodevalue(pair.b)
    end
    ret_value += nodevalue(expr.aff)
    ret_value += expr.aff.constant
    return ret_value
end
nodedual(con_ref::JuMP.ConstraintRef{JuMP.Model,MOI.ConstraintIndex}) = getnode(con).constraint_dual_values[con]
nodedual(con_ref::JuMP.ConstraintRef{JuMP.Model,JuMP.NonlinearConstraintIndex}) = getnode(con).nl_constraint_dual_values[con]

@deprecate nodevalue value
@deprecate nodedual dual

# JuMP.variable_type(::OptiNode) = JuMP.VariableRef
# JuMP.constraint_type(::OptiNode) = JuMP.ConstraintRef
# getattribute(node::OptiNode, symbol::Symbol) = jump_model(node).obj_dict[symbol]
# setattribute(node::OptiNode, symbol::Symbol, attribute::Any) = jump_model(node).obj_dict[symbol] = attribute
