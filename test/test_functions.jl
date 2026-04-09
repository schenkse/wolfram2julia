@testset "End-to-end functions" begin

    # Named function definitions
    @test translate_string("f[x_] := x^2")           == "f(x) = x^2"
    @test translate_string("f[x_, y_] := x + y")     == "f(x, y) = x + y"
    @test translate_string("f[x_, y_] := x^2 + y^2") == "f(x, y) = x^2 + y^2"
    @test translate_string("square[n_] := n^2")       == "square(n) = n^2"

    # Typed patterns — type annotation stripped in v1
    @test translate_string("f[x_Integer] := x + 1")  == "f(x) = x + 1"

    # Function calls
    @test translate_string("f[x]")                   == "f(x)"
    @test translate_string("f[x, y]")                == "f(x, y)"
    @test translate_string("g[f[x]]")                == "g(f(x))"

    # Pure functions
    @test translate_string("Function[{x}, x^2]")     == "(x) -> x^2"
    @test translate_string("Function[{x, y}, x + y]") == "(x, y) -> x + y"
    @test translate_string("Function[x, x^2]")       == "x -> x^2"

    # Short-form pure function
    @test translate_string("#^2 &")                  == "(_s1) -> _s1^2"
    @test translate_string("# + 1 &")               == "(_s1) -> _s1 + 1"

    # CompoundExpression
    @test translate_string("a; b; c")                == "a\nb\nc"
    @test translate_string("a; b")                   == "a\nb"

    # Set (plain assignment)
    @test translate_string("x = 5")                  == "x = 5"

    # Rule
    @test translate_string("x -> 5")                 == "x => 5"

end
