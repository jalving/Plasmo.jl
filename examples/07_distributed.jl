using Distributed
addprocs(2)
@everywhere using Plasmo

# the top-level graph
rgraph = Plasmo.RemoteOptiGraph(; name=:remote, worker=2)
@remote_execute rgraph begin
    #graph = local_graph(rgraph)
    n1 = add_node(graph)
    @variable(n1, x >= 0)
end

# do everything in a remote call
dsg1 = add_subgraph(dgraph, worker=2)
@remote_execute dsg1 begin
    n1 = add_node(dsg1)
    @variable(n1, x >= 0)
end

# a different approach; add variables to remote nodes via jump macro
# doesn't work with how JuMP handles registering objects
# probably not a good idea for scaling memory anyways
# n1 = add_node(rgraph)
# @variable(n1, x >= 0)

dsg2 = add_subgraph(dgraph, worker=3)
@remote dsg2 begin
    n2 = add_node(dsg1)
    @variable(n2, x >= 0)
end

# returns RemoteNodeRef
n1 = get_node(dsg1, 1)
n2 = get_node(dsg2, 2)

# Add a constraint to a remote graph
@linkconstraint(rgraph, n1[:x] == n2[:x])

# optimizing dgraph requires fetching the other graphs (slow)
@objective(dgraph, Min, sum(n1[:x] + n2[:x]))

set_optimizer(dsg1, Ipopt.Optimizer)
optimize!(dsg1)

set_optimizer(dsg2, Ipopt.Optimizer)
optimize!(dsg2)

println("n1[:x]= ", value(dsg1, n1[:x]))
println("n2[:x]= ", value(dsg2, n2[:x]))

# optimizing dgraph requires fetching the other graphs (slow)
set_optimizer(rgraph, Ipopt.Optimizer)
optimize!(rgraph)

# TODO: develop and run a distributed algorithm on a remote graph
