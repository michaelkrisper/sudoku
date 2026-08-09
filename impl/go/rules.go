// Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED.
// Techniques (same set as the python reference): naked/hidden singles,
// naked/hidden pairs, pointing pairs, box-line reduction, X-Wing, Swordfish.
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
	units [27][9]uint8 // 0..8 rows, 9..17 cols, 18..26 boxes
	peers [81][20]uint8
	boxOf [81]uint8
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
		boxOf[i] = uint8(i/27*3 + i%9/3)
		var seen [81]bool
		for _, ui := range [3]int{i / 9, 9 + i%9, 18 + int(boxOf[i])} {
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

type rules struct {
	cand [81]uint16
	bad  bool // contradiction found -> UNSOLVED
}

// strip removes mask bits from cell i; contradiction if it empties the cell.
func (s *rules) strip(i int, mask uint16) bool {
	if s.cand[i]&mask != 0 {
		s.cand[i] &^= mask
		if s.cand[i] == 0 {
			s.bad = true
		}
		return true
	}
	return false
}

func (s *rules) nakedSingles(placed *[81]bool) bool {
	prog := false
	for i := 0; i < 81; i++ {
		c := s.cand[i]
		if !placed[i] && c&(c-1) == 0 {
			placed[i] = true
			prog = true
			ps := &peers[i]
			for _, p := range ps {
				s.strip(int(p), c)
			}
		}
	}
	return prog
}

func (s *rules) hiddenSingles() bool {
	prog := false
	for ui := range units {
		u := &units[ui]
		for d := 1; d <= 9; d++ {
			bit := uint16(1) << d
			cnt, last := 0, 0
			for _, i := range u {
				if s.cand[i]&bit != 0 {
					cnt++
					last = int(i)
				}
			}
			if cnt == 0 {
				s.bad = true
				return prog
			}
			if cnt == 1 && s.cand[last] != bit {
				s.cand[last] = bit
				prog = true
			}
		}
	}
	return prog
}

func (s *rules) nakedPairs() bool {
	prog := false
	for ui := range units {
		u := &units[ui]
		for a := 0; a < 8; a++ {
			m := s.cand[u[a]]
			if bits.OnesCount16(m) != 2 {
				continue
			}
			for b := a + 1; b < 9; b++ {
				if s.cand[u[b]] == m {
					for k := 0; k < 9; k++ {
						if k != a && k != b && s.strip(int(u[k]), m) {
							prog = true
						}
					}
				}
			}
		}
	}
	return prog
}

func (s *rules) hiddenPairs() bool {
	prog := false
	for ui := range units {
		u := &units[ui]
		var pos [10]uint16 // positions (0..8 within unit) holding digit d
		var cnt [10]int
		for d := 1; d <= 9; d++ {
			for k, i := range u {
				if s.cand[i]&(1<<d) != 0 {
					pos[d] |= 1 << k
					cnt[d]++
				}
			}
		}
		for x := 1; x <= 8; x++ {
			if cnt[x] != 2 {
				continue
			}
			for y := x + 1; y <= 9; y++ {
				if cnt[y] != 2 || pos[y] != pos[x] {
					continue
				}
				mask := uint16(1<<x | 1<<y)
				pm := pos[x]
				for pm != 0 {
					k := bits.TrailingZeros16(pm)
					pm &= pm - 1
					i := int(u[k])
					if s.cand[i]&^mask != 0 {
						s.cand[i] &= mask
						if s.cand[i] == 0 {
							s.bad = true
						}
						prog = true
					}
				}
			}
		}
	}
	return prog
}

func (s *rules) pointingAndBoxline() bool {
	prog := false
	for b := 0; b < 9; b++ { // pointing pairs/triples
		box := &units[18+b]
		for d := 1; d <= 9; d++ {
			bit := uint16(1) << d
			var places [9]uint8
			np := 0
			for _, i := range box {
				if s.cand[i]&bit != 0 {
					places[np] = i
					np++
				}
			}
			if np < 2 || np > 3 {
				continue
			}
			r0, c0 := places[0]/9, places[0]%9
			sameRow, sameCol := true, true
			for k := 1; k < np; k++ {
				if places[k]/9 != r0 {
					sameRow = false
				}
				if places[k]%9 != c0 {
					sameCol = false
				}
			}
			if sameRow { // box -> row
				for _, i := range units[r0] {
					if int(boxOf[i]) != b && s.strip(int(i), bit) {
						prog = true
					}
				}
			} else if sameCol { // box -> col
				for _, i := range units[9+c0] {
					if int(boxOf[i]) != b && s.strip(int(i), bit) {
						prog = true
					}
				}
			}
		}
	}
	for li := 0; li < 18; li++ { // box-line reduction (rows, then cols)
		line := &units[li]
		for d := 1; d <= 9; d++ {
			bit := uint16(1) << d
			theBox := -1
			multi := false
			for _, i := range line {
				if s.cand[i]&bit != 0 {
					b := int(boxOf[i])
					if theBox < 0 {
						theBox = b
					} else if theBox != b {
						multi = true
						break
					}
				}
			}
			if theBox < 0 || multi {
				continue
			}
			for _, i := range units[18+theBox] {
				inLine := false
				if li < 9 {
					inLine = int(i)/9 == li
				} else {
					inLine = int(i)%9 == li-9
				}
				if !inLine && s.strip(int(i), bit) {
					prog = true
				}
			}
		}
	}
	return prog
}

// fish covers X-Wing (size 2) and Swordfish (size 3), rows and columns as base.
func (s *rules) fish(size int) bool {
	prog := false
	for pass := 0; pass < 2; pass++ { // 0: rows base, 1: cols base
		for d := 1; d <= 9; d++ {
			bit := uint16(1) << d
			var baseLi [9]int
			var basePs [9]uint16 // cross-coordinates holding d in that line
			nb := 0
			for li := 0; li < 9; li++ {
				var ps uint16
				for k := 0; k < 9; k++ {
					i := li*9 + k
					if pass == 1 {
						i = k*9 + li
					}
					if s.cand[i]&bit != 0 {
						ps |= 1 << k
					}
				}
				if pc := bits.OnesCount16(ps); pc >= 2 && pc <= size {
					baseLi[nb], basePs[nb] = li, ps
					nb++
				}
			}
			if size == 2 {
				for a := 0; a < nb; a++ {
					for b := a + 1; b < nb; b++ {
						if s.fishApply(pass, bit, basePs[a]|basePs[b],
							1<<baseLi[a]|1<<baseLi[b], size) {
							prog = true
						}
					}
				}
			} else {
				for a := 0; a < nb; a++ {
					for b := a + 1; b < nb; b++ {
						for c := b + 1; c < nb; c++ {
							if s.fishApply(pass, bit, basePs[a]|basePs[b]|basePs[c],
								1<<baseLi[a]|1<<baseLi[b]|1<<baseLi[c], size) {
								prog = true
							}
						}
					}
				}
			}
		}
	}
	return prog
}

func (s *rules) fishApply(pass int, bit, union, keep uint16, size int) bool {
	if bits.OnesCount16(union) != size {
		return false
	}
	prog := false
	for um := union; um != 0; um &= um - 1 {
		cc := bits.TrailingZeros16(um)
		for k := 0; k < 9; k++ {
			if keep&(1<<k) != 0 {
				continue
			}
			i := k*9 + cc // rows base: eliminate along the column
			if pass == 1 {
				i = cc*9 + k // cols base: eliminate along the row
			}
			if s.strip(i, bit) {
				prog = true
			}
		}
	}
	return prog
}

func (s *rules) solve(g *[81]uint8) bool {
	s.bad = false
	for i := 0; i < 81; i++ {
		if g[i] != 0 {
			s.cand[i] = 1 << g[i]
		} else {
			s.cand[i] = all
		}
	}
	var placed [81]bool
	for !s.bad { // cheapest technique first
		if s.nakedSingles(&placed) {
			continue
		}
		if s.hiddenSingles() {
			continue
		}
		if s.nakedPairs() {
			continue
		}
		if s.hiddenPairs() {
			continue
		}
		if s.pointingAndBoxline() {
			continue
		}
		if s.fish(2) {
			continue
		}
		if s.fish(3) {
			continue
		}
		break
	}
	if s.bad {
		return false
	}
	for i := 0; i < 81; i++ {
		if bits.OnesCount16(s.cand[i]) != 1 {
			return false
		}
	}
	for ui := range units { // must be a valid full grid
		var m uint16
		for _, i := range units[ui] {
			m |= s.cand[i]
		}
		if m != all {
			return false
		}
	}
	for i := 0; i < 81; i++ {
		g[i] = uint8(bits.Len16(s.cand[i]) - 1)
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
	var s rules
	t0 := time.Now()
	for r := 0; r < reps; r++ {
		for i := range grids {
			g := grids[i] // fresh copy per repetition
			solved[i] = s.solve(&g)
			results[i] = g
		}
	}
	ns := time.Since(t0).Nanoseconds()
	fmt.Fprintf(os.Stderr, "ns=%d\n", ns)
	writeResults(results, solved)
}
