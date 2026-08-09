//! Knuth's Algorithm X with Dancing Links, flat-array based.
//!
//! The exact-cover matrix is built once at startup; per puzzle only the
//! mutable link arrays (L/R/U/D/size) are copied and the clue rows covered.

use sudoku::{parse_args, read_puzzles, run_solver, write_results, Grid};

const NCOLS: usize = 324; // 81 cell + 81 row-digit + 81 col-digit + 81 box-digit
const NNODES: usize = 1 + NCOLS + 729 * 4; // root + headers + 4 nodes per candidate row
const FIRST: usize = NCOLS + 1; // index of first row node

/// Immutable after build().
struct Base {
    c0: [u16; NNODES],
    rid: [u16; NNODES],
    l0: [u16; NNODES],
    r0: [u16; NNODES],
    u0: [u16; NNODES],
    d0: [u16; NNODES],
    sz0: [u16; NCOLS + 1],
}

/// Per-puzzle working copies.
struct Dlx {
    l: [u16; NNODES],
    r: [u16; NNODES],
    u: [u16; NNODES],
    d: [u16; NNODES],
    sz: [u16; NCOLS + 1],
    sol: [u16; 81],
    nsol: usize,
}

fn build() -> Box<Base> {
    let mut b = Box::new(Base {
        c0: [0; NNODES],
        rid: [0; NNODES],
        l0: [0; NNODES],
        r0: [0; NNODES],
        u0: [0; NNODES],
        d0: [0; NNODES],
        sz0: [0; NCOLS + 1],
    });
    for h in 0..=NCOLS {
        // 0 = root, 1..324 = column headers
        b.l0[h] = (if h > 0 { h - 1 } else { NCOLS }) as u16;
        b.r0[h] = (if h < NCOLS { h + 1 } else { 0 }) as u16;
        b.u0[h] = h as u16;
        b.d0[h] = h as u16;
    }
    let mut n = FIRST;
    for cell in 0..81 {
        let (r, c) = (cell / 9, cell % 9);
        let bx = r / 3 * 3 + c / 3;
        for d in 0..9 {
            // d = digit - 1
            let rid = (cell * 9 + d) as u16;
            let cols = [1 + cell, 82 + r * 9 + d, 163 + c * 9 + d, 244 + bx * 9 + d];
            for col in cols {
                b.c0[n] = col as u16;
                b.rid[n] = rid;
                b.d0[n] = col as u16;
                let up = b.u0[col] as usize;
                b.u0[n] = up as u16;
                b.d0[up] = n as u16;
                b.u0[col] = n as u16;
                b.sz0[col] += 1;
                n += 1;
            }
            let f = n - 4; // link the 4 nodes of this row circularly
            b.l0[f] = (f + 3) as u16;
            b.r0[f] = (f + 1) as u16;
            b.l0[f + 1] = f as u16;
            b.r0[f + 1] = (f + 2) as u16;
            b.l0[f + 2] = (f + 1) as u16;
            b.r0[f + 2] = (f + 3) as u16;
            b.l0[f + 3] = (f + 2) as u16;
            b.r0[f + 3] = f as u16;
        }
    }
    b
}

impl Dlx {
    fn new() -> Box<Dlx> {
        Box::new(Dlx {
            l: [0; NNODES],
            r: [0; NNODES],
            u: [0; NNODES],
            d: [0; NNODES],
            sz: [0; NCOLS + 1],
            sol: [0; 81],
            nsol: 0,
        })
    }

    fn cover(&mut self, base: &Base, c0: u16) {
        let c = c0 as usize;
        self.r[self.l[c] as usize] = self.r[c];
        self.l[self.r[c] as usize] = self.l[c];
        let mut i = self.d[c];
        while i != c0 {
            let mut j = self.r[i as usize];
            while j != i {
                let jj = j as usize;
                self.d[self.u[jj] as usize] = self.d[jj];
                self.u[self.d[jj] as usize] = self.u[jj];
                self.sz[base.c0[jj] as usize] -= 1;
                j = self.r[jj];
            }
            i = self.d[i as usize];
        }
    }

    fn uncover(&mut self, base: &Base, c0: u16) {
        let c = c0 as usize;
        let mut i = self.u[c];
        while i != c0 {
            let mut j = self.l[i as usize];
            while j != i {
                let jj = j as usize;
                self.sz[base.c0[jj] as usize] += 1;
                self.d[self.u[jj] as usize] = j;
                self.u[self.d[jj] as usize] = j;
                j = self.l[jj];
            }
            i = self.u[i as usize];
        }
        self.r[self.l[c] as usize] = c0;
        self.l[self.r[c] as usize] = c0;
    }

    fn search(&mut self, base: &Base) -> bool {
        let mut best = self.r[0];
        if best == 0 {
            return true;
        }
        let mut s = self.sz[best as usize];
        if s > 1 {
            // Knuth's S heuristic, early out on size <= 1
            let mut j = self.r[best as usize];
            while j != 0 {
                let sj = self.sz[j as usize];
                if sj < s {
                    s = sj;
                    best = j;
                    if s < 2 {
                        break;
                    }
                }
                j = self.r[j as usize];
            }
        }
        self.cover(base, best);
        let mut i = self.d[best as usize];
        while i != best {
            self.sol[self.nsol] = base.rid[i as usize];
            self.nsol += 1;
            let mut j = self.r[i as usize];
            while j != i {
                self.cover(base, base.c0[j as usize]);
                j = self.r[j as usize];
            }
            if self.search(base) {
                return true;
            }
            let mut j = self.l[i as usize];
            while j != i {
                self.uncover(base, base.c0[j as usize]);
                j = self.l[j as usize];
            }
            self.nsol -= 1;
            i = self.d[i as usize];
        }
        self.uncover(base, best);
        false
    }

    fn solve(&mut self, base: &Base, g: &mut Grid) -> bool {
        let mut rm = [0u16; 9]; // cheap consistency gate
        let mut cm = [0u16; 9];
        let mut bm = [0u16; 9];
        for i in 0..81 {
            let d = g[i];
            if d != 0 {
                let (r, c) = (i / 9, i % 9);
                let b = r / 3 * 3 + c / 3;
                let bit = 1u16 << d;
                if (rm[r] | cm[c] | bm[b]) & bit != 0 {
                    return false;
                }
                rm[r] |= bit;
                cm[c] |= bit;
                bm[b] |= bit;
            }
        }

        // fresh copies of the mutable arrays; c0 and rid are never modified
        self.l = base.l0;
        self.r = base.r0;
        self.u = base.u0;
        self.d = base.d0;
        self.sz = base.sz0;
        self.nsol = 0;

        for i in 0..81 {
            // pre-select clue rows (gate makes this safe)
            let d = g[i] as usize;
            if d != 0 {
                let node = (FIRST + (i * 9 + d - 1) * 4) as u16;
                self.cover(base, base.c0[node as usize]);
                let mut j = self.r[node as usize];
                while j != node {
                    self.cover(base, base.c0[j as usize]);
                    j = self.r[j as usize];
                }
            }
        }

        if !self.search(base) {
            return false;
        }
        for &rid in &self.sol[..self.nsol] {
            g[rid as usize / 9] = (rid % 9 + 1) as u8;
        }
        true
    }
}

fn main() {
    let (reps, _threads) = parse_args();
    let base = build();
    let mut dlx = Dlx::new();
    let puzzles = read_puzzles();
    let (results, ns) = run_solver(reps, &puzzles, |g| dlx.solve(&base, g));
    write_results(&results, ns);
}
