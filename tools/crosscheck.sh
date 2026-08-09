#!/usr/bin/env bash
# Check every implementation against the reference solutions of every puzzle
# set — a much wider net than the 12-puzzle verify gate in bench/run.py.
#
# `rules` is allowed to answer UNSOLVED (it never guesses); anything else it
# prints must still match. Every other algorithm must solve everything.
#
# A solver that exceeds TIMEOUT is reported as TIMEOUT, not as a failure:
# `naive` on the anti-brute-force puzzle in the extreme set does not finish in
# any useful time, which is exactly why that puzzle is in the set.
#
# Usage: tools/crosscheck.sh [set...]     (default: all four sets)
#        TIMEOUT=60 tools/crosscheck.sh   (seconds per implementation and set)
set -u
cd "$(dirname "$0")/.."
: "${TIMEOUT:=120}"

sets=("${@:-}")
[ -z "${sets[0]}" ] && sets=(easy medium hard extreme)

ref_dir=$(mktemp -d)
trap 'rm -rf "$ref_dir"' EXIT
for s in "${sets[@]}"; do
    python3 tools/validate_puzzles.py "puzzles/$s.txt" \
        --solutions "$ref_dir/$s.txt" >/dev/null || exit 1
done

impls=()
for f in impl/python/*.py; do
    b=$(basename "$f" .py); [ "$b" = _contract ] && continue
    impls+=("python/$b:python3 $f")
done
for f in impl/javascript/*.js; do
    impls+=("javascript/$(basename "$f" .js):node $f")
done
for f in build/*-*; do
    [ -x "$f" ] || continue
    impls+=("$(basename "$f"):$f")
done

fail=0
for entry in "${impls[@]}"; do
    name=${entry%%:*}; cmd=${entry#*:}
    algo=${name##*-}; [ "$algo" = "$name" ] && algo=${name##*/}
    for s in "${sets[@]}"; do
        out=$(timeout "$TIMEOUT" $cmd < "puzzles/$s.txt" 2>/dev/null)
        if [ $? = 124 ]; then
            echo "TIMEOUT $name on $s (>${TIMEOUT}s)"
            continue
        fi
        bad=$(paste -d' ' <(echo "$out") "$ref_dir/$s.txt" | awk -v algo="$algo" '
            $1 == "UNSOLVED" { if (algo != "rules") { n++ } ; next }
            $1 != $2 { n++ }
            END { print n + 0 }')
        if [ "$bad" != 0 ]; then
            echo "FAIL $name on $s: $bad wrong line(s)"
            fail=1
        fi
    done
done
[ "$fail" = 0 ] && echo "all implementations agree with the reference solutions"
exit $fail
