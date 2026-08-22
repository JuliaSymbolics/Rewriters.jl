using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(path = dirname(@__DIR__))
Pkg.instantiate()

using Documenter
using Rewriters

makedocs(
    sitename = "Rewriters.jl",
    modules = [Rewriters],
    clean = true,
    doctest = true,
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Rewriter Interface" => "interfaces.md",
        "API Reference" => "api.md",
    ],
)
