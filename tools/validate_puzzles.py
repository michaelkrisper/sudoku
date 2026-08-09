#!/usr/bin/env python3
"""Validate puzzle files: 81 chars, consistent clues, exactly one solution.

Usage: validate_puzzles.py FILE... [--solutions OUT]
--solutions writes the reference solutions of the (single) input file.
"""
import sys

ALL = 0x3FE


def count_solutions(g, limit=2):
    """Return (number of solutions capped at `limit`, first solution)."""
    rows, cols, boxes = [0] * 9, [0] * 9, [0] * 9
    for i, d in enumerate(g):
        if d:
            r, c = divmod(i, 9)
            b = r // 3 * 3 + c // 3
            bit = 1 << d
            if (rows[r] | cols[c] | boxes[b]) & bit:
                return 0, None
            rows[r] |= bit
            cols[c] |= bit
            boxes[b] |= bit
    n = 0
    first = None

    def bt():
        nonlocal n, first
        best, best_n, best_cand = -1, 10, 0
        for i in range(81):
            if g[i]:
                continue
            r, c = divmod(i, 9)
            b = r // 3 * 3 + c // 3
            cand = ALL & ~(rows[r] | cols[c] | boxes[b])
            k = cand.bit_count()
            if k < best_n:
                best, best_n, best_cand = i, k, cand
                if k <= 1:
                    break
        if best == -1:
            n += 1
            if first is None:
                first = bytes(g)
            return n >= limit
        r, c = divmod(best, 9)
        b = r // 3 * 3 + c // 3
        cand = best_cand
        while cand:
            bit = cand & -cand
            cand ^= bit
            g[best] = bit.bit_length() - 1
            rows[r] |= bit
            cols[c] |= bit
            boxes[b] |= bit
            done = bt()
            g[best] = 0
            rows[r] ^= bit
            cols[c] ^= bit
            boxes[b] ^= bit
            if done:
                return True
        return False

    bt()
    return n, first


def main():
    args = sys.argv[1:]
    sol_out = None
    if '--solutions' in args:
        k = args.index('--solutions')
        sol_out = args[k + 1]
        del args[k:k + 2]
    all_ok = True
    for path in args:
        ok = True
        sols = []
        for ln, line in enumerate(open(path), 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if len(line) != 81 or not line.isdigit():
                print(f"{path}:{ln}: not 81 digits")
                ok = False
                continue
            n, first = count_solutions(bytearray(int(c) for c in line))
            if n != 1:
                print(f"{path}:{ln}: {n if n < 2 else '>1'} solutions")
                ok = False
            else:
                sols.append(''.join(map(str, first)))
        print(f"{path}: {'OK' if ok else 'FAILED'} ({len(sols)} puzzles)")
        all_ok &= ok
        if sol_out and ok:
            open(sol_out, 'w').write('\n'.join(sols) + '\n')
    sys.exit(0 if all_ok else 1)


main()
