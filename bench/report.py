"""Turn a results JSON into the README benchmark section plus charts.

Charts are faceted (one panel per algorithm) so that no categorical palette is
needed: within a panel every mark is the same hue and identity comes from the
axis, not from colour. Both a light and a dark PNG are written; the README picks
one via <picture>/prefers-color-scheme.
"""
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator, NullFormatter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'
BEGIN, END = '<!-- BENCH:BEGIN -->', '<!-- BENCH:END -->'

ALGO_ORDER = ['naive', 'mrv', 'norvig', 'dlx', 'rules', 'mrv_mt']
ALGO_TITLE = {'naive': 'naive backtracking', 'mrv': 'MRV + bitmasks',
              'norvig': 'constraint propagation', 'dlx': 'dancing links',
              'rules': 'rule-based (no guessing)', 'mrv_mt': 'MRV, multithreaded'}
SET_ORDER = ['easy', 'medium', 'hard', 'extreme']

# Palette: single-hue marks on the chart surface (see dataviz reference palette).
THEMES = {
    'light': dict(surface='#fcfcfb', ink='#0b0b0b', muted='#898781',
                  grid='#e1e0d9', axis='#c3c2b7', mark='#2a78d6'),
    'dark': dict(surface='#1a1a19', ink='#ffffff', muted='#898781',
                 grid='#2c2c2a', axis='#383835', mark='#3987e5'),
}


def index(runs):
    return {(r['lang'], r['algo'], r['set']): r for r in runs}


def langs_in(runs):
    seen = []
    for r in runs:
        if r['lang'] not in seen:
            seen.append(r['lang'])
    return seen


def cell(r):
    if r is None:
        return '&mdash;'
    if r.get('status') == 'dnf':
        return 'DNF'
    if r.get('status', 'ok') != 'ok':
        return 'ERR'
    us = r['us_per_puzzle']
    return f'{us:,.2f}' if us >= 0.01 else f'{us:.4f}'


def table_for_set(by, langs, algos, set_name):
    """One table per puzzle set; the fastest language per algorithm is bold."""
    best = {}
    for a in algos:
        timed = [(r['us_per_puzzle'], r['lang']) for lang in langs
                 if (r := by.get((lang, a, set_name))) and r.get('status') == 'ok']
        if timed:
            best[a] = min(timed)[1]
    head = '| language | ' + ' | '.join(algos) + ' |'
    sep = '|---' * (len(algos) + 1) + '|'
    rows = []
    for lang in langs:
        cells = []
        for a in algos:
            text = cell(by.get((lang, a, set_name)))
            cells.append(f'**{text}**' if best.get(a) == lang else text)
        rows.append(f'| `{lang}` | ' + ' | '.join(cells) + ' |')
    return '\n'.join([head, sep] + rows)


def human(us):
    """Readable microsecond label — the axis is log, the labels should not be."""
    if us >= 1000:
        return f'{us / 1000:,.0f} ms'
    if us >= 1:
        return f'{us:.0f} µs'
    return f'{us:.2f} µs'


def rules_note(runs, set_name):
    """Without this, the rules column reads as the fastest solver on the hard
    sets, when in fact it is the one that gives up."""
    rs = [r for r in runs if r['algo'] == 'rules' and r['set'] == set_name
          and r.get('status') == 'ok']
    if not rs:
        return ''
    solved, total = rs[0]['solved'], rs[0]['puzzles']
    if solved == total:
        return f'`rules` solved all {total} puzzles of this set by logic alone.'
    return (f'`rules` solved {solved} of {total} puzzles here and gave up on the '
            f'rest, so its column covers less work than the others — it is not '
            f'faster, it is doing less.')


def style(ax, th):
    ax.set_facecolor(th['surface'])
    ax.tick_params(colors=th['muted'], labelsize=8, length=0)
    for side in ('top', 'right', 'left'):
        ax.spines[side].set_visible(False)
    ax.spines['bottom'].set_color(th['axis'])
    ax.spines['bottom'].set_linewidth(1)


