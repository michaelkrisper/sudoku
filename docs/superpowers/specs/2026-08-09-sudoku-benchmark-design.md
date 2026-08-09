# Sudoku Solver Benchmark — Design

Datum: 2026-08-09
Repo: michaelkrisper/sudoku

## Ziel

Benchmark von 5 Sudoku-Algorithmen plus einer Multithreading-Variante
in 7 Sprachen (42 Implementierungen), mit Fokus auf maximale Performance
pro Sprache (Compiler-Flags, Cache-Layout, Mikrooptimierungen).
Die Solver bleiben minimal (reine stdin/stdout-Programme); Tabellen und
Charts erzeugt ausschließlich der Harness. Normierte Referenz-Ergebnisse
kommen aus GitHub Actions; lokale Läufe dienen der Entwicklung.

## Algorithmen

| Key      | Beschreibung |
|----------|--------------|
| `naive`  | Backtracking, erste leere Zelle, Ziffern 1–9 der Reihe nach. Baseline (entspricht dem alten Notebook). |
| `mrv`    | Backtracking mit Bitmasken-Kandidaten (27 Masken: 9 Zeilen, 9 Spalten, 9 Boxen) und Most-Constrained-Cell-Auswahl (wenigste Kandidaten zuerst, `popcnt`/`tzcnt`). |
| `norvig` | Constraint Propagation nach Peter Norvig: Elimination + Naked Singles als Fixpunkt-Iteration, dann Suche mit MRV. |
| `dlx`    | Knuths Algorithm X mit Dancing Links; Sudoku als Exact-Cover-Matrix (729 Zeilen × 324 Spalten). |
| `rules`  | Rein regelbasiert, ohne Raten: Naked/Hidden Singles, Naked/Hidden Pairs, Pointing Pairs, Box-Line-Reduction, X-Wing, Swordfish. Darf Puzzles ungelöst lassen — die Lösungsquote ist Teil des Ergebnisses. Darf nie eine falsche Lösung liefern. |
| `mrv_mt` | Multithreading-Variante von `mrv`: Thread-Pool parallelisiert über die Puzzles des Batches (Puzzle-Level-Parallelismus; die Suche selbst bleibt sequenziell). Python: `multiprocessing` (GIL); Assembly: pthreads. Report zeigt Speedup gegenüber `mrv`. |

## Sprachen

Python (CPython), JavaScript (Node), Go, Rust, C++, C, x86-64 Assembly
(NASM, Linux-Syscalls; Zielmaschine MacBook Pro 11,1 = Haswell, AVX2/BMI
verfügbar).

Performance-Vorgaben:
- C/C++/Rust: `-O3 -march=native -flto` (Rust: `opt-level=3`, `lto=true`, `target-cpu=native`).
- Assembly: Bitmasken in Registern, `tzcnt`/`popcnt`, minimale Speicherzugriffe.
- Python: flache Arrays statt verschachtelter Listen, lokale Namensbindung in Hot Loops; numpy nur wo es tatsächlich schneller ist.
- JavaScript: monomorphe Typed Arrays (`Uint8Array`/`Uint32Array`).
- Board-Repräsentation überall flach (81 Bytes) + 27 Bitmasken, cache-freundlich.

## I/O-Vertrag (identisch für alle 42 Implementierungen)

- Aufruf: `solver [reps] [threads] < puzzles.txt`; beide Argumente
  optional, default 1. Single-threaded-Solver ignorieren `threads`.
- Input (stdin): eine Zeile pro Puzzle, exakt 81 Zeichen aus `0`–`9`
  (`0` = leere Zelle). Leere Zeilen und Zeilen mit `#` werden ignoriert.
- Ablauf: alle Puzzles einlesen und parsen → Monotonic-Clock starten →
  Solve-Schleife `reps`-mal über alle Puzzles → Clock stoppen.
  Jede Wiederholung löst eine frische Kopie des ungelösten Puzzles
  (der Kopiervorgang ist Teil der Messung, bei 81 Bytes vernachlässigbar).
- Output (stdout): pro Puzzle eine Zeile, in Eingabereihenfolge:
  die 81-stellige Lösung oder `UNSOLVED`.
- Output (stderr): genau eine Zeile `ns=<gesamt-nanosekunden>` für die
  komplette Solve-Schleife (alle reps).
- Exit-Code 0, auch bei UNSOLVED-Puzzles.

Damit bleibt Interpreter-Start und I/O außerhalb der Messung; der
Harness wählt `reps` so, dass die Messzeit ≥ ~1 s beträgt, und teilt.

## Puzzle-Sets (`puzzles/`)

