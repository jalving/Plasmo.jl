# A remote graph tracks its worker and a DistributedArray as a persistent reference to the graph on the worker

struct RemoteOptiGraph <: AbstractOptiGraph
    worker::Int
    graph::DArray{OptiGraph, 1, Vector{OptiGraph}}
end

function RemoteOptiGraph(; worker::Int=1)
    if !(worker in workers())
        error("The provided worker $worker is not in existing workers: $(workers())")
    end
    darray = distribute([OptiGraph()], procs=[worker])
    return RemoteOptiGraph(worker, darray)
end

# Track remote nodes

struct RemoteNodeRef
    remote_graph::RemoteOptiGraph
    node_index::NodeIndex
end

function add_node(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker add_node(localpart(rgraph.graph)[1])
    return RemoteNodeRef(rgraph, fetch(f).idx )
end

# TODO: figure out how we build distributed models
# function JuMP.add_variable(rnode::RemoteNodeRef, v::JuMP.ScalarVariable, name::String="")
#     @spawnat rnode.remote_graph.worker begin 
#         graph = localpart(rgraph.graph)[1]
#         node = graph.optinode_map[rnode.index]
#         JuMP.add_variable(node, v, name)
#     end
# end

function JuMP.all_variables(rgraph::RemoteOptiGraph)
    f = @spawnat rgraph.worker all_variables(localpart(rgraph.graph)[1])
    return fetch(f)
end
    
function Base.string(rgraph::RemoteOptiGraph)
    return "RemoteOptiGraph"
end
Base.print(io::IO, graph::RemoteOptiGraph) = Base.print(io, Base.string(graph))
Base.show(io::IO, graph::RemoteOptiGraph) = Base.print(io, graph)


# TODO: what information should be stored, if any?
# should we store local constraint information (i.e. partial constraints)? 

# use case
# dgraph = DOptiGraph(worker=2)
# dsg1 = add_subgraph(dgraph, worker=2)
# dsg2 = add_subgraph(dgraph, worker=3)

# worker = 2
# darray = distribute([OptiGraph()], procs=[worker])
# @spawnat 2 println(localpart(darray)[1])
# @spawnat 2 add_node(localpart(darray)[1])
