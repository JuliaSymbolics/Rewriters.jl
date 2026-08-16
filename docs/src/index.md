# Rewriters.jl

Rewriters.jl provides composable rewriters for symbolic expression trees. A
rewriter is a callable object that returns a rewritten value or `nothing` when
it does not apply.

```@example
using Rewriters

increment = PassThrough(x -> x isa Int && x < 3 ? x + 1 : nothing)
Fixpoint(increment)(1)
```

See the [API reference](api.md) for the complete public interface.
