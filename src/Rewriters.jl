"""
    Rewriters

Tools for composing rewriters over scalar values and expression trees.

A rewriter is a callable object that accepts one input and returns either a
rewritten value or `nothing`. Returning `nothing` means that the rewriter did
not apply. A caller that needs a total transformation can wrap a rewriter in
[`PassThrough`](@ref), which retains the input when the wrapped rewriter does
not apply.

The traversal constructors [`Prewalk`](@ref) and [`Postwalk`](@ref) use the
`TermInterface` tree interface. A tree node must satisfy `istree(x)`, expose
an `operation(x)` and `arguments(x)`, and be reconstructible with
`similarterm(x, operation, arguments)`. A rewriter passed to a traversal is
called at every visited node. The prewalk applies it before visiting children;
the postwalk applies it after visiting children.

The exported constructors are ordinary Julia functions and callable structs,
so they can be composed without depending on any package-specific expression
type. The Rewriter Interface page documents the complete contract and generic
examples.
"""
module Rewriters
include("timer.jl")
import TermInterface: arguments, istree, node_count, operation, similarterm,
    unsorted_arguments
using PrecompileTools: @compile_workload, @setup_workload

export Empty, IfElse, If, Chain, RestartedChain, Fixpoint, Postwalk, Prewalk, PassThrough

# Cache of printed rules to speed up @timer
const repr_cache = IdDict()
cached_repr(x) = Base.get!(() -> repr(x), repr_cache, x)

"""
    Empty()

A rewriter that always returns `nothing`.

Rewriters use `nothing` to indicate that they did not change their input. Use
`PassThrough(Empty())` when a no-op rewriter should instead return its input.

# Returns

`nothing` for every input.

# Examples

```julia
julia> Empty()(:x)
nothing
```
"""
struct Empty end

(rw::Empty)(x) = nothing

instrument(x, f) = f(x)
instrument(x::Empty, f) = x

"""
    IfElse(cond, yes, no)

Select between two rewriters using a predicate.

# Arguments

- `cond`: A callable object. It is evaluated as `cond(x)`.
- `yes`: Rewriter applied when `cond(x)` is `true`.
- `no`: Rewriter applied when `cond(x)` is `false`.

The selected rewriter receives the original input. Each branch must follow the
rewriter contract and return either a rewritten value or `nothing`.

# Returns

The result returned by `yes(x)` when `cond(x)` is `true`, otherwise the result
returned by `no(x)`.

# Examples

```julia
julia> rw = IfElse(iseven, x -> x + 1, x -> nothing);
julia> rw(2)
3
julia> rw(3)
nothing
```
"""
struct IfElse{F, A, B}
    """Predicate used to select a branch."""
    cond::F
    """Rewriter used when `cond(x)` is `true`."""
    yes::A
    """Rewriter used when `cond(x)` is `false`."""
    no::B
end

instrument(x::IfElse, f) = IfElse(x.cond, instrument(x.yes, f), instrument(x.no, f))

function (rw::IfElse)(x)
    return rw.cond(x) ? rw.yes(x) : rw.no(x)
end

"""
    If(cond, rw)

Construct an [`IfElse`](@ref) that applies `rw` when `cond` is true and
otherwise reports no change with [`Empty`](@ref).

# Arguments

- `cond`: Callable predicate evaluated as `cond(x)`.
- `rw`: Rewriter applied when the predicate is true.

# Returns

An [`IfElse`](@ref) that uses `rw` as its true branch and [`Empty`](@ref) as its
false branch.
"""
If(f, x) = IfElse(f, x, Empty())

