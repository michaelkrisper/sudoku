//! Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED.
//!
//! Mirrors impl/c/rules.c exactly: naked singles, hidden singles,
//! naked pairs, hidden pairs, pointing pairs/triples, box-line reduction,
//! X-Wing, Swordfish -- applied to a fixpoint, cheapest technique first.

use sudoku::{parse_args, read_puzzles, run_solver, write_results, Grid};

const ALL: u16 = 0x3FE;

struct Tables {
    units: [[u8; 9]; 27], // 9 rows, 9 cols, 9 boxes
    peers: [[u8; 20]; 81],
    box_of: [u8; 81],
}

fn init_tables() -> Tables {
    let mut t = Tables {
        units: [[0; 9]; 27],
        peers: [[0; 20]; 81],
        box_of: [0; 81],
    };
    for r in 0..9 {
        for c in 0..9 {
            let i = r * 9 + c;
            t.units[r][c] = i as u8;
            t.units[9 + c][r] = i as u8;
            t.box_of[i] = (r / 3 * 3 + c / 3) as u8;
        }
    }
    for b in 0..9 {
        for k in 0..9 {
            t.units[18 + b][k] = ((b / 3 * 3 + k / 3) * 9 + b % 3 * 3 + k % 3) as u8;
        }
    }
    for i in 0..81 {
        let mut n = 0;
        for j in 0..81 {
            if j != i && (j / 9 == i / 9 || j % 9 == i % 9 || t.box_of[j] == t.box_of[i]) {
                t.peers[i][n] = j as u8;
                n += 1;
            }
        }
    }
    t
}

struct Rules<'a> {
    t: &'a Tables,
    cand: [u16; 81],
    bad: bool, // contradiction flag
}

