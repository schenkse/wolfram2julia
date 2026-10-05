# Translation measurements

Measured locally on macOS ARM64 with Julia 1.13.1 and compiled modules disabled. Timings are warmed wall-clock samples, excluding startup. They are observations, not CI thresholds.

## Lexer

The original lexer repeatedly computed character length while scanning byte positions. Replacing those scans with constant-time byte bounds and using valid Unicode indices removed the quadratic growth.

| Approximate input bytes | Original seconds | Final seconds |
|---|---:|---:|
| 10,000 | 0.324 | 0.000260 |
| 20,000 | 1.299 | 0.000566 |
| 40,000 | 5.169 | 0.000931 |

Inputs repeat `x + 1; ` and have 9,996, 19,999, and 39,998 bytes. Original numbers are one warmed sample; final numbers are the minimum of five warmed samples. The trend is quadratic before the bounds fix and linear afterward.

## Parser and translator allocations

These measurements compare the implementation immediately before the final allocation changes with the implementation afterward, keeping the corrected semantics and location metadata in both versions. Parser figures exclude tokenization. Translator figures use an already parsed AST.

| Workload | Parser before | Parser after | Translator before | Translator after |
|---|---:|---:|---:|---:|
| 1,000 top-level atoms | 163,152 | 35,152 | 50,384 | 42,064 |
| 1,000 calls with arithmetic in a list | 787,424 | 595,296 | 1,948,496 | 1,652,176 |

All figures are allocated bytes. Atomic expressions no longer allocate unused additive/multiplicative argument vectors. Translation joins consume generators instead of temporary arrays of strings. Recursive string emission remains in place.

Reproduce the workloads with:

```bash
julia --compiled-modules=no --project=. benchmarks/translation.jl
```
