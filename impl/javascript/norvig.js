// Norvig-style constraint propagation + search (bitmask candidates).
//
// The state is kept in two mutually redundant views, which is what makes the
// hidden-single test cheap:
//
//   st[cell]                 which digits may still go in this cell
//   st[81 + unit * 9 + d]    which positions of `unit` may still hold digit d+1
//
// Norvig derives the second from the first on demand, scanning nine cells per
// unit after every elimination — a data-dependent loop with an early exit.
// Maintaining it incrementally costs three AND-NOTs per elimination and turns
// the test into two predicates on a value already in hand: zero is a
// contradiction, a single set bit is a hidden single.
//
// Both views live in one flat array so a search node clones them with a single
// .set(), the way the C port copies one struct.
'use strict';
const fs = require('fs');

const ALL = 0x3FE;                          // bits 1..9 set
const ALLPOS = 0x1FF;                       // position bits 0..8 set
const NSTATE = 81 + 27 * 9;                 // cand block, then places block

// UNITS: 27 units x 9 cells (9 rows, 9 cols, 9 boxes)
const UNITS = new Uint8Array(27 * 9);
for (let r = 0; r < 9; r++)
  for (let c = 0; c < 9; c++) UNITS[r * 9 + c] = r * 9 + c;
for (let c = 0; c < 9; c++)
  for (let r = 0; r < 9; r++) UNITS[(9 + c) * 9 + r] = r * 9 + c;
for (let b = 0; b < 9; b++) {
  const br = (b / 3) | 0, bc = b % 3;
  for (let j = 0; j < 9; j++)
    UNITS[(18 + b) * 9 + j] = (br * 3 + ((j / 3) | 0)) * 9 + bc * 3 + (j % 3);
}

// UNITS_OF: the 3 unit ids per cell (row, col, box); PEERS: 20 sorted peers.
// UBASE/PBASE: the same 3 units pre-multiplied into UNITS / places offsets.
// POSBIT: this cell's position bit within each of its 3 units.
const UNITS_OF = new Uint8Array(81 * 3);
const UBASE = new Uint16Array(81 * 3);
const PBASE = new Uint16Array(81 * 3);
const POSBIT = new Uint16Array(81 * 3);
const PEERS = new Uint8Array(81 * 20);
for (let i = 0; i < 81; i++) {
  const r = (i / 9) | 0, c = i % 9;
  const b = ((i / 27) | 0) * 3 + ((c / 3) | 0);
  UNITS_OF[i * 3] = r;
  UNITS_OF[i * 3 + 1] = 9 + c;
  UNITS_OF[i * 3 + 2] = 18 + b;
  POSBIT[i * 3] = 1 << c;                   // along the row
  POSBIT[i * 3 + 1] = 1 << r;               // down the column
  POSBIT[i * 3 + 2] = 1 << ((r % 3) * 3 + c % 3);   // within the box
  for (let t = 0; t < 3; t++) {
    UBASE[i * 3 + t] = UNITS_OF[i * 3 + t] * 9;
    PBASE[i * 3 + t] = 81 + UNITS_OF[i * 3 + t] * 9;
  }
  let n = 0;
  for (let j = 0; j < 81; j++) {
    if (j === i) continue;
    const jr = (j / 9) | 0, jc = j % 9;
    const jb = ((j / 27) | 0) * 3 + ((jc / 3) | 0);
    if (jr === r || jc === c || jb === b) PEERS[i * 20 + n++] = j;
  }
}

const NC = new Uint8Array(1024);            // popcount table
for (let i = 1; i < 1024; i++) NC[i] = NC[i >> 1] + (i & 1);

const st0 = new Uint16Array(NSTATE);
const STACK = [];                           // one trial buffer per search depth
for (let d = 0; d < 82; d++) STACK.push(new Uint16Array(NSTATE));

