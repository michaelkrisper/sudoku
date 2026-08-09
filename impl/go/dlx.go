// Knuth's Algorithm X with Dancing Links, flat-array based.
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

const (
	ncols  = 324             // 81 cell + 81 row-digit + 81 col-digit + 81 box-digit
	nnodes = 1 + ncols + 729*4 // root + headers + 4 nodes per candidate row
	first  = ncols + 1       // index of first row node
)

// Immutable matrix, built once at startup. cIdx and rowID are never modified;
// l0/r0/u0/d0/sz0 are the pristine link arrays copied per puzzle.
var (
	l0, r0, u0, d0 [nnodes]int32
	cIdx, rowID    [nnodes]int32
	sz0            [ncols + 1]int32
)

func init() {
	for h := int32(0); h <= ncols; h++ { // 0 = root, 1..324 = column headers
		if h == 0 {
			l0[h] = ncols
		} else {
			l0[h] = h - 1
		}
		if h < ncols {
			r0[h] = h + 1
		} else {
			r0[h] = 0
		}
		u0[h], d0[h] = h, h
	}
	n := int32(first)
	for cell := int32(0); cell < 81; cell++ {
		r, c := cell/9, cell%9
		b := r/3*3 + c/3
		for d := int32(0); d < 9; d++ { // d = digit - 1
			rid := cell*9 + d
			for _, col := range [4]int32{1 + cell, 82 + r*9 + d, 163 + c*9 + d, 244 + b*9 + d} {
				cIdx[n] = col
				rowID[n] = rid
				d0[n] = col
				u0[n] = u0[col]
				d0[u0[col]] = n
				u0[col] = n
				sz0[col]++
				n++
			}
			f := n - 4 // link the 4 nodes of this row circularly
			l0[f], r0[f] = f+3, f+1
			l0[f+1], r0[f+1] = f, f+2
			l0[f+2], r0[f+2] = f+1, f+3
			l0[f+3], r0[f+3] = f+2, f
		}
	}
}

type dlx struct {
	l, r, u, d [nnodes]int32
	sz         [ncols + 1]int32
	sol        [81]int32
	ns         int
}

func (x *dlx) cover(c0 int32) {
	x.r[x.l[c0]] = x.r[c0]
	x.l[x.r[c0]] = x.l[c0]
	for i := x.d[c0]; i != c0; i = x.d[i] {
		for j := x.r[i]; j != i; j = x.r[j] {
			x.d[x.u[j]] = x.d[j]
			x.u[x.d[j]] = x.u[j]
			x.sz[cIdx[j]]--
		}
	}
}

func (x *dlx) uncover(c0 int32) {
	for i := x.u[c0]; i != c0; i = x.u[i] {
		for j := x.l[i]; j != i; j = x.l[j] {
			x.sz[cIdx[j]]++
			x.d[x.u[j]] = j
			x.u[x.d[j]] = j
		}
	}
	x.r[x.l[c0]] = c0
	x.l[x.r[c0]] = c0
}

func (x *dlx) search() bool {
	best := x.r[0]
	if best == 0 {
		return true
	}
	s := x.sz[best]
	if s > 1 { // Knuth's S heuristic, early out on size <= 1
		for j := x.r[best]; j != 0; j = x.r[j] {
			if sj := x.sz[j]; sj < s {
				s, best = sj, j
				if s < 2 {
					break
				}
			}
		}
	}
	x.cover(best)
	for i := x.d[best]; i != best; i = x.d[i] {
		x.sol[x.ns] = rowID[i]
		x.ns++
		for j := x.r[i]; j != i; j = x.r[j] {
			x.cover(cIdx[j])
		}
		if x.search() {
			return true
		}
		for j := x.l[i]; j != i; j = x.l[j] {
			x.uncover(cIdx[j])
		}
		x.ns--
	}
	x.uncover(best)
	return false
}

func (x *dlx) solve(g *[81]uint8) bool {
	var rm, cm, bm [9]uint16 // cheap consistency gate
	for i := 0; i < 81; i++ {
		d := g[i]
		if d != 0 {
			r, c := i/9, i%9
			b := r/3*3 + c/3
			bit := uint16(1) << d
			if (rm[r]|cm[c]|bm[b])&bit != 0 {
				return false
			}
			rm[r] |= bit
			cm[c] |= bit
			bm[b] |= bit
		}
	}

	// fresh copies of the mutable arrays; cIdx and rowID stay shared
	x.l, x.r, x.u, x.d = l0, r0, u0, d0
	x.sz = sz0
	x.ns = 0

	for i := 0; i < 81; i++ { // pre-select clue rows (gate makes this safe)
		d := g[i]
		if d != 0 {
			node := int32(first) + (int32(i)*9+int32(d)-1)*4
			x.cover(cIdx[node])
			for j := x.r[node]; j != node; j = x.r[j] {
				x.cover(cIdx[j])
			}
		}
	}

	if !x.search() {
		return false
	}
	for k := 0; k < x.ns; k++ {
		rid := x.sol[k]
		g[rid/9] = uint8(rid%9) + 1
	}
	return true
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
	x := new(dlx)
	t0 := time.Now()
	for r := 0; r < reps; r++ {
		for i := range grids {
			g := grids[i] // fresh copy per repetition
			solved[i] = x.solve(&g)
			results[i] = g
		}
	}
	ns := time.Since(t0).Nanoseconds()
	fmt.Fprintf(os.Stderr, "ns=%d\n", ns)
	writeResults(results, solved)
}
