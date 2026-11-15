include_guard(GLOBAL)

if(NOT CMAKE_SCRIPT_MODE_FILE)
    set(FINGERPRINT_BINEXPORT_ROOT "${CMAKE_BINARY_DIR}/_deps/binexport")
    set(FINGERPRINT_GHIDRA_ROOT "$ENV{GHIDRA_INSTALL_DIR}" CACHE PATH "Ghidra 11.0.3 installation directory")
    find_program(FINGERPRINT_BINEXPORT_EXECUTABLE
        NAMES analyzeHeadless.bat analyzeHeadless
        HINTS "${FINGERPRINT_GHIDRA_ROOT}/support"
        NO_CMAKE_FIND_ROOT_PATH)
    if(NOT FINGERPRINT_BINEXPORT_EXECUTABLE)
        message(FATAL_ERROR "Ghidra headless analyzer was not found. Set FINGERPRINT_GHIDRA_ROOT to your Ghidra 11.0.3 installation.")
    endif()
    get_filename_component(_support "${FINGERPRINT_BINEXPORT_EXECUTABLE}" DIRECTORY)
    get_filename_component(_ghidra "${_support}" DIRECTORY)
    file(STRINGS "${_ghidra}/Ghidra/application.properties" _version REGEX "^application.version=")
    if(NOT _version STREQUAL "application.version=11.0.3")
        message(FATAL_ERROR "The bundled BinExport extension requires Ghidra 11.0.3; found ${_version}")
    endif()
    find_package(Java 17 REQUIRED COMPONENTS Runtime Development)
    set(_extension "${FINGERPRINT_BINEXPORT_ROOT}/profile/.ghidra/.ghidra_11.0.3_PUBLIC/Extensions")
    set(_jar "${_extension}/BinExport/lib/BinExport.jar")
    if(NOT EXISTS "${_jar}")
        file(MAKE_DIRECTORY "${FINGERPRINT_BINEXPORT_ROOT}")
        set(_archive "${FINGERPRINT_BINEXPORT_ROOT}/BinExport_Ghidra-Java.zip")
        file(DOWNLOAD
            "https://github.com/google/binexport/releases/download/v12-20240417-ghidra_11.0.3/BinExport_Ghidra-Java.zip"
            "${_archive}"
            EXPECTED_HASH SHA256=b010285c23f350c4f1ff6a1ebb4d07a9af0e24b75a458ba1eee0d631e0c9327e
            TLS_VERIFY ON
            STATUS _download_status)
        list(GET _download_status 0 _download_code)
        if(NOT _download_code EQUAL 0)
            message(FATAL_ERROR "Failed to download BinExport: ${_download_status}")
        endif()
        file(ARCHIVE_EXTRACT INPUT "${_archive}" DESTINATION "${FINGERPRINT_BINEXPORT_ROOT}/extension")
        file(ARCHIVE_EXTRACT
            INPUT "${FINGERPRINT_BINEXPORT_ROOT}/extension/ghidra_11.0.3_PUBLIC_20240417_BinExport.zip"
            DESTINATION "${_extension}")
    endif()
    file(MAKE_DIRECTORY "${FINGERPRINT_BINEXPORT_ROOT}/scripts")
    set(_script "${FINGERPRINT_BINEXPORT_ROOT}/scripts/FingerprintBinExport.java")
    file(CONFIGURE OUTPUT "${_script}" CONTENT [=[
import com.google.security.binexport.BinExport2Builder;
import ghidra.app.script.GhidraScript;
import java.nio.file.Files;
import java.nio.file.Path;

public class FingerprintBinExport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        if (currentProgram == null || getScriptArgs().length != 1) {
            throw new IllegalArgumentException("Expected a program and one export path");
        }
        var builder = new BinExport2Builder(currentProgram, currentProgram.getMemory());
        try (var output = Files.newOutputStream(Path.of(getScriptArgs()[0]))) {
            builder.build().writeTo(output);
        }
    }
}
]=] @ONLY)
    set(FINGERPRINT_BINEXPORT_DEPENDENCIES
        "${FINGERPRINT_BINEXPORT_EXECUTABLE}"
        "${Java_JAVA_EXECUTABLE}"
        "${_ghidra}/Ghidra/application.properties"
        "${_jar}"
        "${_script}")
    set(FINGERPRINT_BINDIFF_ROOT "${CMAKE_BINARY_DIR}/_deps/bindiff")
    find_program(FINGERPRINT_BINDIFF_EXECUTABLE
        NAMES bindiff
        PATHS "$ENV{ProgramFiles}/BinDiff/bin"
        NO_CMAKE_FIND_ROOT_PATH)
    if(NOT FINGERPRINT_BINDIFF_EXECUTABLE AND CMAKE_HOST_WIN32)
        set(_archive "${FINGERPRINT_BINDIFF_ROOT}/bindiff8.msi")
        set(_executable "${FINGERPRINT_BINDIFF_ROOT}/bin/ProgramFiles/BinDiff/bin/bindiff.exe")
        if(NOT EXISTS "${_executable}")
            file(MAKE_DIRECTORY "${FINGERPRINT_BINDIFF_ROOT}")
            file(DOWNLOAD
                "https://github.com/google/bindiff/releases/download/v8/bindiff8.msi"
                "${_archive}"
                EXPECTED_HASH SHA256=688831e490bef8a20c9917048b693bad591f346b3b96489fc79ad8d20d7cb15f
                TLS_VERIFY ON
                STATUS _download_status)
            list(GET _download_status 0 _download_code)
            if(NOT _download_code EQUAL 0)
                message(FATAL_ERROR "Failed to download BinDiff: ${_download_status}")
            endif()
            find_program(_fingerprint_msiexec NAMES msiexec REQUIRED)
            find_program(_fingerprint_powershell NAMES pwsh powershell REQUIRED)
            set(_directory "${FINGERPRINT_BINDIFF_ROOT}/bin")
            set(_log "${FINGERPRINT_BINDIFF_ROOT}/extract.log")
            cmake_path(NATIVE_PATH _archive NORMALIZE _native_archive)
            cmake_path(NATIVE_PATH _directory NORMALIZE _native_directory)
            cmake_path(NATIVE_PATH _log NORMALIZE _native_log)
            execute_process(
                COMMAND "${CMAKE_COMMAND}" -E env
                    "FINGERPRINT_MSIEXEC=${_fingerprint_msiexec}"
                    "FINGERPRINT_MSI_ARCHIVE=${_native_archive}"
                    "FINGERPRINT_MSI_DIRECTORY=${_native_directory}"
                    "FINGERPRINT_MSI_LOG=${_native_log}"
                    "${_fingerprint_powershell}" -NoProfile -NonInteractive -Command [=[
                        $arguments = '/a "' + $env:FINGERPRINT_MSI_ARCHIVE + '" /qn TARGETDIR="' + $env:FINGERPRINT_MSI_DIRECTORY + '" /L*v "' + $env:FINGERPRINT_MSI_LOG + '"'
                        $process = Start-Process -FilePath $env:FINGERPRINT_MSIEXEC -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
                        exit $process.ExitCode
                    ]=]
                RESULT_VARIABLE _extract_status
                TIMEOUT 300)
            if(NOT _extract_status STREQUAL "0")
                message(FATAL_ERROR "Failed to extract BinDiff (${_extract_status}); see ${FINGERPRINT_BINDIFF_ROOT}/extract.log")
            endif()
        endif()
        set(FINGERPRINT_BINDIFF_EXECUTABLE "${_executable}" CACHE FILEPATH "Path to the BinDiff CLI" FORCE)
    endif()
    if(NOT FINGERPRINT_BINDIFF_EXECUTABLE OR NOT EXISTS "${FINGERPRINT_BINDIFF_EXECUTABLE}")
        message(FATAL_ERROR "BinDiff was not found. Install it or set FINGERPRINT_BINDIFF_EXECUTABLE to the CLI executable.")
    endif()
    add_executable(fingerprint_bindiff IMPORTED GLOBAL)
    set_target_properties(fingerprint_bindiff PROPERTIES IMPORTED_LOCATION "${FINGERPRINT_BINDIFF_EXECUTABLE}")
    set(FINGERPRINT_BINDIFF_DEPENDENCIES "${FINGERPRINT_BINDIFF_EXECUTABLE}" ${FINGERPRINT_BINEXPORT_DEPENDENCIES})
    add_custom_target(fingerprint_bindiff_build DEPENDS ${FINGERPRINT_BINDIFF_DEPENDENCIES})
    return()
