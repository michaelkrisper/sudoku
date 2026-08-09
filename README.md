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

Measured on Intel(R) Core(TM) i5-4258U CPU @ 2.40GHz (4 cores), 2026-08-09 21:39:23. Each number is microseconds per puzzle — median of 3 runs, with the repetition count calibrated so every measured loop runs at least one second. Lower is better; DNF means the 60 s budget for the set ran out.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/time_by_impl_dark.png">
  <img alt="Time per puzzle by implementation, hard set" src="assets/time_by_impl_light.png">
</picture>

<details><summary>easy set (µs per puzzle)</summary>

| language | mrv | rules | mrv_mt |
|---|---|---|---|
| `python` | 495.96 | 2,332.48 | 474.61 |

</details>

### hard set (µs per puzzle)

| language | mrv | rules | mrv_mt |
|---|---|---|---|
| `python` | 20,256.04 | 4,988.66 | 10,768.93 |

### How far pure logic gets you

The `rules` solver never guesses. Whatever it leaves `UNSOLVED` genuinely needs search:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/rules_solve_rate_dark.png">
  <img alt="Share of puzzles solved by logic alone" src="assets/rules_solve_rate_light.png">
</picture>

### Multithreading

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/mt_speedup_dark.png">
  <img alt="Multithreaded speedup by language" src="assets/mt_speedup_light.png">
</picture>

<!-- BENCH:END -->