def chart_by_impl(by, langs, algos, set_name, theme, path):
    """Small multiples: one panel per algorithm, dot plot on a log axis.

    Dots (position encoding) rather than bars, because the spread covers several
    orders of magnitude and a bar on a log axis misstates its own length.
    """
    th = THEMES[theme]
    n = len(algos)
    # sharex matters: with per-panel ranges the same dot position would mean a
    # different number in every panel, and the panels are meant to be compared.
    fig, axes = plt.subplots(1, n, figsize=(2.35 * n, 0.42 * len(langs) + 1.9),
                             sharey=True, sharex=True)
    fig.patch.set_facecolor(th['surface'])
    axes = [axes] if n == 1 else list(axes)
    ys = range(len(langs))
    for ax, algo in zip(axes, algos):
        style(ax, th)
        vals, labels = [], []
        for lang in langs:
            r = by.get((lang, algo, set_name))
            ok = r is not None and r.get('status') == 'ok'
            vals.append(r['us_per_puzzle'] if ok else None)
            labels.append('' if ok else ('DNF' if r and r.get('status') == 'dnf' else ''))
        ax.set_xscale('log')
        ax.grid(axis='x', color=th['grid'], linewidth=1, zorder=0)
        ax.set_axisbelow(True)
        pts = [(y, v) for y, v in zip(ys, vals) if v is not None]
        if pts:
            ax.scatter([v for _, v in pts], [y for y, _ in pts], s=46,
                       color=th['mark'], edgecolor=th['surface'], linewidth=2,
                       zorder=3)
            fast = min(pts, key=lambda p: p[1])
            slow = max(pts, key=lambda p: p[1])
            for y, v in {fast, slow}:
                ax.annotate(human(v), (v, y), textcoords='offset points',
                            xytext=(0, 8), ha='center', fontsize=7,
                            color=th['muted'])
        for y, lab in zip(ys, labels):
            if lab:
                ax.text(0.5, y, lab, transform=ax.get_yaxis_transform(),
                        ha='center', va='center', fontsize=7, color=th['muted'])
        ax.xaxis.set_minor_formatter(NullFormatter())
        ax.xaxis.set_major_locator(LogLocator(numticks=4))
        ax.set_title(f'{algo}\n{ALGO_TITLE[algo]}', fontsize=8.5,
                     color=th['ink'], pad=9, linespacing=1.5)
    axes[0].set_yticks(list(ys))
    axes[0].set_yticklabels(langs, fontsize=8, color=th['ink'])
    axes[0].invert_yaxis()
    fig.suptitle(f'Microseconds per puzzle — {set_name} set (lower is better, log scale)',
                 fontsize=10.5, color=th['ink'], y=0.985)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(path, dpi=170, facecolor=th['surface'])
    plt.close(fig)


def chart_bars(pairs, title, xlabel, theme, path, fmt='{:.2f}'):
    th = THEMES[theme]
    labels = [p[0] for p in pairs]
    vals = [p[1] for p in pairs]
    fig, ax = plt.subplots(figsize=(6.2, 0.42 * len(pairs) + 1.5))
    fig.patch.set_facecolor(th['surface'])
    style(ax, th)
    ax.grid(axis='x', color=th['grid'], linewidth=1, zorder=0)
    ax.set_axisbelow(True)
    ax.barh(labels, vals, height=0.55, color=th['mark'], zorder=3)
    ax.invert_yaxis()
    ax.set_xlabel(xlabel, fontsize=8, color=th['muted'])
    ax.set_title(title, fontsize=10.5, color=th['ink'], pad=10, loc='left')
    ax.tick_params(axis='y', labelcolor=th['ink'], labelsize=8)
    span = max(vals) if vals else 1
    for y, v in enumerate(vals):
        ax.text(v + span * 0.015, y, fmt.format(v), va='center', fontsize=8,
                color=th['ink'])
    ax.set_xlim(0, span * 1.14)
    fig.tight_layout()
    fig.savefig(path, dpi=170, facecolor=th['surface'])
    plt.close(fig)


def findings(by, langs, algos, sets):
    """The ratio between an easy and a hard set says more about an algorithm
    than either number alone, so state it explicitly."""
    if not {'easy', 'hard'} <= set(sets):
        return []
    ref = 'cpp-gcc' if 'cpp-gcc' in langs else langs[-1]
    rows = []
    for a in algos:
        e, h = by.get((ref, a, 'easy')), by.get((ref, a, 'hard'))
        if not (e and h and e.get('status') == 'ok' and h.get('status') == 'ok'):
            continue
        # Only comparable where the work is the same on both sets. `rules`
        # abandons the puzzles it cannot deduce, so its ratio would flatter it.
        if e['solved'] < e['puzzles'] or h['solved'] < h['puzzles']:
            continue
        rows.append((a, e['us_per_puzzle'], h['us_per_puzzle']))
    if len(rows) < 2:
        return []
    rows.sort(key=lambda r: r[2] / r[1], reverse=True)
    table = ['| algorithm | easy | hard | factor |', '|---|---|---|---|']
    table += [f'| `{a}` | {e:,.1f} | {h:,.1f} | {h / e:,.1f}× |' for a, e, h in rows]
    return ['### How the algorithms scale with difficulty', '',
            f'Time per puzzle in `{ref}`, and how much of it the hard set costs:',
            '', *table, '',
            'The ranking is not a property of the algorithms — it is a function '
            'of how hard the input is. Constraint propagation carries a high '
            'fixed cost per assignment and spends it whether or not there is a '
            'search tree to prune, which makes it the slowest choice on easy '
            'puzzles and a good one where the search actually explodes. Plain '
            'MRV is the opposite: almost free per cell, but it pays the full '
            'price of every branch it has to take.', '',
            'Note also that `extreme` here is not the hardest set for a machine. '
            'Those puzzles are hard for *humans*; their search trees are shallow, '
            'so the solvers that win on `hard` do not win on `extreme`.', '']


