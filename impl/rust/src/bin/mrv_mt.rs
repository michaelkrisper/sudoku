//! mrv parallelized over puzzles: worker threads pull (rep, puzzle) tasks
//! off a shared atomic counter (dynamic scheduling; puzzle cost varies).

use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::Instant;

use sudoku::{mrv, parse_args, read_puzzles, write_results, Grid};

struct Tasks<'a> {
    puzzles: &'a [Grid],
    next: AtomicUsize,
    total: usize,   // reps * npuz
    lastrep: usize, // first task index of the final repetition
}

/// Drains the task queue. Only the final repetition is recorded, so every
/// result index is produced exactly once; the caller merges by index.
fn worker(t: &Tasks) -> Vec<(usize, Option<Grid>)> {
    let npuz = t.puzzles.len();
    let mut local = Vec::new();
    loop {
        let task = t.next.fetch_add(1, Ordering::Relaxed);
        if task >= t.total {
            return local;
        }
        let p = task % npuz;
        let mut g = t.puzzles[p]; // fresh copy each repetition
        let ok = mrv::solve(&mut g);
        if task >= t.lastrep {
            local.push((p, ok.then_some(g)));
        }
    }
}

fn main() {
    let (reps, threads) = parse_args();
    let puzzles = read_puzzles();
    let npuz = puzzles.len();
    let total = (reps as usize).saturating_mul(npuz);
    let tasks = Tasks {
        puzzles: &puzzles,
        next: AtomicUsize::new(0),
        total,
        lastrep: total - npuz,
    };
    let mut results: Vec<Option<Grid>> = vec![None; npuz];

    let t0 = Instant::now();
    thread::scope(|s| {
        // main thread works too; threads are created once for all reps
        let handles: Vec<_> = (1..threads).map(|_| s.spawn(|| worker(&tasks))).collect();
        for (p, r) in worker(&tasks) {
            results[p] = r;
        }
        for h in handles {
            for (p, r) in h.join().unwrap_or_default() {
                results[p] = r;
            }
        }
    });
    let ns = t0.elapsed().as_nanos();

    write_results(&results, ns);
}
