# wolfram2julia

A command-line tool and Julia library that translates Wolfram Mathematica expressions to Julia code.

## Architecture

This project is a compiler pipeline: **source text → tokens → AST → Julia string**. Each stage is a separate file.

### Pipeline stages

1. **Lexer** ([src/lexer.jl](src/lexer.jl)) — Converts Wolfram source to a flat `Token` stream. Handles Mathematica-specific syntax: `1.5*^3` scientific notation, pattern bindings (`x_`, `x_Integer`, `__`, `___`), anonymous function slots (`#`, `#1`, `##`), and nested comments `(* ... *)`.

2. **Parser** ([src/parser.jl](src/parser.jl)) — Recursive-descent parser that produces an AST. Infix expressions are lowered to FullForm during parsing (e.g., `a - b` → `Plus[a, Times[-1, b]]`). Throws `ParseError` with line/column on syntax errors.

3. **AST** ([src/ast.jl](src/ast.jl)) — Five node types, all subtypes of abstract `MExpr`: `MInteger`, `MReal`, `MSymbol`, `MString`, `MExprNode`. Compound expressions use `MExprNode(head, args)` mirroring Mathematica's FullForm. Use `is_head(e, "Plus")` and `head_name(e)` for pattern matching.

4. **Translator** ([src/translator.jl](src/translator.jl)) — Walks the AST and emits Julia strings. Key translation rules:
   - `SetDelayed[f[x_], body]` → `f(x) = body` (function definitions)
   - `Function[{x}, body]` and `body &` slot-style → Julia lambdas
   - `Times[a, Power[b,-1]]` → `a / b` (division pattern)
   - `{a, b}` → `[a, b]` (lists)
   - `x -> 5` → `x => 5` (rules)
   - Compound expressions (`;`) → newline-separated statements
   - Throws `TranslationError` for unsupported constructs.

5. **CLI** ([src/cli.jl](src/cli.jl)) — Entry point wrapping `translate_string`/`translate_file`, with `--help`/`--version` flags.

### Design decisions

- The parser normalizes both infix (e.g., `a + b`) and FullForm (e.g., `Plus[a, b]`) input into the same AST, so the translator only needs to handle FullForm.
- Parenthesization in the translator is precedence-aware to avoid redundant parens.
- Type annotations in patterns (`x_Integer`) are parsed but currently silently dropped—the variable name is used without a Julia type annotation.