"""
    Chain(rws)

Apply an iterable of rewriters in order.

The output of each rewriter becomes the input to the next one. A `nothing`
result means that the current input is retained and the chain continues.
Consequently, `Chain` returns its input when every rewriter reports no change.

# Arguments

- `rws`: Iterable of callable rewriters.

# Fields

- `rws`: The iterable of rewriters, retained as supplied by the caller.

# Returns

A callable `Chain` object. For input `x`, each rewriter is called with the
current value. A `nothing` result leaves the current value unchanged, and the
final current value is returned.

# Examples

```julia
julia> rw = Chain((x -> x + 1, x -> 2x));
julia> rw(1)
4
```
"""
struct Chain
    """Iterable of callable rewriters applied from left to right."""
    rws
end

function (rw::Chain)(x)
    for f in rw.rws
        y = @timer cached_repr(f) f(x)
        if y !== nothing
            x = y
        end
    end
    return x
end

instrument(c::Chain, f) = Chain(map(x -> instrument(x, f), c.rws))

"""
    RestartedChain(rws)

Apply an iterable of rewriters and restart from the first rewriter after the
first successful rewrite.

Unlike [`Chain`](@ref), a successful rewrite returns to the beginning of the
sequence. The resulting chain therefore keeps applying earlier rules after a
later rule changes the input. If no rewriter changes the input, the original
input is returned.

# Arguments

- `rws`: Iterable of callable rewriters.

# Returns

A callable `RestartedChain` object. It returns the value after the first
successful rewrite and one subsequent pass through the complete sequence, or
the original input when no rewriter applies.
"""
struct RestartedChain{Cs}
    """Iterable of callable rewriters applied in sequence."""
    rws::Cs
end

instrument(c::RestartedChain, f) = RestartedChain(map(x -> instrument(x, f), c.rws))

function (rw::RestartedChain)(x)
    for f in rw.rws
        y = @timer cached_repr(f) f(x)
        if y !== nothing
            return Chain(rw.rws)(y)
        end
    end
    return x
end

@generated function (rw::RestartedChain{<:NTuple{N, Any}})(x) where {N}
    steps = [
        quote
                f = rw.rws[$i]
                y = @timer cached_repr(repr(f)) f(x)
                if y !== nothing
                    return Chain(rw.rws)(y)
            end
            end for i in 1:N
    ]
    return Expr(:block, steps..., :(return x))
end
"""
    Fixpoint(rw)

Repeatedly apply `rw` until it reports no change or returns a value equal to the
previous value.

The fixpoint loop treats `nothing` as no change and returns the most recent
input. Rewriters that alternate between distinct values do not converge and
will continue until their own logic reaches a fixed point.

# Arguments

- `rw`: Callable rewriter.

# Fields

- `rw`: The callable rewriter repeatedly applied to the current value.

# Returns

A callable `Fixpoint` object. It returns the last value before a `nothing`
result, or when two successive values compare equal with `isequal`.

# Examples

```julia
julia> rw = Fixpoint(x -> x < 4 ? x + 1 : nothing);
julia> rw(1)
4
```
"""
struct Fixpoint{C}
    """Callable rewriter repeatedly applied until it reaches a fixpoint."""
    rw::C
end

instrument(x::Fixpoint, f) = Fixpoint(instrument(x.rw, f))

function (rw::Fixpoint)(x)
    f = rw.rw
    y = @timer cached_repr(f) f(x)
    while x !== y && !isequal(x, y)
        y === nothing && return x
        x = y
        y = @timer cached_repr(f) f(x)
    end
    return x
end

struct Walk{ord, C, F, threaded}
    rw::C
    thread_cutoff::Int
    similarterm::F
end

function instrument(x::Walk{ord, C, F, threaded}, f) where {ord, C, F, threaded}
    irw = instrument(x.rw, f)
    return Walk{ord, typeof(irw), typeof(x.similarterm), threaded}(
        irw,
        x.thread_cutoff,
        x.similarterm
    )
end

using .Threads

