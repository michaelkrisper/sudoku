# Sudoku Benchmark — Phase 1: Harness + Python Reference — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Working benchmark scaffold: puzzle sets, one shared harness (build/verify/bench/report/README) and all 6 algorithms in Python as reference implementation.

**Architecture:** Each solver is a standalone stdin/stdout program following the I/O contract of the spec (`docs/superpowers/specs/2026-08-09-sudoku-benchmark-design.md`). The harness `bench/run.py` knows all (language, algorithm) pairs, skips missing implementations and is thus, from Task 4 on, the permanent test tool for all later languages.

**Tech Stack:** Python ≥ 3.10 (int.bit_count), matplotlib (harness only), curl (puzzle downloads). No further dependencies.

## Global Constraints

- I/O contract (spec, verbatim): invocation `solver [reps] [threads] < puzzles.txt`, both default 1; input 81-char lines from `0-9`, ignore `#` lines and empty lines; read/parse all puzzles → monotonic clock → solve reps × all puzzles (each repetition on a fresh copy) → stop clock; stdout: per puzzle `81 digits` or `UNSOLVED` in input order; stderr: exactly `ns=<total>`; exit code 0 even with UNSOLVED.
- Invalid puzzles: output `UNSOLVED`, never crash, never a wrong solution.
- Solvers stay minimal: no argument-parser libs, no output beyond the contract.
- Algorithm keys: `naive`, `mrv`, `norvig`, `dlx`, `rules`, `mrv_mt`.
- Commits: concise English messages, no co-author line.

---

### Task 1: Repo scaffold

**Files:**
- Delete: `SudokuSolver.ipynb`
- Create: `.gitignore`, `README.md`, `Makefile`, directories `puzzles/ impl/python/ bench/ tools/ results/ assets/`

**Interfaces:**
- Produces: directory layout per spec; `make` (no-op default target `all`), called by the harness from Task 4 on.

- [ ] **Step 1: Remove notebook, create directories**

```bash
cd /home/michi/sudoku
git rm -q SudokuSolver.ipynb
mkdir -p puzzles impl/python bench tools results assets
touch results/.gitkeep assets/.gitkeep
```

- [ ] **Step 2: .gitignore**

```gitignore
build/
__pycache__/
results/*.json
!results/.gitkeep
```

- [ ] **Step 3: README stub** (extended by the harness in Task 10; set the markers now)

```markdown
# sudoku

Benchmark of sudoku solving algorithms (naive backtracking, MRV bitmask,
Norvig constraint propagation, Dancing Links, pure rule-based) across
Python, JavaScript, Go, Rust, C++, C and x86-64 assembly.

Run: `python3 bench/run.py`

<!-- BENCH:BEGIN -->
_No benchmark results yet._
<!-- BENCH:END -->
```

- [ ] **Step 4: Makefile stub**

```make
.PHONY: all clean
all:
	@echo "nothing to build yet (interpreted languages only)"
clean:
	rm -rf build
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Scaffold repo layout, remove tutorial notebook"
```

---

### Task 2: Puzzle sets + validation + reference solutions

**Files:**
- Create: `tools/normalize.py`, `tools/validate_puzzles.py`, `puzzles/{easy,medium,hard,extreme,verify}.txt`, `puzzles/verify_solutions.txt`

**Interfaces:**
- Produces: puzzle files (81-char lines, `0` = empty); `verify_solutions.txt` line-by-line parallel to `verify.txt`; `tools/validate_puzzles.py <in> [--solutions <out>]` — exit 1 on invalid/ambiguous puzzle.

- [ ] **Step 1: `tools/normalize.py`** — arbitrary source formats → 81-char lines

```python
#!/usr/bin/env python3
"""Normalize sudoku collections (Norvig easy50/top95/hardest, Project
Euler p096) to one 81-char line per puzzle, 0 = empty. stdin -> stdout."""
import re, sys

digits = []
for line in sys.stdin:
    line = line.strip()
    if re.fullmatch(r'[0-9.]+', line):
        digits.append(line.replace('.', '0'))
s = ''.join(digits)
assert len(s) % 81 == 0, f"total digit count {len(s)} not divisible by 81"
for i in range(0, len(s), 81):
    print(s[i:i+81])
```

- [ ] **Step 2: `tools/validate_puzzles.py`** — validity, solvability, uniqueness; optionally writes solutions. Contains its own bitmask backtracker with solution counter (deliberately independent of `impl/`, so it can later serve as reference checker).

