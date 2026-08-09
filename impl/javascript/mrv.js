// Backtracking with bitmask candidates and most-constrained-cell order.
'use strict';
const fs = require('fs');

const ALL = 0x3FE;                          // bits 1..9 set
const ROW = new Uint8Array(81);
const COL = new Uint8Array(81);
const BOX = new Uint8Array(81);
for (let i = 0; i < 81; i++) {
  ROW[i] = (i / 9) | 0;
  COL[i] = i % 9;
  BOX[i] = ((i / 27) | 0) * 3 + (((i % 9) / 3) | 0);
}
const NC = new Uint8Array(1024);            // popcount table
for (let i = 1; i < 1024; i++) NC[i] = NC[i >> 1] + (i & 1);

// masks hold the still-allowed digit bits per row/col/box
const rows = new Uint16Array(9);
const cols = new Uint16Array(9);
const boxes = new Uint16Array(9);
const empties = new Uint8Array(81);

function bt(g, k, n) {
  if (k === n) return true;
  let bestJ = k, bestN = 10, bestCand = 0;
  for (let j = k; j < n; j++) {
    const i = empties[j];
    const cand = rows[ROW[i]] & cols[COL[i]] & boxes[BOX[i]];
    const nc = NC[cand];
    if (nc < bestN) {
      if (nc === 0) return false;           // dead end
      bestJ = j; bestN = nc; bestCand = cand;
      if (nc === 1) break;
    }
  }
  const i = empties[bestJ];
  empties[bestJ] = empties[k];
  empties[k] = i;
  const r = ROW[i], c = COL[i], b = BOX[i];
  let cand = bestCand;
  while (cand) {
    const bit = cand & -cand;
    cand -= bit;
    g[i] = 31 - Math.clz32(bit);
    rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
    if (bt(g, k + 1, n)) return true;
    rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
  }
  g[i] = 0;
  return false;
}

function solve(g) {
  rows.fill(ALL); cols.fill(ALL); boxes.fill(ALL);
  let n = 0;
  for (let i = 0; i < 81; i++) {
    const d = g[i];
    if (d) {
      const bit = 1 << d;
      const r = ROW[i], c = COL[i], b = BOX[i];
      if (!(rows[r] & cols[c] & boxes[b] & bit)) return false; // duplicate clue
      rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
    } else empties[n++] = i;
  }
  return bt(g, 0, n);
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
