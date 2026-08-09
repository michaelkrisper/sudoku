#!/usr/bin/env bash
# Check every implementation against the edge cases of the I/O contract that the
# normal verify run does not exercise: argument handling, comment and blank
# lines, contradictory input, empty input, and the shape of the stderr line.
set -u
cd "$(dirname "$0")/.."

impls=()
for f in impl/python/*.py; do
    b=$(basename "$f" .py); [ "$b" = _contract ] && continue
    impls+=("python/$b:python3 $f")
done
for f in impl/javascript/*.js; do
    impls+=("javascript/$(basename "$f" .js):node $f")
done
for f in build/*-*; do
    [ -x "$f" ] && impls+=("$(basename "$f"):$f")
done

easy1=$(head -1 puzzles/easy.txt)
fail=0

check() {  # check <name> <description> <condition-result>
    [ "$3" = ok ] || { echo "FAIL $1: $2"; fail=1; }
}

for entry in "${impls[@]}"; do
    name=${entry%%:*}; cmd=${entry#*:}

    # one ns= line on stderr, nothing else
    err=$(echo "$easy1" | $cmd 2>&1 >/dev/null)
    n=$(echo "$err" | grep -c '^ns=[0-9][0-9]*$')
    check "$name" "stderr must be exactly one 'ns=<digits>' line, got: $err" \
        "$([ "$(echo "$err" | wc -l)" = 1 ] && [ "$n" = 1 ] && echo ok)"

    # comments and blank lines are skipped, not counted as puzzles
    out=$(printf '# a comment\n\n%s\n\n' "$easy1" | $cmd 2>/dev/null | grep -c .)
    check "$name" "comment/blank lines must be skipped (got $out output lines, want 1)" \
        "$([ "$out" = 1 ] && echo ok)"

    # explicit reps and threads arguments are accepted
    out=$(echo "$easy1" | $cmd 3 2 2>/dev/null | grep -c .)
    check "$name" "must accept 'reps threads' args (got $out output lines, want 1)" \
        "$([ "$out" = 1 ] && echo ok)"

    # a contradictory puzzle yields UNSOLVED and exit 0, never a crash
    out=$(printf '11%079d\n' 0 | $cmd 2>/dev/null); rc=$?
    check "$name" "contradictory puzzle must print UNSOLVED and exit 0 (got '$out', rc=$rc)" \
        "$([ "$out" = UNSOLVED ] && [ "$rc" = 0 ] && echo ok)"

    # empty input is not an error
    </dev/null $cmd >/dev/null 2>&1
    check "$name" "empty input must exit 0 (rc=$?)" "$([ $? = 0 ] && echo ok)"
done

[ "$fail" = 0 ] && echo "all implementations honour the I/O contract"
exit $fail
