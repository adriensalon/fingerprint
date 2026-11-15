include_guard(GLOBAL)
cmake_minimum_required(VERSION 3.25)
project(fingerprint)

option(FINGERPRINT_BUILD_DEMO "Builds demo executables and fingerprint comparisons" ON)

include(cmake/tlsh.cmake)

file(GLOB FINGERPRINT_TOOL_SCRIPTS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/*.cmake")

function(_fingerprint_compare_pairwise_all tool target1 target2)
    cmake_parse_arguments(PARSE_ARGV 3 ARG "" "" "DEPENDS;ARGS")
    if(NOT TARGET "${target1}" OR NOT TARGET "${target2}")
        message(FATAL_ERROR "Unknown target in fingerprint comparison")
    endif()
    string(MAKE_C_IDENTIFIER "${tool}_${target1}_${target2}" name)
    string(SHA256 id "${tool}|${target1}|${target2}")
    string(SUBSTRING "${id}" 0 12 id)
    set(comparison "fingerprint_${name}_${id}")
    set(comparison "${comparison}" PARENT_SCOPE)
    if(TARGET "${comparison}")
        return()
    endif()
    set(script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/cmake/${tool}.cmake")
    set(directory "${CMAKE_CURRENT_BINARY_DIR}/fingerprint")
    set(output "${directory}/${name}_${id}.json")
    set(extra_args "${ARG_ARGS}")
    set(extra_deps "${ARG_DEPENDS}")
    if(tool STREQUAL "tlsh")
        list(APPEND extra_args "-DFINGERPRINT_TLSH_EXECUTABLE=$<TARGET_FILE:fingerprint_tlsh>")
        list(APPEND extra_deps fingerprint_tlsh_build)
    endif()
    add_custom_command(
        OUTPUT "${output}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${directory}"
        COMMAND "${CMAKE_COMMAND}"
            "-DINPUT1=$<TARGET_FILE:${target1}>"
            "-DINPUT2=$<TARGET_FILE:${target2}>"
            "-DOUTPUT=${output}"
            ${extra_args}
            -P "${script}"
        DEPENDS
            "${target1}"
            "${target2}"
            "${script}"
            ${FINGERPRINT_TOOL_SCRIPTS}
            ${extra_deps}
        COMMENT ""
        VERBATIM)
    add_custom_target("${comparison}" DEPENDS "${output}")
endfunction()

function(_fingerprint_compare_variadic tool)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "" "" "DEPENDS;ARGS")
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
            _fingerprint_compare_pairwise_all(
                "${tool}"
                "${left_target}"
                "${right_target}"
                DEPENDS ${ARG_DEPENDS}
                ARGS ${ARG_ARGS})
            list(APPEND comparisons "${comparison}")
        endforeach()
    endforeach()

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
    if(NOT TARGET fingerprint_compare)
        add_custom_target(fingerprint_compare ALL)
    endif()
    add_dependencies(fingerprint_compare "${group}")
endfunction()

function(fingerprint_compare)
    cmake_parse_arguments(PARSE_ARGV 0 ARG "" "" "DEPENDS;ARGS")
    set(targets ${ARG_UNPARSED_ARGUMENTS})
    list(LENGTH targets count)
    if(count LESS 2)
        message(FATAL_ERROR "At least two targets are required for fingerprint comparison")
    endif()
    _fingerprint_compare_variadic(sha256 ${targets} DEPENDS ${ARG_DEPENDS} ARGS ${ARG_ARGS})
    _fingerprint_compare_variadic(tlsh ${targets} DEPENDS ${ARG_DEPENDS} ARGS ${ARG_ARGS})
endfunction()

if(FINGERPRINT_BUILD_DEMO)
    add_subdirectory(demo)
endif()
