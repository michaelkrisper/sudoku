// Pure rule-based solver (no guessing). Unsolvable-by-logic -> UNSOLVED.
//
// Mirrors impl/c/rules.c exactly: naked singles, hidden singles, naked
// pairs, hidden pairs, pointing pairs/triples, box-line reduction,
// X-Wing, Swordfish -- applied to a fixpoint, cheapest technique first.
#include <array>
#include <bit>
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

constexpr std::uint16_t ALL = 0x3FE;  // bits 1..9 set

struct Tables {
    std::array<std::array<std::uint8_t, 9>, 27> units{};  // 9 rows, 9 cols, 9 boxes
    std::array<std::array<std::uint8_t, 20>, 81> peers{};
    std::array<std::uint8_t, 81> box_of{};
};

constexpr Tables TBL = [] {
    Tables t{};
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            const int i = r * 9 + c;
            t.units[r][c] = static_cast<std::uint8_t>(i);
            t.units[9 + c][r] = static_cast<std::uint8_t>(i);
            t.box_of[i] = static_cast<std::uint8_t>(r / 3 * 3 + c / 3);
        }
    for (int b = 0; b < 9; b++)
        for (int k = 0; k < 9; k++)
            t.units[18 + b][k] = static_cast<std::uint8_t>(
                (b / 3 * 3 + k / 3) * 9 + b % 3 * 3 + k % 3);
    for (int i = 0; i < 81; i++) {
        int n = 0;
        for (int j = 0; j < 81; j++)
            if (j != i && (j / 9 == i / 9 || j % 9 == i % 9 ||
                           t.box_of[j] == t.box_of[i]))
                t.peers[i][n++] = static_cast<std::uint8_t>(j);
    }
    return t;
}();

struct RulesSolver {
    std::array<std::uint16_t, 81> cand{};
    bool bad = false;  // contradiction flag

    // Remove mask bits from cell i; contradiction if it empties the cell.
    bool strip(int i, std::uint16_t mask)
    {
        if (cand[i] & mask) {
            cand[i] &= static_cast<std::uint16_t>(~mask);
            if (cand[i] == 0)
                bad = true;
            return true;
        }
        return false;
    }

    bool naked_singles(std::array<std::uint8_t, 81>& placed)
    {
        bool prog = false;
        for (int i = 0; i < 81; i++) {
            const std::uint16_t c = cand[i];
            if (!placed[i] && std::popcount(c) == 1) {
                placed[i] = 1;
                prog = true;
                for (const int p : TBL.peers[i]) {
                    strip(p, c);
                    if (bad)
                        return prog;
                }
            }
        }
        return prog;
    }

    bool hidden_singles()
    {
        bool prog = false;
        for (int u = 0; u < 27; u++)
            for (int d = 1; d <= 9; d++) {
                const auto bit = static_cast<std::uint16_t>(1u << d);
                int cnt = 0, last = 0;
                for (const int i : TBL.units[u]) {
                    if (cand[i] & bit) {
                        cnt++;
                        last = i;
                    }
                }
                if (cnt == 0) {
                    bad = true;
                    return prog;
                }
                if (cnt == 1 && cand[last] != bit) {
                    cand[last] = bit;
                    prog = true;
                }
            }
        return prog;
    }

    bool naked_pairs()
    {
        bool prog = false;
        for (int u = 0; u < 27; u++)
            for (int a = 0; a < 9; a++)
                for (int b = a + 1; b < 9; b++) {
                    const std::uint16_t m = cand[TBL.units[u][a]];
                    if (std::popcount(m) == 2 && cand[TBL.units[u][b]] == m)
                        for (int k = 0; k < 9; k++)
                            if (k != a && k != b) {
                                prog |= strip(TBL.units[u][k], m);
                                if (bad)
                                    return prog;
                            }
                }
        return prog;
    }

