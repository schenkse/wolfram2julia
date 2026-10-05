# wolfram2julia

A command-line tool and Julia library that translates a numerical subset of Wolfram Mathematica expressions to Julia code. It accepts infix syntax such as `a + b` and FullForm syntax such as `Plus[a, b]`.

This project was developed with assistance from AI coding agents, including Claude Code and Codex.

## Installation and use

Requires Julia 1.10 or later. The only runtime dependency is the `Statistics` standard library.

```bash
git clone <repo-url>
cd wolfram2julia
julia --project=. -e 'using Pkg; Pkg.instantiate()'
ln -s "$(pwd)/bin/wolfram2julia" ~/.local/bin/wolfram2julia

wolfram2julia input.wl
echo 'Sin[Pi] + x^2' | wolfram2julia
wolfram2julia - < input.wl
wolfram2julia -- -filename.wl
```

The launcher resolves symlinks, so it works from any directory. `--help` and `--version` print information without reading input. Help takes precedence if both appear. The CLI validates all arguments first, rejects unknown options, and accepts one filename or `-` for stdin. With no filename, it reads piped input.

Successful translation goes to stdout. Expected input, translation, and file errors return status 1 and go to stderr without a stack trace. Source errors include the filename or `<stdin>`, line, character column, source line, and caret.

```text
<stdin>:1:5: TranslationError: If is not yet supported
Sin[If[x,1,2]]
    ^
```

Each CLI process incurs Julia startup and compilation costs. Use the library for repeated translations:

```julia
using Pkg
Pkg.activate("/path/to/wolfram2julia")
using Wolfram2Julia

translate_string("f[x_Integer] := x^2")  # "f(x::Integer) = x^2"
translate_file("expressions.wl")
translate(MExprNode("Plus", MInteger(1), MInteger(2)))  # "1 + 2"
```

The library throws `LexError`, `ParseError`, or `TranslationError`, with line and column when source information is available.

## Supported behavior

| Input | Julia behavior |
|---|---|
| Arithmetic `+ - * / ^`, unary signs | Preserves grouping, denominator products, and power associativity |
| `2 x`, `a (b + c)` | Implicit multiplication |
| `f@g@x`, `f@g[x]` | Prefix application, `f(g(x))` |
| Unicode symbols and strings | Scanned using character boundaries; nested comments are skipped |
| `1.`, `.5`, `1.234*^3` | `1.0`, `0.5`, `1.234e3`; mantissa digits are retained |
| Large integer literals | Exact decimal literals, parsed beyond `Int64` as `BigInt` |
| `f[x_] := body`, `f[x_] = body` | Julia function definitions with the same pattern validation |
| `Function[{x}, body]`, `body &` | Lambdas that accept unused extra arguments |
| `#`, `#n`, `##`, `##n` | Slots and argument tuples, with independent nested function scopes |
| `{a,b}`, `x -> y`, `x :> y` | Lists, pairs, and pairs with a thunk for the delayed value |
| `a; b;` | Statements ending in `nothing`; nested compounds use `begin … end` |
| Unknown heads | Generic calls, for example `Foo[x]` becomes `Foo(x)` |

Spaces between operands imply multiplication. A newline ends a complete top-level expression. Expressions continue across newlines after an operator, inside brackets, or with an explicit backslash at the end of a line. This follows [Wolfram input syntax](https://reference.wolfram.com/language/tutorial/InputSyntax.html).

Real literals use ordinary Julia floating-point semantics, including rounding and underflow. Literals outside Julia's floating-point literal range are rejected with a source location. Preserving decimal spelling does not add arbitrary-precision real arithmetic.

Function patterns map `Integer` to Julia `Integer`, `Real` to `AbstractFloat`, and `String`, `Symbol`, and `Complex` to the corresponding Julia types. Unknown constraints produce errors. A final `x__` binds a tuple of at least one argument; `x___` also permits zero. Typed forms such as `x__Integer` constrain every argument. Multiple or non-final sequence parameters are rejected. Sequence bindings splice into calls and lists, while a direct sequence result remains a tuple.

```text
f[x___Integer] := {x}    → f(x::Integer...) = [x...]
(##2 &)[1,2,3]          → (2, 3) when executed
```

Slots outside a slot-style pure function, `#0`, and nonnumeric slot indices produce errors.

Supported math functions include `Sin`, `Cos`, `Tan`, `ArcSin`, `ArcCos`, `ArcTan`, `Exp`, `Log`, `Sqrt`, `Abs`, `Sign`, `Floor`, `Ceiling`, `Round`, `Factorial`, `Mod`, `Max`, `Min`, `GCD`, `LCM`, `Re`, `Im`, `Conjugate`, `Log2`, `Log10`, `Total`, and `Mean`. The real two-argument `ArcTan[x,y]` becomes `atan(y,x)`.

`Max` and `Min` accept scalars and recursively nested lists, including variables containing lists. Empty inputs yield `-Inf` and `Inf`, respectively. Nonempty integer inputs retain integer results. Literal lists flatten directly; dynamic inputs cause one recursive helper to be emitted.

`Mean` requires one argument. `translate_string` and `translate_file` emit `import Statistics` once when needed and include any extrema helper. `translate` omits imports; the caller must make `Statistics` available. If a single-node translation needs an extrema helper, it returns one `begin` expression containing the helper and the value.

Constants map as follows: `Pi` to `pi`, `E` to `MathConstants.e`, `I` to `im`, `Infinity` to `Inf`, `True`/`False` to `true`/`false`, and `Null` to `nothing`.

## Semantic limits

This is a source translator, not a Wolfram evaluator. Julia evaluates assignments and function definitions differently from Wolfram, especially immediate versus delayed evaluation. Symbolic algebra, general pattern matching, arbitrary-precision real numbers, and Wolfram's general sequence evaluation rules are outside this numerical subset. Explicit control flow such as `If`, `Do`, `While`, and `For`, and matrix operations such as `Dot`, `Transpose`, and `Inverse`, produce translation errors. Notebook `.nb` files are unsupported. Generic custom calls require suitable Julia definitions.

## Development

The compiler pipeline is source text → tokens → AST → Julia string. See [AGENTS.md](AGENTS.md) for implementation conventions.

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=. benchmarks/translation.jl
```

The benchmark is a manual measurement tool, with no timing assertions. Recorded results are in [docs/performance.md](docs/performance.md).
