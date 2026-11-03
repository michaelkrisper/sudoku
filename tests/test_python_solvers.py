"""Every Python implementation against the reference solutions.

The compiled implementations are covered by `bench/run.py --verify` and
`tools/crosscheck.sh` in CI; this keeps the interpreted reference ports under
plain pytest so they are checked even without the native toolchains.
"""
import subprocess
import sys

import pytest
from conftest import ROOT

ALGOS = ['naive', 'mrv', 'norvig', 'dlx', 'rules', 'mrv_mt']


def read(name):
    lines = (ROOT / 'puzzles' / name).read_text().splitlines()
    return [ln for ln in lines if ln.strip() and not ln.startswith('#')]


def solve(algo, puzzles, *args):
    proc = subprocess.run([sys.executable, str(ROOT / 'impl/python' / f'{algo}.py'), *args],
                          input='\n'.join(puzzles) + '\n', capture_output=True,
                          text=True, timeout=300, check=True)
    assert proc.stderr.count('ns=') == 1
    return proc.stdout.splitlines()


@pytest.mark.parametrize('algo', ALGOS)
def test_solves_verify_set(algo):
    puzzles = read('verify.txt')
    expected = read('verify_solutions.txt')
    if algo == 'naive':
        # plain backtracking in Python takes minutes on the hardest verify
        # puzzles; the first three exercise the same code paths
        puzzles, expected = puzzles[:3], expected[:3]
    got = solve(algo, puzzles)
    assert len(got) == len(expected)
    for g, want in zip(got, expected, strict=True):
        if algo == 'rules' and g == 'UNSOLVED':
            continue
        assert g == want


@pytest.mark.parametrize('algo', ALGOS)
def test_contradictory_puzzle_is_unsolved(algo):
    assert solve(algo, ['11' + '0' * 79]) == ['UNSOLVED']


def test_mrv_mt_matches_mrv_with_threads():
    puzzles = read('easy.txt')
    assert solve('mrv_mt', puzzles, '1', '4') == solve('mrv', puzzles)
