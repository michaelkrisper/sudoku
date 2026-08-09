// mrv parallelized over puzzles: worker goroutines pull indices off an
// atomic counter (dynamic scheduling; puzzle difficulty is very uneven).
package main

import (
	"bufio"
	"fmt"
	"io"
	"math/bits"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const all = 0x3FE // bits 1..9 set

var boxOf [81]uint8

func init() {
	for i := 0; i < 81; i++ {
		boxOf[i] = uint8(i/27*3 + i%9/3)
	}
}

type solver struct {
	g       *[81]uint8
	rows    [9]uint16
	cols    [9]uint16
	boxes   [9]uint16
	empties [81]uint8
	n       int
}

func (s *solver) solve(g *[81]uint8) bool {
	s.g = g
	for i := 0; i < 9; i++ {
		s.rows[i], s.cols[i], s.boxes[i] = all, all, all
	}
	s.n = 0
	for i := 0; i < 81; i++ {
		d := g[i]
		if d != 0 {
			bit := uint16(1) << d
			r, c, b := i/9, i%9, boxOf[i]
			if s.rows[r]&s.cols[c]&s.boxes[b]&bit == 0 {
				return false // duplicate clue
			}
			s.rows[r] ^= bit
			s.cols[c] ^= bit
			s.boxes[b] ^= bit
		} else {
			s.empties[s.n] = uint8(i)
			s.n++
		}
	}
	return s.bt(0)
}

func (s *solver) bt(k int) bool {
	if k == s.n {
		return true
	}
	bestJ := k
	bestN := 10
	var bestCand uint16
	for j := k; j < s.n; j++ {
		i := int(s.empties[j])
		cand := s.rows[i/9] & s.cols[i%9] & s.boxes[boxOf[i]]
		nc := bits.OnesCount16(cand)
		if nc < bestN {
			if nc == 0 {
				return false // dead end
			}
			bestJ, bestN, bestCand = j, nc, cand
			if nc == 1 {
				break
			}
		}
	}
	i := int(s.empties[bestJ])
	s.empties[bestJ] = s.empties[k]
	s.empties[k] = uint8(i)
	r, c, b := i/9, i%9, boxOf[i]
	cand := bestCand
	for cand != 0 {
		bit := cand & -cand
		cand -= bit
		s.g[i] = uint8(bits.TrailingZeros16(bit))
		s.rows[r] ^= bit
		s.cols[c] ^= bit
		s.boxes[b] ^= bit
		if s.bt(k + 1) {
			return true
		}
		s.rows[r] ^= bit
		s.cols[c] ^= bit
		s.boxes[b] ^= bit
	}
	s.g[i] = 0
	return false
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
	threads := 1
	if len(os.Args) > 1 {
		if v, err := strconv.Atoi(os.Args[1]); err == nil && v > 0 {
			reps = v
		}
	}
	if len(os.Args) > 2 {
		if v, err := strconv.Atoi(os.Args[2]); err == nil && v > 0 {
			threads = v
		}
	}
	runtime.GOMAXPROCS(threads)
	grids := readPuzzles()
	n := len(grids)
	results := make([][81]uint8, n)
	solved := make([]bool, n)
	t0 := time.Now()
	for rep := 0; rep < reps; rep++ {
		if threads <= 1 {
			var s solver
			for i := range grids {
				g := grids[i] // fresh copy per repetition
				solved[i] = s.solve(&g)
				results[i] = g
			}
		} else {
			var next int64
			var wg sync.WaitGroup
			for w := 0; w < threads; w++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					var s solver
					for {
						idx := atomic.AddInt64(&next, 1) - 1
						if idx >= int64(n) {
							return
						}
						g := grids[idx] // fresh copy per repetition
						solved[idx] = s.solve(&g)
						results[idx] = g
					}
				}()
			}
			wg.Wait()
		}
	}
	ns := time.Since(t0).Nanoseconds()
	fmt.Fprintf(os.Stderr, "ns=%d\n", ns)
	writeResults(results, solved)
}
