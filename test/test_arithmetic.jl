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

end
