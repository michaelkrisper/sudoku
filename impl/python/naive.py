"""Naive backtracking: first empty cell, digits 1-9 in order."""
from _contract import run

_ROWSTART = [i - i % 9 for i in range(81)]
_COL = [i % 9 for i in range(81)]
_BOXSTART = [i // 27 * 27 + i % 9 // 3 * 3 for i in range(81)]


def solve(g, rowstart=_ROWSTART, col=_COL, boxstart=_BOXSTART):
    def valid(pos, d):
        rs = rowstart[pos]
        if d in g[rs:rs + 9] or d in g[col[pos]::9]:
            return False
        bs = boxstart[pos]
        return not (d in g[bs:bs + 3] or d in g[bs + 9:bs + 12]
                    or d in g[bs + 18:bs + 21])

    def bt():
        try:
            pos = g.index(0)
        except ValueError:
            return True
        rs = rowstart[pos]; bs = boxstart[pos]
        used = set(g[rs:rs + 9])
        used.update(g[col[pos]::9])
        used.update(g[bs:bs + 3], g[bs + 9:bs + 12], g[bs + 18:bs + 21])
        for d in range(1, 10):
            if d not in used:
                g[pos] = d
                if bt():
                    return True
        g[pos] = 0
        return False

    for i in range(81):          # reject inconsistent clues
        d = g[i]
        if d:
            g[i] = 0
            if not valid(i, d):
                return None
            g[i] = d
    return g if bt() else None


if __name__ == '__main__':
    run(solve)
