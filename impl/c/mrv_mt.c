/* mrv parallelized over puzzles: worker threads pull (rep, puzzle) tasks
 * off a shared atomic counter (dynamic scheduling; puzzle cost varies). */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdatomic.h>
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

static uint8_t (*g_puzzles)[81];
static uint8_t (*g_sol)[81];
static uint8_t *g_ok;
static size_t g_npuz;
static size_t g_total;    /* reps * npuz */
static size_t g_lastrep;  /* first task index of the final repetition */
static atomic_size_t g_next;

static void *worker(void *arg)
{
    (void)arg;
    for (;;) {
        size_t t = atomic_fetch_add_explicit(&g_next, 1,
                                             memory_order_relaxed);
        if (t >= g_total)
            break;
        size_t p = t % g_npuz;
        uint8_t g[81];
        memcpy(g, g_puzzles[p], 81);
        int ok = solve(g);
        if (t >= g_lastrep) { /* every result index written exactly once */
            g_ok[p] = (uint8_t)ok;
            memcpy(g_sol[p], g, 81);
        }
    }
    return NULL;
}

int main(int argc, char **argv)
{
    long reps = argc > 1 ? atol(argv[1]) : 1;
    long threads = argc > 2 ? atol(argv[2]) : 1;
    if (reps < 1)
        reps = 1;
    if (threads < 1)
        threads = 1;

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

    g_puzzles = puzzles;
    g_sol = malloc((n ? n : 1) * sizeof *g_sol);
    g_ok = calloc(n ? n : 1, 1);
    g_npuz = n;
    g_total = (size_t)reps * n;
    g_lastrep = g_total - n;
    atomic_store(&g_next, 0);

    /* main thread works too; threads are created once for all reps */
    pthread_t *tid = malloc((size_t)(threads - 1) * sizeof *tid + 1);
    long spawned = 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (long i = 0; i < threads - 1; i++) {
        if (pthread_create(&tid[spawned], NULL, worker, NULL) != 0)
            break; /* main thread still drains the queue */
        spawned++;
    }
    worker(NULL);
    for (long i = 0; i < spawned; i++)
        pthread_join(tid[i], NULL);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long long ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL
                 + (t1.tv_nsec - t0.tv_nsec);

    char out[82];
    out[81] = '\n';
    for (size_t p = 0; p < n; p++) {
        if (g_ok[p]) {
            for (int i = 0; i < 81; i++)
                out[i] = (char)('0' + g_sol[p][i]);
            fwrite(out, 1, 82, stdout);
        } else {
            fputs("UNSOLVED\n", stdout);
        }
    }
    fprintf(stderr, "ns=%lld\n", ns);

    free(tid);
    free(puzzles);
    free(g_sol);
    free(g_ok);
    return 0;
}
