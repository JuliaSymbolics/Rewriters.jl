using Rewriters
using TermInterface
using Test

struct TestNode
    operation::Symbol
    arguments::Vector{Any}
end

Base.:(==)(a::TestNode, b::TestNode) =
    a.operation == b.operation && a.arguments == b.arguments

TermInterface.istree(::TestNode) = true
TermInterface.operation(x::TestNode) = x.operation
TermInterface.arguments(x::TestNode) = x.arguments
TermInterface.similarterm(::TestNode, operation, arguments; kwargs...) =
    TestNode(operation, Any[arguments...])
TermInterface.node_count(x::TestNode) = 1 + sum(node_count, x.arguments; init=0)

@testset "Rewriter contracts" begin
    @test Empty()(:x) === nothing
    @test PassThrough(Empty())(:x) === :x

    @test IfElse(iseven, x -> x + 1, x -> x - 1)(2) == 3
    @test If(iseven, x -> x + 1)(3) === nothing

    @test Chain((x -> x + 1, Empty(), x -> 2x))(1) == 4
    @test Chain((Empty(), Empty()))(:x) === :x

    restarted = RestartedChain((x -> x == 1 ? 2 : nothing,
        x -> x == 2 ? 3 : nothing))
    @test restarted(1) == 3
    @test Fixpoint(x -> x < 3 ? x + 1 : nothing)(1) == 3

    tree = TestNode(:+, Any[TestNode(:*, Any[1, 2]), 3])
    replace_one = PassThrough(x -> x === 1 ? 10 : nothing)
    @test Prewalk(replace_one)(tree) ==
        TestNode(:+, Any[TestNode(:*, Any[10, 2]), 3])
    @test Postwalk(replace_one)(tree) ==
        TestNode(:+, Any[TestNode(:*, Any[10, 2]), 3])

    seen = Any[]
    recording = PassThrough(x -> (push!(seen, x); nothing))
    Postwalk(recording)(tree)
    @test first(seen) == 1
    @test last(seen) == tree
end
