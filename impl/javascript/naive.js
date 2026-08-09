// Naive backtracking: first empty cell, digits 1-9 in order.
'use strict';
const fs = require('fs');

function valid(g, pos, d) {
  const rs = pos - (pos % 9);
  for (let j = 0; j < 9; j++) if (g[rs + j] === d) return false;
  for (let j = pos % 9; j < 81; j += 9) if (g[j] === d) return false;
  const bs = ((pos / 27) | 0) * 27 + (((pos % 9) / 3) | 0) * 3;
  for (let r = 0; r < 27; r += 9)
    for (let j = 0; j < 3; j++) if (g[bs + r + j] === d) return false;
  return true;
}

function bt(g) {
  let pos = -1;
  for (let i = 0; i < 81; i++) if (g[i] === 0) { pos = i; break; }
  if (pos < 0) return true;
  for (let d = 1; d <= 9; d++) {
    if (valid(g, pos, d)) {
      g[pos] = d;
      if (bt(g)) return true;
    }
  }
  g[pos] = 0;
  return false;
}

function solve(g) {
  for (let i = 0; i < 81; i++) {        // reject inconsistent clues
    const d = g[i];
    if (d) {
      g[i] = 0;
      const ok = valid(g, i, d);
      g[i] = d;
      if (!ok) return false;
    }
  }
  return bt(g);
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
