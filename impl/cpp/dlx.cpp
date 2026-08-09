// Knuth's Algorithm X with Dancing Links, flat-array based.
// The exact-cover matrix skeleton is built once at compile time; per
// puzzle only the mutable link arrays are copied and clue rows covered.
#include <array>
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

using Grid = std::array<std::uint8_t, 81>;

constexpr int NCOLS = 324;  // 81 cell + 81 row-digit + 81 col-digit + 81 box-digit
constexpr int NNODES = 1 + NCOLS + 729 * 4;  // root + headers + 4 nodes per row
constexpr int FIRST = NCOLS + 1;             // index of first row node

struct Skeleton {
    std::array<std::uint16_t, NNODES> col{}, rid{};        // immutable
    std::array<std::uint16_t, NNODES> l{}, r{}, u{}, d{};  // initial links
    std::array<std::uint16_t, NCOLS + 1> sz{};
};

consteval Skeleton build()
{
    Skeleton m;
    for (int h = 0; h <= NCOLS; h++) {  // 0 = root, 1..324 = column headers
        m.l[h] = static_cast<std::uint16_t>(h ? h - 1 : NCOLS);
        m.r[h] = static_cast<std::uint16_t>(h < NCOLS ? h + 1 : 0);
        m.u[h] = m.d[h] = static_cast<std::uint16_t>(h);
    }
    int n = FIRST;
    for (int cell = 0; cell < 81; cell++) {
        const int row = cell / 9, c = cell % 9;
        const int box = row / 3 * 3 + c / 3;
        for (int dig = 0; dig < 9; dig++) {  // dig = digit - 1
            const int rid = cell * 9 + dig;
            const std::array<int, 4> cols{1 + cell, 82 + row * 9 + dig,
                                          163 + c * 9 + dig, 244 + box * 9 + dig};
            for (const int cx : cols) {
                m.col[n] = static_cast<std::uint16_t>(cx);
                m.rid[n] = static_cast<std::uint16_t>(rid);
                m.d[n] = static_cast<std::uint16_t>(cx);
                m.u[n] = m.u[cx];
                m.d[m.u[cx]] = static_cast<std::uint16_t>(n);
                m.u[cx] = static_cast<std::uint16_t>(n);
                m.sz[cx]++;
                n++;
            }
            const int f = n - 4;  // link the 4 nodes of this row circularly
            m.l[f] = static_cast<std::uint16_t>(f + 3);
            m.r[f] = static_cast<std::uint16_t>(f + 1);
            m.l[f + 1] = static_cast<std::uint16_t>(f);
            m.r[f + 1] = static_cast<std::uint16_t>(f + 2);
            m.l[f + 2] = static_cast<std::uint16_t>(f + 1);
            m.r[f + 2] = static_cast<std::uint16_t>(f + 3);
            m.l[f + 3] = static_cast<std::uint16_t>(f + 2);
            m.r[f + 3] = static_cast<std::uint16_t>(f);
        }
    }
    return m;
}

constexpr Skeleton SKEL = build();

// Per-puzzle mutable state; col/rid stay in the immutable skeleton.
struct Dancer {
    std::array<std::uint16_t, NNODES> l, r, u, d;
    std::array<std::uint16_t, NCOLS + 1> sz;
    std::array<std::uint16_t, 81> sol;
    int nsol = 0;

    void reset()
    {
        l = SKEL.l;
        r = SKEL.r;
        u = SKEL.u;
        d = SKEL.d;
        sz = SKEL.sz;
        nsol = 0;
    }

    void cover(std::uint16_t c0)
    {
        r[l[c0]] = r[c0];
        l[r[c0]] = l[c0];
        for (std::uint16_t i = d[c0]; i != c0; i = d[i])
            for (std::uint16_t j = r[i]; j != i; j = r[j]) {
                d[u[j]] = d[j];
                u[d[j]] = u[j];
                sz[SKEL.col[j]]--;
            }
    }

    void uncover(std::uint16_t c0)
    {
        for (std::uint16_t i = u[c0]; i != c0; i = u[i])
            for (std::uint16_t j = l[i]; j != i; j = l[j]) {
                sz[SKEL.col[j]]++;
                d[u[j]] = j;
                u[d[j]] = j;
            }
        r[l[c0]] = c0;
        l[r[c0]] = c0;
    }

