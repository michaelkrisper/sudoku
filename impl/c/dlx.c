/* Knuth's Algorithm X with Dancing Links, flat-array based. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NCOLS 324                    /* 81 cell + 81 row-digit + 81 col-digit + 81 box-digit */
#define NNODES (1 + NCOLS + 729 * 4) /* root + headers + 4 nodes per candidate row */
#define FIRST (NCOLS + 1)            /* index of first row node */

/* immutable after build() */
static uint16_t C0[NNODES], RID[NNODES];
static uint16_t L0[NNODES], R0[NNODES], U0[NNODES], D0[NNODES];
static uint16_t SZ0[NCOLS + 1];

/* per-puzzle working copies */
static uint16_t L[NNODES], R[NNODES], U[NNODES], D[NNODES];
static uint16_t SZ[NCOLS + 1];

static uint16_t sol[81];
static int nsol;

static void build(void) {
    for (int h = 0; h <= NCOLS; h++) { /* 0 = root, 1..324 = column headers */
        L0[h] = (uint16_t)(h ? h - 1 : NCOLS);
        R0[h] = (uint16_t)(h < NCOLS ? h + 1 : 0);
        U0[h] = D0[h] = (uint16_t)h;
    }
    int n = FIRST;
    for (int cell = 0; cell < 81; cell++) {
        int r = cell / 9, c = cell % 9;
        int b = r / 3 * 3 + c / 3;
        for (int d = 0; d < 9; d++) { /* d = digit - 1 */
            int rid = cell * 9 + d;
            int cols[4] = {1 + cell, 82 + r * 9 + d, 163 + c * 9 + d,
                           244 + b * 9 + d};
            for (int k = 0; k < 4; k++, n++) {
                int col = cols[k];
                C0[n] = (uint16_t)col;
                RID[n] = (uint16_t)rid;
                D0[n] = (uint16_t)col;
                U0[n] = U0[col];
                D0[U0[col]] = (uint16_t)n;
                U0[col] = (uint16_t)n;
                SZ0[col]++;
            }
            int f = n - 4; /* link the 4 nodes of this row circularly */
            L0[f] = (uint16_t)(f + 3); R0[f] = (uint16_t)(f + 1);
            L0[f + 1] = (uint16_t)f; R0[f + 1] = (uint16_t)(f + 2);
            L0[f + 2] = (uint16_t)(f + 1); R0[f + 2] = (uint16_t)(f + 3);
            L0[f + 3] = (uint16_t)(f + 2); R0[f + 3] = (uint16_t)f;
        }
    }
}

static inline void cover(uint16_t c0) {
    R[L[c0]] = R[c0];
    L[R[c0]] = L[c0];
    for (uint16_t i = D[c0]; i != c0; i = D[i])
        for (uint16_t j = R[i]; j != i; j = R[j]) {
            D[U[j]] = D[j];
            U[D[j]] = U[j];
            SZ[C0[j]]--;
        }
}

static inline void uncover(uint16_t c0) {
    for (uint16_t i = U[c0]; i != c0; i = U[i])
        for (uint16_t j = L[i]; j != i; j = L[j]) {
            SZ[C0[j]]++;
            D[U[j]] = j;
            U[D[j]] = j;
        }
    R[L[c0]] = c0;
    L[R[c0]] = c0;
}

static int search(void) {
    uint16_t best = R[0];
    if (!best)
        return 1;
    uint16_t s = SZ[best];
    if (s > 1) { /* Knuth's S heuristic, early out on size <= 1 */
        for (uint16_t j = R[best]; j; j = R[j]) {
            uint16_t sj = SZ[j];
            if (sj < s) {
                s = sj;
                best = j;
                if (s < 2)
                    break;
            }
        }
    }
    cover(best);
    for (uint16_t i = D[best]; i != best; i = D[i]) {
        sol[nsol++] = RID[i];
        for (uint16_t j = R[i]; j != i; j = R[j])
            cover(C0[j]);
        if (search())
            return 1;
        for (uint16_t j = L[i]; j != i; j = L[j])
            uncover(C0[j]);
        nsol--;
    }
    uncover(best);
    return 0;
}

