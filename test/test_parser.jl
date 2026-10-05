@testset "Parser" begin

    function parse1(src)
        stmts = parse_string(src)
        @test length(stmts) == 1
        stmts[1]
    end

    @testset "atoms" begin
        @test parse1("42")    == MInteger(42)
        @test parse1("3.14")  == MReal(3.14)
        @test parse1("x")     == MSymbol("x")
        @test parse1("\"hi\"") == MString("hi")
    end

    @testset "FullForm Plus" begin
        e = parse1("Plus[a, b]")
        @test is_head(e, "Plus")
        @test e.args == MExpr[MSymbol("a"), MSymbol("b")]
    end

    @testset "infix Plus n-ary" begin
        e = parse1("a + b + c")
        @test is_head(e, "Plus")
        @test length(e.args) == 3
        @test e.args[1] == MSymbol("a")
        @test e.args[2] == MSymbol("b")
        @test e.args[3] == MSymbol("c")
    end

    @testset "subtraction → Times[-1, x]" begin
        e = parse1("a - b")
        @test is_head(e, "Plus")
        @test e.args[1] == MSymbol("a")
        neg = e.args[2]
        @test is_head(neg, "Times")
        @test neg.args[1] == MInteger(-1)
        @test neg.args[2] == MSymbol("b")
    end

    @testset "division → Power[b,-1]" begin
        e = parse1("a / b")
        @test is_head(e, "Times")
        @test e.args[1] == MSymbol("a")
        inv = e.args[2]
        @test is_head(inv, "Power")
        @test inv.args[2] == MInteger(-1)
    end

    @testset "Power right-associative" begin
        e = parse1("a^b^c")
        @test is_head(e, "Power")
        @test e.args[1] == MSymbol("a")
        inner = e.args[2]
        @test is_head(inner, "Power")
        @test inner.args[1] == MSymbol("b")
        @test inner.args[2] == MSymbol("c")
    end

    @testset "unary minus" begin
        e = parse1("-x")
        @test is_head(e, "Times")
        @test e.args[1] == MInteger(-1)
        @test e.args[2] == MSymbol("x")
    end

    @testset "function call" begin
        e = parse1("f[x]")
        @test is_head(e, "f")
        @test e.args == MExpr[MSymbol("x")]
    end

    @testset "nested call" begin
        e = parse1("Sin[Pi]")
        @test is_head(e, "Sin")
        @test e.args[1] == MSymbol("Pi")
    end

    @testset "SetDelayed with pattern" begin
        e = parse1("f[x_] := x^2")
        @test is_head(e, "SetDelayed")
        lhs = e.args[1]
        @test is_head(lhs, "f")
        pat = lhs.args[1]
        @test is_head(pat, "Pattern")
        @test pat.args[1] == MSymbol("x")
        @test is_head(pat.args[2], "Blank")
        rhs = e.args[2]
        @test is_head(rhs, "Power")
    end

    @testset "SetDelayed multi-arg" begin
        e = parse1("f[x_, y_] := x + y")
        lhs = e.args[1]
        @test length(lhs.args) == 2
        @test is_head(lhs.args[1], "Pattern")
        @test is_head(lhs.args[2], "Pattern")
    end

    @testset "typed pattern x_Integer" begin
        e = parse1("f[x_Integer] := x")
        lhs = e.args[1]
        pat = lhs.args[1]
        @test is_head(pat, "Pattern")
        blank = pat.args[2]
        @test is_head(blank, "Blank")
        @test blank.args[1] == MSymbol("Integer")
    end

    @testset "Function with List" begin
        e = parse1("Function[{x}, x^2]")
        @test is_head(e, "Function")
        vars = e.args[1]
        @test is_head(vars, "List")
        @test vars.args[1] == MSymbol("x")
    end

    @testset "pure function short form" begin
        e = parse1("#^2 &")
        @test is_head(e, "Function")
        body = e.args[1]
        @test is_head(body, "Power")
        @test is_head(body.args[1], "Slot")
    end

    @testset "list literal" begin
        e = parse1("{1, 2, 3}")
        @test is_head(e, "List")
        @test e.args == MExpr[MInteger(1), MInteger(2), MInteger(3)]
    end

    @testset "CompoundExpression" begin
        stmts = parse_string("a; b; c")
        @test length(stmts) == 1
        e = stmts[1]
        @test is_head(e, "CompoundExpression")
        @test length(e.args) == 3
    end

    @testset "parenthesized grouping" begin
        e = parse1("(a + b) * c")
        @test is_head(e, "Times")
        @test is_head(e.args[1], "Plus")
    end

    @testset "ParseError on bad input" begin
        @test_throws ParseError parse_string("f[")
    end

end

@testset "prefix application" begin
    @test translate_string("f@g@x") == "f(g(x))"
    @test translate_string("f@g[x]") == "f(g(x))"
    @test translate_string("f[x]@g[y]") == "f(x)(g(y))"
    @test Core.eval(Module(), Meta.parse(translate_string("Sin@Cos[0]"))) == sin(cos(0))
end

@testset "multiplication and input boundaries" begin
    @test translate_string("2 x (a + b)") == "2 * x * (a + b)"
    @test length(parse_string("x\ny")) == 2
    @test translate_string("x +\n y") == "x + y"
    @test translate_string("f[x_] :=\n x^2") == "f(x) = x^2"
    @test translate_string("f[\nx\n y\n]") == "f(x * y)"
    @test translate_string("x \\\n y") == "x * y"
    @test translate_string("(2\n 3)") == "2 * 3"
    @test_throws ParseError parse_string("f[x}")
    @test_throws ParseError parse_string("x @@ y")
end

@testset "nested compound parsing" begin
    @test is_head(parse_string("(a;b)")[1], "CompoundExpression")
    @test is_head(parse_string("f[a;b]")[1].args[1], "CompoundExpression")
    @test is_head(parse_string("{a;b, c}")[1].args[1], "CompoundExpression")
    @test parse_string("a;")[1].args[end] == MSymbol("Null")
    @test parse_string("(a;)")[1].args[end] == MSymbol("Null")
    @test parse_string("f[a;, b]")[1].args[1].args[end] == MSymbol("Null")
    @test length(parse_string("a;;")[1].args) == 3
end