endif()

find_program(FINGERPRINT_BINDIFF_EXECUTABLE NAMES bindiff NO_CMAKE_FIND_ROOT_PATH)
if(NOT FINGERPRINT_BINDIFF_EXECUTABLE OR NOT EXISTS "${FINGERPRINT_BINDIFF_EXECUTABLE}")
    message(FATAL_ERROR "BinDiff executable was not found at: ${FINGERPRINT_BINDIFF_EXECUTABLE}")
endif()
if(NOT DEFINED OUTPUT OR OUTPUT STREQUAL "")
    message(FATAL_ERROR "OUTPUT is required for the BinDiff comparison report")
endif()
if(EXISTS "${OUTPUT}")
    file(READ "${OUTPUT}" _report)
else()
    set(_report "{\"tools\":{}}")
endif()
function(_fingerprint_bindiff_export input out_export)
    get_filename_component(input "${input}" REALPATH)
    file(SHA256 "${input}" input_hash)
    string(SHA256 key "${input}|${input_hash}|${_ghidra_hash}|${_jar_hash}|${_script_hash}")
    get_filename_component(directory "${OUTPUT}" DIRECTORY ABSOLUTE)
    set(directory "${directory}/.binexport/${key}")
    set(export "${directory}/export.BinExport")
    file(MAKE_DIRECTORY "${directory}")
    file(LOCK "${directory}/export.lock" GUARD FUNCTION TIMEOUT 900 RESULT_VARIABLE lock_status)
    if(NOT lock_status STREQUAL "0")
        message(FATAL_ERROR "Failed to lock BinExport cache for ${input}: ${lock_status}")
    endif()
    set(size 0)
    if(EXISTS "${export}")
        file(SIZE "${export}" size)
    endif()
    if(size LESS_EQUAL 8)
        file(LOCK "${FINGERPRINT_BINEXPORT_ROOT}/ghidra.lock" GUARD FUNCTION TIMEOUT 900 RESULT_VARIABLE lock_status)
        if(NOT lock_status STREQUAL "0")
            message(FATAL_ERROR "Failed to lock the Ghidra profile: ${lock_status}")
        endif()
        file(REMOVE "${export}.tmp")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env
                "USERPROFILE=${_native_profile}"
                "JAVA_TOOL_OPTIONS=${_java_options}"
                "LOCALAPPDATA=${_native_profile}/cache"
                "PATH=${_java_path}"
                "${FINGERPRINT_BINEXPORT_EXECUTABLE}" "${directory}" project
                -import "${input}"
                -scriptPath "${FINGERPRINT_BINEXPORT_ROOT}/scripts"
                -postScript FingerprintBinExport.java "${export}.tmp"
                -deleteProject -overwrite -max-cpu 2
                -log "${directory}/ghidra.log"
                -scriptlog "${directory}/script.log"
            RESULT_VARIABLE status
            OUTPUT_VARIABLE output
            ERROR_VARIABLE error
            TIMEOUT 900)
        if(NOT status STREQUAL "0" OR NOT EXISTS "${export}.tmp")
            message(FATAL_ERROR "BinExport failed for ${input}: ${error}\n${output}")
        endif()
        file(SIZE "${export}.tmp" size)
        if(size LESS_EQUAL 8)
            message(FATAL_ERROR "BinExport produced an empty or incomplete export for ${input}")
        endif()
        file(RENAME "${export}.tmp" "${export}")
    endif()
    set(${out_export} "${export}" PARENT_SCOPE)
