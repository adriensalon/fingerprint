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

function(_fingerprint_compare_pairwise target1 target2)
    cmake_parse_arguments(PARSE_ARGV 2 ARG "" "" "DEPENDS;ARGS")
    if(NOT TARGET "${target1}" OR NOT TARGET "${target2}")
        message(FATAL_ERROR "Unknown target in fingerprint comparison")
    endif()
    string(MAKE_C_IDENTIFIER "${target1}_${target2}" name)
    string(SHA256 id "${target1}|${target2}")
    string(SUBSTRING "${id}" 0 12 id)
    set(comparison "fingerprint_${name}_${id}")
    set(comparison "${comparison}" PARENT_SCOPE)
    if(TARGET "${comparison}")
        return()
    endif()
    set(directory "${CMAKE_CURRENT_BINARY_DIR}/fingerprint")
    set(output "${directory}/${name}_${id}.json")
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
                "-DFINGERPRINT_BSIM_EXECUTABLE=$<TARGET_FILE:fingerprint_bsim>"
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
endfunction()

function(fingerprint_compare)
    cmake_parse_arguments(PARSE_ARGV 0 ARG "" "" "DEPENDS;ARGS")
    set(targets ${ARG_UNPARSED_ARGUMENTS})
    list(LENGTH targets count)
    if(count LESS 2)
        message(FATAL_ERROR "At least two targets are required for fingerprint comparison")
    endif()
    set(comparisons)
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
        endforeach()
    endforeach()

    if(NOT TARGET fingerprint_compare)
        add_custom_target(fingerprint_compare ALL)
    endif()
    foreach(tool IN LISTS FINGERPRINT_TOOLS)
        string(SHA256 id "${tool}|${targets}")
        string(SUBSTRING "${id}" 0 12 id)
        set(group "fingerprint_${tool}_all_${id}")
        if(NOT TARGET "${group}")
            add_custom_target("${group}"
                COMMAND "${CMAKE_COMMAND}" -E echo "Compared fingerprints with ${tool} for ${count} targets"
                COMMENT ""
                VERBATIM)
            add_dependencies("${group}" ${comparisons})
        endif()
        add_dependencies(fingerprint_compare "${group}")
    endforeach()
endfunction()

if(FINGERPRINT_BUILD_DEMO)
    add_subdirectory(demo)
endif()
