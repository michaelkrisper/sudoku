"""Norvig-style constraint propagation + search (bitmask candidates).

The state is kept in two mutually redundant views, which is what makes the
hidden-single test cheap:

  cand[cell]      which digits may still go in this cell   (9-bit mask)
  places[unit][d] which positions of this unit may still hold digit d

Norvig's formulation derives the second from the first on demand, scanning
nine cells per unit after every elimination. Maintaining `places` incrementally
costs three AND-NOTs per elimination and turns the test into two predicates on
a value we already hold: zero is a contradiction, a single bit is a hidden
single whose position is one bit_length away.
"""
import sys

from _contract import run

sys.setrecursionlimit(10000)   # eliminate/assign chains can nest deeply

ALL = 0x3FE                     # bits 1..9 set
ALLPOS = 0x1FF                  # position bits 0..8 set

_rows = [tuple(r * 9 + c for c in range(9)) for r in range(9)]
_cols = [tuple(r * 9 + c for r in range(9)) for c in range(9)]
_boxes = [tuple((br * 3 + i) * 9 + bc * 3 + j
                for i in range(3) for j in range(3))
          for br in range(3) for bc in range(3)]
_all_units = _rows + _cols + _boxes
_units_of = [[] for _ in range(81)]
for _u in _all_units:
    for _i in _u:
        _units_of[_i].append(_u)
UNITS_OF = tuple(tuple(us) for us in _units_of)
PEERS = tuple(tuple(sorted({j for u in UNITS_OF[i] for j in u} - {i}))
              for i in range(81))

# `places` is flat: index unit * 9 + (digit - 1).
#
# ELIM[cell * 9 + (digit - 1)] gives the three (index, and-not mask) pairs to
# apply when that digit leaves that cell -- one list lookup and one unpack
# instead of recomputing unit ids, positions and shifts on every elimination.
# A cell's position is `c` along its row, `r` down its column and
# (r % 3) * 3 + c % 3 inside its box.
ELIM = tuple(
    tuple(v for _u, _p in ((_i // 9, _i % 9),
                           (9 + _i % 9, _i // 9),
                           (18 + (_i // 27) * 3 + (_i % 9) // 3,
                            (_i // 9 % 3) * 3 + _i % 3))
          for v in (_u * 9 + _d, ~(1 << _p)))
    for _i in range(81) for _d in range(9))
# Cells of the unit a flat `places` index belongs to, for naming the hidden
# single once we know its position bit.
UCELLS = tuple(_all_units[_k // 9] for _k in range(243))


def eliminate(cand, places, i, bit, PEERS=PEERS, ELIM=ELIM, UCELLS=UCELLS):
    c = cand[i]
    if not c & bit:
        return True
    c &= ~bit
    if not c:
        return False
    cand[i] = c

    # `bit` can no longer sit at this cell's position in any of its 3 units.
    k0, m0, k1, m1, k2, m2 = ELIM[i * 9 + bit.bit_length() - 2]
    places[k0] &= m0
    places[k1] &= m1
    places[k2] &= m2

    if not c & (c - 1):                     # naked single: strip from peers
        for p in PEERS[i]:
            if cand[p] & c and not eliminate(cand, places, p, c):
                return False

    # Re-read: the propagation above may have narrowed these further.
    for k in (k0, k1, k2):
        p = places[k]
        if not p:                           # bit has nowhere left in unit
            return False
        if not p & (p - 1):                 # exactly one place: hidden single
            place = UCELLS[k][p.bit_length() - 1]
            pc = cand[place]
            if pc & (pc - 1) and not assign(cand, places, place, bit):
                return False
    return True


def assign(cand, places, i, bit):
    other = cand[i] & ~bit
    while other:
        lb = other & -other
        other ^= lb
        if not eliminate(cand, places, i, lb):
            return False
    return True


def search(cand, places):
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
        trial = cand[:]                     # both views must be cloned
        tplaces = places[:]
        if assign(trial, tplaces, best, bit):
            r = search(trial, tplaces)
            if r is not None:
                return r
    return None


def solve(g):
    if len(g) != 81:
        return None
    cand = [ALL] * 81
    places = [ALLPOS] * 243
    for i in range(81):
        d = g[i]
        if d:
            bit = 1 << d
            if cand[i] != bit and not assign(cand, places, i, bit):
                return None
    r = search(cand, places)
    if r is None:
        return None
    return [c.bit_length() - 1 for c in r]


if __name__ == '__main__':
    run(solve)