static int solve(const uint8_t *g, uint8_t *out) {
    uint16_t rm[9] = {0}, cm[9] = {0}, bm[9] = {0}; /* cheap consistency gate */
    for (int i = 0; i < 81; i++) {
        int d = g[i];
        if (d) {
            int r = i / 9, c = i % 9;
            int b = r / 3 * 3 + c / 3;
            uint16_t bit = (uint16_t)(1u << d);
            if ((rm[r] | cm[c] | bm[b]) & bit)
                return 0;
            rm[r] |= bit;
            cm[c] |= bit;
            bm[b] |= bit;
        }
    }

    /* fresh copies of the mutable arrays; C0 and RID are never modified */
    memcpy(L, L0, sizeof L);
    memcpy(R, R0, sizeof R);
    memcpy(U, U0, sizeof U);
    memcpy(D, D0, sizeof D);
    memcpy(SZ, SZ0, sizeof SZ);
    nsol = 0;

    for (int i = 0; i < 81; i++) { /* pre-select clue rows (gate makes this safe) */
        int d = g[i];
        if (d) {
            uint16_t node = (uint16_t)(FIRST + (i * 9 + d - 1) * 4);
            cover(C0[node]);
            for (uint16_t j = R[node]; j != node; j = R[j])
                cover(C0[j]);
        }
    }

    if (!search())
        return 0;
    memcpy(out, g, 81);
    for (int k = 0; k < nsol; k++)
        out[sol[k] / 9] = (uint8_t)(sol[k] % 9 + 1);
    return 1;
}

int main(int argc, char **argv) {
    long reps = argc > 1 ? atol(argv[1]) : 1;
    if (reps < 1)
        reps = 1;
    /* argv[2] (threads) ignored: single-threaded solver */

    build();

    uint8_t (*puzzles)[81] = NULL;
    size_t npuz = 0, cap = 0;
    char *line = NULL;
    size_t lcap = 0;
    ssize_t len;
    while ((len = getline(&line, &lcap, stdin)) != -1) {
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (len == 0 || line[0] == '#')
            continue;
        if (npuz == cap) {
            cap = cap ? cap * 2 : 64;
            puzzles = realloc(puzzles, cap * sizeof *puzzles);
            if (!puzzles)
                return 0; /* contract: never non-zero exit */
        }
        int ok = len == 81;
        for (int i = 0; ok && i < 81; i++)
            ok = line[i] >= '0' && line[i] <= '9';
        if (ok)
            for (int i = 0; i < 81; i++)
                puzzles[npuz][i] = (uint8_t)(line[i] - '0');
        else
            memset(puzzles[npuz], 10, 81); /* malformed line -> UNSOLVED */
        npuz++;
    }
    free(line);

    uint8_t (*sols)[81] = malloc(npuz ? npuz * sizeof *sols : 1);
    uint8_t *solved = calloc(npuz ? npuz : 1, 1);
    if (!sols || !solved)
        return 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (long rep = 0; rep < reps; rep++)
        for (size_t p = 0; p < npuz; p++)
            solved[p] = puzzles[p][0] <= 9 &&
                        (uint8_t)solve(puzzles[p], sols[p]);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL +
                   (t1.tv_nsec - t0.tv_nsec);

    for (size_t p = 0; p < npuz; p++) {
        if (solved[p]) {
            char buf[82];
            for (int i = 0; i < 81; i++)
                buf[i] = (char)('0' + sols[p][i]);
            buf[81] = '\0';
            puts(buf);
        } else {
            puts("UNSOLVED");
        }
    }
    fprintf(stderr, "ns=%lld\n", ns);
    free(puzzles);
    free(sols);
    free(solved);
    return 0;
}
