# wolfram2julia

A command-line tool and Julia library that translates Wolfram Mathematica expressions to Julia code.

Both infix notation (`a + b`, `f[x_] := ...`) and FullForm notation (`Plus[a, b]`, `SetDelayed[...]`) are supported as input.

---

## Supported features

**Arithmetic & algebra**
- Binary and n-ary operators: `+`, `-`, `*`, `/`, `^`
- Unary negation: `-x`
- Division as `a / b` (from infix `/` or `Times[a, Power[b, -1]]`)
- Correct operator precedence and parenthesization

**Math functions**

| Mathematica | Julia |
|---|---|
| `Sin`, `Cos`, `Tan` | `sin`, `cos`, `tan` |
| `ArcSin`, `ArcCos`, `ArcTan` | `asin`, `acos`, `atan` |
| `Exp` | `exp` |
| `Log[x]` | `log(x)` |
| `Log[b, x]` | `log(b, x)` |
| `Sqrt` | `sqrt` |
| `Abs` | `abs` |
| `Floor`, `Ceiling`, `Round` | `floor`, `ceil`, `round` |
| `Factorial` / `n!` | `factorial(n)` |

**Constants**

| Mathematica | Julia |
|---|---|
| `Pi` | `pi` |
| `E` | `MathConstants.e` |
| `I` | `im` |
| `Infinity` | `Inf` |
| `True` / `False` | `true` / `false` |

**Function definitions**
- Named functions: `f[x_] := body` → `f(x) = body`
- Multi-argument: `f[x_, y_] := body` → `f(x, y) = body`
- Pure functions (long form): `Function[{x}, body]` → `(x) -> body`
- Pure functions (short form): `#^2 &` → `(_s1) -> _s1^2`
- Function calls: `f[x, y]` → `f(x, y)`

**Other**
- Lists: `{1, 2, 3}` → `[1, 2, 3]`
- Rules: `x -> 5` → `x => 5`
- Compound expressions: `a; b; c` → three lines
- Nested comments: `(* ... (* nested *) ... *)`

---

## Installation

**Requirements:** Julia 1.10 or later.

Clone the repository and navigate to it:

```bash
git clone <repo-url>
cd wolfram2julia
```

To use the CLI binary, add it to your PATH. The simplest approach is a symlink:

```bash
ln -s "$(pwd)/bin/wolfram2julia" ~/.local/bin/wolfram2julia
```

Make sure `~/.local/bin` is on your `$PATH` (add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile if needed).

