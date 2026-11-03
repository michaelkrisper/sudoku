"""The harness plumbing: solver invocation, the stderr contract and the verify gate."""
import sys

import pytest
import run
from conftest import ROOT


def fake(script):
    """A solver command that runs `script` with the contract's argv."""
    return [sys.executable, '-c', script]


def test_load_set_skips_comments_and_blank_lines(tmp_path, monkeypatch):
    (tmp_path / 'puzzles').mkdir()
    (tmp_path / 'puzzles' / 'x.txt').write_text('# header\n\n' + '1' * 81 + '\n  \n' + '2' * 81 + '\n')
    monkeypatch.setattr(run, 'ROOT', tmp_path)
    assert run.load_set('x') == ['1' * 81, '2' * 81]


def test_run_solver_parses_stdout_and_ns():
    cmd = fake('import sys; print("a"); print("b"); sys.stderr.write("noise\\nns=1234\\n")')
    assert run.run_solver(cmd, '') == (['a', 'b'], 1234)


def test_run_solver_passes_reps_and_threads():
    cmd = fake('import sys; print(" ".join(sys.argv[1:])); sys.stderr.write("ns=1\\n")')
    lines, _ = run.run_solver(cmd, '', reps=7, threads=3)
    assert lines == ['7 3']


def test_run_solver_rejects_missing_ns_line():
    with pytest.raises(RuntimeError, match='no ns='):
        run.run_solver(fake('print("x")'), '')


def test_run_solver_rejects_nonzero_exit():
    with pytest.raises(RuntimeError, match='exit 3'):
        run.run_solver(fake('import sys; sys.exit(3)'), '')


def echo_solver(answers):
    """A fake solver that prints a fixed list of answers."""
    body = '\\n'.join(answers)
    return fake(f'import sys; print("{body}"); sys.stderr.write("ns=1\\n")')


def test_verify_accepts_correct_and_rejects_wrong_answers(capsys):
    expected = run.load_set('verify_solutions')
    wrong = list(expected)
    wrong[2] = expected[3]
    good, failed = run.verify([('l', 'mrv', echo_solver(expected)),
                               ('l', 'dlx', echo_solver(wrong)),
                               ('l', 'norvig', echo_solver(expected[:-1]))])
    assert [i[1] for i in good] == ['mrv']
    assert failed == ['l/dlx', 'l/norvig']
    out = capsys.readouterr().out
    assert 'wrong solution for puzzle(s) [2]' in out
    assert '11 lines, expected 12' in out


def test_verify_lets_only_rules_answer_unsolved():
    answers = run.load_set('verify_solutions')
    answers[0] = 'UNSOLVED'
    good, failed = run.verify([('l', 'rules', echo_solver(answers)),
                               ('l', 'mrv', echo_solver(answers))])
    assert [i[1] for i in good] == ['rules']
    assert failed == ['l/mrv']


def test_discover_finds_interpreted_implementations():
    impls = run.discover(['python', 'javascript'], run.ALGOS)
    assert {(lang, algo) for lang, algo, _ in impls} == \
        {(lang, algo) for lang in ('python', 'javascript') for algo in run.ALGOS}
    lang, algo, cmd = impls[0]
    assert cmd[-1] == str(ROOT / 'impl/python' / f'{algo}.py')
