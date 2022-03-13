using Distributed
addprocs(1)

@everywhere using Pkg
@everywhere Pkg.activate("./")
@everywhere pushfirst!(LOAD_PATH,"/home/jordan/.julia/dev/Plasmo")
@everywhere using Plasmo

include("Plasmo/src/distribute.jl")

#distributed optigraph
dgraph = DOptiGraph()
set_workers(dgraph, workers())
gref = add_optigraph!(dgraph, 2)

#gref = dgraph.optigraphs[1]
remotecall(Core.eval, gref.worker, Main, :(println($(gref.optigraph_symbol))))

@optinode(gref, nodes[1:5])
remotecall(Core.eval, nodes[1].worker, Main, :(println($(nodes[1].optinode_symbol))))

#add variables
@variable(nodes[1], x >= 0)
remotecall(Core.eval, nodes[1].worker, Main, :(println(all_variables($(nodes[1].optinode_symbol)))))

@variable(nodes[1], y[1:10] >= 0)
remotecall(Core.eval, nodes[1].worker, Main, :(println(all_variables($(nodes[1].optinode_symbol)))))

#TODO: constraints
@constraint(nodes[1], y[1:10] >= 0)



value(y[1])


# @spawnat 2 begin
#     global sym = gensym()
#     @eval Main $sym = OptiGraph()
# end
# @spawnat 2 println(eval(sym))

# @spawnat 2 sym = gensym()
# @spawnat 2 @eval $sym = OptiGraph()
# @spawnat 2 println(eval(sym))

# @spawnat 2 @eval Main @optinode(eval(sym),n1)
# @spawnat 2 @eval Main @optinode(eval(sym),nodes[1:100])
# @spawnat 2 @eval Main @variable(n1,x>=0)
#
# @spawnat 2 println(eval(n1))
# @spawnat 2 println(eval(sym))


# idx = length(dgraph.optigraphs)
# dgraph.optigraphs[idx + 1] = subgraph_sym
# optigraph_ref = OptiGraphRef(optigraph_sym, worker)
#
#
# #TODO: figure how to check for RemoteException
# r = remotecall(error,2)
# Distributed.call_on_owner(Distributed.fetch_ref, r)
# rid = remoteref_id(rr)
#
# if rr.where == myid()
#     f(rid, args...)
# else
#     remotecall_fetch(f, rr.where, rid, args...)
# #fetch_ref(rid, args...) = fetch(lookup_ref(rid).c, args...)
#
#
# #DOptiGraph
# workrs = workers()
# dgraph = DOptiGraph(workrs)
# optigraph = dgraph.optigraphs[1]
#
#
# remotecall_wait(Core.eval, 2, Main, :(println("test")))
