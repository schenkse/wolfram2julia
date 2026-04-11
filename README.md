# wolfram2julia

A command-line tool and Julia library that translates Wolfram Mathematica expressions to Julia code.

Both infix notation (`a + b`, `f[x_] := ...`) and FullForm notation (`Plus[a, b]`, `SetDelayed[...]`) are supported as input.

> **Built with LLMs:** This project was heavily developed with the assistance of AI language models, in particular [Claude Code](https://claude.ai/code) by Anthropic.

---

## Capabilities

| Category | Supported |
|---|---|
| Arithmetic | `+`, `-`, `*`, `/`, `^`, unary negation, correct precedence |
| Math functions | `Sin/Cos/Tan`, `ArcSin/ArcCos/ArcTan`, `Exp`, `Log`, `Sqrt`, `Abs`, `Floor/Ceiling/Round`, `Factorial`, `Mod`, `Max/Min`, `GCD/LCM`, `Re/Im/Conjugate`, `Log2/Log10`, `Total/Mean` |
| Constants | `Pi → pi`, `E → MathConstants.e`, `I → im`, `Infinity → Inf`, `True/False → true/false`, `Null → nothing` |
| Function definitions | Named (`f[x_] := body`), multi-arg, pure long form (`Function[{x}, body]`), pure short form (`#^2 &`) |
| Collections & rules | `{a, b} → [a, b]`, `x -> 5 → x => 5`, `x :> expr → x => (() -> expr)` |
| Compound expressions | `a; b; c` → newline-separated statements |
| Unknown heads | Passed through as generic calls: `Foo[a, b] → Foo(a, b)` |

**Not yet supported:** control flow (`If`, `While`, `For`, `Do`), matrix ops (`Dot`, `Transpose`, `Inverse`), type annotations from patterns (`x_Integer` → `x`, type dropped), `.nb` notebook files.

---

## Requirements

Julia 1.10 or later. No external dependencies.

---

## Installation

```bash
git clone <repo-url>
cd wolfram2julia
```

To use the CLI, symlink the binary onto your `$PATH`:

```bash
ln -s "$(pwd)/bin/wolfram2julia" ~/.local/bin/wolfram2julia
```

---

## Usage

### CLI

```bash
wolfram2julia input.wl           # translate a file
echo "Sin[Pi] + x^2" | wolfram2julia  # from stdin
wolfram2julia --help
wolfram2julia --version
```

> **Cold-start note:** Each CLI invocation pays a ~1–2 s Julia JIT startup cost. For bulk translation, use the library interface below — it pays this cost only once.

**Examples:**

```
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

### Julia library

```julia
using Pkg; Pkg.activate("/path/to/wolfram2julia")
using Wolfram2Julia

translate_string("f[x_] := x^2 + Sin[x]")   # → "f(x) = x^2 + sin(x)"
translate_file("expressions.wl")             # → translated file contents as string
```

Errors throw typed exceptions: `ParseError` (with line/col) for malformed input and `TranslationError` for unsupported constructs.

---

## Testing

```bash
julia --project=. test/runtests.jl
```
