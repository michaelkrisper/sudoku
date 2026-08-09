// mrv parallelized over puzzles via worker_threads.
// Dynamic scheduling: workers pull puzzle indices from an atomic counter in a
// SharedArrayBuffer (puzzle difficulty is very uneven, balance beats overhead).
'use strict';
const fs = require('fs');
const { Worker, isMainThread, workerData } = require('node:worker_threads');

// --- mrv solver (identical to mrv.js) -------------------------------------
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
      if (nc === 0) return false;
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
      if (!(rows[r] & cols[c] & boxes[b] & bit)) return false;
      rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
    } else empties[n++] = i;
  }
  return bt(g, 0, n);
}

// --- shared-memory layout ---------------------------------------------------
// ctrl (4 x Int32): NEXT (dynamic puzzle index), DONE (workers finished this
// pass), GEN (pass generation counter), STOP (shutdown flag).
// Then: grids n*81 bytes | results n*81 bytes | solved n bytes.
const NEXT = 0, DONE = 1, GEN = 2, STOP = 3;
const CTRL_BYTES = 16;

function views(sab, n) {
  return {
    ctrl: new Int32Array(sab, 0, 4),
    grids: new Uint8Array(sab, CTRL_BYTES, n * 81),
    results: new Uint8Array(sab, CTRL_BYTES + n * 81, n * 81),
    solved: new Uint8Array(sab, CTRL_BYTES + 2 * n * 81, n),
  };
}

function solveShared(v, idx, scratch) {
  const base = idx * 81;
  for (let i = 0; i < 81; i++) scratch[i] = v.grids[base + i];
  if (solve(scratch)) {
    v.results.set(scratch, base);
    v.solved[idx] = 1;
  } else v.solved[idx] = 0;
}

// --- worker ------------------------------------------------------------------
if (!isMainThread) {
  const n = workerData.n;
  const v = views(workerData.sab, n);
  const ctrl = v.ctrl;
  const scratch = new Uint8Array(81);
  let gen = 0;
  for (;;) {
    Atomics.wait(ctrl, GEN, gen);           // sleep until next pass (or shutdown)
    gen = Atomics.load(ctrl, GEN);
    if (Atomics.load(ctrl, STOP)) break;
    for (;;) {
      const idx = Atomics.add(ctrl, NEXT, 1);
      if (idx >= n) break;
      solveShared(v, idx, scratch);
    }
    Atomics.add(ctrl, DONE, 1);
    Atomics.notify(ctrl, DONE);
  }
  process.exit(0);
}

// --- main ---------------------------------------------------------------------
function main() {
  const reps = process.argv.length > 2 ? parseInt(process.argv[2], 10) : 1;
  const threads = process.argv.length > 3 ? parseInt(process.argv[3], 10) : 1;
  const lines = fs.readFileSync(0, 'utf8').split('\n');
  const puzzles = [];
  for (let k = 0; k < lines.length; k++) {
    const s = lines[k].trim();
    if (s.length !== 0 && s.charCodeAt(0) !== 35) puzzles.push(s);
  }
  const n = puzzles.length;
  const sab = new SharedArrayBuffer(CTRL_BYTES + 2 * n * 81 + n);
  const v = views(sab, n);
  for (let p = 0; p < n; p++)
    for (let i = 0; i < 81; i++) v.grids[p * 81 + i] = puzzles[p].charCodeAt(i) - 48;
  const ctrl = v.ctrl;
  const scratch = new Uint8Array(81);
  let workers = null;

  const t0 = process.hrtime.bigint();
  if (threads <= 1) {
    for (let rep = 0; rep < reps; rep++)
      for (let p = 0; p < n; p++) solveShared(v, p, scratch);
  } else {
    workers = [];                           // create once, reuse across reps
    for (let t = 0; t < threads; t++)
      workers.push(new Worker(__filename, { workerData: { sab, n } }));
    for (let rep = 0; rep < reps; rep++) {
      Atomics.store(ctrl, NEXT, 0);
      Atomics.store(ctrl, DONE, 0);
      Atomics.add(ctrl, GEN, 1);
      Atomics.notify(ctrl, GEN);
      for (;;) {                            // block until all workers report done
        const d = Atomics.load(ctrl, DONE);
        if (d >= threads) break;
        Atomics.wait(ctrl, DONE, d);
      }
    }
  }
  const ns = process.hrtime.bigint() - t0;

  const out = new Array(n);
  for (let p = 0; p < n; p++) {
    if (v.solved[p]) {
      let s = '';
      for (let i = 0; i < 81; i++) s += v.results[p * 81 + i];
      out[p] = s;
    } else out[p] = 'UNSOLVED';
  }
  fs.writeSync(2, 'ns=' + ns + '\n');
  fs.writeSync(1, out.join('\n') + '\n');
  if (workers !== null) {                   // wake workers so they exit cleanly
    Atomics.store(ctrl, STOP, 1);
    Atomics.add(ctrl, GEN, 1);
    Atomics.notify(ctrl, GEN);
  }
  process.exit(0);
}

main();