endfunction()

set(_requires_export FALSE)
foreach(_index IN ITEMS 1 2)
    unset(_export${_index})
    get_filename_component(_extension "${INPUT${_index}}" LAST_EXT)
    string(TOLOWER "${_extension}" _extension)
    if(DEFINED FINGERPRINT_BINDIFF_INPUT${_index})
        set(_export${_index} "${FINGERPRINT_BINDIFF_INPUT${_index}}")
    elseif(_extension STREQUAL ".binexport")
        set(_export${_index} "${INPUT${_index}}")
    else()
        if(NOT EXISTS "${INPUT${_index}}" OR IS_DIRECTORY "${INPUT${_index}}")
            message(FATAL_ERROR "BinDiff input file does not exist: ${INPUT${_index}}")
        endif()
        set(_requires_export TRUE)
    endif()
endforeach()
if(_requires_export)
    set(_profile "${FINGERPRINT_BINEXPORT_ROOT}/profile")
    set(_jar "${_profile}/.ghidra/.ghidra_11.0.3_PUBLIC/Extensions/BinExport/lib/BinExport.jar")
    set(_script "${FINGERPRINT_BINEXPORT_ROOT}/scripts/FingerprintBinExport.java")
    foreach(_required IN ITEMS FINGERPRINT_BINEXPORT_EXECUTABLE FINGERPRINT_BINEXPORT_JAVA_EXECUTABLE _jar _script)
        if(NOT EXISTS "${${_required}}")
            message(FATAL_ERROR "BinExport dependency was not found: ${_required}=${${_required}}. Configure the project before running this script.")
        endif()
    endforeach()
    get_filename_component(_support "${FINGERPRINT_BINEXPORT_EXECUTABLE}" DIRECTORY)
    get_filename_component(_ghidra "${_support}" DIRECTORY)
    file(SHA256 "${_ghidra}/Ghidra/application.properties" _ghidra_hash)
    file(SHA256 "${_jar}" _jar_hash)
    file(SHA256 "${_script}" _script_hash)
    file(MAKE_DIRECTORY "${_profile}/cache" "${_profile}/tmp")
    cmake_path(NATIVE_PATH _profile NORMALIZE _native_profile)
    set(_java_options "$ENV{JAVA_TOOL_OPTIONS} -Duser.home=\"${_native_profile}\"")
    get_filename_component(_java_bin "${FINGERPRINT_BINEXPORT_JAVA_EXECUTABLE}" DIRECTORY)
    if(CMAKE_HOST_WIN32)
        set(_java_path "${_java_bin};$ENV{PATH}")
    else()
        set(_java_path "${_java_bin}:$ENV{PATH}")
    endif()
    foreach(_index IN ITEMS 1 2)
        if(NOT DEFINED _export${_index})
            _fingerprint_bindiff_export("${INPUT${_index}}" _export${_index})
        endif()
    endforeach()
