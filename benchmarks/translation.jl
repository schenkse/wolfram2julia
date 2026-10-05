# Manual, warmed measurements. Timing is deliberately outside the test suite.
using Wolfram2Julia

for n in (10_000, 20_000, 40_000)
    source = repeat("x + 1; ", n ÷ 7)
    tokenize(source)
    elapsed = minimum(@elapsed(tokenize(source)) for _ in 1:5)
    println("lexer ", ncodeunits(source), " bytes: ", elapsed, " s")
end

function allocations(tokens, ast)
    parser = @allocated Wolfram2Julia.parse_program!(Wolfram2Julia.Parser(tokens))
    translator = @allocated translate(ast)
    (; parser, translator)
end

for (name, source) in (
    ("atoms", repeat("x\n", 1000)),
    ("calls and arithmetic", "{" * join(fill("f[x] + y*z", 1000), ",") * "}"),
)
    tokens = tokenize(source)
    expressions = parse_string(source)
    ast = length(expressions) == 1 ? only(expressions) : MExprNode("List", expressions)
    allocations(tokens, ast)
    println(name, ": ", allocations(tokens, ast), " bytes")
end
