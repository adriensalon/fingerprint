# fingerprint

The `fingerprint_compare` build target reports pairwise similarity for
executables and shared libraries with SHA-256, TLSH, ssdeep, capa, BinDiff and
BSim. It compares static library archives by SHA-256.

```cmake
# BinDiff and BSim tools require a Ghidra installation
# If not provided, fingerprint will look at GHIDRA_INSTALL_DIR too
fingerprint_compare(executable_targets... GHIDRA_DIR "path/to/ghidra")
fingerprint_compare(static_library_targets...)
```

Use `POST_BUILD <target>` to build the other inputs first and compare that
set when the selected target links. The selected target must be one of the
comparison inputs and must be declared in the calling CMake directory.

```cmake
fingerprint_compare(mylib mylib_2 mylib_3 POST_BUILD mylib)
```

The aggregate `fingerprint_compare` target refreshes every registered set.

### Requirements

- CMake 3.25
- A C++20 compiler for the executable fingerprint tools
- Ghidra 11.0.3 and a JDK for BinDiff and BSim
