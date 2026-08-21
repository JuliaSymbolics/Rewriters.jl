const TIMER_OUTPUTS = true
const being_timed = Ref{Bool}(false)

if TIMER_OUTPUTS
    import TimerOutputs: timeit

    struct TimerCall{F, A}
        f::F
        args::A
    end

    (call::TimerCall)() = call.f(call.args...)
end

"""
    @timer name expr

Evaluate `expr`, recording its elapsed time under `name` when timer output is
enabled for this package. When timing is disabled, `expr` is evaluated directly.
In either mode the expression is evaluated exactly once and its value is
returned.

# Arguments

- `name`: Label passed to `TimerOutputs.timeit` when timing is enabled.
- `expr`: Expression to evaluate.

# Returns

The value of `expr`.
"""
macro timer(name, expr)
    if TIMER_OUTPUTS
        timed_expr = if expr isa Expr && expr.head === :call
            f = expr.args[1]
            args = Expr(:tuple, map(esc, expr.args[2:end])...)
            :(timeit(TimerCall($(esc(f)), $args), $(esc(name))))
        else
            :(timeit(() -> $(esc(expr)), $(esc(name))))
        end
        return :(
            if being_timed[]
                $timed_expr
            else
                $(esc(expr))
            end
        )
    end
    return esc(expr)
end

"""
    @iftimer expr

Evaluate `expr` while preserving the package's timing instrumentation
configuration. This macro currently leaves the expression unchanged.

# Arguments

- `expr`: Expression to evaluate.

# Returns

The value of `expr`.
"""
macro iftimer(expr)
    return esc(expr)
end

export @timer
export @iftimer
