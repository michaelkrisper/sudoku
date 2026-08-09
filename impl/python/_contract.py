"""Shared I/O contract for the python solvers.

Usage: python3 <solver>.py [reps] [threads] < puzzles.txt
"""
import sys, time


def run(solve, solve_batch=None):
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    threads = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    puzzles = [ln.strip() for ln in sys.stdin.read().splitlines()
               if ln.strip() and not ln.startswith('#')]
    grids = [bytes(int(c) for c in p) for p in puzzles]
    results = [None] * len(grids)
    t0 = time.perf_counter_ns()
    for _ in range(reps):
        if solve_batch is not None:
            results = solve_batch(grids, threads)
        else:
            for i, g in enumerate(grids):
                results[i] = solve(bytearray(g))
    ns = time.perf_counter_ns() - t0
    sys.stderr.write(f"ns={ns}\n")
    sys.stdout.write('\n'.join(
        ''.join(map(str, r)) if r is not None else 'UNSOLVED'
        for r in results) + '\n')
