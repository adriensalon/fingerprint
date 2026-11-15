#include <array>
#include <cstdio>
#include <limits>

namespace {
constexpr std::size_t cities = 8;
using Matrix = std::array<std::array<int, cities>, cities>;
constexpr Matrix roads{{
    {{0, 4, 0, 0, 0, 0, 0, 8}}, {{4, 0, 8, 0, 0, 0, 0, 11}},
    {{0, 8, 0, 7, 0, 4, 2, 0}}, {{0, 0, 7, 0, 9, 14, 0, 0}},
    {{0, 0, 0, 9, 0, 10, 0, 0}}, {{0, 0, 4, 14, 10, 0, 2, 0}},
    {{0, 0, 2, 0, 0, 2, 0, 1}}, {{8, 11, 0, 0, 0, 0, 1, 0}}
}};
struct Routes {
    std::array<int, cities> distance;
    std::array<int, cities> previous;
};
Routes shortest_paths(std::size_t source) {
    constexpr int infinity = std::numeric_limits<int>::max();
    Routes result;
    result.distance.fill(infinity);
    result.previous.fill(-1);
    result.distance[source] = 0;
    std::array<bool, cities> visited{};
    for (std::size_t step = 0; step < cities; ++step) {
        auto nearest = cities;
        for (std::size_t i = 0; i < cities; ++i)
            if (!visited[i] && (nearest == cities || result.distance[i] < result.distance[nearest])) nearest = i;
        if (nearest == cities || result.distance[nearest] == infinity) break;
        visited[nearest] = true;
        for (std::size_t next = 0; next < cities; ++next) {
            auto cost = roads[nearest][next];
            if (cost && !visited[next] && result.distance[nearest] + cost < result.distance[next]) {
                result.distance[next] = result.distance[nearest] + cost;
                result.previous[next] = static_cast<int>(nearest);
            }
        }
    }
    return result;
}
void print_path(const Routes& routes, int destination) {
    if (routes.previous[destination] >= 0) {
        print_path(routes, routes.previous[destination]);
        std::printf(" -> ");
    }
    std::printf("%c", 'A' + destination);
}
}
int main(int argc, char** argv) {
    if (argc > 2 || (argc == 2 && (argv[1][0] < 'A' || argv[1][0] > 'H' || argv[1][1] != '\0'))) {
        std::fprintf(stderr, "Usage: %s [source-city A-H]\n", argv[0]);
        return 2;
    }
    auto source = argc == 2 ? static_cast<std::size_t>(argv[1][0] - 'A') : 0;
    auto routes = shortest_paths(source);
    for (std::size_t destination = 0; destination < cities; ++destination) {
        std::printf("%c to %c: distance=%d route=", static_cast<int>('A' + source), static_cast<int>('A' + destination), routes.distance[destination]);
        print_path(routes, static_cast<int>(destination));
        std::printf("\n");
    }
    return 0;
}
