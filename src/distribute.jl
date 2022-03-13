using Distributed
using DataStructures
#Wrapper around julia remote channel
struct OptiGraphRef
    optigraph_symbol::Symbol  # symbol corresponding optigraph variable on worker
    worker::Int               # worker id where optigraph resides
    obj_dict::Dict{Symbol,Any}
end

mutable struct OptiNodeRef <: JuMP.AbstractModel
    optinode_symbol::Symbol
    worker::Int
    label::String
end

struct OptiEdgeRef
    optiedge_symbol::Symbol
    worker::Int
end

struct RemoteVariableRef
end

#An optigraph distributed among Julia workers.  Used for distributed model building
mutable struct DOptiGraph #<: Plasmo.AbstractOptiGraph
    optigraphs::OrderedDict{Int,OptiGraphRef}   #map optigraph index to reference
    workers::Vector{Int}                        #vector of workers
    optigraph_map::OrderedDict{Int,Vector{Int}} #Map worker to optigraph indices
end


function DOptiGraph()
    return DOptiGraph(OrderedDict{Int,OptiGraphRef}(),
                      Int[],
                      OrderedDict{Int,Vector{Int}}())
end


function set_workers(dgraph::DOptiGraph, wrkrs::Vector{Int})
    @assert issubset(wrkrs, workers())
    dgraph.workers = wrkrs
    for worker in dgraph.workers
        dgraph.optigraph_map[worker] = Int[]
        #add_optigraph!(dgraph, worker)
    end
    return nothing
end


function add_optigraph!(dgraph::DOptiGraph, worker::Int)
    optigraph_sym = gensym()
    remotecall_wait(Core.eval, worker, Main, :($optigraph_sym = OptiGraph()))
    idx = length(dgraph.optigraphs)
    optigraph_ref = OptiGraphRef(optigraph_sym, worker, Dict{Symbol,Any}())
    dgraph.optigraphs[idx + 1] = optigraph_ref
    push!(dgraph.optigraph_map[worker],idx + 1)
    return optigraph_ref
end


function add_node!(optigraph_ref::OptiGraphRef)
    optigraph_sym = optigraph_ref.optigraph_symbol
    optinode_sym = gensym()
    remotecall_wait(Core.eval, optigraph_ref.worker, Main, :($optinode_sym = add_node!($optigraph_sym)))
    optinode_ref = OptiNodeRef(optinode_sym, optigraph_ref.worker, "test")
    return optinode_ref

    #TODO: check for RemoteException
    #return isa(v, RemoteException) ? throw(v) : v
end

#this adds the variable, but I think it is creating the variable and then passing it through communication
function JuMP.add_variable(node::OptiNodeRef, v::JuMP.AbstractVariable, base_name::String="")
    optinode_sym = node.optinode_symbol
    remotecall_wait(Core.eval, node.worker, Main, :(JuMP.add_variable($(optinode_sym), $v, $base_name)))
    #return RemoteVariableRef?
end
