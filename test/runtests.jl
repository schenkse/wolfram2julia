using Test
using Wolfram2Julia

@testset "Wolfram2Julia" begin
    include("test_lexer.jl")
    include("test_parser.jl")
    include("test_translator.jl")
    include("test_arithmetic.jl")
    include("test_functions.jl")
end
