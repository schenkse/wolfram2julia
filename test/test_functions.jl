@testset "End-to-end functions" begin

    # Named function definitions
    @test translate_string("f[x_] := x^2")           == "f(x) = x^2"
    @test translate_string("f[x_, y_] := x + y")     == "f(x, y) = x + y"
    @test translate_string("f[x_, y_] := x^2 + y^2") == "f(x, y) = x^2 + y^2"
    @test translate_string("square[n_] := n^2")       == "square(n) = n^2"

    # Typed patterns → Julia type annotations
    @test translate_string("f[x_Integer] := x + 1")  == "f(x::Integer) = x + 1"
    @test translate_string("f[x_Real] := x + 1.0")   == "f(x::AbstractFloat) = x + 1.0"
    @test translate_string("f[x_String] := x")       == "f(x::String) = x"
    @test translate_string("f[x_Symbol] := x")       == "f(x::Symbol) = x"
    @test translate_string("f[x_Complex] := x")      == "f(x::Complex) = x"
    # Unknown constraints fail explicitly.
    @test_throws TranslationError translate_string("f[x_MyType] := x")

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

    # Set with pattern LHS (f[x_] = body)
    @test translate_string("f[x_] = x^2")            == "f(x) = x^2"

    # Rule
    @test translate_string("x -> 5")                 == "x => 5"

end

@testset "compound scope and results" begin
    for (source, expected) in (("f[x_] := (y = x+1; y^2); f[2]", 9), ("f[x_] := (x^2;); f[2]", nothing), ("((#; #+1) &)[2]", 3), ("(1; #+1 &)[2]", 3), ("{(1;2), (3;)}", [2,nothing]), ("Abs[(1; -2)]", 2))
        code = translate_string(source)
        @test Core.eval(Module(), Meta.parse("begin\n" * code * "\nend")) == expected
    end
    @test translate_string("1;Null;2;") == "1\nnothing\n2\nnothing"
end

@testset "consistent function constraints" begin
    for op in ("=", ":=")
        @test translate_string("f[x_Integer] $op x") == "f(x::Integer) = x"
        @test translate_string("f[_Real] $op 1") == "f(_p1::AbstractFloat) = 1"
        @test_throws TranslationError translate_string("f[x_Unknown] $op x")
        @test_throws TranslationError translate_string("f[1] $op 2")
        m = Module()
        Core.eval(m, Meta.parse(translate_string("f[x_Integer] $op x")))
        @test Base.invokelatest(Core.eval(m, :f), big(2)) == big(2)
        Core.eval(m, Meta.parse(translate_string("g[x_Real] $op x")))
        @test Base.invokelatest(Core.eval(m, :g), Float32(2)) isa Float32
    end
end

@testset "sequence patterns" begin
    for (source, expected) in (
        ("f[x___] := x; f[]", ()),
        ("f[x__] := x; f[1,2,3]", (1,2,3)),
        ("f[a_, x__] := {a,x}; f[0,1,2]", [0,1,2]),
        ("f[x___Integer] := Plus[x]; f[1,2,3]", 6),
        ("f[x__Integer] := Max[x]; f[1,2,3]", 3),
        ("f[x___] := g[x]; g[a_, b_] := a+b; f[2,3]", 5),
        ("f[x___] := Function[{x}, {x}]; f[1,2][3]", [3]))
        @test Core.eval(Module(), Meta.parse("begin\n" * translate_string(source) * "\nend")) == expected
    end
    @test_throws MethodError Core.eval(Module(), Meta.parse("begin\n" * translate_string("f[x__] := x; f[]") * "\nend"))
    @test_throws MethodError Core.eval(Module(), Meta.parse("begin\n" * translate_string("f[x___Integer] := x; f[1.5]") * "\nend"))
    @test_throws TranslationError translate_string("f[x__, y_] := x")
    @test_throws TranslationError translate_string("f[x___, y___] := x")
    @test_throws TranslationError translate_string("f[x___Unknown] := x")
end

@testset "slot sequences" begin
    for (source, expected) in (("(## &)[1,2,3]", (1,2,3)), ("(##2 &)[1,2,3]", (2,3)), ("({##2} &)[1,2,3]", [2,3]), ("(Plus[##] &)[1,2,3]", 6), ("({#,##2} &)[1,2,3]", [1,2,3]), ("(## & )[]", ()))
        @test Core.eval(Module(), Meta.parse(translate_string(source))) == expected
    end
end
