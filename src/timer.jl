const TIMER_OUTPUTS = true
const being_timed = Ref{Bool}(false)

if TIMER_OUTPUTS
    using TimerOutputs

    """
        @timer name expr

    Evaluate `expr`, recording its elapsed time under `name` when timing is
    enabled for this package.

    The expression is evaluated exactly once and its value is returned. The
    macro is intended for instrumentation inside rewriter pipelines; it does
    not change the rewriter contract.
    """
    macro timer(name, expr)
        :(if being_timed[]
              @timeit $(esc(name)) $(esc(expr))
          else
              $(esc(expr))
          end)
    end

    """
        @iftimer expr

    Evaluate `expr` while preserving the package's timing instrumentation
    configuration.
    """
    macro iftimer(expr)
        esc(expr)
    end

else
    macro timer(name, expr)
        esc(expr)
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
