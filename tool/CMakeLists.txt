cmake_minimum_required(VERSION 3.25)
project(fingerprint_tools LANGUAGES CXX)

include("${CMAKE_CURRENT_LIST_DIR}/../cmake/tlsh.cmake")
add_executable(fingerprint_tlsh ${FINGERPRINT_TLSH_SOURCES})
target_include_directories(fingerprint_tlsh PRIVATE
    "${FINGERPRINT_TLSH_SOURCE_DIR}/include"
    "${FINGERPRINT_TLSH_SOURCE_DIR}/src"
    "${FINGERPRINT_TLSH_SOURCE_DIR}/Windows")
if(WIN32)
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include")
    file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/include/dirent.h"
        CONTENT "#pragma once\n#include <WinFunctions.h>\n" @ONLY)
    target_include_directories(fingerprint_tlsh BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/include")
endif()
target_compile_definitions(fingerprint_tlsh PRIVATE WINDOWS WIN32 _WINDOWS _CRT_SECURE_NO_WARNINGS TLSH_LIB)
set_target_properties(fingerprint_tlsh PROPERTIES OUTPUT_NAME tlsh)

add_executable(fingerprint_report_tool report.cpp)
target_compile_features(fingerprint_report_tool PRIVATE cxx_std_20)
set_target_properties(fingerprint_tlsh fingerprint_report_tool PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>")
