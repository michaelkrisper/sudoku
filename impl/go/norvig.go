// Norvig-style constraint propagation + search (bitmask candidates).
package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"
	"os"
	"strconv"
	"strings"
	"time"
)

const all = 0x3FE // bits 1..9 set

var (
	units   [27][9]uint8 // 0..8 rows, 9..17 cols, 18..26 boxes
	unitsOf [81][3]uint8 // row, col, box unit index per cell
	peers   [81][20]uint8
)

func init() {
	for r := 0; r < 9; r++ {
		for c := 0; c < 9; c++ {
			units[r][c] = uint8(r*9 + c)
			units[9+c][r] = uint8(r*9 + c)
		}
	}
	for b := 0; b < 9; b++ {
		br, bc := b/3, b%3
		for k := 0; k < 9; k++ {
			units[18+b][k] = uint8((br*3+k/3)*9 + bc*3 + k%3)
		}
	}
	for i := 0; i < 81; i++ {
		unitsOf[i] = [3]uint8{uint8(i / 9), uint8(9 + i%9), uint8(18 + i/27*3 + i%9/3)}
		var seen [81]bool
		for _, ui := range unitsOf[i] {
			for _, j := range units[ui] {
				seen[j] = true
			}
		}
		seen[i] = false
		k := 0
		for j := 0; j < 81; j++ {
			if seen[j] {
				peers[i][k] = uint8(j)
				k++
			}
		}
	}
}

func eliminate(cand *[81]uint16, i int, bit uint16) bool {
	c := cand[i]
	if c&bit == 0 {
		return true
	}
	c &^= bit
	if c == 0 {
		return false
	}
	cand[i] = c
	if c&(c-1) == 0 { // naked single: strip from peers
		ps := &peers[i]
		for _, p := range ps {
			if cand[p]&c != 0 && !eliminate(cand, int(p), c) {
				return false
			}
		}
	}
	for _, ui := range unitsOf[i] { // hidden single for `bit`?
		u := &units[ui]
		place := -1
		for _, j := range u {
			if cand[j]&bit != 0 {
				if place >= 0 {
					place = -2
					break
				}
				place = int(j)
			}
		}
		if place == -1 { // bit has nowhere left in unit
			return false
		}
		if place >= 0 {
			pc := cand[place]
			if pc&(pc-1) != 0 && !assign(cand, place, bit) {
				return false
			}
		}
	}
	return true
}

func assign(cand *[81]uint16, i int, bit uint16) bool {
	other := cand[i] &^ bit
	for other != 0 {
		lb := other & -other
		other ^= lb
		if !eliminate(cand, i, lb) {
			return false
		}
	}
	return true
}

func search(cand *[81]uint16) bool {
	best := -1
	bestN := 10
	for i := 0; i < 81; i++ { // MRV cell
		c := cand[i]
		if c&(c-1) != 0 {
			n := bits.OnesCount16(c)
			if n < bestN {
				best, bestN = i, n
				if n == 2 {
					break
				}
			}
		}
	}
	if best < 0 {
		return true // all cells singles: solved
	}
	c := cand[best]
	for c != 0 {
		bit := c & -c
		c ^= bit
		trial := *cand // fresh copy per branch
		if assign(&trial, best, bit) && search(&trial) {
			*cand = trial
			return true
		}
	}
	return false
}

func solve(g *[81]uint8) bool {
	var cand [81]uint16
	for i := range cand {
		cand[i] = all
	}
	for i := 0; i < 81; i++ {
		d := g[i]
		if d != 0 {
			bit := uint16(1) << d
			if cand[i] != bit && !assign(&cand, i, bit) {
				return false
			}
		}
	}
	if !search(&cand) {
		return false
	}
	for i := 0; i < 81; i++ {
		g[i] = uint8(bits.Len16(cand[i]) - 1)
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
