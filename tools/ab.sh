#!/usr/bin/env bash
# Fast, repeatable timing of one implementation — the tool to use while
# optimizing, where bench/run.py is too slow to iterate against.
#
#   tools/ab.sh build/c-gcc-mrv hard          # auto-calibrated, best of 5
#   tools/ab.sh build/asm-mrv hard 200 3      # 200 reps, best of 3
#
# Reports the BEST run, not the mean: the fastest observation is the one least
# contaminated by scheduling, interrupts and frequency dips, so it is the stable
# thing to compare two versions of the same code against.
#
# Pins to one core (taskset) to keep the frequency and cache state steady.
set -eu
cd "$(dirname "$0")/.."

bin=${1:?usage: ab.sh <binary-or-command> <set> [reps] [rounds]}
set_name=${2:-hard}
reps=${3:-0}
rounds=${4:-5}
cpu=${AB_CPU:-2}

puzzles="puzzles/${set_name}.txt"
[ -f "$puzzles" ] || { echo "no such set: $puzzles" >&2; exit 1; }

run() { taskset -c "$cpu" $bin "$1" 1 < "$puzzles" 2>&1 >/dev/null | sed -n 's/^ns=//p'; }

if [ "$reps" = 0 ]; then          # calibrate to ~1s of measured work
    one=$(run 1)
    reps=$(( 1000000000 / (one > 0 ? one : 1) ))
    [ "$reps" -lt 1 ] && reps=1
    [ "$reps" -gt 20000 ] && reps=20000
fi

best=""
for _ in $(seq "$rounds"); do
    ns=$(run "$reps")
    [ -z "$best" ] || [ "$ns" -lt "$best" ] && best=$ns
done

n=$(grep -c '^[0-9]\{81\}$' "$puzzles")
awk -v ns="$best" -v reps="$reps" -v n="$n" -v b="$bin" -v s="$set_name" \
    'BEGIN { printf "%-26s %-8s %8.2f us/puzzle  (%d reps, best of runs)\n", b, s, ns/reps/n/1000, reps }'
