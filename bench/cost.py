"""What each implementation costs beyond its solve time.

Throughput is only part of the picture. A solver also has a size, a price of
admission before it solves anything at all, and a memory footprint — and for the
managed runtimes those dwarf the algorithm by orders of magnitude. This module
measures them; bench/report.py renders them.

Measured per implementation:
  artifact_bytes   the binary, or the source that ships for interpreted languages
  stripped_bytes   the binary with symbols removed (compiled languages only)
  startup_ms       fastest wall time for a run with empty input
  startup_rss_kb   peak resident memory of that same run
  peak_rss_kb      peak resident memory while solving a whole puzzle set

Measured per language:
  build_s          a clean build of all six solvers
  source_lines     non-blank, non-comment lines of solver source
"""
import re
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIME = '/usr/bin/time'
MEM_SET = 'hard'          # representative: deep search, real allocation pressure
MEM_TIMEOUT = 60          # same budget the benchmark gives a set
STARTUP_ROUNDS = 7

# Which sources belong to a language, and how its comments start. Only lines
# that are neither blank nor pure comment are counted.
SOURCES = {
    'python': ('impl/python/*.py', ('#',)),
    'javascript': ('impl/javascript/*.js', ('//',)),
    'go': ('impl/go/*.go', ('//',)),
    'rust': ('impl/rust/src/**/*.rs', ('//',)),
    'cpp-gcc': ('impl/cpp/*.cpp', ('//',)),
    'cpp-clang': ('impl/cpp/*.cpp', ('//',)),
    'c-gcc': ('impl/c/*.c', ('//',)),
    'c-clang': ('impl/c/*.c', ('//',)),
    'asm': ('impl/asm/*.asm', (';',)),
}

# What `make` has to redo for a clean build of one language.
BUILD_TARGETS = {
    'python': None, 'javascript': None,        # nothing to build
    'go': 'build/go-*', 'rust': 'build/rust-*',
    'cpp-gcc': 'build/cpp-gcc-*', 'cpp-clang': 'build/cpp-clang-*',
    'c-gcc': 'build/c-gcc-*', 'c-clang': 'build/c-clang-*',
    'asm': 'build/asm-*',
}


