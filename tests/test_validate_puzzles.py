"""The reference solver that every implementation is checked against."""
import pytest
from conftest import ROOT
from validate_puzzles import count_solutions

PUZZLE = '003020600900305001001806400008102900700000008006708200002609500800203009005010300'
SOLUTION = '483921657967345821251876493548132976729564138136798245372689514814253769695417382'


def grid(s):
    return bytearray(int(c) for c in s)


def read(name):
    lines = (ROOT / 'puzzles' / name).read_text().splitlines()
    return [ln for ln in lines if ln.strip() and not ln.startswith('#')]


def test_unique_puzzle_is_solved():
    n, first = count_solutions(grid(PUZZLE))
    assert n == 1
    assert ''.join(map(str, first)) == SOLUTION


def test_solved_grid_counts_as_one_solution():
    n, first = count_solutions(grid(SOLUTION))
    assert (n, bytes(first)) == (1, bytes(grid(SOLUTION)))


def test_empty_grid_stops_at_limit():
    assert count_solutions(grid('0' * 81))[0] == 2
    assert count_solutions(grid('0' * 81), limit=5)[0] == 5


def test_contradictory_clues_have_no_solution():
    assert count_solutions(grid('11' + '0' * 79)) == (0, None)


def test_input_grid_is_restored():
    g = grid(PUZZLE)
    count_solutions(g)
    assert g == grid(PUZZLE)


@pytest.mark.parametrize('name', ['easy', 'medium', 'hard', 'extreme', 'verify'])
def test_puzzle_sets_are_well_formed_and_unique(name):
    puzzles = read(f'{name}.txt')
    assert puzzles
    for p in puzzles:
        assert len(p) == 81 and p.isdigit(), p
        assert count_solutions(grid(p))[0] == 1, p


def test_verify_solutions_match_reference_solver():
    for p, want in zip(read('verify.txt'), read('verify_solutions.txt'), strict=True):
        n, first = count_solutions(grid(p))
        assert n == 1
        assert ''.join(map(str, first)) == want
        assert all(p_c in ('0', w_c) for p_c, w_c in zip(p, want, strict=True))
