//! Backtracking with bitmask candidates and most-constrained-cell order.

use sudoku::{mrv, parse_args, read_puzzles, run_solver, write_results};

fn main() {
    let (reps, _threads) = parse_args();
    let puzzles = read_puzzles();
    let (results, ns) = run_solver(reps, &puzzles, mrv::solve);
    write_results(&results, ns);
}
