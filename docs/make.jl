using Documenter, Plasmo, JuMP, LightGraphs, Plots

#Fix issue with GKS for plotting
ENV["GKSwstype"] = "100"

makedocs(sitename="Plasmo.jl", modules=[Plasmo],
        doctest=true,format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"),
        authors = "Jordan Jalving",
        pages = [
        "Introduction" => "index.md",
        "Modeling" => "documentation/modeling.md",
        "Partitioning and Graph Operations" => "documentation/partitioning.md",
        "Solvers" => "documentation/solvers.md",
        "Plotting" => "documentation/plotting.md",
        "Tutorials" => "tutorials/tutorials.md"]
        )

deploydocs(
    repo = "github.com/zavalab/Plasmo.jl.git"
    )
