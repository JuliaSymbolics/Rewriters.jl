"""
A rewriter is any function which takes an expression and returns an expression
or `nothing`. If `nothing` is returned that means there was no changes applicable
to the input expression.

The `Rewriters` module contains some types which create and transform
rewriters.

- `Empty()` is a rewriter which always returns `nothing`
- `Chain(itr)` chain an iterator of rewriters into a single rewriter which applies
   each chained rewriter in the given order.
   If a rewriter returns `nothing` this is treated as a no-change.
- `RestartedChain(itr)` like `Chain(itr)` but restarts from the first rewriter once on the
   first successful application of one of the chained rewriters.
- `IfElse(cond, rw1, rw2)` runs the `cond` function on the input, applies `rw1` if cond
   returns true, `rw2` if it returns false
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

"""
module Rewriters
include("timer.jl")
import TermInterface: arguments, istree, node_count, operation, similarterm,
    unsorted_arguments

export Empty, IfElse, If, Chain, RestartedChain, Fixpoint, Postwalk, Prewalk, PassThrough

# Cache of printed rules to speed up @timer
const repr_cache = IdDict()
cached_repr(x) = Base.get!(()->repr(x), repr_cache, x)

"""
    Empty()

A rewriter that always returns `nothing`.

Rewriters use `nothing` to indicate that they did not change their input. Use
`PassThrough(Empty())` when a no-op rewriter should instead return its input.

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
    cond::F
    yes::A
    no::B
end

instrument(x::IfElse, f) = IfElse(x.cond, instrument(x.yes, f), instrument(x.no, f))

function (rw::IfElse)(x)
    rw.cond(x) ?  rw.yes(x) : rw.no(x)
end

"""
    If(cond, rw)

Construct an [`IfElse`](@ref) that applies `rw` when `cond` is true and
otherwise reports no change with [`Empty`](@ref).

# Arguments

- `cond`: Callable predicate evaluated as `cond(x)`.
- `rw`: Rewriter applied when the predicate is true.
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

# Examples

```julia
julia> rw = Chain((x -> x + 1, x -> 2x));
julia> rw(1)
4
```
"""
struct Chain
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

instrument(c::Chain, f) = Chain(map(x->instrument(x,f), c.rws))

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
"""
struct RestartedChain{Cs}
    rws::Cs
end

instrument(c::RestartedChain, f) = RestartedChain(map(x->instrument(x,f), c.rws))

function (rw::RestartedChain)(x)
    for f in rw.rws
        y = @timer cached_repr(f) f(x)
        if y !== nothing
            return Chain(rw.rws)(y)
        end
    end
    return x
end

@generated function (rw::RestartedChain{<:NTuple{N,Any}})(x) where N
    quote
        for i in 1:$N
            let f = rw.rws[i]
                y = @timer cached_repr(repr(f)) f(x)
                if y !== nothing
                    return Chain(rw.rws)(y)
                end
            end
        end
        return x
    end
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

# Examples

```julia
julia> rw = Fixpoint(x -> x < 4 ? x + 1 : nothing);
julia> rw(1)
4
```
"""
struct Fixpoint{C}
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

function instrument(x::Walk{ord, C,F,threaded}, f) where {ord,C,F,threaded}
    irw = instrument(x.rw, f)
    Walk{ord, typeof(irw), typeof(x.similarterm), threaded}(irw,
                                                            x.thread_cutoff,
                                                            x.similarterm)
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
"""
function Postwalk(rw; threaded::Bool=false, thread_cutoff=100, similarterm=similarterm)
    Walk{:post, typeof(rw), typeof(similarterm), threaded}(rw, thread_cutoff, similarterm)
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
"""
function Prewalk(rw; threaded::Bool=false, thread_cutoff=100, similarterm=similarterm)
    Walk{:pre, typeof(rw), typeof(similarterm), threaded}(rw, thread_cutoff, similarterm)
end

"""
    PassThrough(rw)

Wrap a rewriter so that it returns its input when the wrapped rewriter returns
`nothing`.

# Arguments

- `rw`: Callable rewriter.

# Examples

```julia
julia> PassThrough(Empty())(:x)
:x
```
"""
struct PassThrough{C}
    rw::C
end
instrument(x::PassThrough, f) = PassThrough(instrument(x.rw, f))

(p::PassThrough)(x) = (y=p.rw(x); y === nothing ? x : y)

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
        if istree(x)
            _args = map(arguments(x)) do arg
                if node_count(arg) > p.thread_cutoff
                    Threads.@spawn p(arg)
                else
                    p(arg)
                end
            end
            args = map((t,a) -> passthrough(t isa Task ? fetch(t) : t, a), _args, arguments(x))
            t = p.similarterm(x, operation(x), args)
        end
        return ord === :post ? p.rw(t) : t
    else
        return p.rw(x)
    end
end

function instrument_io(x)
    function io_instrumenter(r)
        function (args...)
            println("Rule: ", r)
            println("Input: ", args)
            res = r(args...)
            println("Output: ", res)
            res
        end
    end

    instrument(x, io_instrumenter)
end

end # end module
