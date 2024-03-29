"""
    ProjectionMap

A mapping between OptiGraph elements (nodes and edges) and elements in a graph projection. 
A graph projection can be for example a hypergraph, a bipartite graph
or a standard graph.
"""
mutable struct ProjectionMap{GT <: Graphs.AbstractGraph}
    optigraph::OptiGraph
    projected_graph::GT
    proj_to_opti_map::Dict         #map projected graph vertices to optigraph elements
    opti_to_proj_map::Dict         #map optigraph elements to projected elements
end

function ProjectionMap(
	optigraph::OptiGraph, 
	projection::GT
) where GT <: Graphs.AbstractGraph
    return ProjectionMap(optigraph, projection, Dict(), Dict())
end

function Base.getindex(graph_map::ProjectionMap, vertex::Union{Int64,Graphs.AbstractEdge})
    return graph_map.proj_to_opti_map[vertex]
end

function Base.setindex!(
    graph_map::ProjectionMap, 
    vertex::Union{Int64,Graphs.AbstractEdge}, 
    value::OptiElement
)
    return graph_map.proj_to_opti_map[vertex] = value
end

function Base.getindex(graph_map::ProjectionMap, element::OptiElement)
    return graph_map.opti_to_proj_map[element]
end

function Base.setindex!(
    graph_map::ProjectionMap, 
    element::OptiElement, 
    value::Union{Int64,Graphs.AbstractEdge}
)
    return graph_map.opti_to_proj_map[element] = value
end

Base.broadcastable(graph_map::ProjectionMap) = Ref(graph_map)

"""
    get_mapped_elements(proj_map::ProjectionMap, elements::Vector{OptiElement})

Get the projected graph elements that correspond to the supplied optigraph elements.

    get_mapped_elements(proj_map::ProjectionMap, elements::Vector{Any})

Get the optiraph elements that correspond to the supplied projected graph elements.
"""
function get_mapped_elements(proj_map::ProjectionMap, elements::Vector{OptiElement})
    return getindex.(Ref(proj_map.opti_to_proj_map), elements)
end

function get_mapped_elements(proj_map::ProjectionMap, elements::Vector)
    return getindex.(Ref(proj_map.proj_to_opti_map), elements)
end

"""
    build_hypergraph(graph::OptiGraph)

Retrieve a hypergraph representation of the optigraph `graph`. Returns a [`HyperGraph`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges.
"""
function build_hypergraph(optigraph::OptiGraph)
    hypergraph = GOI.HyperGraph()
    hyper_map = ProjectionMap(optigraph, hypergraph)
    for node in all_nodes(optigraph)
        hypernode = Graphs.add_vertex!(hypergraph)
        hyper_map[hypernode] = node
        hyper_map[node] = hypernode
    end
    for edge in all_edges(optigraph)
        nodes = all_nodes(edge)
        hypernodes = Base.getindex.(hyper_map, nodes)
        @assert length(hypernodes) >= 2
        hyperedge = Graphs.add_edge!(hypergraph, hypernodes...)
        hyper_map[hyperedge] = edge
        hyper_map[edge] = hyperedge
    end
    return hyper_map
end
@deprecate gethypergraph build_hyper_graph
@deprecate hyper_graph build_hyper_graph

"""
    build_clique_graph(graph::OptiGraph)

Retrieve a standard graph representation of the optigraph `graph`. Returns a `LightGraphs.Graph` object, as well as a dictionary
that maps vertices and edges to the optinodes and optiedges.
"""
function build_clique_graph(optigraph::OptiGraph)
    graph = Graphs.Graph()
    graph_map = ProjectionMap(optigraph, graph)
    for optinode in all_nodes(optigraph)
        Graphs.add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optinode
        graph_map[optinode] = vertex
    end
    for edge in all_edges(optigraph)
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for i in 1:length(edge_vertices)
            vertex_from = edge_vertices[i]
            other_vertices = edge_vertices[(i + 1):end]
            for j in 1:length(other_vertices)
                vertex_to = other_vertices[j]
                inserted = Graphs.add_edge!(graph, vertex_from, vertex_to)
            end
        end
    end
    return graph_map
end
@deprecate getcliquegraph build_clique_graph
@deprecate clique_graph build_clique_graph

"""
    edge_graph(optigraph::OptiGraph)

Retrieve the edge-graph representation of `optigraph`. This is sometimes called the line graph of a hypergraph.
Returns a `ProjectionMap`.
"""
function build_edge_graph(optigraph::OptiGraph)
    graph = Graphs.Graph()
    graph_map = ProjectionMap(optigraph, graph)
    for optiedge in all_edges(optigraph)
        Graphs.add_vertex!(graph)
        vertex = nv(graph)
        graph_map[vertex] = optiedge
        graph_map[optiedge] = vertex
    end
    edge_array = all_edges(optigraph)
    n_edges = length(edge_array)
    for i in 1:n_edges - 1
        for j in (i + 1):n_edges
            e1 = edge_array[i]
            e2 = edge_array[j]
            if !isempty(intersect(e1.nodes, e2.nodes))
                Graphs.add_edge!(graph, graph_map[e1], graph_map[e2])
            end
        end
    end
    return graph_map
end
@deprecate edge_graph build_edge_graph

"""
    edge_hyper_graph(graph::OptiGraph)

Retrieve an edge-hypergraph representation of the optigraph `graph`. Returns a [`ProjectionMap`](@ref) object, as well as a dictionary
that maps hypernodes and hyperedges to the original optinodes and optiedges. This is also called the dual-hypergraph representation of a hypergraph.
"""
function build_edge_hypergraph(optigraph::OptiGraph)
    # create a primal hypergraph first. we need to do this to get the node --> edge mapping
    primal_map = build_hypergraph(optigraph)

    # build the edge hypergraph
    hypergraph = GOI.HyperGraph()
    hyper_map = ProjectionMap(optigraph, hypergraph)
    for edge in all_edges(optigraph)
        hypernode = Graphs.add_vertex!(hypergraph)
        hyper_map[hypernode] = edge
        hyper_map[edge] = hypernode
    end
    for node in all_nodes(optigraph)
        hyperedges = incident_edges(primal_map, node)
        dual_nodes = Base.getindex.(hyper_map, hyperedges)
        @assert length(dual_nodes) >= 2
        hyperedge = Graphs.add_edge!(hypergraph, dual_nodes...)
        hyper_map[hyperedge] = node
        hyper_map[node] = hyperedge
    end
    return hyper_map
end
@deprecate edge_hyper_graph build_edge_hypergraph

"""
    bipartite_graph(optigraph::OptiGraph)

Create a bipartite graph representation from `optigraph`.  
The bipartite graph contains two sets of vertices corresponding to optinodes and optiedges respectively.
"""
function build_bipartite_graph(optigraph::OptiGraph)
    graph = GOI.BipartiteGraph()
    graph_map = ProjectionMap(optigraph, graph)
    for optinode in all_nodes(optigraph)
        Graphs.add_vertex!(graph; bipartite=1)
        node_vertex = nv(graph)
        graph_map[node_vertex] = optinode
        graph_map[optinode] = node_vertex
    end
    for edge in all_edges(optigraph)
        Graphs.add_vertex!(graph; bipartite=2)
        edge_vertex = nv(graph)
        graph_map[edge] = edge_vertex
        graph_map[edge_vertex] = edge
        nodes = edge.nodes
        edge_vertices = [graph_map[optinode] for optinode in nodes]
        for node_vertex in edge_vertices
            Graphs.add_edge!(graph, edge_vertex, node_vertex)
        end
    end
    return graph, graph_map
end