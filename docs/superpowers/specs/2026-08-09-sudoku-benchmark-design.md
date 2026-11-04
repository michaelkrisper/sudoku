# Sudoku Solver Benchmark — Design

Date: 2026-08-09
Repo: michaelkrisper/sudoku

## Goal

Benchmark of 5 sudoku algorithms plus one multithreading variant
in 7 languages (42 implementations), focused on maximum performance
per language (compiler flags, cache layout, micro-optimizations).
The solvers stay minimal (plain stdin/stdout programs); tables and
charts are produced exclusively by the harness. Normalized reference results
come from GitHub Actions; local runs are for development.

## Algorithms

| Key      | Description |
|----------|--------------|
| `naive`  | Backtracking, first empty cell, digits 1–9 in order. Baseline (matches the old notebook). |
| `mrv`    | Backtracking with bitmask candidates (27 masks: 9 rows, 9 columns, 9 boxes) and most-constrained-cell selection (fewest candidates first, `popcnt`/`tzcnt`). |
| `norvig` | Constraint propagation after Peter Norvig: elimination + naked singles as fixed-point iteration, then search with MRV. |
| `dlx`    | Knuth's Algorithm X with Dancing Links; sudoku as exact-cover matrix (729 rows × 324 columns). Canonical form for **all** languages: the matrix is built once at startup; per puzzle only the mutable link arrays (L/R/U/D/size) are copied and the clue rows are covered. |
| `rules`  | Purely rule-based, no guessing: naked/hidden singles, naked/hidden pairs, pointing pairs, box-line reduction, X-Wing, Swordfish. May leave puzzles unsolved — the solve rate is part of the result. Must never return a wrong solution. |
| `mrv_mt` | Multithreading variant of `mrv`: a thread pool parallelizes over the puzzles of the batch (puzzle-level parallelism; the search itself stays sequential). Python: `multiprocessing` (GIL); Assembly: pthreads. Report shows speedup over `mrv`. |

## Languages

Python (CPython), JavaScript (Node), Go, Rust, C++, C, x86-64 Assembly
(NASM, Linux syscalls; target machine MacBook Pro 11,1 = Haswell, AVX2/BMI
available).

C and C++ are built with **both** compilers and reported separately —
harness keys `c-gcc`, `c-clang`, `cpp-gcc`, `cpp-clang`. Identical
source, identical flags; the comparison measures code generation.
This gives 9 language variants × 6 algorithms = 54 data points from
42 source files.

Performance requirements:
- C/C++/Rust: `-O3 -march=native -flto` (Rust: `opt-level=3`, `lto=true`, `target-cpu=native`).
- Assembly: NASM, `global main`, linked against libc (`gcc -no-pie -pthread`).
  I/O, parsing, timing and output may use libc; the **solver
  itself must be handwritten assembly** — no call into a C solver.
  Bitmasks in registers, `tzcnt`/`popcnt`/`blsr`/`andn` (Haswell, BMI1/BMI2),
  minimal memory accesses.
- Python: flat arrays instead of nested lists, local name binding in hot loops; numpy only where it is actually faster.
- JavaScript: monomorphic typed arrays (`Uint8Array`/`Uint32Array`).
- Board representation flat everywhere (81 bytes) + 27 bitmasks, cache-friendly.

## I/O contract (identical for all 42 implementations)

- Invocation: `solver [reps] [threads] < puzzles.txt`; both arguments
  optional, default 1. Single-threaded solvers ignore `threads`.
- Input (stdin): one line per puzzle, exactly 81 characters from `0`–`9`
  (`0` = empty cell). Empty lines and lines with `#` are ignored.
- Flow: read and parse all puzzles → start monotonic clock →
  solve loop `reps` times over all puzzles → stop clock.
  Each repetition solves a fresh copy of the unsolved puzzle
  (the copy is part of the measurement, negligible at 81 bytes).
- Output (stdout): one line per puzzle, in input order:
  the 81-digit solution or `UNSOLVED`.
- Output (stderr): exactly one line `ns=<total-nanoseconds>` for the
  complete solve loop (all reps).
- Exit code 0, even with UNSOLVED puzzles.

This keeps interpreter startup and I/O outside the measurement; the
harness picks `reps` so that the measured time is ≥ ~1 s, and divides.

## Puzzle sets (`puzzles/`)

| File | Contents |
|-------|--------|
| `easy.txt` | 50 easy puzzles (many clues) |
| `medium.txt` | 50 medium puzzles |
| `hard.txt` | Norvig's hard95 |
| `extreme.txt` | 17-clue selection + anti-backtracking puzzles (incl. "platinum blonde") |
| `verify.txt` + `verify_solutions.txt` | Verification set with known solutions for the correctness check |

Results are aggregated per set. Each (implementation, set) has
a timeout (default 60 s for the whole run); exceeding it = DNF.

## Harness (`bench/run.py`, a single one for all)

1. **Build:** runs `make` in the repo root; each compiled language has a
   Makefile target, scripting languages need none.