| Datei | Inhalt |
|-------|--------|
| `easy.txt` | 50 leichte Puzzles (viele Clues) |
| `medium.txt` | 50 mittlere Puzzles |
| `hard.txt` | Norvigs hard95 |
| `extreme.txt` | 17-Clue-Auswahl + Anti-Backtracking-Puzzles (u.a. „platinum blonde") |
| `verify.txt` + `verify_solutions.txt` | Verifikationsset mit bekannten Lösungen für die Korrektheitsprüfung |

Ergebnisse werden pro Set aggregiert. Pro (Implementierung, Set) gilt
ein Timeout (default 60 s für den ganzen Lauf); Überschreitung = DNF.

## Harness (`bench/run.py`, ein einziger für alle)

1. **Build:** ruft `make` im Repo-Root; jede kompilierte Sprache hat ein
   Makefile-Target, Skriptsprachen brauchen keins.
2. **Verify:** führt jede Implementierung auf `verify.txt` aus und
   vergleicht mit `verify_solutions.txt`. `rules` darf `UNSOLVED`
   liefern, aber nie eine abweichende Lösung. Fehlschlag ⇒
   Implementierung wird im Benchmark als FAIL markiert, nicht gemessen.
3. **Bench:** pro (Implementierung, Set): reps kalibrieren, laufen
   lassen, `ns=` einlesen, Lösungen erneut verifizieren. `mrv_mt` läuft
   mit `threads` = Anzahl CPU-Kerne. Der Harness löscht beim Start
   `PR_SET_THP_DISABLE` per `prctl(41,0)` (ctypes), damit lokale Läufe
   aus Claude-Sessions dieselbe THP-Umgebung haben wie ein normales
   Terminal bzw. GitHub-Runner.
4. **Report:** Text-Tabelle auf stdout (µs/Puzzle Median über Sets,
   Puzzles/s, Lösungsquote); Rohdaten als JSON nach
   `results/<timestamp>.json`.
5. **README:** generiert aus dem JSON die Ergebnis-Sektion des README:
   Markdown-Tabellen plus Chart-PNGs (matplotlib) nach `assets/` —
   Zeit pro Algorithmus×Sprache (log-Skala, die Spanne beträgt mehrere
   Größenordnungen) und Lösungsquote für `rules`. Nur der Harness
   visualisiert; die 42 Solver selbst bleiben beim minimalen I/O-Vertrag.

CLI: `bench/run.py [--lang ...] [--algo ...] [--set ...]` zum Filtern.

## Repo-Struktur

```
sudoku/
├── Makefile                 # baut alle kompilierten Implementierungen
├── algorithms.md            # Beschreibung der 5 Algorithmen
├── puzzles/                 # Puzzle-Sets (s.o.)
├── impl/
│   ├── python/{naive,mrv,norvig,dlx,rules,mrv_mt}.py
│   ├── javascript/*.js
│   ├── go/*.go
│   ├── rust/               # ein Cargo-Workspace, 5 Binaries
│   ├── cpp/*.cpp
│   ├── c/*.c
│   └── asm/*.asm
├── bench/run.py             # Build + Verify + Bench + Report + README-Generierung
├── assets/                  # generierte Chart-PNGs fürs README
└── results/                 # Roh-JSON pro Lauf (gitignored bis auf Beispiele)
```

Das alte `SudokuSolver.ipynb` wird gelöscht (bleibt in der Git-History).

## Fehlerbehandlung

- Ungültige Puzzles (Widerspruch in den Clues): Solver gibt `UNSOLVED` aus, stürzt nicht ab.
- Harness wertet fehlende/zu wenige Output-Zeilen, fehlendes `ns=`, Crash oder Timeout als FAIL/DNF und benennt die Implementierung im Report.

## CI: normierte Ergebnisse via GitHub Actions

- `.github/workflows/bench.yml`: `workflow_dispatch` + Push auf `main`;
  ubuntu-latest; installiert Toolchains (gcc, g++, rustup, go, node,
  nasm), baut, führt `bench/run.py` komplett aus.
- Ergebnisse: `results/<sha>.json`, Text-Report und Chart-PNGs als
  Workflow-Artifacts; bei `workflow_dispatch` zusätzlich Commit von
  README-Sektion + `assets/` zurück ins Repo.
- Runner-Hardware ist einheitlich, aber shared — der Report weist die
  Runner-CPU aus (`/proc/cpuinfo`) und der Harness nimmt pro Messung
  den Median aus 3 Läufen.
- Das Repo wird public geschaltet, sobald der komplette Benchmark lokal
  einmal grün durchgelaufen ist (vorher: Test auf dieser Maschine).

## Umsetzungsphasen

1. Gerüst: Repo-Struktur, Puzzle-Sets, Referenzlösungen, Harness mit Verify.
2. Python: alle 6 Implementierungen (dient als Referenz für alle weiteren).
3. C: alle 6 (Vorlage für die übrigen kompilierten Sprachen).
4. C++, Rust, Go, JavaScript.
5. Assembly: naive, mrv, mrv_mt (pthreads), dann norvig, dlx, rules.
6. Mikrooptimierungs-Pass pro Sprache, finaler lokaler Volllauf.
7. CI-Workflow, Repo public, Referenzlauf auf GitHub-Runnern, Ergebnisse ins README.

Jede Phase endet mit grünem Verify und einem Commit.

## Nicht-Ziele (bewusst weggelassen)

- GUI, Puzzle-Generator, Schwierigkeitsbewertung.
- Intra-Puzzle-Parallelisierung (paralleler Suchbaum): parallelisiert wird nur über Puzzles (`mrv_mt`); die 5 Kern-Algorithmen bleiben single-threaded, damit der Algorithmen-Vergleich sauber bleibt.
