include_guard(GLOBAL)
cmake_minimum_required(VERSION 3.25)
project(fingerprint)

option(FINGERPRINT_BUILD_DEMO "Builds demo executables and fingerprint comparisons" ON)

include(cmake/tlsh.cmake)
include(cmake/ssdeep.cmake)
include(cmake/capa.cmake)
include(cmake/bindiff.cmake)
include(cmake/bsim.cmake)

set(FINGERPRINT_TOOLS sha256 tlsh ssdeep capa bindiff bsim)
file(GLOB FINGERPRINT_TOOL_SCRIPTS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/*.cmake")

function(_fingerprint_report)
    cmake_parse_arguments(PARSE_ARGV 0 ARG "" "TARGET_COUNT" "INPUTS;DEPENDS")
    if(NOT TARGET fingerprint_report_tool)
        add_executable(fingerprint_report_tool EXCLUDE_FROM_ALL "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/tool/report.cpp")
        target_compile_features(fingerprint_report_tool PRIVATE cxx_std_20)
    endif()
    string(SHA256 id "${ARG_INPUTS}")
    string(SUBSTRING "${id}" 0 12 id)
    set(report "fingerprint_report_${id}")
    if(NOT TARGET "${report}")
        set(directory "${CMAKE_CURRENT_BINARY_DIR}/fingerprint/$<CONFIG>")
        set(manifest "${directory}/report_${id}.inputs")
        set(summary "${directory}/report_${id}.txt")
        list(JOIN ARG_INPUTS "\n" inputs)
        file(GENERATE OUTPUT "${manifest}" CONTENT "${inputs}\n")
        add_custom_target("${report}"
            COMMAND "$<TARGET_FILE:fingerprint_report_tool>"
                --expected-targets "${ARG_TARGET_COUNT}"
                "--configuration=$<CONFIG>"
                --manifest "${manifest}" --output "${summary}"
            BYPRODUCTS "${summary}"
            DEPENDS fingerprint_report_tool
            COMMENT ""
            VERBATIM
            USES_TERMINAL)
        add_dependencies("${report}" ${ARG_DEPENDS})
    endif()
    if(NOT TARGET fingerprint_report)
        add_custom_target(fingerprint_report)
    endif()
    add_dependencies(fingerprint_report "${report}")
    add_dependencies(fingerprint_compare fingerprint_report)
endfunction()

function(_fingerprint_compare_pairwise target1 target2)
    cmake_parse_arguments(PARSE_ARGV 2 ARG "" "" "DEPENDS;ARGS")
    if(NOT TARGET "${target1}" OR NOT TARGET "${target2}")
        message(FATAL_ERROR "Unknown target in fingerprint comparison")
    endif()
    string(MAKE_C_IDENTIFIER "${target1}_${target2}" name)
    string(SHA256 id "${target1}|${target2}|${FINGERPRINT_BINEXPORT_EXECUTABLE}|${FINGERPRINT_BSIM_EXECUTABLE}")
    string(SUBSTRING "${id}" 0 12 id)
    set(comparison "fingerprint_${name}_${id}")
    set(comparison "${comparison}" PARENT_SCOPE)
    if(TARGET "${comparison}")
        get_target_property(report "${comparison}" FINGERPRINT_REPORT)
        set(report "${report}" PARENT_SCOPE)
        return()
    endif()
    set(directory "${CMAKE_CURRENT_BINARY_DIR}/fingerprint/$<CONFIG>")
    set(output "${directory}/${name}_${id}.json")
    set(report "${output}" PARENT_SCOPE)
    set(temporary "${output}.tmp")
    set(commands)
    set(extra_deps "${ARG_DEPENDS}")
    foreach(tool IN LISTS FINGERPRINT_TOOLS)
        set(extra_args "${ARG_ARGS}")
        if(tool STREQUAL "tlsh")
            list(APPEND extra_args "-DFINGERPRINT_TLSH_EXECUTABLE=$<TARGET_FILE:fingerprint_tlsh>")
            list(APPEND extra_deps fingerprint_tlsh_build "$<TARGET_FILE:fingerprint_tlsh>")
        elseif(tool STREQUAL "ssdeep")
            list(APPEND extra_args "-DFINGERPRINT_SSDEEP_EXECUTABLE=$<TARGET_FILE:fingerprint_ssdeep>")
            list(APPEND extra_deps fingerprint_ssdeep_build "$<TARGET_FILE:fingerprint_ssdeep>")
        elseif(tool STREQUAL "capa")
            list(APPEND extra_args "-DFINGERPRINT_CAPA_EXECUTABLE=$<TARGET_FILE:fingerprint_capa>")
            list(APPEND extra_deps fingerprint_capa_build "$<TARGET_FILE:fingerprint_capa>")
        elseif(tool STREQUAL "bindiff")
            list(APPEND extra_args
                "-DFINGERPRINT_BINDIFF_EXECUTABLE=$<TARGET_FILE:fingerprint_bindiff>"
                "-DFINGERPRINT_BINEXPORT_EXECUTABLE=${FINGERPRINT_BINEXPORT_EXECUTABLE}"
                "-DFINGERPRINT_BINEXPORT_ROOT=${FINGERPRINT_BINEXPORT_ROOT}"
                "-DFINGERPRINT_BINEXPORT_JAVA_EXECUTABLE=${Java_JAVA_EXECUTABLE}")
            list(APPEND extra_deps fingerprint_bindiff_build ${FINGERPRINT_BINDIFF_DEPENDENCIES})
        elseif(tool STREQUAL "bsim")
            list(APPEND extra_args
                "-DFINGERPRINT_BSIM_EXECUTABLE=${FINGERPRINT_BSIM_EXECUTABLE}"
                "-DFINGERPRINT_BSIM_ROOT=${FINGERPRINT_BSIM_ROOT}"
                "-DFINGERPRINT_BSIM_JAVA_EXECUTABLE=${Java_JAVA_EXECUTABLE}")
            list(APPEND extra_deps fingerprint_bsim_build ${FINGERPRINT_BSIM_DEPENDENCIES})
        endif()
        set(script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/cmake/${tool}.cmake")
        list(APPEND commands COMMAND "${CMAKE_COMMAND}"
            "-DINPUT1=$<TARGET_FILE:${target1}>"
            "-DINPUT2=$<TARGET_FILE:${target2}>"
            "-DINPUT1_TARGET=${target1}"
            "-DINPUT2_TARGET=${target2}"
            "-DBUILD_CONFIG=$<CONFIG>"
            "-DOUTPUT=${temporary}"
            ${extra_args}
            -P "${script}")
    endforeach()
    add_custom_command(
        OUTPUT "${output}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${directory}"
        COMMAND "${CMAKE_COMMAND}" -E rm -f "${temporary}"
        ${commands}
        COMMAND "${CMAKE_COMMAND}" -E rename "${temporary}" "${output}"
        DEPENDS
            "${target1}"
            "${target2}"
            ${FINGERPRINT_TOOL_SCRIPTS}
            ${extra_deps}
        COMMENT ""
        VERBATIM)
    add_custom_target("${comparison}" DEPENDS "${output}")
    set_property(TARGET "${comparison}" PROPERTY FINGERPRINT_REPORT "${output}")
endfunction()

function(fingerprint_compare)
    cmake_parse_arguments(PARSE_ARGV 0 ARG "" "GHIDRA_DIR" "DEPENDS;ARGS")
    if("GHIDRA_DIR" IN_LIST ARG_KEYWORDS_MISSING_VALUES)
        message(FATAL_ERROR "GHIDRA_DIR requires a Ghidra installation directory")
    endif()
    set(targets ${ARG_UNPARSED_ARGUMENTS})
    list(REMOVE_DUPLICATES targets)
    list(LENGTH targets count)
    if(count LESS 2)
        message(FATAL_ERROR "At least two targets are required for fingerprint comparison")
    endif()

    if(ARG_GHIDRA_DIR)
        get_filename_component(ghidra_dir "${ARG_GHIDRA_DIR}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        set(ghidra_headless ghidra_headless-NOTFOUND)
        find_program(ghidra_headless
            NAMES analyzeHeadless.bat analyzeHeadless
            PATHS "${ghidra_dir}/support"
            NO_DEFAULT_PATH NO_CACHE NO_CMAKE_FIND_ROOT_PATH)
    else()
        find_program(FINGERPRINT_GHIDRA_EXECUTABLE
            NAMES analyzeHeadless.bat analyzeHeadless
            HINTS "$ENV{GHIDRA_INSTALL_DIR}/support"
            NO_CMAKE_FIND_ROOT_PATH)
        set(ghidra_headless "${FINGERPRINT_GHIDRA_EXECUTABLE}")
    endif()
    if(NOT ghidra_headless)
        message(FATAL_ERROR "Ghidra headless analyzer was not found. Use fingerprint_compare(... GHIDRA_DIR <installation-directory>), set GHIDRA_INSTALL_DIR, or add Ghidra's support directory to PATH.")
    endif()
    find_package(Java 17 REQUIRED COMPONENTS Runtime Development)
    _fingerprint_bindiff_setup("${ghidra_headless}")
    _fingerprint_bsim_setup("${ghidra_headless}")

    set(comparisons)
    set(reports)
    math(EXPR last_index "${count} - 1")
    foreach(i RANGE 0 ${last_index})
        list(GET targets ${i} left_target)
        foreach(j RANGE ${i} ${last_index})
            if(i EQUAL j)
                continue()
            endif()
            list(GET targets ${j} right_target)
            _fingerprint_compare_pairwise(
                "${left_target}"
                "${right_target}"
                DEPENDS ${ARG_DEPENDS}
                ARGS ${ARG_ARGS})
            list(APPEND comparisons "${comparison}")
            list(APPEND reports "${report}")
        endforeach()
    endforeach()

    if(NOT TARGET fingerprint_compare)
        add_custom_target(fingerprint_compare ALL)
    endif()
    set(groups)
    foreach(tool IN LISTS FINGERPRINT_TOOLS)
        string(SHA256 id "${tool}|${reports}")
        string(SUBSTRING "${id}" 0 12 id)
        set(group "fingerprint_${tool}_all_${id}")
        if(NOT TARGET "${group}")
            add_custom_target("${group}"
                COMMAND "${CMAKE_COMMAND}" -E echo "Compared fingerprints with ${tool} for ${count} targets"
                COMMENT ""
                VERBATIM)
            add_dependencies("${group}" ${comparisons})
        endif()
        list(APPEND groups "${group}")
    endforeach()
    _fingerprint_report(TARGET_COUNT "${count}" INPUTS ${reports} DEPENDS ${groups})
endfunction()

if(FINGERPRINT_BUILD_DEMO)
    add_subdirectory(demo)
endif()
