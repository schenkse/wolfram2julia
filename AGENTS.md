# wolfram2julia

A source translator for a numerical subset of Wolfram Mathematica. Keep the compiler pipeline: source text → tokens → AST → Julia string.

## Pipeline

- `src/lexer.jl` uses byte offsets and valid Julia string indices. Columns count characters. It preserves real literal digits, normalizes scientific notation, emits newline tokens, and reports unterminated strings/comments at their opening location.
- `src/parser.jl` lowers infix syntax to FullForm. Delimiter depth distinguishes top-level newline boundaries from multiline bracketed input. One delimiter-aware argument parser handles calls and lists. Compounds retain every `Null`.
- `src/ast.jl` defines five `MExpr` subtypes. `MInteger.value` is `Union{Int64,BigInt}`. `MReal` retains a numeric `.value` and normalized `.literal` spelling. `MExprNode` carries optional `.line`/`.col`, defaulting to zero for manual constructors. Equality ignores locations and compares numeric values. Use `is_head` and `head_name` for matching.
- `src/translator.jl` emits strings with precedence-aware grouping. Program compounds become statements; compounds used as values become `begin … end` expressions. A translation context tracks sequence bindings, the current slot tuple, and generated requirements. Keep that context local to each translation and respect function scope.
- `src/cli.jl` validates options and separates output from diagnostics. Expected lexer/parser/translation/file failures return status 1 without stack traces. Source diagnostics include filename, line, column, source, and caret. The launcher resolves its own symlink before activating the project.

## Translation conventions

- Both `=` and `:=` share function-pattern validation. Known constraints map to `Integer`, `AbstractFloat`, `String`, `Symbol`, and `Complex`; unknown constraints fail. Only the final parameter may be a sequence. `__` requires an argument; `___` permits none. Sequence bindings are tuples and splice into calls/lists.
- Pure functions bind argument tuples for slots, accept unused extra arguments, and isolate nested slot scopes. Slots outside their function and `#0` fail.
- `Max`/`Min` flatten literal lists. Dynamic nested lists use one generated recursive helper; empty inputs yield infinities and nonempty integer results remain integers.
- Source translation emits `import Statistics` once for `Mean`, plus required helpers. Single-node `translate` omits imports and wraps required helper definitions in one `begin` expression.
- Preserve ordinary Julia numeric behavior. Integer literals remain exact; real literal spelling preserves digits without arbitrary-precision arithmetic. Reject floating-point literal overflow with a source location.
- Custom heads pass through as Julia calls. Keep unsupported control-flow and matrix operations explicit errors. Assignment evaluation and symbolic computation retain the limitations documented in README.md.

## Verification

Use focused parser/output/execution tests for semantic changes and CLI subprocess tests for process behavior. Run `Pkg.test()` for final verification. Use `benchmarks/translation.jl` for warmed measurements; timing thresholds belong outside CI. Julia 1.10 is the minimum supported version.