```python
#!/usr/bin/env python3
"""Validate puzzle files: 81 chars, consistent clues, exactly one solution.
Usage: validate_puzzles.py FILE... [--solutions OUT]  (--solutions only with one FILE)"""
import sys

ALL = 0x3FE

def count_solutions(g, limit=2):
    rows, cols, boxes = [0]*9, [0]*9, [0]*9
    for i, d in enumerate(g):
        if d:
            r, c = divmod(i, 9); b = r//3*3 + c//3
            bit = 1 << d
            if (rows[r] | cols[c] | boxes[b]) & bit:
                return 0, None
            rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
    n = 0; first = None
    def bt():
        nonlocal n, first
        best, bc, bcand = -1, 10, 0
        for i in range(81):
            if g[i]: continue
            r, c = divmod(i, 9); b = r//3*3 + c//3
            cand = ALL & ~(rows[r] | cols[c] | boxes[b])
            k = cand.bit_count()
            if k < bc:
                best, bc, bcand = i, k, cand
                if k <= 1: break
        if best == -1:
            n += 1
            if first is None: first = bytes(g)
            return n >= 2
        r, c = divmod(best, 9); b = r//3*3 + c//3
        cand = bcand
        while cand:
            bit = cand & -cand; cand ^= bit
            g[best] = bit.bit_length() - 1
            rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
            done = bt()
            g[best] = 0
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit
            if done: return True
        return False
    bt()
    return n, first

def main():
    args = sys.argv[1:]
    sol_out = None
    if '--solutions' in args:
        k = args.index('--solutions'); sol_out = args[k+1]; del args[k:k+2]
    ok = True
    for path in args:
        sols = []
        for ln, line in enumerate(open(path), 1):
            line = line.strip()
            if not line or line.startswith('#'): continue
            if len(line) != 81 or not line.isdigit():
                print(f"{path}:{ln}: not 81 digits"); ok = False; continue
            n, first = count_solutions(bytearray(int(c) for c in line))
            if n != 1:
                print(f"{path}:{ln}: {n if n < 2 else '>1'} solutions"); ok = False
            else:
                sols.append(''.join(map(str, first)))
        print(f"{path}: OK" if ok else f"{path}: FAILED")
        if sol_out and ok:
            open(sol_out, 'w').write('\n'.join(sols) + '\n')
    sys.exit(0 if ok else 1)

main()
```

- [ ] **Step 3: Download and normalize sources**

```bash
cd /home/michi/sudoku
S=/tmp/claude-1000/-home-michi/*/scratchpad; mkdir -p sudoku_dl 2>/dev/null || true
curl -fsSL http://norvig.com/easy50.txt   | python3 tools/normalize.py > puzzles/easy.txt
curl -fsSL https://projecteuler.net/project/resources/p096_sudoku.txt \
                                          | python3 tools/normalize.py > puzzles/medium.txt
curl -fsSL http://norvig.com/top95.txt    | python3 tools/normalize.py > puzzles/hard.txt
curl -fsSL http://norvig.com/hardest.txt  | python3 tools/normalize.py > puzzles/extreme.txt
wc -l puzzles/*.txt   # expected: easy 50, medium 50, hard 95, extreme 11
```

