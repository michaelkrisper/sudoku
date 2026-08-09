"""Knuth's Algorithm X with Dancing Links, flat-array based."""
from _contract import run

NCOLS = 324                     # 81 cell + 81 row-digit + 81 col-digit + 81 box-digit
NNODES = 1 + NCOLS + 729 * 4    # root + headers + 4 nodes per candidate row
FIRST = NCOLS + 1               # index of first row node


def _build():
    L = [0] * NNODES; R = [0] * NNODES
    U = [0] * NNODES; D = [0] * NNODES
    C = [0] * NNODES; RID = [0] * NNODES
    SZ = [0] * (NCOLS + 1)
    for h in range(NCOLS + 1):  # 0 = root, 1..324 = column headers
        L[h] = h - 1 if h else NCOLS
        R[h] = h + 1 if h < NCOLS else 0
        U[h] = D[h] = h
    n = FIRST
    for cell in range(81):
        r, c = divmod(cell, 9)
        b = r // 3 * 3 + c // 3
        for d in range(9):      # d = digit - 1
            rid = cell * 9 + d
            for col in (1 + cell, 82 + r * 9 + d, 163 + c * 9 + d,
                        244 + b * 9 + d):
                C[n] = col; RID[n] = rid
                D[n] = col; U[n] = U[col]; D[U[col]] = n; U[col] = n
                SZ[col] += 1
                n += 1
            f = n - 4           # link the 4 nodes of this row circularly
            L[f] = f + 3; R[f] = f + 1
            L[f + 1] = f; R[f + 1] = f + 2
            L[f + 2] = f + 1; R[f + 2] = f + 3
            L[f + 3] = f + 2; R[f + 3] = f
    return L, R, U, D, C, SZ, RID


L0, R0, U0, D0, C, SZ0, RID = _build()


def solve(g):
    rm = [0] * 9; cm = [0] * 9; bm = [0] * 9   # cheap consistency gate
    for i in range(81):
        d = g[i]
        if d:
            r, c = divmod(i, 9)
            b = r // 3 * 3 + c // 3
            bit = 1 << d
            if (rm[r] | cm[c] | bm[b]) & bit:
                return None
            rm[r] |= bit; cm[c] |= bit; bm[b] |= bit

    # fresh copies of the mutable arrays; C and RID are never modified
    L = L0.copy(); R = R0.copy(); U = U0.copy(); D = D0.copy()
    SZ = SZ0.copy()

    def cover(c0, L=L, R=R, U=U, D=D, C=C, SZ=SZ):
        R[L[c0]] = R[c0]; L[R[c0]] = L[c0]
        i = D[c0]
        while i != c0:
            j = R[i]
            while j != i:
                D[U[j]] = D[j]; U[D[j]] = U[j]; SZ[C[j]] -= 1
                j = R[j]
            i = D[i]

    def uncover(c0, L=L, R=R, U=U, D=D, C=C, SZ=SZ):
        i = U[c0]
        while i != c0:
            j = L[i]
            while j != i:
                SZ[C[j]] += 1; D[U[j]] = j; U[D[j]] = j
                j = L[j]
            i = U[i]
        R[L[c0]] = c0; L[R[c0]] = c0

    for i in range(81):         # pre-select clue rows (gate makes this safe)
        d = g[i]
        if d:
            node = FIRST + (i * 9 + d - 1) * 4
            cover(C[node])
            j = R[node]
            while j != node:
                cover(C[j])
                j = R[j]

    sol = []

    def search(L=L, R=R, U=U, D=D, C=C, SZ=SZ, RID=RID, sol=sol,
               cover=cover, uncover=uncover):
        best = R[0]             # root is 0, headers are 1..324 (truthy)
        if not best:
            return True
        s = SZ[best]
        if s > 1:               # Knuth's S heuristic, early out on size <= 1
            j = R[best]
            while j:
                sj = SZ[j]
                if sj < s:
                    s = sj; best = j
                    if s < 2:
                        break
                j = R[j]
        cover(best)
        i = D[best]
        while i != best:
            sol.append(RID[i])
            j = R[i]
            while j != i:
                cover(C[j])
                j = R[j]
            if search():
                return True
            j = L[i]
            while j != i:
                uncover(C[j])
                j = L[j]
            sol.pop()
            i = D[i]
        uncover(best)
        return False

    if not search():
        return None
    out = list(g)
    for rid in sol:
        out[rid // 9] = rid % 9 + 1
    return out


if __name__ == '__main__':
    run(solve)