    bool search()
    {
        std::uint16_t best = r[0];
        if (!best)
            return true;
        std::uint16_t s = sz[best];
        if (s > 1) {  // Knuth's S heuristic, early out on size <= 1
            for (std::uint16_t j = r[best]; j; j = r[j]) {
                const std::uint16_t sj = sz[j];
                if (sj < s) {
                    s = sj;
                    best = j;
                    if (s < 2)
                        break;
                }
            }
        }
        cover(best);
        for (std::uint16_t i = d[best]; i != best; i = d[i]) {
            sol[nsol++] = SKEL.rid[i];
            for (std::uint16_t j = r[i]; j != i; j = r[j])
                cover(SKEL.col[j]);
            if (search())
                return true;
            for (std::uint16_t j = l[i]; j != i; j = l[j])
                uncover(SKEL.col[j]);
            nsol--;
        }
        uncover(best);
        return false;
    }
};

bool solve(const Grid& g, Grid& out, Dancer& dx)
{
    std::array<std::uint16_t, 9> rm{}, cm{}, bm{};  // cheap consistency gate
    for (int i = 0; i < 81; i++) {
        if (const int d = g[i]) {
            const int r = i / 9, c = i % 9, b = r / 3 * 3 + c / 3;
            const auto bit = static_cast<std::uint16_t>(1u << d);
            if ((rm[r] | cm[c] | bm[b]) & bit)
                return false;
            rm[r] |= bit;
            cm[c] |= bit;
            bm[b] |= bit;
        }
    }

    dx.reset();
    for (int i = 0; i < 81; i++) {  // pre-select clue rows (gate makes this safe)
        if (const int d = g[i]) {
            const auto node =
                static_cast<std::uint16_t>(FIRST + (i * 9 + d - 1) * 4);
            dx.cover(SKEL.col[node]);
            for (std::uint16_t j = dx.r[node]; j != node; j = dx.r[j])
                dx.cover(SKEL.col[j]);
        }
    }

    if (!dx.search())
        return false;
    out = g;
    for (int k = 0; k < dx.nsol; k++)
        out[dx.sol[k] / 9] = static_cast<std::uint8_t>(dx.sol[k] % 9 + 1);
    return true;
}

long parse_arg(std::string_view s)
{
    long v = 0;
    std::from_chars(s.data(), s.data() + s.size(), v);
    return v < 1 ? 1 : v;
}

std::vector<Grid> read_puzzles()
{
    std::string input;
    char buf[1 << 16];
    std::size_t got;
    while ((got = std::fread(buf, 1, sizeof buf, stdin)) > 0)
        input.append(buf, got);

    std::vector<Grid> puzzles;
    std::string_view rest{input};
    while (!rest.empty()) {
        const auto nl = rest.find('\n');
        std::string_view line = rest.substr(0, nl);
        rest.remove_prefix(nl == std::string_view::npos ? rest.size() : nl + 1);
        if (line.ends_with('\r'))
            line.remove_suffix(1);
        if (line.empty() || line.front() == '#' || line.size() != 81)
            continue;
        Grid g;
        bool ok = true;
        for (int i = 0; i < 81; i++) {
            ok &= line[i] >= '0' && line[i] <= '9';
            g[i] = static_cast<std::uint8_t>(line[i] - '0');
        }
        if (ok)
            puzzles.push_back(g);
    }
    return puzzles;
}

void write_output(std::span<const Grid> sol, std::span<const std::uint8_t> ok)
{
    std::string out;
    out.reserve(sol.size() * 82);
    for (std::size_t p = 0; p < sol.size(); p++) {
        if (ok[p]) {
            for (const std::uint8_t d : sol[p])
                out.push_back(static_cast<char>('0' + d));
            out.push_back('\n');
        } else {
            out += "UNSOLVED\n";
        }
    }
    std::fwrite(out.data(), 1, out.size(), stdout);
}

}  // namespace

int main(int argc, char** argv)
{
    const long reps = argc > 1 ? parse_arg(argv[1]) : 1;
    // threads (argv[2]) ignored: single-threaded solver

    const std::vector<Grid> puzzles = read_puzzles();
    const std::size_t n = puzzles.size();
    std::vector<Grid> sol(n);
    std::vector<std::uint8_t> ok(n, 0);
    Dancer dx;  // reused across puzzles; reset() copies the skeleton links

    const auto t0 = std::chrono::steady_clock::now();
    for (long r = 0; r < reps; r++)
        for (std::size_t p = 0; p < n; p++)
            ok[p] = solve(puzzles[p], sol[p], dx);
    const auto t1 = std::chrono::steady_clock::now();

    write_output(sol, ok);
    const auto ns =
        std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
    std::fprintf(stderr, "ns=%lld\n", static_cast<long long>(ns));
    return 0;
}
