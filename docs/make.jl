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
        "API Reference" => "api.md",
    ],
)
