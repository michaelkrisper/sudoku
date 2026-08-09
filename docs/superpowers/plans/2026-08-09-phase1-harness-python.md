# Sudoku Benchmark — Phase 1: Harness + Python-Referenz — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lauffähiges Benchmark-Gerüst: Puzzle-Sets, ein gemeinsamer Harness (Build/Verify/Bench/Report/README) und alle 6 Algorithmen in Python als Referenzimplementierung.

**Architecture:** Jeder Solver ist ein eigenständiges stdin/stdout-Programm nach dem I/O-Vertrag der Spec (`docs/superpowers/specs/2026-08-09-sudoku-benchmark-design.md`). Der Harness `bench/run.py` kennt alle (Sprache, Algorithmus)-Paare, überspringt fehlende Implementierungen und ist damit ab Task 4 dauerhaft das Testwerkzeug für alle späteren Sprachen.

**Tech Stack:** Python ≥ 3.10 (int.bit_count), matplotlib (nur Harness), curl (Puzzle-Downloads). Keine weiteren Dependencies.

## Global Constraints

- I/O-Vertrag (Spec, verbatim): Aufruf `solver [reps] [threads] < puzzles.txt`, beide default 1; Input 81-Zeichen-Zeilen aus `0-9`, `#`-Zeilen und Leerzeilen ignorieren; alle Puzzles einlesen/parsen → Monotonic-Clock → reps × alle Puzzles lösen (jede Wiederholung auf frischer Kopie) → Clock stoppen; stdout: pro Puzzle `81 Ziffern` oder `UNSOLVED` in Eingabereihenfolge; stderr: genau `ns=<gesamt>`; Exit-Code 0 auch bei UNSOLVED.
- Ungültige Puzzles: `UNSOLVED` ausgeben, nie crashen, nie falsche Lösung.
- Solver bleiben minimal: keine Argument-Parser-Libs, keine Ausgabe außer Vertrag.
- Algorithmus-Keys: `naive`, `mrv`, `norvig`, `dlx`, `rules`, `mrv_mt`.
- Commits: prägnante englische Messages, keine Co-Author-Zeile.

---

### Task 1: Repo-Gerüst

**Files:**
- Delete: `SudokuSolver.ipynb`
- Create: `.gitignore`, `README.md`, `Makefile`, Verzeichnisse `puzzles/ impl/python/ bench/ tools/ results/ assets/`

**Interfaces:**
- Produces: Verzeichnislayout laut Spec; `make` (no-op Default-Target `all`), von Task 4 an vom Harness aufgerufen.

- [ ] **Step 1: Notebook entfernen, Verzeichnisse anlegen**

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

- [ ] **Step 3: README-Stub** (wird in Task 10 vom Harness erweitert; Marker jetzt schon setzen)

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

- [ ] **Step 4: Makefile-Stub**

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

### Task 2: Puzzle-Sets + Validierung + Referenzlösungen

**Files:**
- Create: `tools/normalize.py`, `tools/validate_puzzles.py`, `puzzles/{easy,medium,hard,extreme,verify}.txt`, `puzzles/verify_solutions.txt`

**Interfaces:**
- Produces: Puzzle-Dateien (81-Zeichen-Zeilen, `0` = leer); `verify_solutions.txt` zeilenweise parallel zu `verify.txt`; `tools/validate_puzzles.py <in> [--solutions <out>]` — Exit 1 bei ungültigem/mehrdeutigem Puzzle.

- [ ] **Step 1: `tools/normalize.py`** — beliebige Quellformate → 81-Zeichen-Zeilen

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

- [ ] **Step 2: `tools/validate_puzzles.py`** — Gültigkeit, Lösbarkeit, Eindeutigkeit; schreibt optional Lösungen. Enthält einen eigenen Bitmask-Backtracker mit Lösungszähler (bewusst unabhängig von `impl/`, damit er später als Referenz-Checker taugt).

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

- [ ] **Step 3: Quellen herunterladen und normalisieren**

```bash
cd /home/michi/sudoku
S=/tmp/claude-1000/-home-michi/*/scratchpad; mkdir -p sudoku_dl 2>/dev/null || true
curl -fsSL http://norvig.com/easy50.txt   | python3 tools/normalize.py > puzzles/easy.txt
curl -fsSL https://projecteuler.net/project/resources/p096_sudoku.txt \
                                          | python3 tools/normalize.py > puzzles/medium.txt
curl -fsSL http://norvig.com/top95.txt    | python3 tools/normalize.py > puzzles/hard.txt
curl -fsSL http://norvig.com/hardest.txt  | python3 tools/normalize.py > puzzles/extreme.txt
wc -l puzzles/*.txt   # erwartet: easy 50, medium 50, hard 95, extreme 11
```

