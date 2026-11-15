#pragma once
#include <cstddef>
#include <cstdint>
#include <span>

namespace demo {
using Bytes = std::span<const std::uint8_t>;
std::size_t sample(std::span<std::uint8_t> output);
std::uint32_t checksum(Bytes input);
std::size_t count_words(Bytes input);
std::size_t count_lines(Bytes input);
std::size_t longest_run(Bytes input);
void transform(std::span<std::uint8_t> input);
void describe(Bytes input);
void extended_analysis(Bytes input);
}
