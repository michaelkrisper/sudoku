//! Norvig-style constraint propagation + search (bitmask candidates).
//!
//! Eliminate + naked singles + hidden singles to a fixpoint, then
//! depth-first search with MRV cell choice.

use sudoku::{parse_args, read_puzzles, run_solver, write_results, Grid};

const ALL: u16 = 0x3FE; // bits 1..9 set

struct Tables {
    peers: [[u8; 20]; 81],   // 20 peers per cell
    units: [[u8; 9]; 27],    // 9 rows, 9 cols, 9 boxes
    unit_of: [[u8; 3]; 81],  // the 3 units containing each cell
}

fn init_tables() -> Tables {
    let mut t = Tables {
        peers: [[0; 20]; 81],
        units: [[0; 9]; 27],
        unit_of: [[0; 3]; 81],
    };
    for r in 0..9 {
        for c in 0..9 {
            t.units[r][c] = (r * 9 + c) as u8;
            t.units[9 + c][r] = (r * 9 + c) as u8;
        }
    }
    for b in 0..9 {
        let (br, bc) = (b / 3, b % 3);
        for k in 0..9 {
            t.units[18 + b][k] = ((br * 3 + k / 3) * 9 + bc * 3 + k % 3) as u8;
        }
    }
    for i in 0..81 {
        t.unit_of[i] = [
            (i / 9) as u8,
            (9 + i % 9) as u8,
            (18 + (i / 27) * 3 + (i % 9) / 3) as u8,
        ];
        let mut seen = [false; 81];
        seen[i] = true;
        let mut np = 0;
        for u in 0..3 {
            for k in 0..9 {
                let j = t.units[t.unit_of[i][u] as usize][k] as usize;
                if !seen[j] {
                    seen[j] = true;
                    t.peers[i][np] = j as u8;
                    np += 1;
                }
            }
        }
    }
    t
}

fn eliminate(t: &Tables, cand: &mut [u16; 81], i: usize, bit: u16) -> bool {
    let mut c = cand[i];
    if c & bit == 0 {
        return true;
    }
    c &= !bit;
    if c == 0 {
        return false;
    }
    cand[i] = c;
    if c & (c - 1) == 0 {
        // naked single: strip from peers
        for k in 0..20 {
            let p = t.peers[i][k] as usize;
            if cand[p] & c != 0 && !eliminate(t, cand, p, c) {
                return false;
            }
        }
    }
    for u in 0..3 {
        // hidden single for `bit`?
        let unit = &t.units[t.unit_of[i][u] as usize];
        let mut place: i32 = -1;
        for &cell in unit {
            if cand[cell as usize] & bit != 0 {
                if place >= 0 {
                    place = -2;
                    break;
                }
                place = cell as i32;
            }
        }
        if place == -1 {
            return false; // bit has nowhere left in unit
        }
        if place >= 0 {
            let p = place as usize;
            let pc = cand[p];
            if pc & (pc - 1) != 0 && !assign(t, cand, p, bit) {
                return false;
            }
        }
    }
    true
}

fn assign(t: &Tables, cand: &mut [u16; 81], i: usize, bit: u16) -> bool {
    let mut other = cand[i] & !bit;
    while other != 0 {
        let lb = other & other.wrapping_neg();
        other ^= lb;
        if !eliminate(t, cand, i, lb) {
            return false;
        }
    }
    true
}

/// On success, cand holds the solved grid (all cells single bits).
fn search(t: &Tables, cand: &mut [u16; 81]) -> bool {
    let mut best = usize::MAX;
    let mut best_n = 10;
    for i in 0..81 {
        // MRV cell
        let c = cand[i];
        if c & (c - 1) != 0 {
            let n = c.count_ones();
            if n < best_n {
                best = i;
                best_n = n;
                if n == 2 {
                    break;
                }
            }
        }
    }
    if best == usize::MAX {
        return true; // all cells singles: solved
    }
    let mut c = cand[best];
    while c != 0 {
        let bit = c & c.wrapping_neg();
        c ^= bit;
        let mut trial = *cand;
        if assign(t, &mut trial, best, bit) && search(t, &mut trial) {
            *cand = trial;
            return true;
        }
    }
    false
}

fn solve(t: &Tables, g: &mut Grid) -> bool {
    let mut cand = [ALL; 81];
    for i in 0..81 {
        let d = g[i];
        if d != 0 {
            let bit = 1u16 << d;
            if cand[i] != bit && !assign(t, &mut cand, i, bit) {
                return false;
            }
        }
    }
    if !search(t, &mut cand) {
        return false;
    }
    for (cell, &c) in g.iter_mut().zip(cand.iter()) {
        *cell = c.trailing_zeros() as u8;
    }
    true
}

fn main() {
    let (reps, _threads) = parse_args();
    let tables = init_tables();
    let puzzles = read_puzzles();
    let (results, ns) = run_solver(reps, &puzzles, |g| solve(&tables, g));
    write_results(&results, ns);
}
