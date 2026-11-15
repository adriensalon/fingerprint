#include "pipeline.hpp"
#include <algorithm>
#include <cstdio>

namespace demo {
std::size_t sample(std::span<std::uint8_t> output) {
    constexpr char message[] = "binary fingerprints compare content, structure and capabilities.\n";
    for (std::size_t i = 0; i < output.size(); ++i)
        output[i] = static_cast<std::uint8_t>(message[(i / 7) % (sizeof(message) - 1)]);
    return output.size();
}

std::uint32_t checksum(Bytes input) {
    std::uint32_t result = 2166136261u;
    for (auto byte : input) {
        result = (result ^ byte) * 16777619u;
#ifdef DEMO_VARIANT
        result ^= result >> 13;
#endif
    }
    return result;
}

std::size_t count_words(Bytes input) {
    std::size_t count = 0;
    bool inside = false;
    for (auto byte : input) {
        bool current = (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9');
        if (current && !inside) ++count;
        inside = current;
    }
    return count;
}

std::size_t count_lines(Bytes input) {
    std::size_t count = 0;
    for (auto byte : input) if (byte == '\n') ++count;
    return count + (!input.empty() && input.back() != '\n' ? 1 : 0);
}

std::size_t longest_run(Bytes input) {
    std::size_t longest = 0, current = 0;
    int previous = -1;
    for (auto byte : input) {
        current = byte == previous ? current + 1 : 1;
        longest = std::max(longest, current);
        previous = byte;
    }
    return longest;
}

void transform(std::span<std::uint8_t> input) {
    // A reversible byte transform for the demo, not an encryption algorithm.
    for (auto& byte : input) byte ^= 0x5a;
}

void describe(Bytes input) {
    std::printf("bytes=%zu words=%zu lines=%zu longest-run=%zu checksum=%08x\n",
        input.size(), count_words(input), count_lines(input), longest_run(input), checksum(input));
}
}