Falls eine URL nicht erreichbar ist: alternative Spiegel suchen (die Dateien sind vielfach gespiegelt, z.B. in GitHub-Klonen von Norvigs sudoku.py) — nicht selbst Puzzles erfinden.

- [ ] **Step 4: `extreme.txt` ergänzen** — Anti-Brute-Force-Puzzle (gegen Zeilen-Reihenfolge-Backtracking konstruiert, Wikipedia „Sudoku solving algorithms") ans Ende anhängen:

```
..............3.85..1.2.......5.7.....4...1...9.......5......73..2.1........4...9
```

(vorher mit `sed 's/\./0/g'` auf `0`-Format bringen). Die Validierung in Step 5 ist das Gate: fällt das Puzzle durch (nicht eindeutig/ungültig), wird es entfernt statt repariert.

- [ ] **Step 5: Alle Sets validieren**

```bash
python3 tools/validate_puzzles.py puzzles/easy.txt puzzles/medium.txt puzzles/hard.txt puzzles/extreme.txt
```

Erwartet: `OK` für alle vier Dateien. Jede Zeile, die als mehrdeutig gemeldet wird, aus der Datei löschen und neu validieren (mehrdeutige Puzzles machen den Lösungsvergleich im Harness unmöglich).

- [ ] **Step 6: Verify-Set bauen** — je 3 Puzzles aus easy/medium/hard, 2 aus extreme, plus das Puzzle aus dem alten Notebook:

```bash
{ head -3 puzzles/easy.txt; head -3 puzzles/medium.txt; head -3 puzzles/hard.txt; \
  head -2 puzzles/extreme.txt; \
  echo 780400120600075009000601078007040260001050930904060005070300012120007400049206007; \
} > puzzles/verify.txt
python3 tools/validate_puzzles.py puzzles/verify.txt --solutions puzzles/verify_solutions.txt
```

Erwartet: `OK`, `verify_solutions.txt` mit 12 Zeilen à 81 Ziffern.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "Add puzzle sets (Norvig easy50/top95/hardest, Euler p096) with validator"
```

---

### Task 3: Python-Kontrakt + `naive` + `mrv`

**Files:**
- Create: `impl/python/_contract.py`, `impl/python/naive.py`, `impl/python/mrv.py`

**Interfaces:**
- Produces: `_contract.run(solve, solve_batch=None)` — `solve(bytearray[81]) -> Sequence[int]|None`; `solve_batch(grids: list[bytes], threads: int) -> list`. Alle weiteren Python-Solver (Tasks 5–8) nutzen exakt diese Signaturen. `mrv.solve` wird von Task 8 (`mrv_mt`) importiert.

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

- [ ] **Step 2: `impl/python/naive.py`** — der Notebook-Algorithmus, nur auf flachem Board:

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

- [ ] **Step 3: `impl/python/mrv.py`** — Bitmasken + Most-Constrained-Cell:

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

- [ ] **Step 4: Manueller Smoke-Test (der Harness kommt erst in Task 4)**

```bash
cd /home/michi/sudoku
python3 impl/python/naive.py < puzzles/verify.txt > /tmp/naive.out 2>/tmp/naive.err
python3 impl/python/mrv.py   < puzzles/verify.txt > /tmp/mrv.out   2>/tmp/mrv.err
diff /tmp/naive.out puzzles/verify_solutions.txt && diff /tmp/mrv.out puzzles/verify_solutions.txt
cat /tmp/naive.err /tmp/mrv.err   # je eine Zeile ns=<zahl>
```

Erwartet: beide diffs leer, zwei plausible `ns=`-Zeilen. (naive darf auf verify.txt langsam sein — die zwei extreme-Puzzles können Sekunden dauern.)

- [ ] **Step 5: Commit**

```bash
git add impl && git commit -m "Add python naive and mrv solvers with shared I/O contract"
```

---

### Task 4: Harness — Discovery + Verify

**Files:**
- Create: `bench/run.py`

**Interfaces:**
- Produces: `python3 bench/run.py --verify [--lang L ...] [--algo A ...]` — baut via `make`, findet vorhandene Implementierungen, prüft gegen `puzzles/verify(_solutions).txt`, Exit 1 bei FAIL. Funktionen `discover()`, `run_solver(cmd, text, reps, threads, timeout) -> (lines, ns)` werden in Task 9 wiederverwendet.

- [ ] **Step 1: `bench/run.py` mit Discovery, THP-Fix und Verify-Modus**

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

- [ ] **Step 2: Verify laufen lassen**

```bash
python3 bench/run.py --verify
```

Erwartet: `PASS python/naive`, `PASS python/mrv`, `2/2 implementations pass verify`, Exit 0.

- [ ] **Step 3: Negativtest** — absichtlich eine Lösung in `puzzles/verify_solutions.txt` um eine Ziffer ändern, `--verify` muss beide Implementierungen FAILen und Exit 1 liefern; Änderung zurücknehmen (`git checkout -- puzzles/verify_solutions.txt`), Verify wieder grün.

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

- [ ] **Step 1: `impl/python/norvig.py`** — Constraint Propagation (Elimination + Naked/Hidden Singles als Fixpunkt) plus MRV-Suche, Kandidaten als Bitmasken statt Strings (Norvigs Algorithmus, nicht seine Datenstrukturen):

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

- [ ] **Step 1: `impl/python/dlx.py`** — Algorithm X mit Dancing Links auf flachen Arrays (kein Objektgraph). 324 Spalten: Zelle(81) + Zeile×Ziffer(81) + Spalte×Ziffer(81) + Box×Ziffer(81); 729 Optionen à 4 Knoten. Matrix wird pro Puzzle neu gebaut (Aufbau ist Teil der Messung — für die kompilierten Sprachen später als Optimierung dokumentieren: einmal bauen, Clues covern/uncovern).

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
- Consumes: `_contract.run(solve)`; `solve` liefert `None` für „nicht rein logisch lösbar" → `UNSOLVED`.

- [ ] **Step 1: `impl/python/rules.py`** — Technik-Pipeline bis Fixpunkt: Naked Singles, Hidden Singles, Naked Pairs, Hidden Pairs, Pointing Pairs, Box-Line-Reduction, X-Wing, Swordfish. Kein Raten. Widerspruch ⇒ `None` (nie falsche Lösung).

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

Hinweis an den Implementierer: der Code oben ist Vorlage, keine Kopiervorschrift — insbesondere `naked_pairs` (die `prog |=`-Zeile ist umständlich) und die doppelte `li`-Berechnung in `fish` beim Schreiben glätten. Verhalten ist durch Step 2/3 abgesichert.

- [ ] **Step 2: Verify** — `python3 bench/run.py --verify --lang python` → `PASS python/rules (N unsolved)`. Erwartung: alle easy gelöst, die beiden extreme-Puzzles im Verify-Set bleiben UNSOLVED; kein FAIL.

- [ ] **Step 3: Plausibilität der Lösungsquote** — `python3 impl/python/rules.py < puzzles/easy.txt | grep -c UNSOLVED` → erwartet 0 oder nahe 0; `... < puzzles/hard.txt | grep -c UNSOLVED` → deutlich > 0. Zahlen im Commit-Text festhalten.

- [ ] **Step 4: Commit** — `git add impl && git commit -m "Add python rule-based solver (singles, pairs, pointing, box-line, fish)"`

---

### Task 8: Python `mrv_mt`

**Files:**
- Create: `impl/python/mrv_mt.py`

**Interfaces:**
- Consumes: `mrv.solve`, `_contract.run(None, solve_batch)`.

- [ ] **Step 1: `impl/python/mrv_mt.py`** — `multiprocessing.Pool` über Puzzles; Pool wird einmal lazily erzeugt (Fork-Overhead zahlt nur die erste rep; bei kalibrierten reps amortisiert):

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

- [ ] **Step 2: Verify + Speedup-Smoke-Test**

```bash
python3 bench/run.py --verify --lang python     # PASS python/mrv_mt (6/6)
python3 impl/python/mrv_mt.py 20 1 < puzzles/hard.txt 2>&1 >/dev/null
python3 impl/python/mrv_mt.py 20 4 < puzzles/hard.txt 2>&1 >/dev/null
```

Erwartet: ns mit 4 Threads deutlich kleiner als mit 1 (nicht notwendig 4×; Fork + IPC kosten).

- [ ] **Step 3: Commit** — `git add impl && git commit -m "Add python mrv_mt multiprocessing variant"`

---

### Task 9: Harness — Bench-Modus + Report + JSON

**Files:**
- Modify: `bench/run.py` (Bench-Teil ersetzt den Platzhalter am Ende von `main()`)

**Interfaces:**
- Produces: `python3 bench/run.py [--set S ...]` — kalibriert reps (Ziel ≥1s), Median aus 3 Läufen, Timeout ⇒ DNF, Text-Tabelle auf stdout, Rohdaten `results/<unix-ts>.json`. JSON-Schema: `{"meta": {"host", "cpu", "date"}, "runs": [{"lang", "algo", "set", "reps", "ns_median", "us_per_puzzle", "puzzles", "solved", "status"}]}` — Task 10 und die CI hängen von diesem Schema ab.

- [ ] **Step 1: Bench-Funktionen an `bench/run.py` anfügen und in `main()` einhängen**

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

In `main()` den Platzhalter ersetzen durch:

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

und `--set` als `ap.add_argument('--set', action='append', choices=SETS)` ergänzen.

- [ ] **Step 2: Kompletter Python-Lauf**

```bash
python3 bench/run.py --lang python
```

Erwartet: Tabelle mit 6 Algorithmen × 4 Sets; `naive` auf `extreme` sehr wahrscheinlich `dnf` (das Anti-Brute-Force-Puzzle ist genau dafür da); `rules` mit Teil-Lösungsquote; JSON-Datei unter `results/`. Plausibilitätsordnung: mrv/norvig/dlx ≪ naive; mrv_mt schneller als mrv auf hard/extreme.

- [ ] **Step 3: Commit** — `git add bench && git commit -m "Add bench mode: calibrated reps, median of 3, JSON results"`

---

### Task 10: README-Generator + Charts

**Files:**
- Modify: `bench/run.py` (`--readme`-Flag), `README.md` (generierte Sektion zwischen den Markern)
- Create: `assets/time_by_impl.png`, `assets/rules_solve_rate.png` (generiert)

**Interfaces:**
- Consumes: JSON-Schema aus Task 9.
- Produces: `python3 bench/run.py --readme results/<file>.json` ersetzt den Block zwischen `<!-- BENCH:BEGIN -->` und `<!-- BENCH:END -->` durch Markdown-Tabellen (µs/Puzzle pro Set, Puzzles/s, Lösungsquote, Speedup mrv_mt vs mrv) und bindet die zwei PNGs ein.

- [ ] **Step 0: REQUIRED — vor dem Schreiben von Chart-Code die `dataviz`-Skill laden** (Skill-Tool, Name `dataviz`); Charts danach mit matplotlib bauen: Balkenchart Zeit pro Algorithmus×Sprache mit log-Skala (Spanne umfasst Größenordnungen), Solve-Rate-Chart für `rules` pro Set.

- [ ] **Step 1: `--readme`-Flag implementieren** — JSON laden, Tabellen als Markdown formatieren (Sets als Spalten, Implementierungen als Zeilen, `dnf`/`error` sichtbar), PNGs nach `assets/` schreiben, README-Block zwischen den Markern ersetzen (Datei komplett lesen, Block per String-Split austauschen, zurückschreiben). Meta-Zeile mit CPU + Datum unter die Tabellen.

- [ ] **Step 2: Generieren + anschauen** — `python3 bench/run.py --readme results/<neueste>.json`; README rendern (`glow README.md` oder im Editor), PNGs öffnen; prüfen: log-Skala beschriftet, dnf-Zellen klar erkennbar.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add README report generation with charts"`

---

### Task 11: Phase-1-Abschluss

- [ ] **Step 1: Gesamtlauf aus sauberem Zustand**

```bash
cd /home/michi/sudoku && git status --short   # muss leer sein
python3 bench/run.py                          # discovery findet nur python -> 6 impls
```

Erwartet: 6× PASS im Verify, vollständige Bench-Tabelle, JSON + README aktuell.

- [ ] **Step 2: Push**

```bash
git push -u origin main
```

(Repo bleibt vorerst privat; public erst nach Phase 6 laut Spec.)

---

## Folgepläne (nicht Teil dieses Plans)

- Phase 3: C (alle 6, Vorlage für kompilierte Sprachen; `-O3 -march=native -flto`, pthreads für `mrv_mt`) + Makefile-Targets `build/c-<algo>`.
- Phase 4: C++, Rust (Cargo-Workspace), Go, JavaScript.
- Phase 5: Assembly (NASM): naive, mrv, mrv_mt, norvig, dlx, rules.
- Phase 6: Mikrooptimierungs-Pass, finaler lokaler Volllauf.
- Phase 7: `.github/workflows/bench.yml`, Repo public, CI-Referenzlauf.
