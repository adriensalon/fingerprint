include_guard(GLOBAL)

if(NOT CMAKE_SCRIPT_MODE_FILE)
    set(FINGERPRINT_TLSH_ROOT "${CMAKE_BINARY_DIR}/_deps/tlsh")
    if(NOT FINGERPRINT_TLSH_SOURCE_DIR)
        set(FINGERPRINT_TLSH_SOURCE_DIR "${FINGERPRINT_TLSH_ROOT}/src")
    endif()
    if(NOT EXISTS "${FINGERPRINT_TLSH_SOURCE_DIR}/CMakeLists.txt")
        find_package(Git REQUIRED)
        message(STATUS "[fingerprint] Downloading TLSH sources")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" clone --depth 1 --branch 4.12.1 https://github.com/trendmicro/tlsh.git "${FINGERPRINT_TLSH_SOURCE_DIR}"
            RESULT_VARIABLE _fingerprint_tlsh_clone_status
            OUTPUT_QUIET
            ERROR_QUIET)
        if(NOT _fingerprint_tlsh_clone_status EQUAL 0)
            message(FATAL_ERROR "Failed to clone TLSH source into ${FINGERPRINT_TLSH_SOURCE_DIR}")
        endif()
        message(STATUS "[fingerprint] TLSH sources ready")
    endif()
    set(FINGERPRINT_TLSH_SOURCES
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh_impl.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh_util.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/input_desc.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/shared_file_functions.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/test/tlsh_unittest.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/Windows/WinFunctions.cpp")
    return()
endif()

find_program(FINGERPRINT_TLSH_EXECUTABLE
    NAMES tlsh tlsh_unittest
    PATHS ENV PATH
    NO_CMAKE_FIND_ROOT_PATH)
if(NOT FINGERPRINT_TLSH_EXECUTABLE)
    message(FATAL_ERROR "TLSH executable was not provided to the comparison script. Build it before invoking this script.")
endif()
if(NOT EXISTS "${FINGERPRINT_TLSH_EXECUTABLE}")
    message(FATAL_ERROR "TLSH executable does not exist at: ${FINGERPRINT_TLSH_EXECUTABLE}")
endif()
execute_process(
    COMMAND "${FINGERPRINT_TLSH_EXECUTABLE}" "-c" "${INPUT1}" "-f" "${INPUT2}" "-ojson"
    RESULT_VARIABLE _status
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE)
if(NOT _status STREQUAL "0")
    message(FATAL_ERROR "TLSH comparison failed for ${INPUT1} and ${INPUT2}: ${_error}\n${_output}")
endif()
string(REGEX MATCH "\"dist\"[ \t]*:[ \t]*\"?([0-9]+)\"?" _dist_match "${_output}")
if(NOT _dist_match)
    message(FATAL_ERROR "TLSH comparison did not return a distance: ${_error}\n${_output}")
endif()
set(_distance "${CMAKE_MATCH_1}")
string(JSON _result SET "{}" distance "${_distance}")
if(EXISTS "${OUTPUT}")
    file(READ "${OUTPUT}" _report)
else()
    set(_report "{\"tools\":{}}")
endif()
string(JSON _report SET "${_report}" tools tlsh "${_result}")
file(WRITE "${OUTPUT}" "${_report}\n")