def _timed(cmd, stdin_text, cwd=ROOT, timeout=None):
    """Run under /usr/bin/time, returning (wall_ms, peak_rss_kb, ok)."""
    full = [TIME, '-f', '%M', *cmd]
    started = time.perf_counter()
    try:
        p = subprocess.run(full, input=stdin_text, cwd=cwd, capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, None, False
    wall_ms = (time.perf_counter() - started) * 1000
    if p.returncode != 0:
        return None, None, False
    try:
        return wall_ms, int(p.stderr.strip().splitlines()[-1]), True
    except (IndexError, ValueError):
        return wall_ms, None, False


def startup(cmd):
    """Cost of starting the thing at all, with nothing to solve.

    Empty input is the least work an implementation can be asked to do while
    still starting its runtime, parsing arguments and honouring the contract.
    The fastest of several rounds is taken for the time (the others carry
    scheduler noise); the median is taken for memory (it is stable).
    """
    times, rss = [], []
    for _ in range(STARTUP_ROUNDS):
        ms, kb, ok = _timed(cmd, '')
        if not ok:
            return None, None
        times.append(ms)
        rss.append(kb)
    return min(times), sorted(rss)[len(rss) // 2]


def peak_rss(cmd):
    """Peak resident memory while solving a whole set.

    Bounded: `naive` does not finish the hard set in any useful time, and its
    memory is the least interesting number here anyway — a solver that cannot
    finish reports no footprint rather than stalling the run.
    """
    text = (ROOT / 'puzzles' / f'{MEM_SET}.txt').read_text()
    _, kb, ok = _timed(cmd, text, timeout=MEM_TIMEOUT)
    return kb if ok else None


def artifact(lang, algo):
    """(bytes on disk, bytes after stripping). Interpreted languages ship
    source, so that source is the artifact and there is nothing to strip."""
    if lang == 'python':
        p = ROOT / 'impl/python' / f'{algo}.py'
        contract = ROOT / 'impl/python/_contract.py'
        return (p.stat().st_size + contract.stat().st_size, None) if p.exists() else (None, None)
    if lang == 'javascript':
        p = ROOT / 'impl/javascript' / f'{algo}.js'
        return (p.stat().st_size, None) if p.exists() else (None, None)
    p = ROOT / 'build' / f'{lang}-{algo}'
    if not p.exists():
        return None, None
    size = p.stat().st_size
    stripped = None
    if shutil.which('strip'):
        tmp = ROOT / 'build' / f'.strip-{lang}-{algo}'
        shutil.copy2(p, tmp)
        if subprocess.run(['strip', '-s', str(tmp)], capture_output=True).returncode == 0:
            stripped = tmp.stat().st_size
        tmp.unlink(missing_ok=True)
    return size, stripped


def source_lines(lang):
    glob, comments = SOURCES[lang]
    base, pattern = (ROOT, glob)
    n = 0
    for path in sorted(base.glob(pattern)):
        for line in path.read_text(errors='replace').splitlines():
            s = line.strip()
            if s and not s.startswith(comments):
                n += 1
    return n


def build_time(lang):
    """Seconds for a clean build of this language's six solvers."""
    target = BUILD_TARGETS[lang]
    if target is None:
        return None
    for p in ROOT.glob(target):
        p.unlink(missing_ok=True)
    if lang == 'rust':
        subprocess.run(['cargo', 'clean', '-q'], cwd=ROOT / 'impl/rust',
                       capture_output=True)
    started = time.perf_counter()
    p = subprocess.run(['make', '-s'], cwd=ROOT, capture_output=True)
    return round(time.perf_counter() - started, 1) if p.returncode == 0 else None


def toolchain(lang):
    probes = {
        'python': ['python3', '--version'], 'javascript': ['node', '--version'],
        'go': ['go', 'version'], 'rust': ['rustc', '--version'],
        'cpp-gcc': ['g++', '--version'], 'cpp-clang': ['clang++', '--version'],
        'c-gcc': ['gcc', '--version'], 'c-clang': ['clang', '--version'],
        'asm': ['nasm', '-v'],
    }
    try:
        out = subprocess.run(probes[lang], capture_output=True, text=True).stdout
        line = out.splitlines()[0]
    except (OSError, IndexError):
        return None
    return re.sub(r'\s+', ' ', line).strip()


def collect(impls, langs, with_build=True):
    """Returns (per-implementation rows, per-language rows)."""
    if not shutil.which(TIME):
        print(f'warning: {TIME} not found, skipping cost measurements')
        return [], []
    rows = []
    for lang, algo, cmd in impls:
        size, stripped = artifact(lang, algo)
        ms, rss = startup(cmd + ['1', '1'])
        rows.append({'lang': lang, 'algo': algo,
                     'artifact_bytes': size, 'stripped_bytes': stripped,
                     'startup_ms': ms, 'startup_rss_kb': rss,
                     'peak_rss_kb': peak_rss(cmd + ['1', '1'])})
        print(f"{lang:11s} {algo:7s} "
              f"{(size or 0) / 1024:8.0f} KB  start {ms or 0:6.1f} ms / "
              f"{(rss or 0) / 1024:6.1f} MB  peak {(rows[-1]['peak_rss_kb'] or 0) / 1024:6.1f} MB")

    lang_rows = []
    for lang in langs:
        lang_rows.append({'lang': lang, 'source_lines': source_lines(lang),
                          'toolchain': toolchain(lang),
                          'build_s': build_time(lang) if with_build else None})
        b = lang_rows[-1]['build_s']
        print(f"{lang:11s} {lang_rows[-1]['source_lines']:6d} lines  "
              f"build {b if b is not None else '-'}")
    return rows, lang_rows
