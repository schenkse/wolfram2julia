@testset "Lexer" begin

    function kinds(src)
        [t.kind for t in tokenize(src) if t.kind != TK_EOF]
    end
    function lexemes(src)
        [t.lexeme for t in tokenize(src) if t.kind != TK_EOF]
    end

    @testset "literals" begin
        @test kinds("42")       == [TK_INTEGER]
        @test kinds("3.14")     == [TK_REAL]
        @test kinds("\"hello\"") == [TK_STRING]
        @test lexemes("42")[1]  == "42"
        @test lexemes("3.14")[1] == "3.14"
        @test lexemes("\"hi\"")[1] == "hi"
    end

    @testset "symbols" begin
        @test kinds("x")    == [TK_SYMBOL]
        @test kinds("Sin")  == [TK_SYMBOL]
        @test kinds("Pi")   == [TK_SYMBOL]
        @test lexemes("myFunc")[1] == "myFunc"
    end

    @testset "delimiters" begin
        @test kinds("[ ] ( ) { } ,") == [TK_LBRACKET, TK_RBRACKET,
                                         TK_LPAREN, TK_RPAREN,
                                         TK_LBRACE, TK_RBRACE,
                                         TK_COMMA]
    end

    @testset "single-char operators" begin
        @test kinds("+ - * / ^ ! & ;") == [TK_PLUS, TK_MINUS, TK_TIMES,
                                            TK_DIVIDE, TK_POWER, TK_BANG,
                                            TK_AMPERSAND, TK_SEMICOLON]
    end

    @testset "multi-char operators" begin
        @test kinds(":=")  == [TK_SETDELAYED]
        @test kinds("->")  == [TK_RULE]
        @test kinds(":>")  == [TK_RULEDELAYED]
        @test kinds("@@")  == [TK_ATAT]
        @test kinds("/.")  == [TK_SLASHDOT]
        @test kinds("=")   == [TK_SET]
    end

    @testset "blank tokens after symbol" begin
        toks = tokenize("x_")
        @test toks[1].kind == TK_BLANK
        @test toks[1].lexeme == "x_"

        toks2 = tokenize("x__")
        @test toks2[1].kind == TK_BLANKSEQ
        @test toks2[1].lexeme == "x__"

        toks3 = tokenize("x___")
        @test toks3[1].kind == TK_BLANKSEQSEQ

        # Typed blank: x_Integer
        toks4 = tokenize("x_Integer")
        @test toks4[1].kind == TK_BLANK
        @test toks4[1].lexeme == "x_Integer"

        # Space between symbol and _ → separate tokens
        toks5 = tokenize("x _")
        @test toks5[1].kind == TK_SYMBOL
        @test toks5[2].kind == TK_BLANK
    end

    @testset "standalone blank" begin
        toks = tokenize("_")
        @test toks[1].kind == TK_BLANK
        @test toks[1].lexeme == "_"
    end

    @testset "standalone blank with type" begin
        toks = tokenize("_Integer")
        @test toks[1].kind == TK_BLANK
        @test toks[1].lexeme == "_Integer"
        @test length(toks) == 2
    end

    @testset "slots" begin
        toks = tokenize("#")
        @test toks[1].kind == TK_SLOT
        @test toks[1].lexeme == "#"

        toks2 = tokenize("#2")
        @test toks2[1].kind == TK_SLOT
        @test toks2[1].lexeme == "#2"

        toks3 = tokenize("##")
        @test toks3[1].kind == TK_SLOTSEQ

        toks4 = tokenize("##2")
        @test toks4[1].kind == TK_SLOTSEQ
        @test toks4[1].lexeme == "##2"
    end

    @testset "comments" begin
        # Simple comment skipped
        @test kinds("(* hello *) x") == [TK_SYMBOL]

        # Nested comment
        @test kinds("(* outer (* inner *) rest *) y") == [TK_SYMBOL]

        # Comment between tokens
        ks = kinds("a (* comment *) + b")
        @test ks == [TK_SYMBOL, TK_PLUS, TK_SYMBOL]
    end

    @testset "scientific notation" begin
        toks = tokenize("1.5*^3")
        @test toks[1].kind == TK_REAL
        @test parse(Float64, toks[1].lexeme) ≈ 1500.0
    end

    @testset "multitoken expressions" begin
        ks = kinds("f[x_, y_] := x + y")
        @test ks == [TK_SYMBOL, TK_LBRACKET, TK_BLANK, TK_COMMA,
                     TK_BLANK, TK_RBRACKET, TK_SETDELAYED,
                     TK_SYMBOL, TK_PLUS, TK_SYMBOL]
    end

end

@testset "lexer byte bounds" begin
    @test tokenize("")[end].kind == TK_EOF
    @test length(tokenize(repeat("x + 1; ", 1000))) == 4001
end

@testset "Unicode scanning" begin
    tokens = tokenize("αβ + \"λ🌍\" (* 日本 *) γ_")
    @test tokens[1].lexeme == "αβ"
    @test tokens[2].col == 4
    @test tokens[3].lexeme == "λ🌍"
    @test translate_string("αβ + γ") == "αβ + γ"
    @test is_head(parse_string("γ_")[1], "Pattern")
    err = try tokenize("αβ ?"); catch e; e; end
    @test err isa LexError
    @test err.col == 4
end

@testset "unterminated strings" begin
    for source in ("  \"abc", "  \"abc\\")
        err = try tokenize(source); catch e; e; end
        @test err isa LexError
        @test (err.line, err.col) == (1, 3)
    end
    @test tokenize("\"\"")[1].lexeme == ""
end

@testset "unterminated comments" begin
    for source in ("\n  (* abc", "\n  (* outer (* inner *)")
        err = try tokenize(source); catch e; e; end
        @test err isa LexError
        @test (err.line, err.col) == (2, 3)
    end
end

@testset "string line continuations" begin
    for newline in ("\n", "\r\n")
        source = "\"α\\" * newline * "β\""
        @test tokenize(source)[1].lexeme == "αβ"
        @test Core.eval(Module(), Meta.parse(translate_string(source))) == "αβ"
    end
end
