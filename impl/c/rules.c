/* Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED.
 *
 * Mirrors impl/python/rules.py exactly: naked singles, hidden singles,
 * naked pairs, hidden pairs, pointing pairs/triples, box-line reduction,
 * X-Wing, Swordfish -- applied to a fixpoint, cheapest technique first.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ALL 0x3FEu

static uint8_t UNITS[27][9];   /* 9 rows, 9 cols, 9 boxes */
static uint8_t PEERS[81][20];
static uint8_t BOX_OF[81];

static void init_tables(void)
{
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            int i = r * 9 + c;
            UNITS[r][c] = (uint8_t)i;
            UNITS[9 + c][r] = (uint8_t)i;
            BOX_OF[i] = (uint8_t)(r / 3 * 3 + c / 3);
        }
    for (int b = 0; b < 9; b++)
        for (int k = 0; k < 9; k++)
            UNITS[18 + b][k] =
                (uint8_t)((b / 3 * 3 + k / 3) * 9 + b % 3 * 3 + k % 3);
    for (int i = 0; i < 81; i++) {
        int n = 0;
        for (int j = 0; j < 81; j++)
            if (j != i && (j / 9 == i / 9 || j % 9 == i % 9 ||
                           BOX_OF[j] == BOX_OF[i]))
                PEERS[i][n++] = (uint8_t)j;
    }
}

/* Solver state (single-threaded). */
static uint16_t cand[81];
static int bad; /* contradiction flag, equivalent to raising in python */

/* Remove mask bits from cell i; contradiction if it empties the cell. */
static inline int strip(int i, uint16_t mask)
{
    if (cand[i] & mask) {
        cand[i] &= (uint16_t)~mask;
        if (cand[i] == 0)
            bad = 1;
        return 1;
    }
    return 0;
}

static int naked_singles(uint8_t *placed)
{
    int prog = 0;
    for (int i = 0; i < 81; i++) {
        uint16_t c = cand[i];
        if (!placed[i] && __builtin_popcount(c) == 1) {
            placed[i] = 1;
            prog = 1;
            for (int k = 0; k < 20; k++) {
                strip(PEERS[i][k], c);
                if (bad)
                    return prog;
            }
        }
    }
    return prog;
}

static int hidden_singles(void)
{
    int prog = 0;
    for (int u = 0; u < 27; u++)
        for (int d = 1; d <= 9; d++) {
            uint16_t bit = (uint16_t)(1u << d);
            int cnt = 0, last = 0;
            for (int k = 0; k < 9; k++) {
                int i = UNITS[u][k];
                if (cand[i] & bit) {
                    cnt++;
                    last = i;
                }
            }
            if (cnt == 0) {
                bad = 1;
                return prog;
            }
            if (cnt == 1 && cand[last] != bit) {
                cand[last] = bit;
                prog = 1;
            }
        }
    return prog;
}

static int naked_pairs(void)
{
    int prog = 0;
    for (int u = 0; u < 27; u++)
        for (int a = 0; a < 9; a++)
            for (int b = a + 1; b < 9; b++) {
                uint16_t m = cand[UNITS[u][a]];
                if (__builtin_popcount(m) == 2 && cand[UNITS[u][b]] == m)
                    for (int k = 0; k < 9; k++)
                        if (k != a && k != b) {
                            prog |= strip(UNITS[u][k], m);
                            if (bad)
                                return prog;
                        }
            }
    return prog;
}

static int hidden_pairs(void)
{
    int prog = 0;
    for (int u = 0; u < 27; u++) {
        uint16_t pos[10]; /* bitmask over the 9 unit positions */
        int two[9], n = 0;
        for (int d = 1; d <= 9; d++) {
            uint16_t p = 0;
            for (int k = 0; k < 9; k++)
                if (cand[UNITS[u][k]] & (1u << d))
                    p |= (uint16_t)(1u << k);
            pos[d] = p;
            if (__builtin_popcount(p) == 2)
                two[n++] = d;
        }
        for (int x = 0; x < n; x++)
            for (int y = x + 1; y < n; y++)
                if (pos[two[x]] == pos[two[y]]) {
                    uint16_t mask =
                        (uint16_t)((1u << two[x]) | (1u << two[y]));
                    for (int k = 0; k < 9; k++)
                        if (pos[two[x]] & (1u << k)) {
                            int i = UNITS[u][k];
                            if (cand[i] & (uint16_t)~mask) {
                                cand[i] &= mask;
                                if (cand[i] == 0) {
                                    bad = 1;
                                    return prog;
                                }
                                prog = 1;
                            }
                        }
                }
    }
    return prog;
}

