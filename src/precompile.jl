@setup_workload begin
    expression = :(f(g(1) + 0, 2))
    replace_g = function (x)
        if istree(x) && operation(x) === :g
            similarterm(x, :h, arguments(x))
        else
            nothing
        end
    end
    remove_zero = function (x)
        if istree(x) && operation(x) === :+ && length(arguments(x)) == 2 &&
                isequal(arguments(x)[2], 0)
            arguments(x)[1]
        else
            nothing
        end
    end

    @compile_workload begin
        Prewalk(PassThrough(replace_g))(expression)
        Postwalk(PassThrough(replace_g))(expression)
        Chain((Prewalk(PassThrough(replace_g)), Postwalk(Fixpoint(remove_zero))))(expression)
        Fixpoint(remove_zero)(:(g(1) + 0))
    end
end