function eliminate(st, i, bit) {
  let c = st[i];
  if (!(c & bit)) return true;
  c &= ~bit;
  if (c === 0) return false;
  st[i] = c;

  // `bit` can no longer sit at this cell's position in any of its 3 units.
  const d = 30 - Math.clz32(bit);           // digit index 0..8
  const t0 = i * 3, t1 = t0 + 1, t2 = t0 + 2;
  const q0 = PBASE[t0] + d, q1 = PBASE[t1] + d, q2 = PBASE[t2] + d;
  st[q0] &= ~POSBIT[t0];
  st[q1] &= ~POSBIT[t1];
  st[q2] &= ~POSBIT[t2];

  if (!(c & (c - 1))) {                     // naked single: strip from peers
    for (let k = i * 20; k < i * 20 + 20; k++) {
      const p = PEERS[k];
      if ((st[p] & c) && !eliminate(st, p, c)) return false;
    }
  }

  // Re-read: the propagation above may have narrowed these further.
  let p0 = st[q0];
  if (p0 === 0) return false;               // bit has nowhere left in unit
  if (!(p0 & (p0 - 1))) {                   // exactly one place: hidden single
    const place = UNITS[UBASE[t0] + 31 - Math.clz32(p0)];
    const pc = st[place];
    if ((pc & (pc - 1)) && !assign(st, place, bit)) return false;
  }
  let p1 = st[q1];
  if (p1 === 0) return false;
  if (!(p1 & (p1 - 1))) {
    const place = UNITS[UBASE[t1] + 31 - Math.clz32(p1)];
    const pc = st[place];
    if ((pc & (pc - 1)) && !assign(st, place, bit)) return false;
  }
  let p2 = st[q2];
  if (p2 === 0) return false;
  if (!(p2 & (p2 - 1))) {
    const place = UNITS[UBASE[t2] + 31 - Math.clz32(p2)];
    const pc = st[place];
    if ((pc & (pc - 1)) && !assign(st, place, bit)) return false;
  }
  return true;
}

function assign(st, i, bit) {
  let other = st[i] & ~bit;
  while (other) {
    const lb = other & -other;
    other ^= lb;
    if (!eliminate(st, i, lb)) return false;
  }
  return true;
}

function search(cand, depth) {
  let best = -1, bestN = 10;
  for (let i = 0; i < 81; i++) {            // MRV cell
    const c = cand[i];
    if (c & (c - 1)) {
      const nc = NC[c];
      if (nc < bestN) {
        best = i; bestN = nc;
        if (nc === 2) break;
      }
    }
  }
  if (best < 0) return cand;                // all cells singles: solved
  let c = cand[best];
  const trial = STACK[depth];
  while (c) {
    const bit = c & -c;
    c ^= bit;
    trial.set(cand);
    if (assign(trial, best, bit)) {
      const r = search(trial, depth + 1);
      if (r !== null) return r;
    }
  }
  return null;
}

function solve(g) {
  st0.fill(ALL, 0, 81);
  st0.fill(ALLPOS, 81, NSTATE);
  for (let i = 0; i < 81; i++) {
    const d = g[i];
    if (d) {
      const bit = 1 << d;
      if (st0[i] !== bit && !assign(st0, i, bit)) return false;
    }
  }
  const r = search(st0, 0);
  if (r === null) return false;
  for (let i = 0; i < 81; i++) g[i] = 31 - Math.clz32(r[i]);
  return true;
}

function main() {
  const reps = process.argv.length > 2 ? parseInt(process.argv[2], 10) : 1;
  const lines = fs.readFileSync(0, 'utf8').split('\n');
  const puzzles = [];
  for (let k = 0; k < lines.length; k++) {
    const s = lines[k].trim();
    if (s.length !== 0 && s.charCodeAt(0) !== 35) puzzles.push(s);
  }
  const n = puzzles.length;
  const grids = new Uint8Array(n * 81);
  for (let p = 0; p < n; p++)
    for (let i = 0; i < 81; i++) grids[p * 81 + i] = puzzles[p].charCodeAt(i) - 48;
  const results = new Uint8Array(n * 81);
  const solved = new Uint8Array(n);
  const scratch = new Uint8Array(81);

  const t0 = process.hrtime.bigint();
  for (let rep = 0; rep < reps; rep++) {
    for (let p = 0; p < n; p++) {
      const base = p * 81;
      for (let i = 0; i < 81; i++) scratch[i] = grids[base + i];
      if (solve(scratch)) {
        solved[p] = 1;
        results.set(scratch, base);
      } else solved[p] = 0;
    }
  }
  const ns = process.hrtime.bigint() - t0;

  const out = new Array(n);
  for (let p = 0; p < n; p++) {
    if (solved[p]) {
      let s = '';
      for (let i = 0; i < 81; i++) s += results[p * 81 + i];
      out[p] = s;
    } else out[p] = 'UNSOLVED';
  }
  fs.writeSync(2, 'ns=' + ns + '\n');
  fs.writeSync(1, out.join('\n') + '\n');
  process.exit(0);
}

main();
