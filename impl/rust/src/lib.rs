//! Shared I/O contract for the sudoku solver binaries, plus the mrv
//! solver core (used by both `mrv` and `mrv_mt`).

use std::io::{Read, Write};
use std::time::Instant;

pub type Grid = [u8; 81];

/// `solver [reps] [threads]`, both optional, default 1.
pub fn parse_args() -> (u64, usize) {
    let mut args = std::env::args().skip(1);
    let reps = args
        .next()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(1)
        .max(1);
    let threads = args
        .next()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1)
        .max(1);
    (reps, threads)
}

/// Read all puzzles from stdin. Empty lines, `#` comments and malformed
/// lines are skipped.
pub fn read_puzzles() -> Vec<Grid> {
    let mut input = String::new();
    let _ = std::io::stdin().lock().read_to_string(&mut input);
    let mut puzzles = Vec::new();
    for line in input.lines() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let bytes = line.as_bytes();
        if bytes.len() != 81 || !bytes.iter().all(u8::is_ascii_digit) {
            continue;
        }
        let mut g = [0u8; 81];
        for (cell, &b) in g.iter_mut().zip(bytes) {
            *cell = b - b'0';
        }
        puzzles.push(g);
    }
    puzzles
}

/// Timed solve loop for the single-threaded solvers: `reps` passes over
/// all puzzles, each solving a fresh copy of the unsolved grid.
pub fn run_solver(
    reps: u64,
    puzzles: &[Grid],
    mut solve: impl FnMut(&mut Grid) -> bool,
) -> (Vec<Option<Grid>>, u128) {
    let mut results = vec![None; puzzles.len()];
    let t0 = Instant::now();
    for _ in 0..reps {
        for (puzzle, result) in puzzles.iter().zip(results.iter_mut()) {
            let mut g = *puzzle;
            *result = solve(&mut g).then_some(g);
        }
    }
    (results, t0.elapsed().as_nanos())
}

/// One line per puzzle (81 digits or UNSOLVED) in one write, then
/// `ns=<nanoseconds>` on stderr.
pub fn write_results(results: &[Option<Grid>], ns: u128) {
    let mut buf = Vec::with_capacity(results.len() * 82);
    for result in results {
        match result {
            Some(g) => {
                buf.extend(g.iter().map(|&d| d + b'0'));
                buf.push(b'\n');
            }
            None => buf.extend_from_slice(b"UNSOLVED\n"),
        }
    }
    let mut out = std::io::stdout().lock();
    let _ = out.write_all(&buf);
    let _ = out.flush();
    eprintln!("ns={ns}");
}

/// Backtracking with bitmask candidates and most-constrained-cell order.
pub mod mrv {
    use crate::Grid;

    const ALL: u16 = 0x3FE; // bits 1..9 set

    #[inline]
    fn row(i: usize) -> usize {
        i / 9
    }
    #[inline]
    fn col(i: usize) -> usize {
        i % 9
    }
    #[inline]
    fn boxx(i: usize) -> usize {
        i / 27 * 3 + i % 9 / 3
    }

    struct Solver {
        rows: [u16; 9],
        cols: [u16; 9],
        boxes: [u16; 9],
        empties: [u8; 81],
        n: usize,
    }

    fn bt(s: &mut Solver, g: &mut Grid, k: usize) -> bool {
        if k == s.n {
            return true;
        }
        let mut best_j = k;
        let mut best_n = 10;
        let mut best_cand = 0u16;
        for j in k..s.n {
            let i = s.empties[j] as usize;
            let cand = s.rows[row(i)] & s.cols[col(i)] & s.boxes[boxx(i)];
            let nc = cand.count_ones();
            if nc < best_n {
                if nc == 0 {
                    return false; // dead end
                }
                best_j = j;
                best_n = nc;
                best_cand = cand;
                if nc == 1 {
                    break;
                }
            }
        }
        let i = s.empties[best_j] as usize;
        s.empties[best_j] = s.empties[k];
        s.empties[k] = i as u8;
        let (r, c, b) = (row(i), col(i), boxx(i));
        let mut cand = best_cand;
        while cand != 0 {
            let bit = cand & cand.wrapping_neg();
            cand ^= bit;
            g[i] = bit.trailing_zeros() as u8;
            s.rows[r] ^= bit;
            s.cols[c] ^= bit;
            s.boxes[b] ^= bit;
            if bt(s, g, k + 1) {
                return true;
            }
            s.rows[r] ^= bit;
            s.cols[c] ^= bit;
            s.boxes[b] ^= bit;
        }
        g[i] = 0;
        false
    }

    pub fn solve(g: &mut Grid) -> bool {
        let mut s = Solver {
            rows: [ALL; 9],
            cols: [ALL; 9],
            boxes: [ALL; 9],
            empties: [0; 81],
            n: 0,
        };
        for i in 0..81 {
            let d = g[i];
            if d != 0 {
                let bit = 1u16 << d;
                let (r, c, b) = (row(i), col(i), boxx(i));
                if s.rows[r] & s.cols[c] & s.boxes[b] & bit == 0 {
                    return false; // duplicate clue
                }
                s.rows[r] ^= bit;
                s.cols[c] ^= bit;
                s.boxes[b] ^= bit;
            } else {
                s.empties[s.n] = i as u8;
                s.n += 1;
            }
        }
        bt(&mut s, g, 0)
    }
}
