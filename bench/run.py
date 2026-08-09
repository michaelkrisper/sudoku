#!/usr/bin/env python3
"""One harness for all implementations: build, verify, benchmark, report."""
import argparse, ctypes, json, os, platform, statistics, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALGOS = ['naive', 'mrv', 'norvig', 'dlx', 'rules', 'mrv_mt']
LANGS = ['python', 'javascript', 'go', 'rust',
         'cpp-gcc', 'cpp-clang', 'c-gcc', 'c-clang', 'asm']
SETS = ['easy', 'medium', 'hard', 'extreme']
SET_TIMEOUT = 60           # seconds per (impl, set) run
TARGET_NS = 1_000_000_000  # calibrate reps until the solve loop takes >= 1s


def clear_thp_disable():
    # Claude Code sessions run with PR_SET_THP_DISABLE (=41) set; clear it so
    # spawned solvers see the same THP environment as a normal terminal.
    try:
        ctypes.CDLL(None).prctl(41, 0, 0, 0, 0)
    except Exception:
        pass


def cmd_for(lang, algo):
    if lang == 'python':
        p = ROOT / 'impl/python' / f'{algo}.py'
        return [sys.executable, str(p)], p
    if lang == 'javascript':
        p = ROOT / 'impl/javascript' / f'{algo}.js'
        return ['node', str(p)], p
    p = ROOT / 'build' / f'{lang}-{algo}'
    return [str(p)], p


def discover(langs, algos):
    impls = []
    for lang in langs:
        for algo in algos:
            cmd, path = cmd_for(lang, algo)
            if path.exists():
                impls.append((lang, algo, cmd))
    return impls


def run_solver(cmd, puzzles_text, reps=1, threads=1, timeout=SET_TIMEOUT):
    proc = subprocess.run(cmd + [str(reps), str(threads)], input=puzzles_text,
                          capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(f"exit {proc.returncode}: {proc.stderr.strip()[:200]}")
    ns = None
    for line in proc.stderr.splitlines():
        if line.startswith('ns='):
            ns = int(line[3:])
    if ns is None:
        raise RuntimeError("no ns= line on stderr")
    return proc.stdout.splitlines(), ns


def load_set(name):
    lines = (ROOT / 'puzzles' / f'{name}.txt').read_text().splitlines()
    return [l for l in lines if l.strip() and not l.startswith('#')]


def verify(impls):
    puzzles = (ROOT / 'puzzles/verify.txt').read_text()
    expected = load_set('verify_solutions')
    failed = []
    for lang, algo, cmd in impls:
        name = f'{lang}/{algo}'
        try:
            lines, _ = run_solver(cmd, puzzles)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            print(f'FAIL {name}: {e}')
            failed.append(name)
            continue
        if len(lines) != len(expected):
            print(f'FAIL {name}: {len(lines)} lines, expected {len(expected)}')
            failed.append(name)
            continue
        bad = [i for i, (got, want) in enumerate(zip(lines, expected))
               if got != want and not (got == 'UNSOLVED' and algo == 'rules')]
        if bad:
            print(f'FAIL {name}: wrong solution for puzzle(s) {bad}')
            failed.append(name)
        else:
            unsolved = sum(1 for l in lines if l == 'UNSOLVED')
            print(f'PASS {name}' + (f' ({unsolved} unsolved)' if unsolved else ''))
    print(f'{len(impls) - len(failed)}/{len(impls)} implementations pass verify')
    return [i for i in impls if f'{i[0]}/{i[1]}' not in failed], failed


def bench_one(cmd, set_name, threads):
    text = (ROOT / 'puzzles' / f'{set_name}.txt').read_text()
    n_puzzles = len(load_set(set_name))
    _, ns = run_solver(cmd, text, reps=1, threads=threads)
    reps = max(1, min(10_000, int(TARGET_NS // max(ns, 1))))
    samples = []
    for _ in range(3):
        lines, ns = run_solver(cmd, text, reps=reps, threads=threads)
        samples.append(ns)
    ns_med = statistics.median(samples)
    return {'reps': reps, 'ns_median': ns_med,
            'us_per_puzzle': ns_med / reps / n_puzzles / 1000,
            'puzzles': n_puzzles,
            'solved': sum(1 for l in lines if l != 'UNSOLVED'),
            'status': 'ok'}


def bench(impls, sets):
    nproc = os.cpu_count() or 1
    runs = []
    for lang, algo, cmd in impls:
        threads = nproc if algo.endswith('_mt') else 1
        for s in sets:
            try:
                r = bench_one(cmd, s, threads)
            except subprocess.TimeoutExpired:
                r = {'status': 'dnf'}
            except RuntimeError as e:
                r = {'status': f'error: {e}'}
            r.update(lang=lang, algo=algo, set=s, threads=threads)
            runs.append(r)
            us = r.get('us_per_puzzle')
            detail = (f"{us:12.2f} us/puzzle  {r['solved']}/{r['puzzles']} solved"
                      if us is not None else r['status'])
            print(f"{lang:11s} {algo:7s} {s:8s} {detail}")
    return runs


def cpu_model():
    try:
        for line in open('/proc/cpuinfo'):
            if line.startswith('model name'):
                return line.split(':', 1)[1].strip()
    except OSError:
        pass
    return 'unknown'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify', action='store_true', help='verify only')
    ap.add_argument('--lang', action='append', choices=LANGS)
    ap.add_argument('--algo', action='append', choices=ALGOS)
    ap.add_argument('--set', action='append', choices=SETS)
    args = ap.parse_args()

    clear_thp_disable()
    subprocess.run(['make', '-s'], cwd=ROOT, check=True)
    impls = discover(args.lang or LANGS, args.algo or ALGOS)
    if not impls:
        sys.exit('no implementations found')

    good, failed = verify(impls)
    if args.verify:
        sys.exit(1 if failed else 0)
    if not good:
        sys.exit('nothing to benchmark')

    runs = bench(good, args.set or SETS)
    out = {'meta': {'host': platform.node(), 'cpu': cpu_model(),
                    'cores': os.cpu_count(),
                    'date': time.strftime('%Y-%m-%d %H:%M:%S')},
           'runs': runs}
    path = ROOT / 'results' / f'{int(time.time())}.json'
    path.write_text(json.dumps(out, indent=1))
    print(f'raw results: {path.relative_to(ROOT)}')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
