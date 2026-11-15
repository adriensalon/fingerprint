#include "pipeline.hpp"
#include <array>
#include <cstdio>

int main(int argc, char** argv) {
    if (argc > 3) {
        std::fprintf(stderr, "Usage: %s [input-file [transformed-output]]\n", argv[0]);
        return 2;
    }
    std::array<std::uint8_t, 65536> buffer{};
    auto size = demo::sample(std::span(buffer).first(4096));
    if (argc >= 2) {
        auto* file = std::fopen(argv[1], "rb");
        if (!file) { std::perror(argv[1]); return 1; }
        size = std::fread(buffer.data(), 1, buffer.size(), file);
        bool failed = std::ferror(file) != 0;
        bool too_large = !failed && std::fgetc(file) != EOF;
        std::fclose(file);
        if (failed || too_large) { std::fprintf(stderr, "Cannot read input (maximum 65536 bytes).\n"); return 1; }
    }
    auto bytes = std::span(buffer).first(size);
    demo::describe(bytes);
#ifdef DEMO_EXTENDED
    demo::extended_analysis(bytes);
#endif
    if (argc == 3) {
        demo::transform(bytes);
        auto* file = std::fopen(argv[2], "wb");
        if (!file) { std::perror(argv[2]); return 1; }
        bool failed = std::fwrite(bytes.data(), 1, size, file) != size;
        if (std::fclose(file) != 0) failed = true;
        if (failed) { std::fprintf(stderr, "Cannot write output.\n"); return 1; }
        std::printf("Wrote %zu transformed bytes.\n", size);
    }
    return 0;
}