    bool hidden_pairs()
    {
        bool prog = false;
        for (int u = 0; u < 27; u++) {
            std::array<std::uint16_t, 10> pos{};  // bitmask over unit positions
            std::array<int, 9> two{};
            int n = 0;
            for (int d = 1; d <= 9; d++) {
                std::uint16_t p = 0;
                for (int k = 0; k < 9; k++)
                    if (cand[TBL.units[u][k]] & (1u << d))
                        p |= static_cast<std::uint16_t>(1u << k);
                pos[d] = p;
                if (std::popcount(p) == 2)
                    two[n++] = d;
            }
            for (int x = 0; x < n; x++)
                for (int y = x + 1; y < n; y++)
                    if (pos[two[x]] == pos[two[y]]) {
                        const auto mask = static_cast<std::uint16_t>(
                            (1u << two[x]) | (1u << two[y]));
                        for (int k = 0; k < 9; k++)
                            if (pos[two[x]] & (1u << k)) {
                                const int i = TBL.units[u][k];
                                if (cand[i] & static_cast<std::uint16_t>(~mask)) {
                                    cand[i] &= mask;
                                    if (cand[i] == 0) {
                                        bad = true;
                                        return prog;
                                    }
                                    prog = true;
                                }
                            }
                    }
        }
        return prog;
    }

    bool pointing_and_boxline()
    {
        bool prog = false;
        for (int b = 0; b < 9; b++)  // pointing pairs/triples
            for (int d = 1; d <= 9; d++) {
                const auto bit = static_cast<std::uint16_t>(1u << d);
                std::array<int, 9> places{};
                int np = 0;
                for (const int i : TBL.units[18 + b])
                    if (cand[i] & bit)
                        places[np++] = i;
                if (np < 2 || np > 3)
                    continue;
                bool samer = true, samec = true;
                for (int j = 1; j < np; j++) {
                    if (places[j] / 9 != places[0] / 9)
                        samer = false;
                    if (places[j] % 9 != places[0] % 9)
                        samec = false;
                }
                if (samer) {  // box -> row
                    for (int c = 0; c < 9; c++) {
                        const int i = places[0] / 9 * 9 + c;
                        if (TBL.box_of[i] != b) {
                            prog |= strip(i, bit);
                            if (bad)
                                return prog;
                        }
                    }
                } else if (samec) {  // box -> col
                    for (int r = 0; r < 9; r++) {
                        const int i = r * 9 + places[0] % 9;
                        if (TBL.box_of[i] != b) {
                            prog |= strip(i, bit);
                            if (bad)
                                return prog;
                        }
                    }
                }
            }
        for (int axis = 0; axis < 2; axis++)  // box-line reduction
            for (int l = 0; l < 9; l++)
                for (int d = 1; d <= 9; d++) {
                    const auto bit = static_cast<std::uint16_t>(1u << d);
                    std::uint16_t boxes = 0;
                    for (const int i : TBL.units[axis * 9 + l])
                        if (cand[i] & bit)
                            boxes |= static_cast<std::uint16_t>(1u << TBL.box_of[i]);
                    if (std::popcount(boxes) != 1)
                        continue;
                    const int bx = std::countr_zero(boxes);
                    for (const int i : TBL.units[18 + bx]) {
                        const bool in_line = axis == 0 ? i / 9 == l : i % 9 == l;
                        if (!in_line) {
                            prog |= strip(i, bit);
                            if (bad)
                                return prog;
                        }
                    }
                }
        return prog;
    }

    // Eliminate digit from the cross lines of a confirmed fish pattern.
    bool fish_eliminate(int axis, std::uint16_t un, std::uint16_t keep,
                        std::uint16_t bit)
    {
        bool prog = false;
        for (int cc = 0; cc < 9; cc++) {
            if (!(un & (1u << cc)))
                continue;
            for (int lc = 0; lc < 9; lc++) {
                if (keep & (1u << lc))
                    continue;
                const int i = axis == 0 ? lc * 9 + cc : cc * 9 + lc;
                prog |= strip(i, bit);
                if (bad)
                    return prog;
            }
        }
        return prog;
    }

