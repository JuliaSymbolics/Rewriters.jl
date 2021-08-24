# Rewriters.jl

This package contains definitions for common combinators that are useful for symbolic expression rewriting.
Its purpose is to provide a shared library of combinators between various symbolic programming Julia packages, for example 
[SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl), [Symbolics.jl](https://github.com/JuliaSymbolics/Symbolics.jl) and [Metatheory.jl](https://github.com/0x0f0f0f/Metatheory.jl).

## Documentation

A rewriter is any function which takes an expression and returns an expression
or `nothing`. If `nothing` is returned that means there was no changes applicable
to the input expression.

The `SymbolicUtils.Rewriters` module contains some types which create and transform
rewriters.

- `Empty()` is a rewriter which always returns `nothing`
- `Chain(itr)` chain an iterator of rewriters into a single rewriter which applies
   each chained rewriter in the given order.
   If a rewriter returns `nothing` this is treated as a no-change.
- `RestartedChain(itr)` like `Chain(itr)` but restarts from the first rewriter once on the
   first successful application of one of the chained rewriters.
- `IfElse(cond, rw1, rw2)` runs the `cond` function on the input, applies `rw1` if cond
   returns true, `rw2` if it retuns false
- `If(cond, rw)` is the same as `IfElse(cond, rw, Empty())`
- `Prewalk(rw; threaded=false, thread_cutoff=100)` returns a rewriter which does a pre-order
   traversal of a given expression and applies the rewriter `rw`. Note that if
   `rw` returns `nothing` when a match is not found, then `Prewalk(rw)` will
   also return nothing unless a match is found at every level of the walk.
   `threaded=true` will use multi threading for traversal. `thread_cutoff` is
   the minimum number of nodes in a subtree which should be walked in a
   threaded spawn.
- `Postwalk(rw; threaded=false, thread_cutoff=100)` similarly does post-order traversal.
- `Fixpoint(rw)` returns a rewriter which applies `rw` repeatedly until there are no changes to be made.
- `PassThrough(rw)` returns a rewriter which if `rw(x)` returns `nothing` will instead
   return `x` otherwise will return `rw(x)`.
