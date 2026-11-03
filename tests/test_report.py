"""Pure formatting helpers of the README generator."""
from report import cell, human, index, kb, langs_in, mb, rules_note, table_for_set


def run(lang, algo, s, us=None, status='ok', **kw):
    r = {'lang': lang, 'algo': algo, 'set': s, 'status': status, **kw}
    if us is not None:
        r['us_per_puzzle'] = us
    return r


def test_cell_formats_status_and_precision():
    assert cell(None) == '&mdash;'
    assert cell({'status': 'dnf'}) == 'DNF'
    assert cell({'status': 'error: boom'}) == 'ERR'
    assert cell({'us_per_puzzle': 1234.5}) == '1,234.50'
    assert cell({'us_per_puzzle': 0.001234}) == '0.0012'


def test_human_labels():
    assert human(12_345) == '12 ms'
    assert human(42.4) == '42 µs'
    assert human(0.5) == '0.50 µs'


def test_sizes():
    assert kb(None) == '&mdash;'
    assert kb(2048) == '2 KB'
    assert kb(3 * 1024 * 1024) == '3.0 MB'
    assert mb(None) == '&mdash;'
    assert mb(1536) == '1.5'


def test_langs_in_keeps_first_seen_order():
    runs = [run('go', 'mrv', 'easy'), run('c', 'mrv', 'easy'), run('go', 'dlx', 'easy')]
    assert langs_in(runs) == ['go', 'c']


def test_table_bolds_fastest_language_per_algorithm():
    runs = [run('go', 'mrv', 'easy', 5.0), run('c', 'mrv', 'easy', 2.0),
            run('go', 'dlx', 'easy', 1.0), run('c', 'dlx', 'easy', status='dnf')]
    table = table_for_set(index(runs), ['go', 'c'], ['mrv', 'dlx'], 'easy').splitlines()
    assert table[0] == '| language | mrv | dlx |'
    assert table[2] == '| `go` | 5.00 | **1.00** |'
    assert table[3] == '| `c` | **2.00** | DNF |'


def test_rules_note():
    assert rules_note([], 'hard') == ''
    full = [run('c', 'rules', 'easy', 1.0, solved=50, puzzles=50)]
    assert 'solved all 50' in rules_note(full, 'easy')
    part = [run('c', 'rules', 'hard', 1.0, solved=30, puzzles=95)]
    assert 'solved 30 of 95' in rules_note(part, 'hard')