    // X-Wing (size 2) / Swordfish (size 3), rows and columns as base.
    bool fish(int size)
    {
        bool prog = false;
        for (int axis = 0; axis < 2; axis++)  // 0: rows base, 1: cols base
            for (int d = 1; d <= 9; d++) {
                const auto bit = static_cast<std::uint16_t>(1u << d);
                std::array<int, 9> bl{};
                std::array<std::uint16_t, 9> bm{};
                int nb = 0;
                for (int li = 0; li < 9; li++) {
                    std::uint16_t ps = 0;
                    for (int k = 0; k < 9; k++) {
                        const int i = axis == 0 ? li * 9 + k : k * 9 + li;
                        if (cand[i] & bit)
                            ps |= static_cast<std::uint16_t>(1u << k);
                    }
                    const int cnt = std::popcount(ps);
                    if (cnt >= 2 && cnt <= size) {
                        bl[nb] = li;
                        bm[nb] = ps;
                        nb++;
                    }
                }
                if (size == 2) {
                    for (int a = 0; a < nb; a++)
                        for (int b = a + 1; b < nb; b++) {
                            const auto un =
                                static_cast<std::uint16_t>(bm[a] | bm[b]);
                            if (std::popcount(un) != 2)
                                continue;
                            const auto keep = static_cast<std::uint16_t>(
                                (1u << bl[a]) | (1u << bl[b]));
                            prog |= fish_eliminate(axis, un, keep, bit);
                            if (bad)
                                return prog;
                        }
                } else {
                    for (int a = 0; a < nb; a++)
                        for (int b = a + 1; b < nb; b++)
                            for (int c = b + 1; c < nb; c++) {
                                const auto un = static_cast<std::uint16_t>(
                                    bm[a] | bm[b] | bm[c]);
                                if (std::popcount(un) != 3)
                                    continue;
                                const auto keep = static_cast<std::uint16_t>(
                                    (1u << bl[a]) | (1u << bl[b]) | (1u << bl[c]));
                                prog |= fish_eliminate(axis, un, keep, bit);
                                if (bad)
                                    return prog;
                            }
                }
            }
        return prog;
    }

    // Returns true and writes 81 digits to out on success, false = UNSOLVED.
    bool solve(const Grid& grid, char* out)
    {
        std::array<std::uint8_t, 81> placed{};
        bad = false;
        for (int i = 0; i < 81; i++)
            cand[i] = grid[i] ? static_cast<std::uint16_t>(1u << grid[i]) : ALL;
        for (;;) {  // cheapest technique first
            if (naked_singles(placed)) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (hidden_singles()) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (naked_pairs()) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (hidden_pairs()) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (pointing_and_boxline()) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (fish(2)) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            if (fish(3)) {
                if (bad)
                    return false;
                continue;
            }
            if (bad)
                return false;
            break;
        }
        for (const std::uint16_t c : cand)
            if (std::popcount(c) != 1)
                return false;
        for (int u = 0; u < 27; u++) {  // must be a valid full grid
            std::uint16_t m = 0;
            for (const int k : TBL.units[u])
                m |= cand[k];
            if (m != ALL)
                return false;
        }
        for (int i = 0; i < 81; i++)
            out[i] = static_cast<char>('0' + std::countr_zero(cand[i]));
        return true;
    }
};

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

}  // namespace

int main(int argc, char** argv)
{
    const long reps = argc > 1 ? parse_arg(argv[1]) : 1;
    // threads (argv[2]) ignored: single-threaded solver

    const std::vector<Grid> puzzles = read_puzzles();
    const std::size_t n = puzzles.size();
    std::vector<std::array<char, 81>> sol(n);
    std::vector<std::uint8_t> ok(n, 0);
    RulesSolver rs;

    const auto t0 = std::chrono::steady_clock::now();
    for (long r = 0; r < reps; r++)
        for (std::size_t p = 0; p < n; p++)
            ok[p] = rs.solve(puzzles[p], sol[p].data());
    const auto t1 = std::chrono::steady_clock::now();

    std::string out;
    out.reserve(n * 82);
    for (std::size_t p = 0; p < n; p++) {
        if (ok[p]) {
            out.append(sol[p].data(), 81);
            out.push_back('\n');
        } else {
            out += "UNSOLVED\n";
        }
    }
    std::fwrite(out.data(), 1, out.size(), stdout);

    const auto ns =
        std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
    std::fprintf(stderr, "ns=%lld\n", static_cast<long long>(ns));
    return 0;
}
