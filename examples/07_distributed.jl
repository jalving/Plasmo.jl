using Plasmo
using Ipopt

addprocs(2)

# the top-level graph
dgraph = RemoteOptiGraph(; worker=2)

dsg1 = add_subgraph(dgraph, worker=2)
n1 = add_node(dsg1)

@remote dsg1 begin
    @variable(n1, x >= 0)
end

dsg2 = add_subgraph(dgraph, worker=3)
n2 = add_node(dsg1)

@remote dsg2 begin
    @variable(n2, x >= 0)
end

@remote dgraph begin
    @linkconstraint(dgraph, n1[:x] == n2[:x])
end

set_optimizer(dsg1, Ipopt.Optimizer)
optimize!(dsg1)

set_optimizer(dsg2, Ipopt.Optimizer)
optimize!(dsg2)

println("n1[:x]= ", value(dsg1, n1[:x]))
println("n2[:x]= ", value(dsg2, n2[:x]))

# optimizing dgraph requires fetching the other graphs (slow)
@remote dgraph begin
    @objective(dgraph, Min, sum(n1[:x] + n2[:x]))
end

set_optimizer(dgraph, Ipopt.Optimizer)
optimize!(dgraph)

println("objective = ", objective_value(graph))