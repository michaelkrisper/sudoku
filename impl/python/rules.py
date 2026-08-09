"""Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED."""
from itertools import combinations
from _contract import run

ALL = 0x3FE
ROWS = [[r*9 + c for c in range(9)] for r in range(9)]
COLS = [[r*9 + c for r in range(9)] for c in range(9)]
BOXES = [[(br*3 + i)*9 + bc*3 + j for i in range(3) for j in range(3)]
         for br in range(3) for bc in range(3)]
UNITS = ROWS + COLS + BOXES
UNITS_OF = [[] for _ in range(81)]
for u in UNITS:
    for i in u:
        UNITS_OF[i].append(u)
PEERS = [sorted({j for u in UNITS_OF[i] for j in u} - {i}) for i in range(81)]


class Contradiction(Exception):
    pass


def strip(cand, i, mask):
    """Remove mask bits from cell i; contradiction if it empties the cell."""
    if cand[i] & mask:
        cand[i] &= ~mask
        if cand[i] == 0:
            raise Contradiction
        return True
    return False


def naked_singles(cand, placed):
    prog = False
    for i in range(81):
        c = cand[i]
        if not placed[i] and c & (c - 1) == 0:
            placed[i] = True
            prog = True
            for p in PEERS[i]:
                strip(cand, p, c)
    return prog


def hidden_singles(cand):
    prog = False
    for u in UNITS:
        for d in range(1, 10):
            bit = 1 << d
            places = [i for i in u if cand[i] & bit]
            if not places:
                raise Contradiction
            if len(places) == 1 and cand[places[0]] != bit:
                cand[places[0]] = bit
                prog = True
    return prog


def naked_pairs(cand):
    prog = False
    for u in UNITS:
        for a, b in combinations(range(9), 2):
            m = cand[u[a]]
            if m.bit_count() == 2 and cand[u[b]] == m:
                for k in range(9):
                    if k != a and k != b:
                        prog |= strip(cand, u[k], m)
    return prog


def hidden_pairs(cand):
    prog = False
    for u in UNITS:
        pos = {d: tuple(i for i in u if cand[i] & (1 << d))
               for d in range(1, 10)}
        two = [d for d, p in pos.items() if len(p) == 2]
        for x, y in combinations(two, 2):
            if pos[x] == pos[y]:
                mask = (1 << x) | (1 << y)
                for i in pos[x]:
                    if cand[i] & ~mask:
                        cand[i] &= mask
                        if cand[i] == 0:
                            raise Contradiction
                        prog = True
    return prog


def pointing_and_boxline(cand):
    prog = False
    for box in BOXES:                               # pointing pairs/triples
        for d in range(1, 10):
            bit = 1 << d
            places = [i for i in box if cand[i] & bit]
            if 2 <= len(places) <= 3:
                rs = {i // 9 for i in places}
                cs = {i % 9 for i in places}
                if len(rs) == 1:                    # box -> row
                    for i in ROWS[next(iter(rs))]:
                        if i not in box:
                            prog |= strip(cand, i, bit)
                elif len(cs) == 1:                  # box -> col
                    for i in COLS[next(iter(cs))]:
                        if i not in box:
                            prog |= strip(cand, i, bit)
    for lines in (ROWS, COLS):                      # box-line reduction
        for line in lines:
            for d in range(1, 10):
                bit = 1 << d
                places = [i for i in line if cand[i] & bit]
                boxes = {i // 9 // 3 * 3 + i % 9 // 3 for i in places}
                if len(boxes) == 1:
                    for i in BOXES[next(iter(boxes))]:
                        if i not in line:
                            prog |= strip(cand, i, bit)
    return prog


def fish(cand, size):
    """X-Wing (size 2) / Swordfish (size 3), rows and columns as base."""
    prog = False
    for lines, cross, coord, lcoord in (
            (ROWS, COLS, lambda i: i % 9, lambda i: i // 9),
            (COLS, ROWS, lambda i: i // 9, lambda i: i % 9)):
        for d in range(1, 10):
            bit = 1 << d
            base = []
            for li, line in enumerate(lines):
                ps = {coord(i) for i in line if cand[i] & bit}
                if 2 <= len(ps) <= size:
                    base.append((li, ps))
            for combo in combinations(base, size):
                union = set().union(*(ps for _, ps in combo))
                if len(union) != size:
                    continue
                keep = {li for li, _ in combo}
                for cc in union:
                    for i in cross[cc]:
                        if lcoord(i) not in keep:
                            prog |= strip(cand, i, bit)
    return prog


def solve(g):
    cand = [ALL] * 81
    for i, d in enumerate(g):
        if d:
            cand[i] = 1 << d
    placed = [False] * 81
    try:
        while True:                                 # cheapest technique first
            if naked_singles(cand, placed):
                continue
            if hidden_singles(cand):
                continue
            if naked_pairs(cand):
                continue
            if hidden_pairs(cand):
                continue
            if pointing_and_boxline(cand):
                continue
            if fish(cand, 2):
                continue
            if fish(cand, 3):
                continue
            break
    except Contradiction:
        return None
    if any(c.bit_count() != 1 for c in cand):
        return None
    for u in UNITS:                                 # must be a valid full grid
        m = 0
        for i in u:
            m |= cand[i]
        if m != ALL:
            return None
    return [c.bit_length() - 1 for c in cand]


if __name__ == '__main__':
    run(solve)