endif()
foreach(_index IN ITEMS 1 2)
    if(NOT EXISTS "${_export${_index}}" OR IS_DIRECTORY "${_export${_index}}")
        message(FATAL_ERROR "BinDiff input export does not exist: ${_export${_index}}")
    endif()
endforeach()
get_filename_component(_directory "${OUTPUT}" DIRECTORY ABSOLUTE)
file(MAKE_DIRECTORY "${_directory}")
execute_process(
    COMMAND "${FINGERPRINT_BINDIFF_EXECUTABLE}"
        "--primary=${_export1}" "--secondary=${_export2}"
        "--output_dir=${_directory}" --output_format=none --nologo
    RESULT_VARIABLE _status
    OUTPUT_VARIABLE _output
    ERROR_VARIABLE _error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
    TIMEOUT 900)
if(NOT _status STREQUAL "0")
    message(FATAL_ERROR "BinDiff comparison failed: ${_error}\n${_output}")
endif()
set(_number "[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?")
set(_result "{}")
foreach(_metric IN ITEMS Similarity Confidence)
    string(REGEX MATCH "${_metric}: (${_number})%" _match "${_output}")
    if(NOT _match)
        message(FATAL_ERROR "BinDiff did not return ${_metric}: ${_output}")
    endif()
    set(_value "${CMAKE_MATCH_1}")
    if(_value LESS 0 OR _value GREATER 100)
        message(FATAL_ERROR "BinDiff returned invalid ${_metric}: ${_value}")
    endif()
    string(TOLOWER "${_metric}" _metric_name)
    string(JSON _result SET "${_result}" ${_metric_name}_percent "${_value}")
endforeach()
string(REGEX MATCH "matched: ([0-9]+) of ([0-9]+)/([0-9]+)" _match "${_output}")
if(NOT _match)
    message(FATAL_ERROR "BinDiff did not return matched function counts: ${_output}")
endif()
set(_matched "${CMAKE_MATCH_1}")
set(_primary "${CMAKE_MATCH_2}")
set(_secondary "${CMAKE_MATCH_3}")
string(JSON _functions SET "{}" matched "${_matched}")
string(JSON _functions SET "${_functions}" input1 "${_primary}")
string(JSON _functions SET "${_functions}" input2 "${_secondary}")
string(JSON _result SET "${_result}" functions "${_functions}")
string(JSON _report SET "${_report}" tools bindiff "${_result}")
file(WRITE "${OUTPUT}" "${_report}\n")
