@testset "End-to-end arithmetic" begin

    @test translate_string("2 + 3")              == "2 + 3"
    @test translate_string("2 - 3")              == "2 - 3"
    @test translate_string("2 * 3")              == "2 * 3"
    @test translate_string("a / b")              == "a / b"
    @test translate_string("x^2")                == "x^2"
    @test translate_string("-x")                 == "-x"
    @test translate_string("x^2 + y^2")          == "x^2 + y^2"
    @test translate_string("a + b + c")          == "a + b + c"
    @test translate_string("(a + b) * c")        == "(a + b) * c"
    @test translate_string("a * (b + c)")        == "a * (b + c)"
    @test translate_string("a^b^c")              == "a^b^c"

    # FullForm
    @test translate_string("Plus[2, 3]")         == "2 + 3"
    @test translate_string("Times[2, 3]")        == "2 * 3"
    @test translate_string("Power[x, 2]")        == "x^2"
    @test translate_string("Times[2, Plus[3, 4]]") == "2 * (3 + 4)"
    @test translate_string("Plus[Times[2, x], Power[x, 3]]") == "2 * x + x^3"

    # Math functions
    @test translate_string("Sqrt[x]")            == "sqrt(x)"
    @test translate_string("Sin[x]")             == "sin(x)"
    @test translate_string("Cos[x]")             == "cos(x)"
    @test translate_string("Exp[x]")             == "exp(x)"
    @test translate_string("Log[x]")             == "log(x)"
    @test translate_string("Abs[x]")             == "abs(x)"
    @test translate_string("Log[2, x]")          == "log(2, x)"

    # Additional math functions
    @test translate_string("Mod[10, 3]")     == "mod(10, 3)"
    @test translate_string("Max[a, b]")      == "max(a, b)"
    @test translate_string("Max[a, b, c]")   == "max(a, b, c)"
    @test translate_string("Min[a, b]")      == "min(a, b)"
    @test translate_string("GCD[12, 8]")     == "gcd(12, 8)"
    @test translate_string("LCM[4, 6]")      == "lcm(4, 6)"
    @test translate_string("Conjugate[z]")   == "conj(z)"
    @test translate_string("Log2[x]")        == "log2(x)"
    @test translate_string("Log10[x]")       == "log10(x)"
    @test translate_string("Total[{1,2,3}]") == "sum([1, 2, 3])"
    @test translate_string("Mean[{1,2,3}]")  == "Statistics.mean([1, 2, 3])"

    # Symbol remapping
    @test translate_string("Sin[Pi]")            == "sin(pi)"
    @test translate_string("Exp[1]")             == "exp(1)"

    # Factorial
    @test translate_string("5!")                 == "factorial(5)"
    @test translate_string("n!")                 == "factorial(n)"

    # List
    @test translate_string("{1, 2, 3}")          == "[1, 2, 3]"

    # Times[-1] edge case
    @test translate(MExprNode("Times", MExpr[MInteger(-1)])) == "-1"

    # 3-arg negation: Times[-1, x, y] → -x * y
    @test translate(MExprNode("Times", MExpr[MInteger(-1), MSymbol("x"), MSymbol("y")])) == "-x * y"

end

@testset "denominator grouping" begin
    @test translate_string("a/(b*c)") == "a / (b * c)"
    @test translate_string("a/b/c") == "a / b / c"
    @test Core.eval(Module(), Meta.parse(translate_string("24/(2*3)"))) == 4
    @test Core.eval(Module(), Meta.parse(translate_string("24/2/3"))) == 4
end

@testset "power grouping" begin
    @test translate_string("(a^b)^c") == "(a^b)^c"
    @test Core.eval(Module(), Meta.parse(translate_string("(2^3)^2"))) == 64
    for base in (MInteger(-2), MReal(-2.0))
        code = translate(MExprNode("Power", base, MInteger(2)))
        @test startswith(code, "(-2")
        @test Core.eval(Module(), Meta.parse(code)) == 4
    end
end
