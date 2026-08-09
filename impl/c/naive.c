/* Naive backtracking: first empty cell, digits 1-9 in order. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int valid(const uint8_t *g, int pos, uint8_t d)
{
    int rs = pos - pos % 9;
    int c = pos % 9;
    int bs = pos / 27 * 27 + pos % 9 / 3 * 3;
    for (int i = 0; i < 9; i++)
        if (g[rs + i] == d || g[c + 9 * i] == d)
            return 0;
    for (int r = 0; r < 3; r++)
        for (int i = 0; i < 3; i++)
            if (g[bs + 9 * r + i] == d)
                return 0;
    return 1;
}

static int bt(uint8_t *g, int start)
{
    int pos = start;
    while (pos < 81 && g[pos])
        pos++;
    if (pos == 81)
        return 1;
    for (uint8_t d = 1; d <= 9; d++) {
        if (valid(g, pos, d)) {
            g[pos] = d;
            if (bt(g, pos + 1))
                return 1;
        }
    }
    g[pos] = 0;
    return 0;
}

static int solve(uint8_t *g)
{
    for (int i = 0; i < 81; i++) {   /* reject inconsistent clues */
        uint8_t d = g[i];
        if (d) {
            g[i] = 0;
            int ok = valid(g, i, d);
            g[i] = d;
            if (!ok)
                return 0;
        }
    }
    return bt(g, 0);
}

int main(int argc, char **argv)
{
    long reps = argc > 1 ? atol(argv[1]) : 1;

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
