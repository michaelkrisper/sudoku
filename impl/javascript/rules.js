// Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED.
// Same technique set as impl/python/rules.py: naked/hidden singles,
// naked/hidden pairs, pointing pairs, box-line reduction, X-Wing, Swordfish.
'use strict';
const fs = require('fs');

const ALL = 0x3FE;

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
const BOXOF = new Uint8Array(81);
for (let i = 0; i < 81; i++)
  BOXOF[i] = ((i / 27) | 0) * 3 + (((i % 9) / 3) | 0);
const PEERS = new Uint8Array(81 * 20);
for (let i = 0; i < 81; i++) {
  const r = (i / 9) | 0, c = i % 9, b = BOXOF[i];
  let n = 0;
  for (let j = 0; j < 81; j++) {
    if (j === i) continue;
    if (((j / 9) | 0) === r || j % 9 === c || BOXOF[j] === b)
      PEERS[i * 20 + n++] = j;
  }
}
const NC = new Uint8Array(1024);
for (let i = 1; i < 1024; i++) NC[i] = NC[i >> 1] + (i & 1);

const CONTRA = new Error('contradiction');

const cand = new Uint16Array(81);
const placed = new Uint8Array(81);
// hidden-pairs scratch: per digit, count and first two places
const hpCnt = new Uint8Array(10);
const hpP0 = new Uint8Array(10);
const hpP1 = new Uint8Array(10);
// fish scratch: base line index + cross-coordinate bitmask
const baseLi = new Uint8Array(9);
const baseM = new Uint16Array(9);

// Remove mask bits from cell i; contradiction if it empties the cell.
function strip(i, mask) {
  if (cand[i] & mask) {
    cand[i] &= ~mask;
    if (cand[i] === 0) throw CONTRA;
    return true;
  }
  return false;
}

function nakedSingles() {
  let prog = false;
  for (let i = 0; i < 81; i++) {
    const c = cand[i];
    if (!placed[i] && (c & (c - 1)) === 0) {
      placed[i] = 1;
      prog = true;
      for (let k = i * 20; k < i * 20 + 20; k++) strip(PEERS[k], c);
    }
  }
  return prog;
}

function hiddenSingles() {
  let prog = false;
  for (let u = 0; u < 27; u++) {
    const base = u * 9;
    for (let d = 1; d <= 9; d++) {
      const bit = 1 << d;
      let cnt = 0, place = -1;
      for (let j = 0; j < 9; j++) {
        const i = UNITS[base + j];
        if (cand[i] & bit) { cnt++; place = i; }
      }
      if (cnt === 0) throw CONTRA;
      if (cnt === 1 && cand[place] !== bit) {
        cand[place] = bit;
        prog = true;
      }
    }
  }
  return prog;
}

function nakedPairs() {
  let prog = false;
  for (let u = 0; u < 27; u++) {
    const base = u * 9;
    for (let a = 0; a < 9; a++) {
      for (let b = a + 1; b < 9; b++) {
        const m = cand[UNITS[base + a]];
        if (NC[m] === 2 && cand[UNITS[base + b]] === m) {
          for (let k = 0; k < 9; k++)
            if (k !== a && k !== b && strip(UNITS[base + k], m)) prog = true;
        }
      }
    }
  }
  return prog;
}

function hiddenPairs() {
  let prog = false;
  for (let u = 0; u < 27; u++) {
    const base = u * 9;
    for (let d = 1; d <= 9; d++) {          // snapshot places per digit
      const bit = 1 << d;
      let cnt = 0;
      for (let j = 0; j < 9; j++) {
        const i = UNITS[base + j];
        if (cand[i] & bit) {
          if (cnt === 0) hpP0[d] = i;
          else if (cnt === 1) hpP1[d] = i;
          cnt++;
        }
      }
      hpCnt[d] = cnt;
    }
    for (let x = 1; x <= 9; x++) {
      if (hpCnt[x] !== 2) continue;
      for (let y = x + 1; y <= 9; y++) {
        if (hpCnt[y] !== 2 || hpP0[x] !== hpP0[y] || hpP1[x] !== hpP1[y]) continue;
        const mask = (1 << x) | (1 << y);
        const i0 = hpP0[x], i1 = hpP1[x];
        if (cand[i0] & ~mask) {
          cand[i0] &= mask;
          if (cand[i0] === 0) throw CONTRA;
          prog = true;
        }
        if (cand[i1] & ~mask) {
          cand[i1] &= mask;
          if (cand[i1] === 0) throw CONTRA;
          prog = true;
        }
      }
    }
  }
  return prog;
}

