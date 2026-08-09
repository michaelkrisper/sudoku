/* Backtracking with bitmask candidates and most-constrained-cell order. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ALL 0x3FE /* bits 1..9 set */

static uint8_t ROW[81], COL[81], BOX[81];

typedef struct {
    uint16_t rows[9], cols[9], boxes[9];
    uint8_t empties[81];
    uint8_t *g;
    int n;
} Solver;

static int bt(Solver *restrict s, int k)
{
    if (k == s->n)
        return 1;
    uint8_t *restrict e = s->empties;
    uint16_t *restrict rows = s->rows;
    uint16_t *restrict cols = s->cols;
    uint16_t *restrict boxes = s->boxes;

    int best_j = k, best_n = 10;
    uint16_t best_cand = 0;
    for (int j = k; j < s->n; j++) {
        int i = e[j];
        uint16_t cand = rows[ROW[i]] & cols[COL[i]] & boxes[BOX[i]];
        int nc = __builtin_popcount(cand);
        if (nc < best_n) {
            if (nc == 0)
                return 0; /* dead end */
            best_j = j;
            best_n = nc;
            best_cand = cand;
            if (nc == 1)
                break;
        }
    }
    int i = e[best_j];
    e[best_j] = e[k];
    e[k] = (uint8_t)i;
    int r = ROW[i], c = COL[i], b = BOX[i];
    uint16_t cand = best_cand;
    while (cand) {
        uint16_t bit = (uint16_t)(cand & -cand);
        cand ^= bit;
        s->g[i] = (uint8_t)__builtin_ctz(bit);
        rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
        if (bt(s, k + 1))
            return 1;
        rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
    }
    s->g[i] = 0;
    return 0;
}

static int solve(uint8_t *restrict g)
{
    Solver s;
    for (int j = 0; j < 9; j++) {
        s.rows[j] = ALL;
        s.cols[j] = ALL;
        s.boxes[j] = ALL;
    }
    s.g = g;
    s.n = 0;
    for (int i = 0; i < 81; i++) {
        int d = g[i];
        if (d) {
            uint16_t bit = (uint16_t)(1u << d);
            int r = ROW[i], c = COL[i], b = BOX[i];
            if (!(s.rows[r] & s.cols[c] & s.boxes[b] & bit))
                return 0; /* duplicate clue */
            s.rows[r] ^= bit; s.cols[c] ^= bit; s.boxes[b] ^= bit;
        } else {
            s.empties[s.n++] = (uint8_t)i;
        }
    }
    return bt(&s, 0);
}

int main(int argc, char **argv)
{
    long reps = argc > 1 ? atol(argv[1]) : 1;

    for (int i = 0; i < 81; i++) {
        ROW[i] = (uint8_t)(i / 9);
        COL[i] = (uint8_t)(i % 9);
        BOX[i] = (uint8_t)(i / 27 * 3 + i % 9 / 3);
    }

    uint8_t (*puzzles)[81] = NULL;
    size_t n = 0, cap = 0;
    char *line = NULL;
    size_t len = 0;
    ssize_t got;
    while ((got = getline(&line, &len, stdin)) != -1) {
        while (got > 0 && (line[got - 1] == '\n' || line[got - 1] == '\r'))
            line[--got] = '\0';
        if (got != 81 || line[0] == '#')
            continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 64;
            puzzles = realloc(puzzles, cap * sizeof *puzzles);
        }
        for (int i = 0; i < 81; i++)
            puzzles[n][i] = (uint8_t)(line[i] - '0');
        n++;
    }
    free(line);

    uint8_t (*sol)[81] = malloc((n ? n : 1) * sizeof *sol);
    uint8_t *ok = calloc(n ? n : 1, 1);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (long r = 0; r < reps; r++) {
        for (size_t p = 0; p < n; p++) {
            uint8_t g[81];
            memcpy(g, puzzles[p], 81);
            ok[p] = (uint8_t)solve(g);
            memcpy(sol[p], g, 81);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL
                 + (t1.tv_nsec - t0.tv_nsec);

    char out[82];
    out[81] = '\n';
    for (size_t p = 0; p < n; p++) {
        if (ok[p]) {
            for (int i = 0; i < 81; i++)
                out[i] = (char)('0' + sol[p][i]);
            fwrite(out, 1, 82, stdout);
        } else {
            fputs("UNSOLVED\n", stdout);
        }
    }
    fprintf(stderr, "ns=%lld\n", ns);

    free(puzzles);
    free(sol);
    free(ok);
    return 0;
}
