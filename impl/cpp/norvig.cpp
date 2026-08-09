// Norvig-style constraint propagation + search (bitmask candidates).
//
// Port of impl/c/norvig.c: eliminate + naked singles + hidden singles
// to a fixpoint, then depth-first search with MRV cell choice.
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
using Cands = std::array<std::uint16_t, 81>;

constexpr std::uint16_t ALL = 0x3FE;  // bits 1..9 set

struct Tables {
    std::array<std::array<std::uint8_t, 9>, 27> units{};    // rows, cols, boxes
    std::array<std::array<std::uint8_t, 20>, 81> peers{};   // 20 peers per cell
    std::array<std::array<std::uint8_t, 3>, 81> unit_of{};  // units of each cell
};

constexpr Tables TBL = [] {
    Tables t{};
    for (int r = 0; r < 9; r++)
        for (int c = 0; c < 9; c++) {
            t.units[r][c] = static_cast<std::uint8_t>(r * 9 + c);
            t.units[9 + c][r] = static_cast<std::uint8_t>(r * 9 + c);
        }
    for (int b = 0; b < 9; b++) {
        const int br = b / 3, bc = b % 3;
        for (int k = 0; k < 9; k++)
            t.units[18 + b][k] =
                static_cast<std::uint8_t>((br * 3 + k / 3) * 9 + bc * 3 + k % 3);
    }
    for (int i = 0; i < 81; i++) {
        t.unit_of[i] = {static_cast<std::uint8_t>(i / 9),
                        static_cast<std::uint8_t>(9 + i % 9),
                        static_cast<std::uint8_t>(18 + i / 27 * 3 + i % 9 / 3)};
        std::array<bool, 81> seen{};
        seen[i] = true;
        int np = 0;
        for (const auto u : t.unit_of[i])
            for (const int j : t.units[u])
                if (!seen[j]) {
                    seen[j] = true;
                    t.peers[i][np++] = static_cast<std::uint8_t>(j);
                }
    }
    return t;
}();

bool assign(Cands& cand, int i, std::uint16_t bit);

bool eliminate(Cands& cand, int i, std::uint16_t bit)
{
    std::uint16_t c = cand[i];
    if (!(c & bit))
        return true;
    c &= static_cast<std::uint16_t>(~bit);
    if (!c)
        return false;
    cand[i] = c;
    if (!(c & (c - 1))) {  // naked single: strip from peers
        for (const int p : TBL.peers[i])
            if ((cand[p] & c) && !eliminate(cand, p, c))
                return false;
    }
    for (const auto u : TBL.unit_of[i]) {  // hidden single for `bit`?
        int place = -1;
        for (const int j : TBL.units[u]) {
            if (cand[j] & bit) {
                if (place >= 0) {
                    place = -2;
                    break;
                }
                place = j;
            }
        }
        if (place == -1)  // bit has nowhere left in unit
            return false;
        if (place >= 0) {
            const std::uint16_t pc = cand[place];
            if ((pc & (pc - 1)) && !assign(cand, place, bit))
                return false;
        }
    }
    return true;
}

bool assign(Cands& cand, int i, std::uint16_t bit)
{
    auto other = static_cast<std::uint16_t>(cand[i] & ~bit);
    while (other) {
        const auto lb = static_cast<std::uint16_t>(other & -other);
        other ^= lb;
        if (!eliminate(cand, i, lb))
            return false;
    }
    return true;
}

// On success, cand holds the solved grid (all cells single bits).
bool search(Cands& cand)
{
    int best = -1, best_n = 10;
    for (int i = 0; i < 81; i++) {  // MRV cell
        const std::uint16_t c = cand[i];
        if (c & (c - 1)) {
            const int n = std::popcount(c);
            if (n < best_n) {
                best = i;
                best_n = n;
                if (n == 2)
                    break;
            }
        }
    }
    if (best < 0)
        return true;  // all cells singles: solved
    std::uint16_t c = cand[best];
    while (c) {
        const auto bit = static_cast<std::uint16_t>(c & -c);
        c ^= bit;
        Cands trial = cand;
        if (assign(trial, best, bit) && search(trial)) {
            cand = trial;
            return true;
        }
    }
    return false;
}

bool solve(const Grid& grid, Cands& cand)
{
    cand.fill(ALL);
    for (int i = 0; i < 81; i++) {
        if (const int d = grid[i]) {
            const auto bit = static_cast<std::uint16_t>(1u << d);
            if (cand[i] != bit && !assign(cand, i, bit))
                return false;
        }
    }
    return search(cand);
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

}  // namespace

int main(int argc, char** argv)
{
    const long reps = argc > 1 ? parse_arg(argv[1]) : 1;
    // threads (argv[2]) ignored: single-threaded solver

    const std::vector<Grid> puzzles = read_puzzles();
    const std::size_t n = puzzles.size();
    std::vector<Cands> cands(n);
    std::vector<std::uint8_t> ok(n, 0);

    const auto t0 = std::chrono::steady_clock::now();
    for (long r = 0; r < reps; r++)
        for (std::size_t p = 0; p < n; p++)
            ok[p] = solve(puzzles[p], cands[p]);
    const auto t1 = std::chrono::steady_clock::now();

    std::string out;
    out.reserve(n * 82);
    for (std::size_t p = 0; p < n; p++) {
        if (ok[p]) {
            for (const std::uint16_t c : cands[p])
                out.push_back(static_cast<char>('0' + std::countr_zero(c)));
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
