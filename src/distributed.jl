# A remote graph tracks its worker and a DistributedArray as a persistent reference to the graph on the worker

struct RemoteOptiGraph <: AbstractOptiGraph
    worker::Int
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}}
end

function RemoteOptiGraph(; name::Symbol=:remote, worker::Int=1)
    if !(worker in workers())
        error("The provided worker $worker is not in existing workers: $(workers())")
    end
    darray = distribute([OptiGraph(name=name)], procs=[worker])
    return RemoteOptiGraph(worker, darray)
end

function local_graph(rgraph::RemoteOptiGraph)
    return localpart(rgraph.graph)[1]
end

function print_local_graph(rgraph::RemoteOptiGraph)
    @spawnat rgraph.worker println(localpart(rgraph.graph)[1])
    return nothing
end

function get_local_graph(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker localpart(rgraph.graph)[1]
    return fetch(f)
end

# Track remote nodes

struct RemoteNodeRef <: JuMP.AbstractModel
    remote_graph::RemoteOptiGraph
    node_index::NodeIndex
end

function add_node(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker add_node(localpart(rgraph.graph)[1])
    return RemoteNodeRef(rgraph, fetch(f).idx)
end

# 
function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker all_variables(localpart(rgraph.graph)[1])

    # remote_vars = RemoteVariableRef[]
    # Cannot return NodeVariableRef; it grabs the entire optigraph
    
    return fetch(f)
end

function Base.string(rgraph::RemoteNodeRef)
    return "RemoteNodeRef"
end
Base.print(io::IO, graph::RemoteNodeRef) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteNodeRef) = Base.print(io, graph)

function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)



# IDEA: Try to use RemoteVariableRefs

# function Base.setindex!(rnode::RemoteNodeRef, value::Any, name::Symbol)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         Base.setindex!(node, value, name)
#     end
#     return nothing
# end

# function Base.getindex(rnode::RemoteNodeRef, name::Symbol)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         Base.getindex(node, name)
#     end
#     return fetch(f)
# end

# # TODO: figure out how we build distributed models
# function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin 
#         graph = local_graph(rgraph)
#         node = graph.optinode_map[rnode.node_index]
#         JuMP.add_variable(node, v, name)
#     end
#     # need to return some kind of remote reference. this would fetch the whole graph.
#     # if we do this; then we have to support all kinds of operations on the remote variable reference
#     return fetch(f)
# end

# function JuMP.object_dictionary(rnode::RemoteNodeRef)
#     rgraph = rnode.remote_graph
#     f = @spawnat rgraph.worker begin
#         graph = localpart(rgraph.graph)[1]
#         node = graph.optinode_map[rnode.node_index]
#         obj_dict = JuMP.object_dictionary(node)
#     end 
#     return fetch(f)
# end