def picture(name, alt):
    return (f'<picture>\n'
            f'  <source media="(prefers-color-scheme: dark)" srcset="assets/{name}_dark.png">\n'
            f'  <img alt="{alt}" src="assets/{name}_light.png">\n'
            f'</picture>')


def build(results_path):
    data = json.loads(Path(results_path).read_text())
    runs, meta = data['runs'], data['meta']
    by = index(runs)
    langs = langs_in(runs)
    algos = [a for a in ALGO_ORDER if any(r['algo'] == a for r in runs)]
    sets = [s for s in SET_ORDER if any(r['set'] == s for r in runs)]
    ASSETS.mkdir(exist_ok=True)

    headline = 'hard' if 'hard' in sets else sets[-1]
    parts = [
        f"Measured on {meta['cpu']} ({meta['cores']} cores), {meta['date']}. "
        f"Each number is microseconds per puzzle. The repetition count is "
        f"calibrated so every measured loop runs at least a second, and the "
        f"median of three runs is reported — except for solvers already taking "
        f"over five seconds per pass, which are measured once. Lower is better; "
        f"DNF means the 60 s budget for that set ran out.",
        '', picture('time_by_impl', f'Time per puzzle by implementation, {headline} set'), '',
    ]

    for s in sets:
        body = table_for_set(by, langs, algos, s)
        note = rules_note(runs, s)
        if s == headline:
            parts += [f'### {s} set (µs per puzzle)', '', body, '', note, '']
        else:
            parts += [f'<details><summary>{s} set (µs per puzzle)</summary>',
                      '', body, '', note, '', '</details>', '']

    chart_by_impl(by, langs, algos, headline, 'light',
                  ASSETS / 'time_by_impl_light.png')
    chart_by_impl(by, langs, algos, headline, 'dark',
                  ASSETS / 'time_by_impl_dark.png')

    if 'rules' in algos:
        rate = []
        for s in sets:
            tot = sum(r['puzzles'] for r in runs if r['algo'] == 'rules' and r['set'] == s)
            sol = sum(r['solved'] for r in runs if r['algo'] == 'rules' and r['set'] == s)
            n_impl = sum(1 for r in runs if r['algo'] == 'rules' and r['set'] == s)
            if n_impl:
                rate.append((s, 100 * sol / tot))
        if rate:
            for theme in THEMES:
                chart_bars(rate, 'Share of puzzles solved by logic alone',
                           'percent of puzzles solved without guessing', theme,
                           ASSETS / f'rules_solve_rate_{theme}.png', '{:.0f}%')
            parts += ['### How far pure logic gets you', '',
                      'The `rules` solver never guesses. Whatever it leaves '
                      '`UNSOLVED` genuinely needs search:', '',
                      picture('rules_solve_rate', 'Share of puzzles solved by logic alone'), '']

    speedups = []
    for lang in langs:
        a = by.get((lang, 'mrv', headline))
        b = by.get((lang, 'mrv_mt', headline))
        if a and b and a.get('status') == 'ok' and b.get('status') == 'ok':
            speedups.append((lang, a['us_per_puzzle'] / b['us_per_puzzle']))
    if speedups:
        for theme in THEMES:
            chart_bars(speedups, f'Multithreaded speedup — mrv_mt vs mrv ({headline} set)',
                       f"speedup factor on {meta['cores']} cores", theme,
                       ASSETS / f'mt_speedup_{theme}.png', '{:.2f}×')
        parts += ['### Multithreading', '',
                  picture('mt_speedup', 'Multithreaded speedup by language'), '']

    parts += findings(by, langs, algos, sets)
    section = '\n'.join(parts).rstrip() + '\n'
    readme = (ROOT / 'README.md').read_text()
    pre, rest = readme.split(BEGIN, 1)
    _, post = rest.split(END, 1)
    (ROOT / 'README.md').write_text(f'{pre}{BEGIN}\n\n{section}\n{END}{post}')
    return len(runs)