"""
    Postwalk(rw; threaded=false, thread_cutoff=100, similarterm=similarterm)

Construct a rewriter that traverses a term bottom-up and applies `rw` after
rewriting the children.

# Arguments

- `rw`: Callable rewriter applied to every visited node.

# Keyword Arguments

- `threaded`: When `true`, traverse sufficiently large child subtrees using
  tasks.
- `thread_cutoff`: Minimum `TermInterface.node_count`
  for spawning a child task.
- `similarterm`: Function used to rebuild a node from its operation and
  rewritten arguments. It defaults to the imported TermInterface method.

If `rw(node)` returns `nothing`, the node is retained while traversal proceeds.
The returned rewriter itself follows the same `nothing` convention at leaves.

# Returns

A callable traversal object. For a tree input, it returns the rebuilt tree or
the result of the final rewrite at the root. For a non-tree input, it returns
`rw(x)`.
"""
function Postwalk(rw; threaded::Bool = false, thread_cutoff = 100, similarterm = similarterm)
    return Walk{:post, typeof(rw), typeof(similarterm), threaded}(rw, thread_cutoff, similarterm)
end

"""
    Prewalk(rw; threaded=false, thread_cutoff=100, similarterm=similarterm)

Construct a rewriter that traverses a term top-down and applies `rw` before
rewriting the children.

# Arguments

- `rw`: Callable rewriter applied to every visited node.

# Keyword Arguments

- `threaded`: When `true`, traverse sufficiently large child subtrees using
  tasks.
- `thread_cutoff`: Minimum `TermInterface.node_count`
  for spawning a child task.
- `similarterm`: Function used to rebuild a node from its operation and
  rewritten arguments.

Use `PassThrough(rw)` internally when a traversal must preserve a node after a
child rewriter reports `nothing`.

# Returns

A callable traversal object with the same return convention as [`Postwalk`](@ref).
"""
function Prewalk(rw; threaded::Bool = false, thread_cutoff = 100, similarterm = similarterm)
    return Walk{:pre, typeof(rw), typeof(similarterm), threaded}(rw, thread_cutoff, similarterm)
end

"""
    PassThrough(rw)

Wrap a rewriter so that it returns its input when the wrapped rewriter returns
`nothing`.

# Arguments

- `rw`: Callable rewriter.

# Returns

A callable `PassThrough` object. For input `x`, it returns `rw(x)` when that
result is not `nothing`, otherwise it returns `x`.

# Examples

```julia
julia> PassThrough(Empty())(:x)
:x
```
"""
struct PassThrough{C}
    """Callable rewriter whose `nothing` result is replaced with its input."""
    rw::C
end
instrument(x::PassThrough, f) = PassThrough(instrument(x.rw, f))

(p::PassThrough)(x) = (y = p.rw(x); y === nothing ? x : y)

passthrough(x, default) = x === nothing ? default : x
function (p::Walk{ord, C, F, false})(x) where {ord, C, F}
    @assert ord === :pre || ord === :post
    if istree(x)
        if ord === :pre
            x = p.rw(x)
        end
        if istree(x)
            x = p.similarterm(x, operation(x), map(PassThrough(p), unsorted_arguments(x)))
        end
        return ord === :post ? p.rw(x) : x
    else
        return p.rw(x)
    end
end

function (p::Walk{ord, C, F, true})(x) where {ord, C, F}
    @assert ord === :pre || ord === :post
    if istree(x)
        if ord === :pre
            x = p.rw(x)
        end
        t = x
        if istree(x)
            _args = map(arguments(x)) do arg
                if node_count(arg) > p.thread_cutoff
                    Threads.@spawn p(arg)
                else
                    p(arg)
                end
            end
            args = map((t, a) -> passthrough(t isa Task ? fetch(t) : t, a), _args, arguments(x))
            t = p.similarterm(x, operation(x), args)
        end
        return ord === :post ? p.rw(t) : t
    else
        return p.rw(x)
    end
end

function instrument_io(x)
    function io_instrumenter(r)
        return function (args...)
            println("Rule: ", r)
            println("Input: ", args)
            res = r(args...)
            println("Output: ", res)
            return res
        end
    end

    return instrument(x, io_instrumenter)
end

include("precompile.jl")

end # end module
