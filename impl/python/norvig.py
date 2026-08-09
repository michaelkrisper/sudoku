"""Norvig-style constraint propagation + search (bitmask candidates)."""
import sys
from _contract import run

sys.setrecursionlimit(10000)   # eliminate/assign chains can nest deeply

ALL = 0x3FE                     # bits 1..9 set

_rows = [tuple(r * 9 + c for c in range(9)) for r in range(9)]
_cols = [tuple(r * 9 + c for r in range(9)) for c in range(9)]
_boxes = [tuple((br * 3 + i) * 9 + bc * 3 + j
                for i in range(3) for j in range(3))
          for br in range(3) for bc in range(3)]
_units_of = [[] for _ in range(81)]
for _u in _rows + _cols + _boxes:
    for _i in _u:
        _units_of[_i].append(_u)
UNITS_OF = tuple(tuple(us) for us in _units_of)
PEERS = tuple(tuple(sorted({j for u in UNITS_OF[i] for j in u} - {i}))
              for i in range(81))


def eliminate(cand, i, bit, PEERS=PEERS, UNITS_OF=UNITS_OF):
    c = cand[i]
    if not c & bit:
        return True
    c &= ~bit
    if not c:
        return False
    cand[i] = c
    if not c & (c - 1):                     # naked single: strip from peers
        for p in PEERS[i]:
            if cand[p] & c and not eliminate(cand, p, c):
                return False
    for u in UNITS_OF[i]:                   # hidden single for `bit`?
        place = -1
        for j in u:
            if cand[j] & bit:
                if place >= 0:
                    place = -2
                    break
                place = j
        if place == -1:                     # bit has nowhere left in unit
            return False
        if place >= 0:
            pc = cand[place]
            if pc & (pc - 1) and not assign(cand, place, bit):
                return False
    return True


def assign(cand, i, bit):
    other = cand[i] & ~bit
    while other:
        lb = other & -other
        other ^= lb
        if not eliminate(cand, i, lb):
            return False
    return True


def search(cand):
    best = -1
    best_n = 10
    for i in range(81):                     # MRV cell
        c = cand[i]
        if c & (c - 1):
            n = c.bit_count()
            if n < best_n:
                best = i
                best_n = n
                if n == 2:
                    break
    if best < 0:
        return cand                         # all cells singles: solved
    c = cand[best]
    while c:
        bit = c & -c
        c ^= bit
        trial = cand[:]
        if assign(trial, best, bit):
            r = search(trial)
            if r is not None:
                return r
    return None


def solve(g):
    if len(g) != 81:
        return None
    cand = [ALL] * 81
    for i in range(81):
        d = g[i]
        if d:
            bit = 1 << d
            if cand[i] != bit and not assign(cand, i, bit):
                return None
    r = search(cand)
    if r is None:
        return None
    return [c.bit_length() - 1 for c in r]


if __name__ == '__main__':
    run(solve)