static int pointing_and_boxline(void)
{
    int prog = 0;
    for (int b = 0; b < 9; b++) /* pointing pairs/triples */
        for (int d = 1; d <= 9; d++) {
            uint16_t bit = (uint16_t)(1u << d);
            int places[9], np = 0;
            for (int k = 0; k < 9; k++) {
                int i = UNITS[18 + b][k];
                if (cand[i] & bit)
                    places[np++] = i;
            }
            if (np < 2 || np > 3)
                continue;
            int samer = 1, samec = 1;
            for (int j = 1; j < np; j++) {
                if (places[j] / 9 != places[0] / 9)
                    samer = 0;
                if (places[j] % 9 != places[0] % 9)
                    samec = 0;
            }
            if (samer) { /* box -> row */
                for (int c = 0; c < 9; c++) {
                    int i = places[0] / 9 * 9 + c;
                    if (BOX_OF[i] != b) {
                        prog |= strip(i, bit);
                        if (bad)
                            return prog;
                    }
                }
            } else if (samec) { /* box -> col */
                for (int r = 0; r < 9; r++) {
                    int i = r * 9 + places[0] % 9;
                    if (BOX_OF[i] != b) {
                        prog |= strip(i, bit);
                        if (bad)
                            return prog;
                    }
                }
            }
        }
    for (int axis = 0; axis < 2; axis++) /* box-line reduction */
        for (int l = 0; l < 9; l++)
            for (int d = 1; d <= 9; d++) {
                uint16_t bit = (uint16_t)(1u << d);
                uint16_t boxes = 0;
                for (int k = 0; k < 9; k++) {
                    int i = UNITS[axis * 9 + l][k];
                    if (cand[i] & bit)
                        boxes |= (uint16_t)(1u << BOX_OF[i]);
                }
                if (__builtin_popcount(boxes) != 1)
                    continue;
                int bx = __builtin_ctz(boxes);
                for (int k = 0; k < 9; k++) {
                    int i = UNITS[18 + bx][k];
                    int inline_ = axis == 0 ? i / 9 == l : i % 9 == l;
                    if (!inline_) {
                        prog |= strip(i, bit);
                        if (bad)
                            return prog;
                    }
                }
            }
    return prog;
}

/* Eliminate digit from the cross lines of a confirmed fish pattern. */
static int fish_eliminate(int axis, uint16_t un, uint16_t keep, uint16_t bit)
{
    int prog = 0;
    for (int cc = 0; cc < 9; cc++) {
        if (!(un & (1u << cc)))
            continue;
        for (int lc = 0; lc < 9; lc++) {
            if (keep & (1u << lc))
                continue;
            int i = axis == 0 ? lc * 9 + cc : cc * 9 + lc;
            prog |= strip(i, bit);
            if (bad)
                return prog;
        }
    }
    return prog;
}

