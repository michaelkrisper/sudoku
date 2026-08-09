"""Backtracking with bitmask candidates and most-constrained-cell order."""
from _contract import run

_ALL = 0x3FE                                  # bits 1..9 set
_ROW = [i // 9 for i in range(81)]
_COL = [i % 9 for i in range(81)]
_BOX = [i // 27 * 3 + i % 9 // 3 for i in range(81)]
_NC = bytes(bin(x).count('1') for x in range(1024))   # popcount table
_DIG = [0] * 1024                             # single-bit mask -> digit
for _d in range(1, 10):
    _DIG[1 << _d] = _d


def solve(g, ALL=_ALL, ROW=_ROW, COL=_COL, BOX=_BOX, NC=_NC, DIG=_DIG):
    # masks hold the still-allowed digit bits per row/col/box
    rows = [ALL] * 9
    cols = [ALL] * 9
    boxes = [ALL] * 9
    empties = []
    for i in range(81):
        d = g[i]
        if d:
            bit = 1 << d
            r = ROW[i]; c = COL[i]; b = BOX[i]
            if not (rows[r] & cols[c] & boxes[b] & bit):
                return None                   # duplicate clue
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit
        else:
            empties.append(i)
    n = len(empties)

    def bt(k):
        if k == n:
            return True
        best_j = k
        best_n = 10
        best_cand = 0
        for j in range(k, n):
            i = empties[j]
            cand = rows[ROW[i]] & cols[COL[i]] & boxes[BOX[i]]
            nc = NC[cand]
            if nc < best_n:
                if nc == 0:
                    return False              # dead end
                best_j = j; best_n = nc; best_cand = cand
                if nc == 1:
                    break
        i = empties[best_j]
        empties[best_j] = empties[k]
        empties[k] = i
        r = ROW[i]; c = COL[i]; b = BOX[i]
        cand = best_cand
        while cand:
            bit = cand & -cand
            cand -= bit
            g[i] = DIG[bit]
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit
            if bt(k + 1):
                return True
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit
        g[i] = 0
        return False

    return g if bt(0) else None


if __name__ == '__main__':
    run(solve)