function pointingBoxline() {
  let prog = false;
  for (let b = 0; b < 9; b++) {             // pointing pairs/triples
    const base = (18 + b) * 9;
    for (let d = 1; d <= 9; d++) {
      const bit = 1 << d;
      let cnt = 0, r0 = -1, c0 = -1;
      let sameRow = true, sameCol = true;
      for (let j = 0; j < 9; j++) {
        const i = UNITS[base + j];
        if (cand[i] & bit) {
          const r = (i / 9) | 0, c = i % 9;
          if (cnt === 0) { r0 = r; c0 = c; }
          else {
            if (r !== r0) sameRow = false;
            if (c !== c0) sameCol = false;
          }
          cnt++;
        }
      }
      if (cnt >= 2 && cnt <= 3) {
        if (sameRow) {                      // box -> row
          for (let c = 0; c < 9; c++) {
            const i = r0 * 9 + c;
            if (BOXOF[i] !== b && strip(i, bit)) prog = true;
          }
        } else if (sameCol) {               // box -> col
          for (let r = 0; r < 9; r++) {
            const i = r * 9 + c0;
            if (BOXOF[i] !== b && strip(i, bit)) prog = true;
          }
        }
      }
    }
  }
  for (let dir = 0; dir < 2; dir++) {       // box-line reduction (rows, cols)
    for (let l = 0; l < 9; l++) {
      for (let d = 1; d <= 9; d++) {
        const bit = 1 << d;
        let boxMask = 0, bb = -1;
        for (let j = 0; j < 9; j++) {
          const i = dir === 0 ? l * 9 + j : j * 9 + l;
          if (cand[i] & bit) { bb = BOXOF[i]; boxMask |= 1 << bb; }
        }
        if (boxMask !== 0 && (boxMask & (boxMask - 1)) === 0) {
          const bbase = (18 + bb) * 9;
          for (let j = 0; j < 9; j++) {
            const i = UNITS[bbase + j];
            const inLine = dir === 0 ? ((i / 9) | 0) === l : i % 9 === l;
            if (!inLine && strip(i, bit)) prog = true;
          }
        }
      }
    }
  }
  return prog;
}

// eliminate `bit` from cross lines of `unionMask`, outside base lines `keepMask`
function fishElim(dir, bit, unionMask, keepMask) {
  let prog = false;
  for (let cc = 0; cc < 9; cc++) {
    if (!(unionMask & (1 << cc))) continue;
    for (let j = 0; j < 9; j++) {
      if (keepMask & (1 << j)) continue;
      const i = dir === 0 ? j * 9 + cc : cc * 9 + j;
      if (strip(i, bit)) prog = true;
    }
  }
  return prog;
}

// X-Wing (size 2) / Swordfish (size 3), rows and columns as base.
function fish(size) {
  let prog = false;
  for (let dir = 0; dir < 2; dir++) {       // 0: rows base, 1: cols base
    for (let d = 1; d <= 9; d++) {
      const bit = 1 << d;
      let nb = 0;
      for (let li = 0; li < 9; li++) {      // snapshot candidate base lines
        let m = 0;
        for (let j = 0; j < 9; j++) {
          const i = dir === 0 ? li * 9 + j : j * 9 + li;
          if (cand[i] & bit) m |= 1 << j;
        }
        const pc = NC[m];
        if (pc >= 2 && pc <= size) { baseLi[nb] = li; baseM[nb] = m; nb++; }
      }
      if (size === 2) {
        for (let a = 0; a < nb; a++) {
          for (let b = a + 1; b < nb; b++) {
            const union = baseM[a] | baseM[b];
            if (NC[union] !== 2) continue;
            const keep = (1 << baseLi[a]) | (1 << baseLi[b]);
            if (fishElim(dir, bit, union, keep)) prog = true;
          }
        }
      } else {
        for (let a = 0; a < nb; a++) {
          for (let b = a + 1; b < nb; b++) {
            for (let c = b + 1; c < nb; c++) {
              const union = baseM[a] | baseM[b] | baseM[c];
              if (NC[union] !== 3) continue;
              const keep = (1 << baseLi[a]) | (1 << baseLi[b]) | (1 << baseLi[c]);
              if (fishElim(dir, bit, union, keep)) prog = true;
            }
          }
        }
      }
    }
  }
  return prog;
}

function solve(g) {
  cand.fill(ALL);
  for (let i = 0; i < 81; i++) if (g[i]) cand[i] = 1 << g[i];
  placed.fill(0);
  try {
    for (;;) {                              // cheapest technique first
      if (nakedSingles()) continue;
      if (hiddenSingles()) continue;
      if (nakedPairs()) continue;
      if (hiddenPairs()) continue;
      if (pointingBoxline()) continue;
      if (fish(2)) continue;
      if (fish(3)) continue;
      break;
    }
  } catch (e) {
    if (e === CONTRA) return false;
    throw e;
  }
  for (let i = 0; i < 81; i++) if (NC[cand[i]] !== 1) return false;
  for (let u = 0; u < 27; u++) {            // must be a valid full grid
    let m = 0;
    for (let j = 0; j < 9; j++) m |= cand[UNITS[u * 9 + j]];
    if (m !== ALL) return false;
  }
  for (let i = 0; i < 81; i++) g[i] = 31 - Math.clz32(cand[i]);
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
