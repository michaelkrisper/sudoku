// Naive backtracking: first empty cell, digits 1-9 in order.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

func valid(g *[81]uint8, pos int, d uint8) bool {
	rs := pos - pos%9
	for k := 0; k < 9; k++ {
		if g[rs+k] == d {
			return false
		}
	}
	for k := pos % 9; k < 81; k += 9 {
		if g[k] == d {
			return false
		}
	}
	bs := pos/27*27 + pos%9/3*3
	for r := 0; r < 27; r += 9 {
		if g[bs+r] == d || g[bs+r+1] == d || g[bs+r+2] == d {
			return false
		}
	}
	return true
}

func bt(g *[81]uint8) bool {
	pos := -1
	for i := 0; i < 81; i++ {
		if g[i] == 0 {
			pos = i
			break
		}
	}
	if pos < 0 {
		return true
	}
	for d := uint8(1); d <= 9; d++ {
		if valid(g, pos, d) {
			g[pos] = d
			if bt(g) {
				return true
			}
		}
	}
	g[pos] = 0
	return false
}

func solve(g *[81]uint8) bool {
	for i := 0; i < 81; i++ { // reject inconsistent clues
		d := g[i]
		if d != 0 {
			g[i] = 0
			ok := valid(g, i, d)
			g[i] = d
			if !ok {
				return false
			}
		}
	}
	return bt(g)
}

func readPuzzles() [][81]uint8 {
	data, _ := io.ReadAll(os.Stdin)
	var grids [][81]uint8
	for _, ln := range strings.Split(string(data), "\n") {
		ln = strings.TrimSpace(ln)
		if ln == "" || ln[0] == '#' || len(ln) != 81 {
			continue
		}
		var g [81]uint8
		ok := true
		for i := 0; i < 81; i++ {
			c := ln[i]
			if c < '0' || c > '9' {
				ok = false
				break
			}
			g[i] = c - '0'
		}
		if ok {
			grids = append(grids, g)
		}
	}
	return grids
}

func writeResults(results [][81]uint8, solved []bool) {
	w := bufio.NewWriter(os.Stdout)
	var line [82]byte
	line[81] = '\n'
	for i := range results {
		if solved[i] {
			for j := 0; j < 81; j++ {
				line[j] = '0' + results[i][j]
			}
			w.Write(line[:])
		} else {
			w.WriteString("UNSOLVED\n")
		}
	}
	w.Flush()
}

func main() {
	reps := 1
	if len(os.Args) > 1 {
		if v, err := strconv.Atoi(os.Args[1]); err == nil && v > 0 {
			reps = v
		}
	}
	grids := readPuzzles()
	results := make([][81]uint8, len(grids))
	solved := make([]bool, len(grids))
	t0 := time.Now()
	for r := 0; r < reps; r++ {
		for i := range grids {
			g := grids[i] // fresh copy per repetition
			solved[i] = solve(&g)
			results[i] = g
		}
	}
	ns := time.Since(t0).Nanoseconds()
	fmt.Fprintf(os.Stderr, "ns=%d\n", ns)
	writeResults(results, solved)
}
