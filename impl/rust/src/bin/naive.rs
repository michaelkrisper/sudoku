//! Naive backtracking: first empty cell, digits 1-9 in order.

use sudoku::{parse_args, read_puzzles, run_solver, write_results, Grid};

fn valid(g: &Grid, pos: usize, d: u8) -> bool {
    let rs = pos - pos % 9;
    let c = pos % 9;
    let bs = pos / 27 * 27 + pos % 9 / 3 * 3;
    for i in 0..9 {
        if g[rs + i] == d || g[c + 9 * i] == d {
            return false;
        }
    }
    for r in 0..3 {
        for i in 0..3 {
            if g[bs + 9 * r + i] == d {
                return false;
            }
        }
    }
    true
}

fn bt(g: &mut Grid, start: usize) -> bool {
    let mut pos = start;
    while pos < 81 && g[pos] != 0 {
        pos += 1;
    }
    if pos == 81 {
        return true;
    }
    for d in 1..=9 {
        if valid(g, pos, d) {
            g[pos] = d;
            if bt(g, pos + 1) {
                return true;
            }
        }
    }
    g[pos] = 0;
    false
}

fn solve(g: &mut Grid) -> bool {
    for i in 0..81 {
        // reject inconsistent clues
        let d = g[i];
        if d != 0 {
            g[i] = 0;
            let ok = valid(g, i, d);
            g[i] = d;
            if !ok {
                return false;
            }
        }
    }
    bt(g, 0)
}

fn main() {
    let (reps, _threads) = parse_args();
    let puzzles = read_puzzles();
    let (results, ns) = run_solver(reps, &puzzles, solve);
    write_results(&results, ns);
}
