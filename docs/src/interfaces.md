# Rewriter Interface \label{rewriter_interface}

A rewriter is any callable object with the following contract:

```julia
result = rewriter(input)
```

- Return a replacement value when the rewriter applies.
- Return `nothing` when it does not apply.
- Do not use `nothing` as a replacement value. Wrap the rewriter in
  [`PassThrough`](@ref) when the caller needs to preserve the input on a
  non-match.

The combinators in this package only depend on this callable interface. They
do not require a particular expression type.

## Tree interface

[`Prewalk`](@ref) and [`Postwalk`](@ref) additionally use the
[`TermInterface`](https://github.com/JuliaSymbolics/TermInterface.jl) tree
interface. For a tree node `x`, the following operations must be defined:

```julia
istree(x)
operation(x)
arguments(x)
similarterm(x, operation(x), new_arguments)
```

`similarterm` must return a node of the same representation as `x`, with the
given operation and arguments. The arguments may already contain rewritten
children. Leaf values should return `false` from `istree` and still be valid
inputs to the rewriter.

The following example defines the minimum generic interface and then uses only
the exported rewriter constructors and `TermInterface` functions:

```@example interface
using Rewriters
using TermInterface

struct Node
    operation::Symbol
    arguments::Vector{Any}
end

TermInterface.istree(::Node) = true
TermInterface.operation(x::Node) = x.operation
TermInterface.arguments(x::Node) = x.arguments
TermInterface.similarterm(::Node, operation, arguments; kwargs...) =
    Node(operation, Any[arguments...])

tree = Node(:call, Any[Node(:+, Any[1, 2]), 3])
replace_one = PassThrough(x -> x === 1 ? 10 : nothing)
rewritten = Postwalk(replace_one)(tree)
arguments(arguments(rewritten)[1])
```

```@example interface
rewritten = Prewalk(replace_one)(tree)
arguments(arguments(rewritten)[1])
```

## Traversal rules

`Prewalk` invokes the rewriter at a node before visiting its children. If the
rewriter returns `nothing` for a tree node, the traversal stops at that node;
use `PassThrough` when a non-match should preserve the node and continue into
its children. `Postwalk` visits the children first and then invokes the
rewriter at the rebuilt node.

For both traversals:

- A rewriter returning `nothing` for a child leaves that child unchanged.
- `similarterm` rebuilds a tree after its children have been processed.
- `threaded=true` may process sufficiently large child subtrees in tasks;
  `thread_cutoff` controls the minimum `node_count` for spawning a task.
- `similarterm` is responsible for preserving any representation-specific
  invariants of the tree type.

`Chain` applies rewriters from left to right and retains the current value when
one returns `nothing`. `RestartedChain` applies the chain from the beginning
after the first successful rewrite. `Fixpoint` repeats a rewriter until it
returns `nothing` or two successive values compare equal with `isequal`.

The behavior is exercised with a `Node` implementation in the package test
suite, so these rules do not depend on a concrete symbolic expression type.