> **Note on startup time:** Julia has a cold-start overhead of ~1–2 seconds per invocation. This is a known Julia limitation for small CLI tools. For bulk translation, prefer the [Julia library interface](#using-as-a-julia-library) which pays this cost only once.

---

## Using as a CLI binary

### From a file

```bash
wolfram2julia input.wl
```

### From stdin (pipe-friendly)

```bash
echo "f[x_] := x^2 + Sin[x]" | wolfram2julia
```

```bash
cat expressions.wl | wolfram2julia > output.jl
```

### Examples

```
$ echo "Sin[Pi] + Cos[0]" | wolfram2julia
sin(pi) + cos(0)

$ echo "f[x_, y_] := Sqrt[x^2 + y^2]" | wolfram2julia
f(x, y) = sqrt(x^2 + y^2)

$ echo "Plus[Times[2, x], Power[x, 3]]" | wolfram2julia
2 * x + x^3

$ echo "#^2 + 1 &" | wolfram2julia
(_s1) -> _s1^2 + 1

$ echo "a; b; c" | wolfram2julia
a
b
c
```

### Options

```
wolfram2julia [options] [file]

Options:
  -h, --help      Show help
  -v, --version   Show version
```

---

## Using as a Julia library

Add the package to your Julia environment:

```julia
julia> ]dev /path/to/wolfram2julia
```

Or activate the project directly:

```julia
using Pkg
Pkg.activate("/path/to/wolfram2julia")
using Wolfram2Julia
```

### `translate_string`

Translate a Mathematica expression string to Julia code:

```julia
julia> translate_string("f[x_] := x^2 + Sin[x]")
"f(x) = x^2 + sin(x)"

julia> translate_string("Plus[Times[2, x], Power[x, 3]]")
"2 * x + x^3"

julia> translate_string("Function[{x, y}, x^2 + y^2]")
"(x, y) -> x^2 + y^2"

julia> translate_string("a; b; c")
"a\nb\nc"
```

Multiple statements separated by `;` are returned joined by newlines.

### `translate_file`

Translate the contents of a `.wl` or `.m` file:

```julia
julia> translate_file("expressions.wl")
"f(x) = x^2\ng(x, y) = x + y"
```

### `translate`

Translate a single `MExpr` AST node directly. Useful when you want to build or inspect the AST yourself:

```julia
julia> e = MExprNode("Plus", MExpr[MSymbol("x"), MExprNode("Power", MExpr[MSymbol("y"), MInteger(2)])])
julia> translate(e)
"x + y^2"
```

### Working with the AST

You can parse a Mathematica string into an AST and inspect or manipulate it before translating:

```julia
julia> stmts = parse_string("f[x_] := x^2 + Sin[x]")
1-element Vector{MExpr}:
 SetDelayed[...]

julia> e = stmts[1]
julia> is_head(e, "SetDelayed")
true

julia> head_name(e.args[2])   # head of the RHS
"Plus"
```

**AST types:**

| Type | Description |
|---|---|
| `MInteger(value)` | Integer literal |
| `MReal(value)` | Floating-point literal |
| `MSymbol(name)` | Symbol / variable |
| `MString(value)` | String literal |
| `MExprNode(head, args)` | Compound expression: `head[args...]` |

**Helper functions:**

```julia
is_head(e, "Plus")      # true if e is MExprNode with head MSymbol("Plus")
head_name(e)            # returns "Plus" or nothing
```

### Error handling

Both `parse_string` and `translate_string` throw typed exceptions on failure:

```julia
try
    translate_string("f[x_")
catch e
    if e isa ParseError
        println("Parse error at $(e.line):$(e.col): $(e.message)")
    end
end
```

| Exception | When thrown |
|---|---|
| `ParseError` | Malformed input (unclosed bracket, unexpected token, etc.) |
| `TranslationError` | AST node that cannot be translated (wrong arity, unsupported form) |

---

## Running the tests

```bash
julia --project=. test/runtests.jl
```

188 tests covering the lexer, parser, translator, and end-to-end arithmetic and function cases.

---

## Project structure

```
wolfram2julia/
├── Project.toml
├── src/
│   ├── Wolfram2Julia.jl    # module root and exports
│   ├── token.jl            # TokenKind enum and Token struct
│   ├── ast.jl              # MExpr AST types and helpers
│   ├── lexer.jl            # tokenizer
│   ├── parser.jl           # recursive-descent parser
│   ├── translator.jl       # MExpr → Julia string
│   └── cli.jl              # CLI entry point
├── test/
│   ├── runtests.jl
│   ├── test_lexer.jl
│   ├── test_parser.jl
│   ├── test_translator.jl
│   ├── test_arithmetic.jl
│   └── test_functions.jl
└── bin/
    └── wolfram2julia       # executable script
```

---

## Limitations (v1)

- **No control flow**: `If`, `Which`, `Do`, `While`, `For` are not yet translated (emitted as generic function calls).
- **No matrix operations**: `Dot`, `Transpose`, `Inverse`, etc. are not yet mapped.
- **Type annotations dropped**: `x_Integer` translates to `x` without a Julia type annotation.
- **Startup latency**: ~1–2 s cold start per CLI invocation due to Julia's JIT compilation. For bulk use, prefer the library interface.
- **No notebook support**: `.nb` files are not parsed; use plain `.wl` or `.m` text files.
