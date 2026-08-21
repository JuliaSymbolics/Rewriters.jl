const TIMER_OUTPUTS = true
const being_timed = Ref{Bool}(false)

if TIMER_OUTPUTS
    import TimerOutputs: timeit

    struct TimerCall{F, A}
        f::F
        args::A
    end

    (call::TimerCall)() = call.f(call.args...)

    """
        @timer name expr

    Evaluate `expr`, recording its elapsed time under `name` when timing is
    enabled for this package.

    The expression is evaluated exactly once and its value is returned. The
    macro is intended for instrumentation inside rewriter pipelines; it does
    not change the rewriter contract.
    """
    macro timer(name, expr)
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

    """
        @iftimer expr

    Evaluate `expr` while preserving the package's timing instrumentation
    configuration.
    """
    macro iftimer(expr)
        return esc(expr)
    end

else
    macro timer(name, expr)
        return esc(expr)
    end

    macro iftimer(expr)
    end
end

@doc """
    @timer name expr

Evaluate `expr`, recording its elapsed time under `name` when timing is
enabled for this package. The expression is evaluated exactly once and its
value is returned.
""" var"@timer"

@doc """
    @iftimer expr

Evaluate `expr` while preserving the package's timing instrumentation
configuration.
""" var"@iftimer"

export @timer
export @iftimer