/* X-Wing (size 2) / Swordfish (size 3), rows and columns as base. */
static int fish(int size)
{
    int prog = 0;
    for (int axis = 0; axis < 2; axis++) /* 0: rows base, 1: cols base */
        for (int d = 1; d <= 9; d++) {
            uint16_t bit = (uint16_t)(1u << d);
            int bl[9];
            uint16_t bm[9];
            int nb = 0;
            for (int li = 0; li < 9; li++) {
                uint16_t ps = 0;
                for (int k = 0; k < 9; k++) {
                    int i = axis == 0 ? li * 9 + k : k * 9 + li;
                    if (cand[i] & bit)
                        ps |= (uint16_t)(1u << k);
                }
                int cnt = __builtin_popcount(ps);
                if (cnt >= 2 && cnt <= size) {
                    bl[nb] = li;
                    bm[nb] = ps;
                    nb++;
                }
            }
            if (size == 2) {
                for (int a = 0; a < nb; a++)
                    for (int b = a + 1; b < nb; b++) {
                        uint16_t un = bm[a] | bm[b];
                        if (__builtin_popcount(un) != 2)
                            continue;
                        uint16_t keep =
                            (uint16_t)((1u << bl[a]) | (1u << bl[b]));
                        prog |= fish_eliminate(axis, un, keep, bit);
                        if (bad)
                            return prog;
                    }
            } else {
                for (int a = 0; a < nb; a++)
                    for (int b = a + 1; b < nb; b++)
                        for (int c = b + 1; c < nb; c++) {
                            uint16_t un = bm[a] | bm[b] | bm[c];
                            if (__builtin_popcount(un) != 3)
                                continue;
                            uint16_t keep = (uint16_t)((1u << bl[a]) |
                                                       (1u << bl[b]) |
                                                       (1u << bl[c]));
                            prog |= fish_eliminate(axis, un, keep, bit);
                            if (bad)
                                return prog;
                        }
            }
        }
    return prog;
}

/* Returns 1 and writes 81 digits to out on success, 0 for UNSOLVED. */
static int solve(const uint8_t *grid, char *out)
{
    uint8_t placed[81] = {0};
    bad = 0;
    for (int i = 0; i < 81; i++)
        cand[i] = grid[i] ? (uint16_t)(1u << grid[i]) : ALL;
    for (;;) { /* cheapest technique first */
        if (naked_singles(placed)) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (hidden_singles()) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (naked_pairs()) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (hidden_pairs()) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (pointing_and_boxline()) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (fish(2)) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        if (fish(3)) {
            if (bad)
                return 0;
            continue;
        }
        if (bad)
            return 0;
        break;
    }
    for (int i = 0; i < 81; i++)
        if (__builtin_popcount(cand[i]) != 1)
            return 0;
    for (int u = 0; u < 27; u++) { /* must be a valid full grid */
        uint16_t m = 0;
        for (int k = 0; k < 9; k++)
            m |= cand[UNITS[u][k]];
        if (m != ALL)
            return 0;
    }
    for (int i = 0; i < 81; i++)
        out[i] = (char)('0' + __builtin_ctz(cand[i]));
    return 1;
}

int main(int argc, char **argv)
{
    int reps = argc > 1 ? atoi(argv[1]) : 1;
    if (reps < 1)
        reps = 1;
    /* threads (argv[2]) ignored: single-threaded solver */
    init_tables();

    size_t n = 0, cap = 256;
    uint8_t *grids = malloc(cap * 81);
    if (!grids)
        return 0;
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        size_t len = strcspn(line, "\r\n");
        if (len == 0 || line[0] == '#')
            continue;
        if (len != 81)
            continue;
        int ok = 1;
        for (size_t k = 0; k < 81; k++)
            if (line[k] < '0' || line[k] > '9')
                ok = 0;
        if (!ok)
            continue;
        if (n == cap) {
            cap *= 2;
            uint8_t *g = realloc(grids, cap * 81);
            if (!g)
                return 0;
            grids = g;
        }
        for (size_t k = 0; k < 81; k++)
            grids[n * 81 + k] = (uint8_t)(line[k] - '0');
        n++;
    }

    char *sols = malloc(n ? n * 81 : 1);
    uint8_t *solved = malloc(n ? n : 1);
    if (!sols || !solved)
        return 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int r = 0; r < reps; r++)
        for (size_t p = 0; p < n; p++)
            solved[p] = (uint8_t)solve(grids + p * 81, sols + p * 81);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL +
                   (t1.tv_nsec - t0.tv_nsec);

    for (size_t p = 0; p < n; p++) {
        if (solved[p]) {
            fwrite(sols + p * 81, 1, 81, stdout);
            fputc('\n', stdout);
        } else {
            fputs("UNSOLVED\n", stdout);
        }
    }
    fprintf(stderr, "ns=%lld\n", ns);
    return 0;
}
