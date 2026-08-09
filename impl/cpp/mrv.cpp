// Backtracking with bitmask candidates and most-constrained-cell order.
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

constexpr auto make_table(auto f)
{
    std::array<std::uint8_t, 81> t{};
    for (int i = 0; i < 81; i++)
        t[i] = static_cast<std::uint8_t>(f(i));
    return t;
}
constexpr auto ROW = make_table([](int i) { return i / 9; });
constexpr auto COL = make_table([](int i) { return i % 9; });
constexpr auto BOX = make_table([](int i) { return i / 27 * 3 + i % 9 / 3; });

struct Solver {
    std::array<std::uint16_t, 9> rows{}, cols{}, boxes{};
    std::array<std::uint8_t, 81> empties{};
    std::uint8_t* g = nullptr;
    int n = 0;

    bool bt(int k)
    {
        if (k == n)
            return true;
        int best_j = k, best_n = 10;
        std::uint16_t best_cand = 0;
        for (int j = k; j < n; j++) {
            const int i = empties[j];
            const auto cand = static_cast<std::uint16_t>(
                rows[ROW[i]] & cols[COL[i]] & boxes[BOX[i]]);
            const int nc = std::popcount(cand);
            if (nc < best_n) {
                if (nc == 0)
                    return false;  // dead end
                best_j = j;
                best_n = nc;
                best_cand = cand;
                if (nc == 1)
                    break;
            }
        }
        const int i = empties[best_j];
        empties[best_j] = empties[k];
        empties[k] = static_cast<std::uint8_t>(i);
        const int r = ROW[i], c = COL[i], b = BOX[i];
        std::uint16_t cand = best_cand;
        while (cand) {
            const auto bit = static_cast<std::uint16_t>(cand & -cand);
            cand ^= bit;
            g[i] = static_cast<std::uint8_t>(std::countr_zero(bit));
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
            if (bt(k + 1))
                return true;
            rows[r] ^= bit; cols[c] ^= bit; boxes[b] ^= bit;
        }
        g[i] = 0;
        return false;
    }
};

bool solve(Grid& g)
{
    Solver s;
    s.rows.fill(ALL);
    s.cols.fill(ALL);
    s.boxes.fill(ALL);
    s.g = g.data();
    for (int i = 0; i < 81; i++) {
        if (const int d = g[i]) {
            const auto bit = static_cast<std::uint16_t>(1u << d);
            const int r = ROW[i], c = COL[i], b = BOX[i];
            if (!(s.rows[r] & s.cols[c] & s.boxes[b] & bit))
                return false;  // duplicate clue
            s.rows[r] ^= bit; s.cols[c] ^= bit; s.boxes[b] ^= bit;
        } else {
            s.empties[s.n++] = static_cast<std::uint8_t>(i);
        }
    }
    return s.bt(0);
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

    const auto t0 = std::chrono::steady_clock::now();
    for (long r = 0; r < reps; r++) {
        for (std::size_t p = 0; p < n; p++) {
            Grid g = puzzles[p];  // fresh copy each repetition
            ok[p] = solve(g);
            sol[p] = g;
        }
    }
    const auto t1 = std::chrono::steady_clock::now();

    write_output(sol, ok);
    const auto ns =
        std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
    std::fprintf(stderr, "ns=%lld\n", static_cast<long long>(ns));
    return 0;
}
