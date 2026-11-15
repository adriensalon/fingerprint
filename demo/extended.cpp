#include "pipeline.hpp"
#include <array>
#include <cstdio>

namespace demo {
namespace {
std::size_t run_length_size(Bytes input) {
    std::size_t encoded = 0;
    for (std::size_t i = 0; i < input.size();) {
        auto start = i++;
        while (i < input.size() && input[i] == input[start] && i - start < 255) ++i;
        encoded += 2; // one count byte and one value byte
    }
    return encoded;
}
std::size_t distinct_bytes(const std::array<std::size_t, 256>& histogram) {
    std::size_t distinct = 0;
    for (auto count : histogram) if (count) ++distinct;
    return distinct;
}
std::size_t most_frequent(const std::array<std::size_t, 256>& histogram) {
    std::size_t best = 0;
    for (std::size_t i = 1; i < histogram.size(); ++i) if (histogram[i] > histogram[best]) best = i;
    return best;
}
}
void extended_analysis(Bytes input) {
    std::array<std::size_t, 256> histogram{};
    for (auto byte : input) ++histogram[byte];
    auto common = most_frequent(histogram);
    auto compressed = run_length_size(input);
    std::printf("distinct-bytes=%zu most-frequent=0x%02zx (%zu occurrences) rle-bytes=%zu ratio=%.2f\n",
        distinct_bytes(histogram), common, histogram[common], compressed,
        input.empty() ? 0.0 : static_cast<double>(compressed) / input.size());
}
}
