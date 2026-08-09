// Knuth's Algorithm X with Dancing Links, flat-typed-array based.
'use strict';
const fs = require('fs');

const NCOLS = 324;              // 81 cell + 81 row-digit + 81 col-digit + 81 box-digit
const NNODES = 1 + NCOLS + 729 * 4; // root + headers + 4 nodes per candidate row
const FIRST = NCOLS + 1;        // index of first row node

// pristine matrix, built once; C and RID are never modified
const L0 = new Int32Array(NNODES);
const R0 = new Int32Array(NNODES);
const U0 = new Int32Array(NNODES);
const D0 = new Int32Array(NNODES);
const C = new Int32Array(NNODES);
const RID = new Int32Array(NNODES);
const SZ0 = new Int32Array(NCOLS + 1);
(function build() {
  for (let h = 0; h <= NCOLS; h++) {  // 0 = root, 1..324 = column headers
    L0[h] = h ? h - 1 : NCOLS;
    R0[h] = h < NCOLS ? h + 1 : 0;
    U0[h] = D0[h] = h;
  }
  let n = FIRST;
  for (let cell = 0; cell < 81; cell++) {
    const r = (cell / 9) | 0, c = cell % 9;
    const b = ((r / 3) | 0) * 3 + ((c / 3) | 0);
    for (let d = 0; d < 9; d++) {   // d = digit - 1
      const rid = cell * 9 + d;
      const colA = 1 + cell, colB = 82 + r * 9 + d;
      const colC = 163 + c * 9 + d, colD = 244 + b * 9 + d;
      for (const col of [colA, colB, colC, colD]) {
        C[n] = col; RID[n] = rid;
        D0[n] = col; U0[n] = U0[col]; D0[U0[col]] = n; U0[col] = n;
        SZ0[col] += 1;
        n += 1;
      }
      const f = n - 4;              // link the 4 nodes of this row circularly
      L0[f] = f + 3; R0[f] = f + 1;
      L0[f + 1] = f; R0[f + 1] = f + 2;
      L0[f + 2] = f + 1; R0[f + 2] = f + 3;
      L0[f + 3] = f + 2; R0[f + 3] = f;
    }
  }
})();

// mutable working copies, refreshed per puzzle via .set()
const L = new Int32Array(NNODES);
const R = new Int32Array(NNODES);
const U = new Int32Array(NNODES);
const D = new Int32Array(NNODES);
const SZ = new Int32Array(NCOLS + 1);
const sol = new Int32Array(81);
let solLen = 0;

function cover(c0) {
  R[L[c0]] = R[c0]; L[R[c0]] = L[c0];
  let i = D[c0];
  while (i !== c0) {
    let j = R[i];
    while (j !== i) {
      D[U[j]] = D[j]; U[D[j]] = U[j]; SZ[C[j]] -= 1;
      j = R[j];
    }
    i = D[i];
  }
}

function uncover(c0) {
  let i = U[c0];
  while (i !== c0) {
    let j = L[i];
    while (j !== i) {
      SZ[C[j]] += 1; D[U[j]] = j; U[D[j]] = j;
      j = L[j];
    }
    i = U[i];
  }
  R[L[c0]] = c0; L[R[c0]] = c0;
}

function search(depth) {
  let best = R[0];                // root is 0, headers are 1..324
  if (best === 0) { solLen = depth; return true; }
  let s = SZ[best];
  if (s > 1) {                    // Knuth's S heuristic, early out on size <= 1
    let j = R[best];
    while (j !== 0) {
      const sj = SZ[j];
      if (sj < s) {
        s = sj; best = j;
        if (s < 2) break;
      }
      j = R[j];
    }
  }
  cover(best);
  let i = D[best];
  while (i !== best) {
    sol[depth] = RID[i];
    let j = R[i];
    while (j !== i) { cover(C[j]); j = R[j]; }
    if (search(depth + 1)) return true;
    j = L[i];
    while (j !== i) { uncover(C[j]); j = L[j]; }
    i = D[i];
  }
  uncover(best);
  return false;
}

const rm = new Uint16Array(9), cm = new Uint16Array(9), bm = new Uint16Array(9);

function solve(g) {
  rm.fill(0); cm.fill(0); bm.fill(0);   // cheap consistency gate
  for (let i = 0; i < 81; i++) {
    const d = g[i];
    if (d) {
      const r = (i / 9) | 0, c = i % 9;
      const b = ((r / 3) | 0) * 3 + ((c / 3) | 0);
      const bit = 1 << d;
      if ((rm[r] | cm[c] | bm[b]) & bit) return false;
      rm[r] |= bit; cm[c] |= bit; bm[b] |= bit;
    }
  }

  L.set(L0); R.set(R0); U.set(U0); D.set(D0); SZ.set(SZ0);

  for (let i = 0; i < 81; i++) {        // pre-select clue rows (gate makes this safe)
    const d = g[i];
    if (d) {
      const node = FIRST + (i * 9 + d - 1) * 4;
      cover(C[node]);
      let j = R[node];
      while (j !== node) {
        cover(C[j]);
        j = R[j];
      }
    }
  }

  solLen = 0;
  if (!search(0)) return false;
  for (let k = 0; k < solLen; k++) {
    const rid = sol[k];
    g[(rid / 9) | 0] = (rid % 9) + 1;
  }
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