If a URL is unreachable: look for alternative mirrors (the files are widely mirrored, e.g. in GitHub clones of Norvig's sudoku.py) — do not invent puzzles.

- [ ] **Step 4: Extend `extreme.txt`** — append the anti-brute-force puzzle (constructed against row-order backtracking, Wikipedia "Sudoku solving algorithms") at the end:

```
..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9
```

(convert to `0` format with `sed 's/\./0/g'` first). The validation in Step 5 is the gate: if the puzzle fails (not unique/invalid), it is removed rather than repaired.

- [ ] **Step 5: Validate all sets**

```bash
python3 tools/validate_puzzles.py puzzles/easy.txt puzzles/medium.txt puzzles/hard.txt puzzles/extreme.txt
```

Expected: `OK` for all four files. Delete every line reported as ambiguous from the file and re-validate (ambiguous puzzles make the solution comparison in the harness impossible).

- [ ] **Step 6: Build verify set** — 3 puzzles each from easy/medium/hard, 2 from extreme, plus the puzzle from the old notebook:

```bash
{ head -3 puzzles/easy.txt; head -3 puzzles/medium.txt; head -3 puzzles/hard.txt; \
  head -2 puzzles/extreme.txt; \
  echo 780400120600075009000601078007040260001050930904060005070300012120007400049206007; \
} > puzzles/verify.txt
python3 tools/validate_puzzles.py puzzles/verify.txt --solutions puzzles/verify_solutions.txt
```

Expected: `OK`, `verify_solutions.txt` with 12 lines of 81 digits each.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "Add puzzle sets (Norvig easy50/top95/hardest, Euler p096) with validator"
```

---

### Task 3: Python contract + `naive` + `mrv`

**Files:**
- Create: `impl/python/_contract.py`, `impl/python/naive.py`, `impl/python/mrv.py`

**Interfaces:**
- Produces: `_contract.run(solve, solve_batch=None)` — `solve(bytearray[81]) -> Sequence[int]|None`; `solve_batch(grids: list[bytes], threads: int) -> list`. All further Python solvers (Tasks 5–8) use exactly these signatures. `mrv.solve` is imported by Task 8 (`mrv_mt`).

- [ ] **Step 1: `impl/python/_contract.py`**

```python
"""Shared I/O contract for the python solvers (see spec).
Usage: python3 <solver>.py [reps] [threads] < puzzles.txt"""
import sys, time

def run(solve, solve_batch=None):
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    threads = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    puzzles = [ln.strip() for ln in sys.stdin.read().splitlines()
               if ln.strip() and not ln.startswith('#')]
    grids = [bytes(int(c) for c in p) for p in puzzles]
    results = [None] * len(grids)
    t0 = time.perf_counter_ns()
    for _ in range(reps):
        if solve_batch is not None:
            results = solve_batch(grids, threads)
        else:
            for i, g in enumerate(grids):
                results[i] = solve(bytearray(g))
    ns = time.perf_counter_ns() - t0
    sys.stderr.write(f"ns={ns}\n")
    sys.stdout.write('\n'.join(
        ''.join(map(str, r)) if r is not None else 'UNSOLVED'
        for r in results) + '\n')
```

- [ ] **Step 2: `impl/python/naive.py`** — the notebook algorithm, just on a flat board:

```python
"""Naive backtracking: first empty cell, digits 1-9 in order."""
from _contract import run

def solve(g):
    def valid(pos, d):
        r, c = divmod(pos, 9)
        for i in range(9):
            if g[r*9 + i] == d or g[i*9 + c] == d:
                return False
        br, bc = r - r % 3, c - c % 3
        for i in range(br, br + 3):
            for j in range(bc, bc + 3):
                if g[i*9 + j] == d:
                    return False
        return True

    def bt():
        try:
            pos = g.index(0)
        except ValueError:
            return True
        for d in range(1, 10):
            if valid(pos, d):
                g[pos] = d
                if bt():
                    return True
                g[pos] = 0
        return False

    for i, d in enumerate(list(g)):          # reject inconsistent clues
        g[i] = 0
        if not valid(i, d) and d:
            return None
        g[i] = d
    return g if bt() else None

if __name__ == '__main__':
    run(solve)
```

- [ ] **Step 3: `impl/python/mrv.py`** — bitmasks + most-constrained cell:

```python
"""Backtracking with bitmask candidates and most-constrained-cell order."""
from _contract import run

ALL = 0x3FE

def solve(g):
    rows, cols, boxes = [0]*9, [0]*9, [0]*9
    for i, d in enumerate(g):
        if d:
            r, c = divmod(i, 9); b = r//3*3 + c//3
            bit = 1 << d
            if (rows[r] | cols[c] | boxes[b]) & bit:
                return None
            rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit

    def bt():
        best, best_n, best_cand = -1, 10, 0
        for i in range(81):
            if g[i]:
                continue
            r, c = divmod(i, 9); b = r//3*3 + c//3
            cand = ALL & ~(rows[r] | cols[c] | boxes[b])
            n = cand.bit_count()
            if n < best_n:
                best, best_n, best_cand = i, n, cand
                if n <= 1:
                    break
        if best == -1:
            return True
        r, c = divmod(best, 9); b = r//3*3 + c//3
        cand = best_cand
        while cand:
            bit = cand & -cand; cand ^= bit
            g[best] = bit.bit_length() - 1
            rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
            if bt():
                return True
            g[best] = 0
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit
        return False

    return g if bt() else None

if __name__ == '__main__':
    run(solve)
```

- [ ] **Step 4: Manual smoke test (the harness only arrives in Task 4)**

```bash
cd /home/michi/sudoku
python3 impl/python/naive.py < puzzles/verify.txt > /tmp/naive.out 2>/tmp/naive.err
python3 impl/python/mrv.py   < puzzles/verify.txt > /tmp/mrv.out   2>/tmp/mrv.err
diff /tmp/naive.out puzzles/verify_solutions.txt && diff /tmp/mrv.out puzzles/verify_solutions.txt
cat /tmp/naive.err /tmp/mrv.err   # one line ns=<number> each
```

Expected: both diffs empty, two plausible `ns=` lines. (naive may be slow on verify.txt — the two extreme puzzles can take seconds.)

- [ ] **Step 5: Commit**

```bash
git add impl && git commit -m "Add python naive and mrv solvers with shared I/O contract"
```

---

### Task 4: Harness — Discovery + Verify

**Files:**
- Create: `bench/run.py`

**Interfaces:**
- Produces: `python3 bench/run.py --verify [--lang L ...] [--algo A ...]` — builds via `make`, finds existing implementations, checks against `puzzles/verify(_solutions).txt`, exit 1 on FAIL. Functions `discover()`, `run_solver(cmd, text, reps, threads, timeout) -> (lines, ns)` are reused in Task 9.

- [ ] **Step 1: `bench/run.py` with discovery, THP fix and verify mode**

```python
#!/usr/bin/env python3
"""One harness for all implementations: build, verify, benchmark, report."""
import argparse, ctypes, json, statistics, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALGOS = ['naive', 'mrv', 'norvig', 'dlx', 'rules', 'mrv_mt']
LANGS = ['python', 'javascript', 'go', 'rust', 'cpp', 'c', 'asm']
SETS = ['easy', 'medium', 'hard', 'extreme']
SET_TIMEOUT = 60          # seconds per (impl, set) run
TARGET_NS = 1_000_000_000  # calibrate reps until solve loop >= 1s

def clear_thp_disable():
    # Claude Code sessions run with PR_SET_THP_DISABLE (=41); clear it so
    # spawned solvers see the same THP environment as a normal terminal.
    try:
        ctypes.CDLL(None).prctl(41, 0, 0, 0, 0)
    except Exception:
        pass

def cmd_for(lang, algo):
    if lang == 'python':
        p = ROOT / 'impl/python' / f'{algo}.py'
        return [sys.executable, str(p)], p
    if lang == 'javascript':
        p = ROOT / 'impl/javascript' / f'{algo}.js'
        return ['node', str(p)], p
    p = ROOT / 'build' / f'{lang}-{algo}'
    return [str(p)], p

def discover(langs, algos):
    impls = []
    for lang in langs:
        for algo in algos:
            cmd, path = cmd_for(lang, algo)
            if path.exists():
                impls.append((lang, algo, cmd))
    return impls

def run_solver(cmd, puzzles_text, reps=1, threads=1, timeout=SET_TIMEOUT):
    argv = cmd + [str(reps), str(threads)]
    proc = subprocess.run(argv, input=puzzles_text, capture_output=True,
                          text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(f"exit {proc.returncode}: {proc.stderr[:200]}")
    ns = None
    for line in proc.stderr.splitlines():
        if line.startswith('ns='):
            ns = int(line[3:])
    if ns is None:
        raise RuntimeError("no ns= line on stderr")
    return proc.stdout.splitlines(), ns

def load_set(name):
    lines = (ROOT / 'puzzles' / f'{name}.txt').read_text().splitlines()
    return [l for l in lines if l.strip() and not l.startswith('#')]

def verify(impls):
    puzzles = (ROOT / 'puzzles/verify.txt').read_text()
    expected = load_set('verify_solutions')
    n_ok = 0
    failed = []
    for lang, algo, cmd in impls:
        name = f'{lang}/{algo}'
        try:
            lines, _ = run_solver(cmd, puzzles)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            print(f'FAIL {name}: {e}')
            failed.append(name)
            continue
        if len(lines) != len(expected):
            print(f'FAIL {name}: {len(lines)} lines, expected {len(expected)}')
            failed.append(name)
            continue
        bad = [i for i, (got, want) in enumerate(zip(lines, expected))
               if got != want and not (got == 'UNSOLVED' and algo == 'rules')]
        if bad:
            print(f'FAIL {name}: wrong solution for puzzle(s) {bad}')
            failed.append(name)
        else:
            unsolved = sum(1 for l in lines if l == 'UNSOLVED')
            extra = f' ({unsolved} unsolved)' if unsolved else ''
            print(f'PASS {name}{extra}')
            n_ok += 1
    print(f'{n_ok}/{len(impls)} implementations pass verify')
    return not failed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify', action='store_true')
    ap.add_argument('--lang', action='append', choices=LANGS)
    ap.add_argument('--algo', action='append', choices=ALGOS)
    args = ap.parse_args()
    clear_thp_disable()
    subprocess.run(['make', '-s'], cwd=ROOT, check=True)
    impls = discover(args.lang or LANGS, args.algo or ALGOS)
    if not impls:
        sys.exit('no implementations found')
    ok = verify(impls)
    if not ok or args.verify:
        sys.exit(0 if ok else 1)
    # bench mode follows in a later task
    print('bench mode not implemented yet; use --verify')

if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Run verify**

```bash
python3 bench/run.py --verify
```

Expected: `PASS python/naive`, `PASS python/mrv`, `2/2 implementations pass verify`, exit 0.

- [ ] **Step 3: Negative test** — deliberately change one digit of a solution in `puzzles/verify_solutions.txt`; `--verify` must FAIL both implementations and return exit 1; revert the change (`git checkout -- puzzles/verify_solutions.txt`), verify green again.

- [ ] **Step 4: Commit**

```bash
git add bench && git commit -m "Add benchmark harness with build and verify stages"
```

---

### Task 5: Python `norvig`

**Files:**
- Create: `impl/python/norvig.py`

**Interfaces:**
- Consumes: `_contract.run(solve)`; `solve(bytearray[81]) -> list[int]|None`.

- [ ] **Step 1: `impl/python/norvig.py`** — constraint propagation (elimination + naked/hidden singles as fixed point) plus MRV search, candidates as bitmasks instead of strings (Norvig's algorithm, not his data structures):

```python
"""Norvig-style constraint propagation + search (bitmask candidates)."""
from _contract import run

ALL = 0x3FE
ROWS = [[r*9 + c for c in range(9)] for r in range(9)]
COLS = [[r*9 + c for r in range(9)] for c in range(9)]
BOXES = [[(br*3 + i)*9 + bc*3 + j for i in range(3) for j in range(3)]
         for br in range(3) for bc in range(3)]
UNITS_OF = [[] for _ in range(81)]
for u in ROWS + COLS + BOXES:
    for i in u:
        UNITS_OF[i].append(u)
PEERS = [sorted({j for u in UNITS_OF[i] for j in u} - {i}) for i in range(81)]

def assign(cand, i, bit):
    other = cand[i] & ~bit
    while other:
        lb = other & -other; other ^= lb
        if not eliminate(cand, i, lb):
            return False
    return True

def eliminate(cand, i, bit):
    if not cand[i] & bit:
        return True
    cand[i] &= ~bit
    c = cand[i]
    if c == 0:
        return False
    if c & (c - 1) == 0:                    # one candidate left: strip peers
        for p in PEERS[i]:
            if not eliminate(cand, p, c):
                return False
    for u in UNITS_OF[i]:                   # digit has one place left in unit?
        places = [j for j in u if cand[j] & bit]
        if not places:
            return False
        if len(places) == 1 and cand[places[0]].bit_count() > 1:
            if not assign(cand, places[0], bit):
                return False
    return True

def search(cand):
    best, best_n = -1, 10
    for i in range(81):
        n = cand[i].bit_count()
        if 1 < n < best_n:
            best, best_n = i, n
    if best == -1:
        return cand
    c = cand[best]
    while c:
        bit = c & -c; c ^= bit
        trial = cand[:]
        if assign(trial, best, bit):
            r = search(trial)
            if r is not None:
                return r
    return None

def solve(g):
    cand = [ALL] * 81
    for i, d in enumerate(g):
        if d and not assign(cand, i, 1 << d):
            return None
    r = search(cand)
    return None if r is None else [c.bit_length() - 1 for c in r]

if __name__ == '__main__':
    run(solve)
```

- [ ] **Step 2: Verify** — `python3 bench/run.py --verify --lang python` → `PASS python/norvig` (3/3).

- [ ] **Step 3: Commit** — `git add impl && git commit -m "Add python norvig constraint-propagation solver"`

---

### Task 6: Python `dlx`

**Files:**
- Create: `impl/python/dlx.py`

**Interfaces:**
- Consumes: `_contract.run(solve)`; `solve(bytearray[81]) -> list[int]|None`.

- [ ] **Step 1: `impl/python/dlx.py`** — Algorithm X with Dancing Links on flat arrays (no object graph). 324 columns: cell(81) + row×digit(81) + column×digit(81) + box×digit(81); 729 options of 4 nodes each. Matrix is rebuilt per puzzle (construction is part of the measurement — document as an optimization for the compiled languages later: build once, cover/uncover clues).

```python
"""Knuth's Algorithm X with Dancing Links, array-based."""
from _contract import run

NCOLS = 324

def solve(g):
    rows_m, cols_m, boxes_m = [0]*9, [0]*9, [0]*9   # cheap consistency gate
    for i, d in enumerate(g):
        if d:
            r, c = divmod(i, 9); b = r//3*3 + c//3
            bit = 1 << d
            if (rows_m[r] | cols_m[c] | boxes_m[b]) & bit:
                return None
            rows_m[r] |= bit; cols_m[c] |= bit; boxes_m[b] |= bit

    size = 1 + NCOLS + 729 * 4      # root + headers + row nodes
    L = [0]*size; R = [0]*size; U = [0]*size; D = [0]*size
    C = [0]*size; SZ = [0]*(NCOLS + 1); RID = [0]*size
    for h in range(NCOLS + 1):      # 0 = root, 1..324 = column headers
        L[h] = h - 1 if h else NCOLS
        R[h] = h + 1 if h < NCOLS else 0
        U[h] = D[h] = h
    n = NCOLS + 1
    first_node = {}
    for cell in range(81):
        r, c = divmod(cell, 9); b = r//3*3 + c//3
        for d in range(1, 10):
            cols = (1 + cell,
                    1 + 81 + r*9 + d - 1,
                    1 + 162 + c*9 + d - 1,
                    1 + 243 + b*9 + d - 1)
            prev = -1
            for col in cols:
                C[n] = col; RID[n] = cell * 9 + d - 1
                D[n] = col; U[n] = U[col]; D[U[col]] = n; U[col] = n
                SZ[col] += 1
                if prev < 0:
                    L[n] = R[n] = n
                    first_node[(cell, d)] = n
                else:
                    L[n] = prev; R[n] = R[prev]
                    L[R[prev]] = n; R[prev] = n
                prev = n
                n += 1

    def cover(col):
        R[L[col]] = R[col]; L[R[col]] = L[col]
        i = D[col]
        while i != col:
            j = R[i]
            while j != i:
                D[U[j]] = D[j]; U[D[j]] = U[j]; SZ[C[j]] -= 1
                j = R[j]
            i = D[i]

    def uncover(col):
        i = U[col]
        while i != col:
            j = L[i]
            while j != i:
                SZ[C[j]] += 1; D[U[j]] = j; U[D[j]] = j
                j = L[j]
            i = U[i]
        R[L[col]] = col; L[R[col]] = col

    solution = []
    for i, d in enumerate(g):       # pre-select clue rows
        if d:
            node = first_node[(i, d)]
            solution.append(RID[node])
            cover(C[node])
            j = R[node]
            while j != node:
                cover(C[j]); j = R[j]

    def search():
        col = R[0]
        if col == 0:
            return True
        best = col
        while col != 0:
            if SZ[col] < SZ[best]:
                best = col
            col = R[col]
        cover(best)
        i = D[best]
        while i != best:
            solution.append(RID[i])
            j = R[i]
            while j != i:
                cover(C[j]); j = R[j]
            if search():
                return True
            j = L[i]
            while j != i:
                uncover(C[j]); j = L[j]
            solution.pop()
            i = D[i]
        uncover(best)
        return False

    if not search():
        return None
    out = [0] * 81
    for rid in solution:
        out[rid // 9] = rid % 9 + 1
    return out

if __name__ == '__main__':
    run(solve)
```

- [ ] **Step 2: Verify** — `python3 bench/run.py --verify --lang python` → `PASS python/dlx` (4/4).

- [ ] **Step 3: Commit** — `git add impl && git commit -m "Add python dancing-links (DLX) solver"`

---

### Task 7: Python `rules`

**Files:**
- Create: `impl/python/rules.py`

**Interfaces:**
- Consumes: `_contract.run(solve)`; `solve` returns `None` for "not solvable by pure logic" → `UNSOLVED`.

- [ ] **Step 1: `impl/python/rules.py`** — technique pipeline until fixed point: naked singles, hidden singles, naked pairs, hidden pairs, pointing pairs, box-line reduction, X-Wing, Swordfish. No guessing. Contradiction ⇒ `None` (never a wrong solution).

```python
"""Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED."""
from itertools import combinations
from _contract import run

ALL = 0x3FE
ROWS = [[r*9 + c for c in range(9)] for r in range(9)]
COLS = [[r*9 + c for r in range(9)] for c in range(9)]
BOXES = [[(br*3 + i)*9 + bc*3 + j for i in range(3) for j in range(3)]
         for br in range(3) for bc in range(3)]
UNITS = ROWS + COLS + BOXES
UNITS_OF = [[] for _ in range(81)]
for u in UNITS:
    for i in u:
        UNITS_OF[i].append(u)
PEERS = [sorted({j for u in UNITS_OF[i] for j in u} - {i}) for i in range(81)]

class Contradiction(Exception):
    pass

def strip(cand, i, bit):
    if cand[i] & bit:
        cand[i] &= ~bit
        if cand[i] == 0:
            raise Contradiction
        return True
    return False

def naked_singles(cand, placed):
    prog = False
    for i in range(81):
        c = cand[i]
        if not placed[i] and c & (c - 1) == 0:
            placed[i] = True
            prog = True
            for p in PEERS[i]:
                strip(cand, p, c)
    return prog

def hidden_singles(cand):
    prog = False
    for u in UNITS:
        for d in range(1, 10):
            bit = 1 << d
            places = [i for i in u if cand[i] & bit]
            if not places:
                raise Contradiction
            if len(places) == 1 and cand[places[0]] != bit:
                cand[places[0]] = bit
                prog = True
    return prog

def naked_pairs(cand):
    prog = False
    for u in UNITS:
        for a, b in combinations(range(9), 2):
            ca = cand[u[a]]
            if ca.bit_count() == 2 and cand[u[b]] == ca:
                for k in range(9):
                    if k != a and k != b:
                        prog |= strip(cand, u[k], ca & cand[u[k]]) \
                            if cand[u[k]] & ca else prog
    return prog

def hidden_pairs(cand):
    prog = False
    for u in UNITS:
        pos = {d: tuple(i for i in u if cand[i] & (1 << d))
               for d in range(1, 10)}
        two = [d for d, p in pos.items() if len(p) == 2]
        for x, y in combinations(two, 2):
            if pos[x] == pos[y]:
                mask = (1 << x) | (1 << y)
                for i in pos[x]:
                    if cand[i] & ~mask:
                        cand[i] &= mask
                        prog = True
    return prog

def pointing_and_boxline(cand):
    prog = False
    for box in BOXES:
        for d in range(1, 10):
            bit = 1 << d
            places = [i for i in box if cand[i] & bit]
            if 2 <= len(places) <= 3:
                rs = {i // 9 for i in places}
                cs = {i % 9 for i in places}
                if len(rs) == 1:                    # pointing: box -> row
                    for i in ROWS[next(iter(rs))]:
                        if i not in box:
                            prog |= strip(cand, i, bit)
                elif len(cs) == 1:                  # pointing: box -> col
                    for i in COLS[next(iter(cs))]:
                        if i not in box:
                            prog |= strip(cand, i, bit)
    for lines in (ROWS, COLS):                      # box-line reduction
        for line in lines:
            for d in range(1, 10):
                bit = 1 << d
                places = [i for i in line if cand[i] & bit]
                boxes = {(i // 9 // 3) * 3 + i % 9 // 3 for i in places}
                if places and len(boxes) == 1:
                    for i in BOXES[next(iter(boxes))]:
                        if i not in line:
                            prog |= strip(cand, i, bit)
    return prog

def fish(cand, size):
    prog = False
    for lines, cross, coord in ((ROWS, COLS, lambda i: i % 9),
                                (COLS, ROWS, lambda i: i // 9)):
        for d in range(1, 10):
            bit = 1 << d
            cand_lines = []
            for li, line in enumerate(lines):
                if any(cand[i] == bit for i in line):
                    continue                        # digit already fixed here
                ps = {coord(i) for i in line if cand[i] & bit}
                if 2 <= len(ps) <= size:
                    cand_lines.append((li, ps))
            for combo in combinations(cand_lines, size):
                union = set().union(*(ps for _, ps in combo))
                if len(union) != size:
                    continue
                keep = {li for li, _ in combo}
                for cc in union:
                    for i in cross[cc]:
                        li = coord(i) if lines is COLS else \
                            (i // 9 if lines is ROWS else i % 9)
                        li = i // 9 if lines is ROWS else i % 9
                        if li not in keep:
                            prog |= strip(cand, i, bit)
    return prog

TECHNIQUES = None  # filled below; ordered cheap -> expensive

def solve(g):
    cand = [ALL] * 81
    placed = [False] * 81
    try:
        for i, d in enumerate(g):
            if d:
                if not cand[i] & (1 << d):
                    return None
                cand[i] = 1 << d
        while True:
            if naked_singles(cand, placed):
                continue
            if hidden_singles(cand):
                continue
            if naked_pairs(cand):
                continue
            if hidden_pairs(cand):
                continue
            if pointing_and_boxline(cand):
                continue
            if fish(cand, 2):
                continue
            if fish(cand, 3):
                continue
            break
    except Contradiction:
        return None
    if all(c.bit_count() == 1 for c in cand):
        return [c.bit_length() - 1 for c in cand]
    return None

if __name__ == '__main__':
    run(solve)
```

Note to the implementer: the code above is a template, not a copy-paste mandate — in particular, clean up `naked_pairs` (the `prog |=` line is clumsy) and the duplicate `li` computation in `fish` while writing. Behavior is covered by Step 2/3.

- [ ] **Step 2: Verify** — `python3 bench/run.py --verify --lang python` → `PASS python/rules (N unsolved)`. Expectation: all easy solved, the two extreme puzzles in the verify set stay UNSOLVED; no FAIL.

- [ ] **Step 3: Solve-rate plausibility** — `python3 impl/python/rules.py < puzzles/easy.txt | grep -c UNSOLVED` → expected 0 or close to 0; `... < puzzles/hard.txt | grep -c UNSOLVED` → clearly > 0. Record the numbers in the commit message.

- [ ] **Step 4: Commit** — `git add impl && git commit -m "Add python rule-based solver (singles, pairs, pointing, box-line, fish)"`

---

### Task 8: Python `mrv_mt`

**Files:**
- Create: `impl/python/mrv_mt.py`

**Interfaces:**
- Consumes: `mrv.solve`, `_contract.run(None, solve_batch)`.

- [ ] **Step 1: `impl/python/mrv_mt.py`** — `multiprocessing.Pool` over puzzles; the pool is created lazily once (only the first rep pays the fork overhead; amortized with calibrated reps):

```python
"""mrv parallelized over puzzles via multiprocessing (GIL)."""
import multiprocessing as mp
from _contract import run
from mrv import solve

_pool = None

def _one(g):
    return solve(bytearray(g))

def solve_batch(grids, threads):
    global _pool
    if threads <= 1:
        return [_one(g) for g in grids]
    if _pool is None:
        _pool = mp.Pool(threads)
    chunk = max(1, len(grids) // (threads * 4))
    return _pool.map(_one, grids, chunksize=chunk)

if __name__ == '__main__':
    run(None, solve_batch)
```

- [ ] **Step 2: Verify + speedup smoke test**

```bash
python3 bench/run.py --verify --lang python     # PASS python/mrv_mt (6/6)
python3 impl/python/mrv_mt.py 20 1 < puzzles/hard.txt 2>&1 >/dev/null
python3 impl/python/mrv_mt.py 20 4 < puzzles/hard.txt 2>&1 >/dev/null
```

Expected: ns with 4 threads clearly smaller than with 1 (not necessarily 4×; fork + IPC cost).

- [ ] **Step 3: Commit** — `git add impl && git commit -m "Add python mrv_mt multiprocessing variant"`

---

### Task 9: Harness — bench mode + report + JSON

**Files:**
- Modify: `bench/run.py` (bench part replaces the placeholder at the end of `main()`)

**Interfaces:**
- Produces: `python3 bench/run.py [--set S ...]` — calibrates reps (target ≥1s), median of 3 runs, timeout ⇒ DNF, text table on stdout, raw data `results/<unix-ts>.json`. JSON schema: `{"meta": {"host", "cpu", "date"}, "runs": [{"lang", "algo", "set", "reps", "ns_median", "us_per_puzzle", "puzzles", "solved", "status"}]}` — Task 10 and CI depend on this schema.

- [ ] **Step 1: Append bench functions to `bench/run.py` and hook them into `main()`**

```python
def bench_one(cmd, algo, set_name, threads):
    text = (ROOT / 'puzzles' / f'{set_name}.txt').read_text()
    n_puzzles = len(load_set(set_name))
    lines, ns = run_solver(cmd, text, reps=1, threads=threads)
    reps = max(1, min(10_000, int(TARGET_NS // max(ns, 1))))
    samples = []
    for _ in range(3):
        lines, ns = run_solver(cmd, text, reps=reps, threads=threads)
        samples.append(ns)
    ns_med = statistics.median(samples)
    solved = sum(1 for l in lines if l != 'UNSOLVED')
    return {'reps': reps, 'ns_median': ns_med,
            'us_per_puzzle': ns_med / reps / n_puzzles / 1000,
            'puzzles': n_puzzles, 'solved': solved, 'status': 'ok'}

def bench(impls, sets):
    import os
    runs = []
    nproc = os.cpu_count() or 1
    for lang, algo, cmd in impls:
        threads = nproc if algo.endswith('_mt') else 1
        for s in sets:
            try:
                r = bench_one(cmd, algo, s, threads)
            except subprocess.TimeoutExpired:
                r = {'status': 'dnf'}
            except RuntimeError as e:
                r = {'status': f'error: {e}'}
            r.update(lang=lang, algo=algo, set=s)
            runs.append(r)
            us = r.get('us_per_puzzle')
            print(f"{lang:11s} {algo:7s} {s:8s} "
                  + (f"{us:12.2f} us/puzzle  {r['solved']}/{r['puzzles']}"
                     if us is not None else r['status']))
    return runs

def cpu_model():
    for line in open('/proc/cpuinfo'):
        if line.startswith('model name'):
            return line.split(':', 1)[1].strip()
    return 'unknown'
```

In `main()`, replace the placeholder with:

```python
    import os, platform
    runs = bench(impls, args.set or SETS)
    out = {'meta': {'host': platform.node(), 'cpu': cpu_model(),
                    'date': time.strftime('%Y-%m-%d %H:%M:%S')},
           'runs': runs}
    path = ROOT / 'results' / f'{int(time.time())}.json'
    path.write_text(json.dumps(out, indent=1))
    print(f'raw results: {path.relative_to(ROOT)}')
```

and add `--set` as `ap.add_argument('--set', action='append', choices=SETS)`.

- [ ] **Step 2: Complete Python run**

```bash
python3 bench/run.py --lang python
```

Expected: table with 6 algorithms × 4 sets; `naive` on `extreme` very likely `dnf` (the anti-brute-force puzzle is there for exactly that); `rules` with partial solve rate; JSON file under `results/`. Plausibility order: mrv/norvig/dlx ≪ naive; mrv_mt faster than mrv on hard/extreme.

- [ ] **Step 3: Commit** — `git add bench && git commit -m "Add bench mode: calibrated reps, median of 3, JSON results"`

---

### Task 10: README generator + charts

**Files:**
- Modify: `bench/run.py` (`--readme` flag), `README.md` (generated section between the markers)
- Create: `assets/time_by_impl.png`, `assets/rules_solve_rate.png` (generated)

**Interfaces:**
- Consumes: JSON schema from Task 9.
- Produces: `python3 bench/run.py --readme results/<file>.json` replaces the block between `<!-- BENCH:BEGIN -->` and `<!-- BENCH:END -->` with Markdown tables (µs/puzzle per set, puzzles/s, solve rate, speedup mrv_mt vs mrv) and embeds the two PNGs.

- [ ] **Step 0: REQUIRED — load the `dataviz` skill before writing chart code** (Skill tool, name `dataviz`); then build charts with matplotlib: bar chart of time per algorithm×language with log scale (range spans orders of magnitude), solve-rate chart for `rules` per set.

- [ ] **Step 1: Implement the `--readme` flag** — load JSON, format tables as Markdown (sets as columns, implementations as rows, `dnf`/`error` visible), write PNGs to `assets/`, replace the README block between the markers (read the whole file, swap the block via string split, write back). Meta line with CPU + date below the tables.

- [ ] **Step 2: Generate + inspect** — `python3 bench/run.py --readme results/<latest>.json`; render the README (`glow README.md` or in the editor), open the PNGs; check: log scale labeled, dnf cells clearly visible.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add README report generation with charts"`

---

### Task 11: Phase 1 wrap-up

- [ ] **Step 1: Full run from a clean state**

```bash
cd /home/michi/sudoku && git status --short   # must be empty
python3 bench/run.py                          # discovery finds only python -> 6 impls
```

Expected: 6× PASS in verify, complete bench table, JSON + README up to date.

- [ ] **Step 2: Push**

```bash
git push -u origin main
```

(Repo stays private for now; public only after Phase 6 per spec.)

---

## Follow-up plans (not part of this plan)

- Phase 3: C (all 6, template for compiled languages; `-O3 -march=native -flto`, pthreads for `mrv_mt`) + Makefile targets `build/c-<algo>`.
- Phase 4: C++, Rust (Cargo workspace), Go, JavaScript.
- Phase 5: Assembly (NASM): naive, mrv, mrv_mt, norvig, dlx, rules.
- Phase 6: Micro-optimization pass, final local full run.
- Phase 7: `.github/workflows/bench.yml`, repo public, CI reference run.
