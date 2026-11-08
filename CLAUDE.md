# CLAUDE.md

A cross-language benchmark of sudoku solvers: six algorithms (`naive`, `mrv`,
`norvig`, `dlx`, `rules`, `mrv_mt`) in seven languages (Python, JavaScript, Go, Rust,
C++, C, x86-64 assembly); C and C++ are each built with gcc and clang, so nine
measured toolchains. `algorithms.md` explains the algorithms. Nothing is deployed; the
product is the generated report in `README.md`.

## The contract

Every implementation is a standalone program and that is the entire interface:

```
solver [reps] [threads] < puzzles.txt
```

stdin: one puzzle per line, 81 chars `0`-`9`. stdout: the 81-digit solution or
`UNSOLVED`, one line per puzzle. stderr: exactly one line `ns=<nanoseconds>` covering
the solve loop only; puzzles are parsed before the clock starts, so startup and I/O
stay out of the number. Anything new must honour this or the harness cannot see it.

## Commands

No package manager for the solvers. Toolchains: gcc, clang, go, cargo, nasm, node,
python3 (see `.github/actions/toolchains/action.yml`).

```sh
pip install -r requirements-dev.txt   # ruff, pytest, matplotlib (pinned)
ruff check .                          # harness, tools, Python solvers
shellcheck tools/*.sh
pytest -q tests                       # harness, report, puzzle validation, Python solvers
make                                  # build every compiled implementation into build/
python3 bench/run.py --verify         # build + 12-puzzle correctness gate
tools/contract_test.sh                # I/O contract edge cases
TIMEOUT=60 tools/crosscheck.sh easy medium   # all implementations vs reference solutions
python3 bench/run.py                  # full build, verify, benchmark, regenerate README
```

- `make` skips missing sources, so the tree builds at any stage of a port. Binaries
  land in `build/<lang>-<algo>` (`build/c-gcc-mrv`, `build/asm-dlx`, ...). Python and
  JS run from `impl/` directly. Native flags throughout (`-march=native`,
  `target-cpu=native`): binaries are not portable between machines.
- `bench/run.py` options: `--verify`, `--no-cost` (skip size/startup/memory),
  `--cost-only RESULTS.json`, `--readme RESULTS.json` (re-render from a saved run),
  `--lang/--algo/--set` (repeatable). It builds with `make -k` under a file lock.
- `tools/ab.sh <binary-or-command> <set> [reps] [rounds]`: the tool while optimizing
  (`bench/run.py` is far too slow to iterate). Pins one core (`AB_CPU`, default 2),
  calibrates to ~1 s, reports the best run, not the mean.
- `tools/validate_puzzles.py` and `tools/normalize.py` maintain `puzzles/`.
- CI (`ci.yml`): jobs `lint` (ruff, shellcheck), `test` (pytest), `correctness`
  (`--verify`, contract test, crosscheck on easy/medium), then the version tag.

## Benchmark workflow

`.github/workflows/bench.yml` (`benchmark`) is `workflow_dispatch` only: a full run
takes most of an hour and its numbers mean nothing while anything else competes for
the runner. It uploads `README.md`, `assets/*.png` and `results/github-runner.json` as
an artifact; commit those through a normal issue + PR. It never pushes to `main`.

## Measurement rules

- `reps` is calibrated so each measured loop runs at least 1 s (`TARGET_NS`), which
  makes a 3 us and a 3 s solver comparable. Median of three runs, except solvers over
  5 s per pass (measured once). 60 s budget per (implementation, set); exceeding it is
  reported as DNF, not as a failure.
- Implementations that fail verification are excluded from the benchmark, not
  reported. A fast wrong answer is not a result.
- `rules` never guesses, so its output is determined by its technique set: all seven
  languages must leave exactly the same puzzles unsolved, byte for byte. A divergence
  is a bug.
- `bench/run.py` clears `PR_SET_THP_DISABLE` at startup (Claude Code sessions inherit
  it; without the reset solvers see a different transparent-hugepage setup than a
  normal terminal). `tools/ab.sh` does not: wrap the binary in a `prctl(41, 0, ...)`
  exec wrapper when measuring from a Claude session.
- A/B comparisons: measure baseline and candidate with the same `rounds`; best-of-9
  systematically beats best-of-5 and invents ~1 % gains. Sequence: measure candidate,
  `git stash`, delete binaries, `make`, measure baseline, `git stash pop`.
- Never benchmark while builds, tests or other agents run on the machine: shared
  cache, memory bandwidth and turbo budget skew best-of-N even with `taskset`.
- Assembly implementations may link against libc, but the solver core is hand-written.

## Measured and rejected (do not retry)

- `dlx.c`: resetting only the header part of `L`/`R` instead of the whole arrays.
  Within noise (sign flipped between runs) and it adds a hidden invariant that the
  row-node halves are never written, which every later `cover`/`uncover` change would
  trip over.
- DLX reverse-order uncover: large regression, reverted immediately.
- Kept: per-unit `places` instead of a hidden-single scan in `norvig` (C/JS/Python), `UPOS`
  word packing in `norvig.c`.

## Gotchas

- The README section between `<!-- BENCH:BEGIN -->` and `<!-- BENCH:END -->` is
  generated by `bench/report.py`; edit the generator, not the tables. Charts in
  `assets/` come in light/dark pairs referenced through `<picture>`.
- `results/*.json` are local raw runs (gitignored); only `results/github-runner.json`
  is committed, and the published report is rendered from it.
- `impl/python/*.py` keep several statements per line in hot loops on purpose (ruff
  `E702` ignored there). Ruff targets py312, line length 100.
- Design and phase notes live in `docs/superpowers/`.

## Workflow

- Every change starts with a GitHub issue. Branch `<issue>-<slug>` from `main`,
  open a PR with `Closes #<issue>`. Never push to `main` directly.
- PRs auto-merge (squash) once CI and the "Linked ticket" check pass; drafts are not merged.
- Versions exist only as git tags `vX.Y.Z`. Every merge to `main` tags the next patch;
  never edit version numbers in files. Minor/major releases: Actions -> Release.
- Nothing is deployed; benchmark results reach `main` only through a PR.
- Details: CONTRIBUTING.md.
