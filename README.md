# fingerprint

CMake POST_BUILD step to report similarity in a list of executable targets as a with sha256, TLSH, ssdeep, capa, BinDiff and BSim.

```cmake
# BinDiff and BSim tools require a Ghidra installation
# If not provided, fingerprint will look at GHIDRA_INSTALL_DIR too
fingerprint_compare(executable_targets... GHIDRA_DIR "path/to/ghidra")
```

### Requirements

- C++ 20 compiler
- CMake 3.20
- Ghidra 10.0.3 for BinDiff and BSim
