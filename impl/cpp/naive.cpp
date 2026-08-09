// Naive backtracking: first empty cell, digits 1-9 in order.
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

bool valid(const Grid& g, int pos, std::uint8_t d)
{
    const int rs = pos - pos % 9;
    const int c = pos % 9;
    const int bs = pos / 27 * 27 + pos % 9 / 3 * 3;
    for (int i = 0; i < 9; i++)
        if (g[rs + i] == d || g[c + 9 * i] == d)
            return false;
    for (int r = 0; r < 3; r++)
        for (int i = 0; i < 3; i++)
            if (g[bs + 9 * r + i] == d)
                return false;
    return true;
}

bool bt(Grid& g, int start)
{
    int pos = start;
    while (pos < 81 && g[pos])
        pos++;
    if (pos == 81)
        return true;
    for (std::uint8_t d = 1; d <= 9; d++) {
        if (valid(g, pos, d)) {
            g[pos] = d;
            if (bt(g, pos + 1))
                return true;
        }
    }
    g[pos] = 0;
    return false;
}

bool solve(Grid& g)
{
    for (int i = 0; i < 81; i++) {  // reject inconsistent clues
        const std::uint8_t d = g[i];
        if (d) {
            g[i] = 0;
            const bool ok = valid(g, i, d);
            g[i] = d;
            if (!ok)
                return false;
        }
    }
    return bt(g, 0);
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
