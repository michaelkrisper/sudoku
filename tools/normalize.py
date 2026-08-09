#!/usr/bin/env python3
"""Normalize sudoku collections to one 81-char line per puzzle, 0 = empty.
Reads stdin, writes stdout."""
import re, sys

digits = []
for line in sys.stdin:
    line = line.strip()
    if re.fullmatch(r'[0-9.]+', line):
        digits.append(line.replace('.', '0'))
s = ''.join(digits)
assert len(s) % 81 == 0, f"total digit count {len(s)} not divisible by 81"
for i in range(0, len(s), 81):
    print(s[i:i + 81])
