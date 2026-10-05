@testset "Translator (unit)" begin

    @testset "atoms" begin
        @test translate(MInteger(42))    == "42"
        @test translate(MInteger(-3))    == "-3"
        @test translate(MReal(3.14))     == "3.14"
        @test translate(MSymbol("x"))    == "x"
        @test translate(MSymbol("Pi"))   == "pi"
        @test translate(MSymbol("E"))    == "MathConstants.e"
        @test translate(MSymbol("I"))    == "im"
        @test translate(MSymbol("True")) == "true"
        @test translate(MString("hi"))   == "\"hi\""
    end

    @testset "Plus" begin
        e = MExprNode("Plus", MExpr[MSymbol("a"), MSymbol("b")])
        @test translate(e) == "a + b"

        e3 = MExprNode("Plus", MExpr[MSymbol("a"), MSymbol("b"), MSymbol("c")])
        @test translate(e3) == "a + b + c"
    end

    @testset "subtraction (Times[-1, x])" begin
        neg_b = MExprNode("Times", MExpr[MInteger(-1), MSymbol("b")])
        e = MExprNode("Plus", MExpr[MSymbol("a"), neg_b])
        @test translate(e) == "a - b"
    end

    @testset "Times" begin
        e = MExprNode("Times", MExpr[MSymbol("a"), MSymbol("b")])
        @test translate(e) == "a * b"
    end

    @testset "Times[-1, x] → -x" begin
        e = MExprNode("Times", MExpr[MInteger(-1), MSymbol("x")])
        @test translate(e) == "-x"
    end

    @testset "division Times[a, Power[b,-1]]" begin
        e = MExprNode("Times", MExpr[MSymbol("a"),
                MExprNode("Power", MExpr[MSymbol("b"), MInteger(-1)])])
        @test translate(e) == "a / b"
    end

    @testset "Power" begin
        e = MExprNode("Power", MExpr[MSymbol("x"), MInteger(2)])
        @test translate(e) == "x^2"
    end

    @testset "parenthesization: Times[Plus[a,b], c]" begin
        e = MExprNode("Times", MExpr[
            MExprNode("Plus", MExpr[MSymbol("a"), MSymbol("b")]),
            MSymbol("c")])
        @test translate(e) == "(a + b) * c"
    end

    @testset "Pattern stripped" begin
        pat = MExprNode("Pattern", MExpr[MSymbol("x"),
                    MExprNode("Blank", MExpr[])])
        @test translate(pat) == "x"
    end

    @testset "List" begin
        e = MExprNode("List", MExpr[MInteger(1), MInteger(2), MInteger(3)])
        @test translate(e) == "[1, 2, 3]"
    end

    @testset "CompoundExpression" begin
        e = MExprNode("CompoundExpression",
                MExpr[MSymbol("a"), MSymbol("b"), MSymbol("c")])
        @test translate(e) == "begin\na\nb\nc\nend"
    end

    @testset "CompoundExpression retains Null" begin
        e = MExprNode("CompoundExpression",
                MExpr[MSymbol("a"), MSymbol("Null")])
        @test translate(e) == "begin\na\nnothing\nend"
    end

    @testset "CompoundExpression trailing semicolon" begin
        # A trailing semicolon preserves the final Null result.
        @test translate_string("a; b;") == "a\nb\nnothing"
    end

    @testset "Rule" begin
        e = MExprNode("Rule", MExpr[MSymbol("a"), MInteger(1)])
        @test translate(e) == "a => 1"
    end

    @testset "Slot" begin
        @test translate(MExprNode("Slot", MExpr[MInteger(1)])) == "_s1"
        @test translate(MExprNode("Slot", MExpr[MInteger(2)])) == "_s2"
    end

    @testset "Log arity validation" begin
        @test_throws TranslationError translate(MExprNode("Log", MExpr[]))
        @test_throws TranslationError translate(MExprNode("Log", MExpr[MSymbol("x"), MSymbol("y"), MSymbol("z")]))
    end

    @testset "unsupported constructs throw TranslationError" begin
        @test_throws TranslationError translate(MExprNode("If",    MExpr[MSymbol("c"), MInteger(1), MInteger(-1)]))
        @test_throws TranslationError translate(MExprNode("Do",    MExpr[MSymbol("body"), MSymbol("iter")]))
        @test_throws TranslationError translate(MExprNode("While", MExpr[MSymbol("cond"), MSymbol("body")]))
        @test_throws TranslationError translate(MExprNode("For",   MExpr[MSymbol("init"), MSymbol("test"), MSymbol("incr"), MSymbol("body")]))
        @test_throws TranslationError translate(MExprNode("Dot",   MExpr[MSymbol("A"), MSymbol("B")]))
        @test_throws TranslationError translate(MExprNode("Transpose", MExpr[MSymbol("A")]))
        @test_throws TranslationError translate(MExprNode("Inverse",   MExpr[MSymbol("A")]))
    end

    @testset "TranslationError source location" begin
        e_no_loc = TranslationError("something failed")
        @test e_no_loc.line == 0
        @test e_no_loc.col  == 0
        @test sprint(showerror, e_no_loc) == "TranslationError: something failed"

        e_with_loc = TranslationError("something failed", 5, 12)
        @test e_with_loc.line == 5
        @test e_with_loc.col  == 12
        @test sprint(showerror, e_with_loc) == "TranslationError at 5:12: something failed"
    end

end

@testset "embedded expressions" begin
    @test translate_string("(# + 1 &)[2]") == "((_s1) -> _s1 + 1)(2)"
    @test Core.eval(Module(), Meta.parse(translate_string("(# + 1 &)[2]"))) == 3
    @test translate_string("(x -> 1) + y") == "(x => 1) + y"
    @test translate_string("(x = 1) + 2") == "(x = 1) + 2"
    @test Core.eval(Module(), Meta.parse(translate_string("(x = 1) + 2"))) == 3
end
