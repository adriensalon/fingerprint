include_guard(GLOBAL)

if(NOT CMAKE_SCRIPT_MODE_FILE)
    set(FINGERPRINT_TLSH_ROOT "${CMAKE_BINARY_DIR}/_deps/tlsh")
    set(FINGERPRINT_TLSH_SOURCE_DIR "${FINGERPRINT_TLSH_ROOT}/src")
    set(FINGERPRINT_TLSH_BINARY "$<TARGET_FILE:fingerprint_tlsh>")
    if(NOT EXISTS "${FINGERPRINT_TLSH_SOURCE_DIR}/CMakeLists.txt")
        find_package(Git REQUIRED)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" clone --depth 1 --branch 4.12.1 https://github.com/trendmicro/tlsh.git "${FINGERPRINT_TLSH_SOURCE_DIR}"
            RESULT_VARIABLE _fingerprint_tlsh_clone_status
            OUTPUT_QUIET
            ERROR_QUIET)
        if(NOT _fingerprint_tlsh_clone_status EQUAL 0)
            message(FATAL_ERROR "Failed to clone TLSH source into ${FINGERPRINT_TLSH_SOURCE_DIR}")
        endif()
    endif()
    set(FINGERPRINT_TLSH_SOURCES
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh_impl.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/tlsh_util.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/input_desc.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src/shared_file_functions.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/test/tlsh_unittest.cpp"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/Windows/WinFunctions.cpp")
    add_executable(fingerprint_tlsh EXCLUDE_FROM_ALL ${FINGERPRINT_TLSH_SOURCES})
    target_include_directories(fingerprint_tlsh PRIVATE
        "${FINGERPRINT_TLSH_SOURCE_DIR}/include"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/src"
        "${FINGERPRINT_TLSH_SOURCE_DIR}/Windows")
    target_compile_definitions(fingerprint_tlsh PRIVATE WINDOWS WIN32 _WINDOWS _CRT_SECURE_NO_WARNINGS TLSH_LIB)
    set_target_properties(fingerprint_tlsh PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${FINGERPRINT_TLSH_ROOT}/bin"
        OUTPUT_NAME "tlsh")
    add_custom_target(fingerprint_tlsh_build DEPENDS fingerprint_tlsh)
    set(FINGERPRINT_TLSH_EXECUTABLE "$<TARGET_FILE:fingerprint_tlsh>")
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
    set(_report "{\"schema_version\":1,\"tools\":{}}")
endif()
string(JSON _report SET "${_report}" tools tlsh "${_result}")
file(WRITE "${OUTPUT}" "${_report}\n")
