// Norvig-style constraint propagation + search (bitmask candidates).
'use strict';
const fs = require('fs');

const ALL = 0x3FE;                          // bits 1..9 set

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

// UNITS_OF: the 3 unit ids per cell (row, col, box); PEERS: 20 sorted peers
const UNITS_OF = new Uint8Array(81 * 3);
const PEERS = new Uint8Array(81 * 20);
for (let i = 0; i < 81; i++) {
  const r = (i / 9) | 0, c = i % 9;
  const b = ((i / 27) | 0) * 3 + ((c / 3) | 0);
  UNITS_OF[i * 3] = r;
  UNITS_OF[i * 3 + 1] = 9 + c;
  UNITS_OF[i * 3 + 2] = 18 + b;
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

const cand0 = new Uint16Array(81);
const STACK = [];                           // one trial buffer per search depth
for (let d = 0; d < 82; d++) STACK.push(new Uint16Array(81));

function eliminate(cand, i, bit) {
  let c = cand[i];
  if (!(c & bit)) return true;
  c &= ~bit;
  if (c === 0) return false;
  cand[i] = c;
  if (!(c & (c - 1))) {                     // naked single: strip from peers
    for (let k = i * 20; k < i * 20 + 20; k++) {
      const p = PEERS[k];
      if ((cand[p] & c) && !eliminate(cand, p, c)) return false;
    }
  }
  for (let ui = 0; ui < 3; ui++) {          // hidden single for `bit`?
    const base = UNITS_OF[i * 3 + ui] * 9;
    let place = -1;
    for (let j = 0; j < 9; j++) {
      const cell = UNITS[base + j];
      if (cand[cell] & bit) {
        if (place >= 0) { place = -2; break; }
        place = cell;
      }
    }
    if (place === -1) return false;         // bit has nowhere left in unit
    if (place >= 0) {
      const pc = cand[place];
      if ((pc & (pc - 1)) && !assign(cand, place, bit)) return false;
    }
  }
  return true;
}

function assign(cand, i, bit) {
  let other = cand[i] & ~bit;
  while (other) {
    const lb = other & -other;
    other ^= lb;
    if (!eliminate(cand, i, lb)) return false;
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
  cand0.fill(ALL);
  for (let i = 0; i < 81; i++) {
    const d = g[i];
    if (d) {
      const bit = 1 << d;
      if (cand0[i] !== bit && !assign(cand0, i, bit)) return false;
    }
  }
  const r = search(cand0, 0);
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
