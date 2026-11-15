include_guard(GLOBAL)

if(NOT CMAKE_SCRIPT_MODE_FILE)
    set(FINGERPRINT_SSDEEP_ROOT "${CMAKE_BINARY_DIR}/_deps/ssdeep")
    find_program(FINGERPRINT_SSDEEP_EXECUTABLE
        NAMES ssdeep
        NO_CMAKE_FIND_ROOT_PATH)
    if(NOT FINGERPRINT_SSDEEP_EXECUTABLE AND CMAKE_HOST_WIN32)
        # Upstream's Windows CLI requires MinGW; use its official release.
        set(_fingerprint_ssdeep_archive "${FINGERPRINT_SSDEEP_ROOT}/ssdeep-2.14.1-win32-binary.zip")
        set(_fingerprint_ssdeep_executable "${FINGERPRINT_SSDEEP_ROOT}/bin/ssdeep-2.14.1/ssdeep.exe")
        if(NOT EXISTS "${_fingerprint_ssdeep_executable}")
            file(MAKE_DIRECTORY "${FINGERPRINT_SSDEEP_ROOT}")
            file(DOWNLOAD
                "https://github.com/ssdeep-project/ssdeep/releases/download/release-2.14.1/ssdeep-2.14.1-win32-binary.zip"
                "${_fingerprint_ssdeep_archive}"
                EXPECTED_HASH SHA256=4606478242049ac039862348ea69cbecdebe2a699b50b7af934abeae0c690353
                TLS_VERIFY ON
                STATUS _fingerprint_ssdeep_download_status)
            list(GET _fingerprint_ssdeep_download_status 0 _fingerprint_ssdeep_download_code)
            if(NOT _fingerprint_ssdeep_download_code EQUAL 0)
                message(FATAL_ERROR "Failed to download ssdeep: ${_fingerprint_ssdeep_download_status}")
            endif()
            file(ARCHIVE_EXTRACT
                INPUT "${_fingerprint_ssdeep_archive}"
                DESTINATION "${FINGERPRINT_SSDEEP_ROOT}/bin")
        endif()
        set(FINGERPRINT_SSDEEP_EXECUTABLE "${_fingerprint_ssdeep_executable}"
            CACHE FILEPATH "Path to the ssdeep executable" FORCE)
    endif()
    if(NOT FINGERPRINT_SSDEEP_EXECUTABLE OR NOT EXISTS "${FINGERPRINT_SSDEEP_EXECUTABLE}")
        message(FATAL_ERROR "ssdeep was not found. Install it or set FINGERPRINT_SSDEEP_EXECUTABLE to its executable path.")
    endif()
    add_executable(fingerprint_ssdeep IMPORTED GLOBAL)
    set_target_properties(fingerprint_ssdeep PROPERTIES
        IMPORTED_LOCATION "${FINGERPRINT_SSDEEP_EXECUTABLE}")
    add_custom_target(fingerprint_ssdeep_build DEPENDS "${FINGERPRINT_SSDEEP_EXECUTABLE}")
    return()
endif()

find_program(FINGERPRINT_SSDEEP_EXECUTABLE
    NAMES ssdeep
    NO_CMAKE_FIND_ROOT_PATH)
if(NOT FINGERPRINT_SSDEEP_EXECUTABLE OR NOT EXISTS "${FINGERPRINT_SSDEEP_EXECUTABLE}")
    message(FATAL_ERROR "ssdeep executable was not found at: ${FINGERPRINT_SSDEEP_EXECUTABLE}")
endif()
foreach(_input IN ITEMS INPUT1 INPUT2)
    if(NOT EXISTS "${${_input}}" OR IS_DIRECTORY "${${_input}}")
        message(FATAL_ERROR "ssdeep input file does not exist: ${${_input}}")
    endif()
endforeach()
if(NOT DEFINED OUTPUT OR OUTPUT STREQUAL "")
    message(FATAL_ERROR "OUTPUT is required for the ssdeep comparison report")
endif()

# Directory mode compares the two inputs once; -a includes scores of zero.
# The Windows CLI requires backslashes in absolute input paths.
cmake_path(NATIVE_PATH INPUT1 NORMALIZE _input1)
cmake_path(NATIVE_PATH INPUT2 NORMALIZE _input2)
execute_process(
    COMMAND "${FINGERPRINT_SSDEEP_EXECUTABLE}" -a -d -c -- "${_input1}" "${_input2}"
    RESULT_VARIABLE _status
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE)
if(NOT _status STREQUAL "0")
    message(FATAL_ERROR "ssdeep comparison failed for ${INPUT1} and ${INPUT2}: ${_error}\n${_output}")
endif()
string(REGEX MATCH ",([0-9]+)[ \t\r\n]*$" _score_match "${_output}")
if(NOT _score_match)
    message(FATAL_ERROR "ssdeep comparison did not return a similarity score: ${_error}\n${_output}")
endif()
set(_score "${CMAKE_MATCH_1}")
if(_score GREATER 100)
    message(FATAL_ERROR "ssdeep returned an invalid similarity score: ${_score}")
endif()

set(_executable "${FINGERPRINT_SSDEEP_EXECUTABLE}")
foreach(_field IN ITEMS _output _executable)
    string(REPLACE "\\" "\\\\" ${_field} "${${_field}}")
    string(REPLACE "\"" "\\\"" ${_field} "${${_field}}")
    string(REPLACE "\r" "\\r" ${_field} "${${_field}}")
    string(REPLACE "\n" "\\n" ${_field} "${${_field}}")
    string(REPLACE "\t" "\\t" ${_field} "${${_field}}")
endforeach()
file(WRITE "${OUTPUT}"
    "{\n"
    "  \"tool\": \"ssdeep\",\n"
    "  \"score\": ${_score},\n"
    "  \"raw_output\": \"${_output}\",\n"
    "  \"executable\": \"${_executable}\"\n"
    "}\n")