impl Rules<'_> {
    /// Remove mask bits from cell i; contradiction if it empties the cell.
    #[inline]
    fn strip(&mut self, i: usize, mask: u16) -> bool {
        if self.cand[i] & mask != 0 {
            self.cand[i] &= !mask;
            if self.cand[i] == 0 {
                self.bad = true;
            }
            true
        } else {
            false
        }
    }

    fn naked_singles(&mut self, placed: &mut [bool; 81]) -> bool {
        let mut prog = false;
        for i in 0..81 {
            let c = self.cand[i];
            if !placed[i] && c.count_ones() == 1 {
                placed[i] = true;
                prog = true;
                let peers = self.t.peers[i];
                for &p in &peers {
                    self.strip(p as usize, c);
                    if self.bad {
                        return prog;
                    }
                }
            }
        }
        prog
    }

    fn hidden_singles(&mut self) -> bool {
        let mut prog = false;
        for u in 0..27 {
            for d in 1..=9 {
                let bit = 1u16 << d;
                let mut cnt = 0;
                let mut last = 0;
                for k in 0..9 {
                    let i = self.t.units[u][k] as usize;
                    if self.cand[i] & bit != 0 {
                        cnt += 1;
                        last = i;
                    }
                }
                if cnt == 0 {
                    self.bad = true;
                    return prog;
                }
                if cnt == 1 && self.cand[last] != bit {
                    self.cand[last] = bit;
                    prog = true;
                }
            }
        }
        prog
    }

    fn naked_pairs(&mut self) -> bool {
        let mut prog = false;
        for u in 0..27 {
            for a in 0..9 {
                for b in a + 1..9 {
                    let m = self.cand[self.t.units[u][a] as usize];
                    if m.count_ones() == 2 && self.cand[self.t.units[u][b] as usize] == m {
                        for k in 0..9 {
                            if k != a && k != b {
                                prog |= self.strip(self.t.units[u][k] as usize, m);
                                if self.bad {
                                    return prog;
                                }
                            }
                        }
                    }
                }
            }
        }
        prog
    }

    fn hidden_pairs(&mut self) -> bool {
        let mut prog = false;
        for u in 0..27 {
            let mut pos = [0u16; 10]; // bitmask over the 9 unit positions
            let mut two = [0usize; 9];
            let mut n = 0;
            for d in 1..=9 {
                let mut p = 0u16;
                for k in 0..9 {
                    if self.cand[self.t.units[u][k] as usize] & (1 << d) != 0 {
                        p |= 1 << k;
                    }
                }
                pos[d] = p;
                if p.count_ones() == 2 {
                    two[n] = d;
                    n += 1;
                }
            }
            for x in 0..n {
                for y in x + 1..n {
                    if pos[two[x]] == pos[two[y]] {
                        let mask = (1u16 << two[x]) | (1u16 << two[y]);
                        for k in 0..9 {
                            if pos[two[x]] & (1 << k) != 0 {
                                let i = self.t.units[u][k] as usize;
                                if self.cand[i] & !mask != 0 {
                                    self.cand[i] &= mask;
                                    if self.cand[i] == 0 {
                                        self.bad = true;
                                        return prog;
                                    }
                                    prog = true;
                                }
                            }
                        }
                    }
                }
            }
        }
        prog
    }

    fn pointing_and_boxline(&mut self) -> bool {
        let mut prog = false;
        for b in 0..9 {
            // pointing pairs/triples
            for d in 1..=9 {
                let bit = 1u16 << d;
                let mut places = [0usize; 9];
                let mut np = 0;
                for k in 0..9 {
                    let i = self.t.units[18 + b][k] as usize;
                    if self.cand[i] & bit != 0 {
                        places[np] = i;
                        np += 1;
                    }
                }
                if !(2..=3).contains(&np) {
                    continue;
                }
                let mut samer = true;
                let mut samec = true;
                for &p in &places[1..np] {
                    if p / 9 != places[0] / 9 {
                        samer = false;
                    }
                    if p % 9 != places[0] % 9 {
                        samec = false;
                    }
                }
                if samer {
                    // box -> row
                    for c in 0..9 {
                        let i = places[0] / 9 * 9 + c;
                        if self.t.box_of[i] as usize != b {
                            prog |= self.strip(i, bit);
                            if self.bad {
                                return prog;
                            }
                        }
                    }
                } else if samec {
                    // box -> col
                    for r in 0..9 {
                        let i = r * 9 + places[0] % 9;
                        if self.t.box_of[i] as usize != b {
                            prog |= self.strip(i, bit);
                            if self.bad {
                                return prog;
                            }
                        }
                    }
                }
            }
        }
        for axis in 0..2 {
            // box-line reduction
            for l in 0..9 {
                for d in 1..=9 {
                    let bit = 1u16 << d;
                    let mut boxes = 0u16;
                    for k in 0..9 {
                        let i = self.t.units[axis * 9 + l][k] as usize;
                        if self.cand[i] & bit != 0 {
                            boxes |= 1 << self.t.box_of[i];
                        }
                    }
                    if boxes.count_ones() != 1 {
                        continue;
                    }
                    let bx = boxes.trailing_zeros() as usize;
                    for k in 0..9 {
                        let i = self.t.units[18 + bx][k] as usize;
                        let inline = if axis == 0 { i / 9 == l } else { i % 9 == l };
                        if !inline {
                            prog |= self.strip(i, bit);
                            if self.bad {
                                return prog;
                            }
                        }
                    }
                }
            }
        }
        prog
    }

    /// Eliminate digit from the cross lines of a confirmed fish pattern.
    fn fish_eliminate(&mut self, axis: usize, un: u16, keep: u16, bit: u16) -> bool {
        let mut prog = false;
        for cc in 0..9 {
            if un & (1 << cc) == 0 {
                continue;
            }
            for lc in 0..9 {
                if keep & (1 << lc) != 0 {
                    continue;
                }
                let i = if axis == 0 { lc * 9 + cc } else { cc * 9 + lc };
                prog |= self.strip(i, bit);
                if self.bad {
                    return prog;
                }
            }
        }
        prog
    }

    /// X-Wing (size 2) / Swordfish (size 3), rows and columns as base.
    fn fish(&mut self, size: u32) -> bool {
        let mut prog = false;
        for axis in 0..2 {
            // 0: rows base, 1: cols base
            for d in 1..=9 {
                let bit = 1u16 << d;
                let mut bl = [0usize; 9];
                let mut bm = [0u16; 9];
                let mut nb = 0;
                for li in 0..9 {
                    let mut ps = 0u16;
                    for k in 0..9 {
                        let i = if axis == 0 { li * 9 + k } else { k * 9 + li };
                        if self.cand[i] & bit != 0 {
                            ps |= 1 << k;
                        }
                    }
                    let cnt = ps.count_ones();
                    if cnt >= 2 && cnt <= size {
                        bl[nb] = li;
                        bm[nb] = ps;
                        nb += 1;
                    }
                }
                if size == 2 {
                    for a in 0..nb {
                        for b in a + 1..nb {
                            let un = bm[a] | bm[b];
                            if un.count_ones() != 2 {
                                continue;
                            }
                            let keep = (1u16 << bl[a]) | (1u16 << bl[b]);
                            prog |= self.fish_eliminate(axis, un, keep, bit);
                            if self.bad {
                                return prog;
                            }
                        }
                    }
                } else {
                    for a in 0..nb {
                        for b in a + 1..nb {
                            for c in b + 1..nb {
                                let un = bm[a] | bm[b] | bm[c];
                                if un.count_ones() != 3 {
                                    continue;
                                }
                                let keep =
                                    (1u16 << bl[a]) | (1u16 << bl[b]) | (1u16 << bl[c]);
                                prog |= self.fish_eliminate(axis, un, keep, bit);
                                if self.bad {
                                    return prog;
                                }
                            }
                        }
                    }
                }
            }
        }
        prog
    }

    fn solve(&mut self, g: &mut Grid) -> bool {
        let mut placed = [false; 81];
        self.bad = false;
        for (cell, &d) in self.cand.iter_mut().zip(g.iter()) {
            *cell = if d != 0 { 1 << d } else { ALL };
        }
        loop {
            // cheapest technique first
            if self.naked_singles(&mut placed) {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.hidden_singles() {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.naked_pairs() {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.hidden_pairs() {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.pointing_and_boxline() {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.fish(2) {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            if self.fish(3) {
                if self.bad {
                    return false;
                }
                continue;
            }
            if self.bad {
                return false;
            }
            break;
        }
        if self.cand.iter().any(|c| c.count_ones() != 1) {
            return false;
        }
        for unit in &self.t.units {
            // must be a valid full grid
            let mut m = 0u16;
            for &k in unit {
                m |= self.cand[k as usize];
            }
            if m != ALL {
                return false;
            }
        }
        for (cell, &c) in g.iter_mut().zip(self.cand.iter()) {
            *cell = c.trailing_zeros() as u8;
        }
        true
    }
}

fn main() {
    let (reps, _threads) = parse_args();
    let tables = init_tables();
    let puzzles = read_puzzles();
    let mut rules = Rules {
        t: &tables,
        cand: [0; 81],
        bad: false,
    };
    let (results, ns) = run_solver(reps, &puzzles, |g| rules.solve(g));
    write_results(&results, ns);
}
