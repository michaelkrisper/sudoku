/* Norvig-style constraint propagation + search (bitmask candidates).
 *
 * Port of impl/python/norvig.py: eliminate + naked singles + hidden
 * singles to a fixpoint, then depth-first search with MRV cell choice.
 * Single-threaded; the `threads` argument is accepted and ignored.
 *
 * The state is kept in two mutually redundant views, which is what makes the
 * hidden-single test cheap:
 *
 *   cand[cell]      which digits may still go in this cell   (9-bit mask)
 *   places[unit][d] which positions of this unit may still hold digit d
 *
 * Norvig's formulation derives the second from the first on demand, scanning
 * nine cells per unit after every elimination. That scan is a data-dependent
 * loop with an early exit, so it mispredicts constantly. Maintaining `places`
 * incrementally costs three AND-NOTs per elimination and turns the test into
 * two branch-free predicates on a value already in a register: `places == 0`
 * is a contradiction, and a single set bit is a hidden single whose position
 * is one tzcnt away.
 */
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ALL 0x3FEu   /* digit bits 1..9 set */
#define ALLPOS 0x1FFu /* position bits 0..8 set */

static uint8_t PEERS[81][20];   /* 20 peers per cell */
static uint8_t UNITS[27 * 9];   /* 9 rows, 9 cols, 9 boxes, flattened */
static uint8_t UNIT_OF[81][3];  /* the 3 units containing each cell */
static uint8_t POS_OF[81][3];   /* this cell's index within each of them */

/* Everything eliminate() needs about one (cell, unit) pair, in one word:
 * the unit's base offset into `places` and `UNITS` in the high half, and the
 * already-inverted position bit in the low half. Without it the compiler emits
 * two byte loads, a multiply-by-nine and a variable-count shift per unit —
 * about a fifth of the function, for three constants known at startup. */
static uint32_t UPOS[81][3];
#define UBASE(w) ((w) >> 16)        /* unit * 9 */
#define UNOTBIT(w) ((uint16_t)(w))  /* ~(1 << position) */

/* One block, so a search node clones both views with a single memcpy. */
typedef struct {
    uint16_t cand[81];
    uint16_t places[27 * 9];    /* [unit * 9 + digit - 1] */
} State;

static void init_tables(void)
{
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            UNITS[r * 9 + c] = (uint8_t)(r * 9 + c);
            UNITS[(9 + c) * 9 + r] = (uint8_t)(r * 9 + c);
        }
    for (int b = 0; b < 9; b++) {
        int br = b / 3, bc = b % 3;
        for (int k = 0; k < 9; k++)
            UNITS[(18 + b) * 9 + k] =
                (uint8_t)((br * 3 + k / 3) * 9 + bc * 3 + k % 3);
    }
    for (int i = 0; i < 81; i++) {
        int r = i / 9, c = i % 9;
        UNIT_OF[i][0] = (uint8_t)r;
        UNIT_OF[i][1] = (uint8_t)(9 + c);
        UNIT_OF[i][2] = (uint8_t)(18 + (r / 3) * 3 + c / 3);
        POS_OF[i][0] = (uint8_t)c;                       /* along the row */
        POS_OF[i][1] = (uint8_t)r;                       /* down the column */
        POS_OF[i][2] = (uint8_t)((r % 3) * 3 + c % 3);   /* within the box */
        for (int t = 0; t < 3; t++)
            UPOS[i][t] = (uint32_t)(UNIT_OF[i][t] * 9) << 16
                       | (uint16_t)~(1u << POS_OF[i][t]);
        bool seen[81] = { false };
        seen[i] = true;
        int np = 0;
        for (int t = 0; t < 3; t++)
            for (int k = 0; k < 9; k++) {
                int j = UNITS[UNIT_OF[i][t] * 9 + k];
                if (!seen[j]) {
                    seen[j] = true;
                    PEERS[i][np++] = (uint8_t)j;
                }
            }
    }
}

static bool assign(State *st, int i, uint16_t bit);

static bool eliminate(State *restrict st, int i, uint16_t bit)
{
    uint16_t *restrict cand = st->cand;
    uint16_t c = cand[i];
    if (!(c & bit))
        return true;
    c &= (uint16_t)~bit;
    if (!c)
        return false;
    cand[i] = c;

    /* Digit `bit` can no longer sit at this cell's position in any of its
     * three units. Three unconditional AND-NOTs; no branches, no scan. */
    const int d = __builtin_ctz(bit) - 1;
    uint16_t *restrict pl = st->places;
    const uint32_t w0 = UPOS[i][0], w1 = UPOS[i][1], w2 = UPOS[i][2];
    pl[UBASE(w0) + d] &= UNOTBIT(w0);
    pl[UBASE(w1) + d] &= UNOTBIT(w1);
    pl[UBASE(w2) + d] &= UNOTBIT(w2);

    if (!(c & (c - 1))) {               /* naked single: strip from peers */
        for (int k = 0; k < 20; k++) {
            int p = PEERS[i][k];
            if ((cand[p] & c) && !eliminate(st, p, c))
                return false;
        }
    }

    /* Re-read: the propagation above may have narrowed these further. The
     * same scaled base indexes both `places` and `UNITS`, so recovering the
     * cell behind a hidden single costs one tzcnt and one load. */
    const uint32_t w[3] = { w0, w1, w2 };
    for (int t = 0; t < 3; t++) {
        unsigned base = UBASE(w[t]);
        uint16_t p = pl[base + d];
        if (!p)                         /* bit has nowhere left in unit */
            return false;
        if (!(p & (p - 1))) {           /* exactly one place: hidden single */
            int place = UNITS[base + __builtin_ctz(p)];
            uint16_t pc = cand[place];
            if ((pc & (pc - 1)) && !assign(st, place, bit))
                return false;
        }
    }
    return true;
}

static bool assign(State *st, int i, uint16_t bit)
{
    uint16_t other = st->cand[i] & (uint16_t)~bit;
    while (other) {
        uint16_t lb = (uint16_t)(other & -other);
        other ^= lb;
        if (!eliminate(st, i, lb))
            return false;
    }
    return true;
}

/* On success, st->cand holds the solved grid (all cells single bits). */
static bool search(State *st)
{
    const uint16_t *restrict cand = st->cand;
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
    uint16_t c = st->cand[best];
    while (c) {
        uint16_t bit = (uint16_t)(c & -c);
        c ^= bit;
        State trial = *st;
        if (assign(&trial, best, bit) && search(&trial)) {
            *st = trial;
            return true;
        }
    }
    return false;
}

static bool solve(const uint8_t *grid, State *st)
{
    for (int i = 0; i < 81; i++)
        st->cand[i] = ALL;
    for (int u = 0; u < 27 * 9; u++)
        st->places[u] = ALLPOS;
    for (int i = 0; i < 81; i++) {
        int d = grid[i];
        if (d) {
            uint16_t bit = (uint16_t)(1u << d);
            if (st->cand[i] != bit && !assign(st, i, bit))
                return false;
        }
    }
    return search(st);
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

    State *states = malloc((n ? n : 1) * sizeof *states);
    bool *ok = malloc((n ? n : 1) * sizeof *ok);
    if (!states || !ok)
        return 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (long r = 0; r < reps; r++)
        for (size_t i = 0; i < n; i++)
            ok[i] = solve(grids[i], &states[i]);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    for (size_t i = 0; i < n; i++) {
        if (ok[i]) {
            char out[82];
            for (int j = 0; j < 81; j++)
                out[j] = (char)('0' + __builtin_ctz(states[i].cand[j]));
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
    free(states);
    free(ok);
    return 0;
}
