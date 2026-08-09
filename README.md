# sudoku

Benchmark of sudoku solving algorithms — naive backtracking, MRV bitmask,
Norvig constraint propagation, Dancing Links (DLX), a pure rule-based solver
and a multithreaded variant — across Python, JavaScript, Go, Rust, C++, C and
x86-64 assembly.

Every solver is a standalone program with the same contract:

```
solver [reps] [threads] < puzzles.txt
```

- stdin: one puzzle per line, 81 characters `0`-`9` (`0` = empty)
- stdout: one line per puzzle — the 81-digit solution or `UNSOLVED`
- stderr: one line `ns=<nanoseconds>` for the solve loop only

Run the benchmark: `python3 bench/run.py`

<!-- BENCH:BEGIN -->
_No benchmark results yet._
<!-- BENCH:END -->
