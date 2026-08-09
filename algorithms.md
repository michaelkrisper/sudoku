# The algorithms

All six solve the same problem and are held to the same contract, so the
benchmark compares implementations rather than problem statements. Every
language implements all six, and `rules` in every language must leave exactly
the same puzzles unsolved — that equality is checked as part of the build.

## `naive` — backtracking

The textbook version, and the one this repository started out as. Find the first
empty cell in row-major order, try the digits 1 to 9, recurse, undo on failure.
Validity is checked by scanning the cell's row, column and box each time.

It is here as the baseline that makes the others legible. On easy puzzles it is
merely slow; on a puzzle constructed to defeat row-major guessing it does not
finish at all, and the benchmark reports DNF.

## `mrv` — backtracking with bitmasks and most-constrained-cell

Same search, two changes that matter enormously:

- **Bitmasks.** Each row, column and box carries a 9-bit mask of the digits still
  available. The candidates for a cell are one AND of three masks, and the next
  candidate is one count-trailing-zeros instruction. No scanning.
- **Most-constrained-cell first (minimum remaining values).** Instead of the
  first empty cell, branch on the cell with the fewest candidates. A cell with
  one candidate is forced, so the search commits to it without branching at all.

The heuristic is what does the work: it prunes the tree near the root, where a
wrong choice is most expensive.

## `norvig` — constraint propagation with search

Peter Norvig's approach. Before every search step, propagate to a fixpoint:

- **Elimination:** assigning a digit removes it from all 20 peers.
- **Naked single:** a cell down to one candidate assigns it, which cascades.
- **Hidden single:** a digit with only one possible place left in a unit is
  assigned there, which cascades too.

Only when propagation stalls does it branch, again on minimum remaining values.
Most easy and medium puzzles are solved entirely by propagation, with no search
at all.

## `dlx` — dancing links

Sudoku restated as exact cover: 324 constraints (each cell filled, each digit
once per row, per column, per box) and 729 candidate placements, each satisfying
exactly four constraints. Knuth's Algorithm X searches this matrix, and the
dancing-links representation makes covering and *uncovering* a column O(1)
pointer surgery — backtracking costs the same as descending.

Every language builds the matrix once at startup and, per puzzle, copies only the
mutable link arrays and covers the clue rows. That copy is inside the measured
region; the one-time construction is not.

## `rules` — pure logic, no guessing

Human solving techniques applied to a fixpoint, cheapest first: naked singles,
hidden singles, naked pairs, hidden pairs, pointing pairs, box-line reduction,
X-Wing, Swordfish. It never guesses and never backtracks.

Consequently it does not always finish, and that is the point: the share of
puzzles it completes measures how much of a set is solvable by pure deduction.
Where it prints `UNSOLVED`, the puzzle genuinely requires search. The one hard
rule is that a wrong grid is never printed — the finished grid is validated
against all 27 units before output, and any contradiction found during
elimination yields `UNSOLVED`.

## `mrv_mt` — the same search, parallel over puzzles

`mrv`, with the batch distributed across worker threads. Scheduling is dynamic —
workers pull the next puzzle index off a shared atomic counter — because puzzle
difficulty inside a set varies by orders of magnitude and a static split would
leave most threads idle behind one straggler.

The search itself stays sequential. Parallelizing the search tree would change
the algorithm being measured; parallelizing the batch measures what the language
and its runtime cost for the same work. Python is the interesting case here: the
GIL forces `multiprocessing`, so its speedup carries process-startup and
pickling costs the thread-based languages do not pay.
