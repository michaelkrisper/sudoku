"""mrv parallelized over puzzles via multiprocessing (GIL)."""
import multiprocessing as mp
from _contract import run
from mrv import solve

_pool = None


def _one(g):
    return solve(bytearray(g))


def solve_batch(grids, threads):
    global _pool
    if threads <= 1:
        return [_one(g) for g in grids]
    if _pool is None:
        try:                                  # fork: cheap start, and _one
            ctx = mp.get_context('fork')      # in __main__ stays picklable
        except ValueError:
            ctx = mp.get_context()
        _pool = ctx.Pool(threads)
    # chunksize 1: puzzle difficulty is very uneven, balance beats IPC cost
    return _pool.map(_one, grids, chunksize=1)


if __name__ == '__main__':
    run(None, solve_batch)
