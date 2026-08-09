/* Norvig-style constraint propagation + search (bitmask candidates).
 *
 * Port of impl/python/norvig.py: eliminate + naked singles + hidden
 * singles to a fixpoint, then depth-first search with MRV cell choice.
 * Single-threaded; the `threads` argument is accepted and ignored.
 */
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ALL 0x3FEu /* bits 1..9 set */

static uint8_t PEERS[81][20];   /* 20 peers per cell */
static uint8_t UNITS[27][9];    /* 9 rows, 9 cols, 9 boxes */
static uint8_t UNIT_OF[81][3];  /* the 3 units containing each cell */

static void init_tables(void)
{
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            UNITS[r][c] = (uint8_t)(r * 9 + c);
            UNITS[9 + c][r] = (uint8_t)(r * 9 + c);
        }
    for (int b = 0; b < 9; b++) {
        int br = b / 3, bc = b % 3;
        for (int k = 0; k < 9; k++)
            UNITS[18 + b][k] =
                (uint8_t)((br * 3 + k / 3) * 9 + bc * 3 + k % 3);
    }
    for (int i = 0; i < 81; i++) {
        UNIT_OF[i][0] = (uint8_t)(i / 9);
        UNIT_OF[i][1] = (uint8_t)(9 + i % 9);
        UNIT_OF[i][2] = (uint8_t)(18 + (i / 27) * 3 + (i % 9) / 3);
        bool seen[81] = { false };
        seen[i] = true;
        int np = 0;
        for (int t = 0; t < 3; t++)
            for (int k = 0; k < 9; k++) {
                int j = UNITS[UNIT_OF[i][t]][k];
                if (!seen[j]) {
                    seen[j] = true;
                    PEERS[i][np++] = (uint8_t)j;
                }
            }
    }
}

static bool assign(uint16_t *cand, int i, uint16_t bit);

static bool eliminate(uint16_t *cand, int i, uint16_t bit)
{
    uint16_t c = cand[i];
    if (!(c & bit))
        return true;
    c &= (uint16_t)~bit;
    if (!c)
        return false;
    cand[i] = c;
    if (!(c & (c - 1))) {               /* naked single: strip from peers */
        for (int k = 0; k < 20; k++) {
            int p = PEERS[i][k];
            if ((cand[p] & c) && !eliminate(cand, p, c))
                return false;
        }
    }
    for (int t = 0; t < 3; t++) {       /* hidden single for `bit`? */
        const uint8_t *u = UNITS[UNIT_OF[i][t]];
        int place = -1;
        for (int k = 0; k < 9; k++) {
            if (cand[u[k]] & bit) {
                if (place >= 0) {
                    place = -2;
                    break;
                }
                place = u[k];
            }
        }
        if (place == -1)                /* bit has nowhere left in unit */
            return false;
        if (place >= 0) {
            uint16_t pc = cand[place];
            if ((pc & (pc - 1)) && !assign(cand, place, bit))
                return false;
        }
    }
    return true;
}

static bool assign(uint16_t *cand, int i, uint16_t bit)
{
    uint16_t other = cand[i] & (uint16_t)~bit;
    while (other) {
        uint16_t lb = (uint16_t)(other & -other);
        other ^= lb;
        if (!eliminate(cand, i, lb))
            return false;
    }
    return true;
}

/* On success, cand holds the solved grid (all cells single bits). */
static bool search(uint16_t *cand)
{
    int best = -1, best_n = 10;
    for (int i = 0; i < 81; i++) {      /* MRV cell */
        uint16_t c = cand[i];
        if (c & (c - 1)) {
            int n = __builtin_popcount(c);
            if (n < best_n) {
                best = i;
                best_n = n;
                if (n == 2)
                    break;
            }
        }
    }
    if (best < 0)
        return true;                    /* all cells singles: solved */
    uint16_t c = cand[best];
    while (c) {
        uint16_t bit = (uint16_t)(c & -c);
        c ^= bit;
        uint16_t trial[81];
        memcpy(trial, cand, sizeof trial);
        if (assign(trial, best, bit) && search(trial)) {
            memcpy(cand, trial, sizeof trial);
            return true;
        }
    }
    return false;
}

static bool solve(const uint8_t *grid, uint16_t *cand)
{
    for (int i = 0; i < 81; i++)
        cand[i] = ALL;
    for (int i = 0; i < 81; i++) {
        int d = grid[i];
        if (d) {
            uint16_t bit = (uint16_t)(1u << d);
            if (cand[i] != bit && !assign(cand, i, bit))
                return false;
        }
    }
    return search(cand);
}

int main(int argc, char **argv)
{
    long reps = 1;
    if (argc > 1) {
        reps = strtol(argv[1], NULL, 10);
        if (reps < 1)
            reps = 1;
    }
    /* argv[2] (threads) intentionally ignored: single-threaded solver */

    init_tables();

    size_t n = 0, cap = 0;
    uint8_t (*grids)[81] = NULL;
    char *line = NULL;
    size_t linecap = 0;
    ssize_t len;
    while ((len = getline(&line, &linecap, stdin)) != -1) {
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (len == 0 || line[0] == '#')
            continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 256;
            grids = realloc(grids, cap * sizeof *grids);
            if (!grids)
                return 0;
        }
        bool valid = (len == 81);
        for (int i = 0; valid && i < 81; i++)
            valid = (line[i] >= '0' && line[i] <= '9');
        if (valid) {
            for (int i = 0; i < 81; i++)
                grids[n][i] = (uint8_t)(line[i] - '0');
        } else {
            memset(grids[n], 10, 81);   /* impossible clue -> UNSOLVED */
        }
        n++;
    }
    free(line);

    uint16_t (*cands)[81] = malloc((n ? n : 1) * sizeof *cands);
    bool *ok = malloc((n ? n : 1) * sizeof *ok);
    if (!cands || !ok)
        return 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (long r = 0; r < reps; r++)
        for (size_t i = 0; i < n; i++)
            ok[i] = solve(grids[i], cands[i]);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    for (size_t i = 0; i < n; i++) {
        if (ok[i]) {
            char out[82];
            for (int j = 0; j < 81; j++)
                out[j] = (char)('0' + __builtin_ctz(cands[i][j]));
            out[81] = '\0';
            puts(out);
        } else {
            puts("UNSOLVED");
        }
    }

    uint64_t ns = (uint64_t)(t1.tv_sec - t0.tv_sec) * 1000000000u
                + (uint64_t)(t1.tv_nsec - t0.tv_nsec);
    fprintf(stderr, "ns=%" PRIu64 "\n", ns);
    free(grids);
    free(cands);
    free(ok);
    return 0;
}