2. **Verify:** runs each implementation on `verify.txt` and
   compares with `verify_solutions.txt`. `rules` may return `UNSOLVED`,
   but never a differing solution. Failure ⇒
   implementation is marked FAIL in the benchmark, not measured.
   Two supplementary checks run separately (not on every benchmark,
   because they take minutes): `tools/crosscheck.sh` checks each
   implementation against the reference solutions of all 207 puzzles,
   `tools/contract_test.sh` checks the edges of the I/O contract
   (comment/empty lines, empty input, contradictory puzzles,
   argument handling, shape of the `ns=` line).
3. **Bench:** per (implementation, set): calibrate reps, run,
   read `ns=`, re-verify solutions. `mrv_mt` runs
   with `threads` = number of CPU cores. At startup the harness clears
   `PR_SET_THP_DISABLE` via `prctl(41,0)` (ctypes), so that local runs
   from Claude sessions have the same THP environment as a normal
   terminal or GitHub runner.
4. **Report:** text table on stdout (µs/puzzle median over sets,
   puzzles/s, solve rate); raw data as JSON to
   `results/<timestamp>.json`.
5. **Cost:** after the timings, `bench/cost.py` measures per implementation
   artifact size (binary or shipped source, plus stripped),
   startup time and resident memory on empty input, and peak RSS while
   solving the `hard` set; per language source lines, toolchain version and
   the duration of a clean build. Deliberately runs *after* the measurement, because
   the clean build replaces the binaries just measured.
   `--no-cost` skips this, `--cost-only <json>` only measures cost afterwards.
6. **README:** generates the results section of the README from the JSON:
   Markdown tables plus chart PNGs (matplotlib) to `assets/` —
   time per algorithm×language (log scale, the range spans several
   orders of magnitude) and solve rate for `rules`. Only the harness
   visualizes; the 42 solvers themselves stick to the minimal I/O contract.

CLI: `bench/run.py [--lang ...] [--algo ...] [--set ...]` for filtering.

## Repo structure

```
sudoku/
├── Makefile                 # builds all compiled implementations
├── algorithms.md            # description of the 6 algorithms
├── puzzles/                 # puzzle sets (see above)
├── impl/
│   ├── python/{naive,mrv,norvig,dlx,rules,mrv_mt}.py + _contract.py
│   ├── javascript/*.js
│   ├── go/*.go              # one standalone main file each
│   ├── rust/                # one Cargo project, 6 binaries + src/lib.rs
│   ├── cpp/*.cpp            # each built once with g++ and clang++
│   ├── c/*.c                # each built once with gcc and clang
│   └── asm/*.asm            # NASM, linked against libc
├── bench/
│   ├── run.py               # build + verify + bench
│   └── report.py            # tables, charts, README generation
├── tools/
│   ├── normalize.py         # foreign formats -> 81-char lines
│   ├── validate_puzzles.py  # validity + uniqueness + reference solutions
│   ├── crosscheck.sh        # all implementations against all 207 puzzles
│   └── contract_test.sh     # I/O contract in edge cases
├── assets/                  # generated chart PNGs for the README
└── results/                 # raw JSON per run (gitignored except github-runner.json)
```

The old `SudokuSolver.ipynb` is deleted (remains in the Git history).

## Error handling

- Invalid puzzles (contradiction in the clues): solver outputs `UNSOLVED`, does not crash.
- Harness treats missing/too few output lines, missing `ns=`, crash or timeout as FAIL/DNF and names the implementation in the report.

## CI: normalized results via GitHub Actions

- `.github/workflows/bench.yml`: `workflow_dispatch` + push to `main`;
  ubuntu-latest; installs toolchains (gcc, g++, rustup, go, node,
  nasm), builds, runs `bench/run.py` in full.
- Results: `results/<sha>.json`, text report and chart PNGs as
  workflow artifacts; on `workflow_dispatch` additionally a commit of the
  README section + `assets/` back to the repo.
- Runner hardware is uniform, but shared — the report states the
  runner CPU (`/proc/cpuinfo`) and the harness takes per measurement
  the median of 3 runs.
- The repo is made public once the complete benchmark has run green
  locally once (before that: testing on this machine).

## Implementation phases

1. Scaffold: repo structure, puzzle sets, reference solutions, harness with verify.
2. Python: all 6 implementations (serves as reference for all others).
3. C: all 6 (template for the remaining compiled languages).
4. C++, Rust, Go, JavaScript.
5. Assembly: naive, mrv, mrv_mt (pthreads), then norvig, dlx, rules.
6. Micro-optimization pass per language, final local full run.
7. CI workflow, repo public, reference run on GitHub runners, results into the README.

Each phase ends with a green verify and a commit.

## Non-goals (deliberately omitted)

- GUI, puzzle generator, difficulty rating.
- Intra-puzzle parallelization (parallel search tree): parallelization is only over puzzles (`mrv_mt`); the 5 core algorithms stay single-threaded so the algorithm comparison stays clean.
