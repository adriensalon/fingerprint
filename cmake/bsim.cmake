include_guard(GLOBAL)

function(_fingerprint_bsim_setup headless)
    set(FINGERPRINT_BSIM_ROOT "${CMAKE_BINARY_DIR}/_deps/bsim")
    set(FINGERPRINT_BSIM_EXECUTABLE "${headless}")
    get_filename_component(_support "${FINGERPRINT_BSIM_EXECUTABLE}" DIRECTORY)
    get_filename_component(_ghidra "${_support}" DIRECTORY)
    set(_bsim "${_ghidra}/Ghidra/Features/BSim")
    if(NOT EXISTS "${_bsim}/lib/BSim.jar")
        message(FATAL_ERROR "The Ghidra installation does not contain BSim: ${_ghidra}")
    endif()
    file(MAKE_DIRECTORY "${FINGERPRINT_BSIM_ROOT}/scripts")
    set(_script "${FINGERPRINT_BSIM_ROOT}/scripts/FingerprintBSim.java")
    file(CONFIGURE OUTPUT "${_script}" CONTENT [=[
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import generic.lsh.vector.LSHVectorFactory;
import ghidra.app.script.GhidraScript;
import ghidra.features.bsim.query.BSimClientFactory;
import ghidra.features.bsim.query.FunctionDatabase;
import ghidra.features.bsim.query.GenSignatures;
import ghidra.features.bsim.query.client.Configuration;
import ghidra.features.bsim.query.client.ExecutableComparison;
import ghidra.features.bsim.query.description.DatabaseInformation;
import ghidra.features.bsim.query.description.DescriptionManager;
import ghidra.features.bsim.query.file.BSimH2FileDBConnectionManager;
import ghidra.features.bsim.query.protocol.CreateDatabase;
import ghidra.features.bsim.query.protocol.InsertRequest;
import ghidra.util.xml.SpecXmlUtils;
import ghidra.xml.NonThreadedXmlPullParserImpl;

public class FingerprintBSim extends GhidraScript {
    private static final String TEMPLATE = "medium_nosize";
    private static final double SIMILARITY = 0.7;
    private static final double SIGNIFICANCE = 10.0;
    private static final int CLUSTER_LIMIT = 1000000;

    @Override
    protected void run() throws Exception {
        var args = getScriptArgs();
        if (args.length == 2 && args[0].equals("generate")) {
            generate(Path.of(args[1]));
        } else if (args.length == 5 && args[0].equals("compare")) {
            compare(Path.of(args[1]), Path.of(args[2]), Path.of(args[3]), Path.of(args[4]));
        } else {
            throw new IllegalArgumentException("Expected generate <xml> or compare <xml1> <xml2> <json> <database>");
        }
    }

    private LSHVectorFactory factory() throws Exception {
        var config = FunctionDatabase.loadConfigurationTemplate(TEMPLATE);
        var factory = FunctionDatabase.generateLSHVectorFactory();
        factory.set(config.weightfactory, config.idflookup, config.info.settings);
        return factory;
    }

    private void generate(Path output) throws Exception {
        if (currentProgram == null) {
            throw new IllegalArgumentException("Signature generation requires an analyzed program");
        }
        var generator = new GenSignatures(false);
        try {
            generator.setVectorFactory(factory());
            generator.openProgram(currentProgram, null, null, null, null, null);
            var functions = currentProgram.getFunctionManager();
            generator.scanFunctions(functions.getFunctions(true), functions.getFunctionCount(), monitor);
            monitor.checkCancelled();
            try (var writer = Files.newBufferedWriter(output)) {
                generator.getDescriptionManager().saveXml(writer);
            }
        } finally {
            generator.dispose();
        }
    }

    private DescriptionManager read(Path file, LSHVectorFactory factory) throws Exception {
        var descriptions = new DescriptionManager();
        try (var input = Files.newInputStream(file)) {
            var parser = new NonThreadedXmlPullParserImpl(input, "BSim signatures", SpecXmlUtils.getXmlHandler(), false);
            try {
                descriptions.restoreXml(parser, factory);
            } finally {
                parser.dispose();
            }
        }
        return descriptions;
    }

    private void insert(FunctionDatabase database, DescriptionManager descriptions) throws Exception {
        var request = new InsertRequest();
        request.manage = descriptions;
        if (request.execute(database) == null) {
            throw new IOException("BSim insert failed: " + database.getLastError().message);
        }
    }

    private String percent(float score) {
        if (score == -1.0f) {
            return "null";
        }
        if (!Float.isFinite(score) || score < 0 || score > 1.00001) {
            throw new IllegalStateException("Invalid native BSim score: " + score);
        }
        return Double.toString(Math.min(1.0, (double) score) * 100.0);
    }

    private void save(Path output, int first, int second, String similarity, String containment, int ignored) throws Exception {
        Files.writeString(output, "{\"similarity_percent\":" + similarity +
            ",\"containment_percent\":" + containment +
            ",\"functions\":{\"input1\":" + first + ",\"input2\":" + second + "}" +
            ",\"ignored_clusters\":" + ignored +
            ",\"settings\":{\"template\":\"" + TEMPLATE + "\",\"similarity_threshold\":" + SIMILARITY +
            ",\"significance_threshold\":" + SIGNIFICANCE + ",\"cluster_limit\":" + CLUSTER_LIMIT + "}}");
    }

    private void compare(Path xml1, Path xml2, Path output, Path databasePath) throws Exception {
        var factory = factory();
        var first = read(xml1, factory);
        var second = read(xml2, factory);
        if (first.numFunctions() == 0 || second.numFunctions() == 0) {
            save(output, first.numFunctions(), second.numFunctions(), "null", "null", 0);
            return;
        }
        String md5First = first.getExecutableRecordSet().first().getMd5();
        String md5Second = second.getExecutableRecordSet().first().getMd5();
        var database = BSimClientFactory.buildClient(databasePath.toUri().toURL(), false);
        try {
            var create = new CreateDatabase();
            create.config_template = TEMPLATE;
            create.info = new DatabaseInformation();
            create.info.databasename = "fingerprint";
            create.info.trackcallgraph = false;
            if (create.execute(database) == null) {
                throw new IOException("BSim database creation failed: " + database.getLastError().message);
            }
            insert(database, first);
            if (!md5First.equals(md5Second)) {
                insert(database, second);
            }
            var comparison = new ExecutableComparison(database, CLUSTER_LIMIT, monitor);
            comparison.addExecutable(md5First);
            if (!md5First.equals(md5Second)) {
                comparison.addExecutable(md5Second);
            }
            comparison.resetThresholds(SIMILARITY, SIGNIFICANCE);
            comparison.performScoring();
            var scorer = comparison.getScorer();
            int index1 = scorer.getExecutable(md5First).getXrefIndex();
            int index2 = scorer.getExecutable(md5Second).getXrefIndex();
            save(output, first.numFunctions(), second.numFunctions(),
                percent(scorer.getNormalizedScore(index1, index2, false)),
                percent(scorer.getNormalizedScore(index1, index2, true)), comparison.getExceedCount());
        } finally {
            database.close();
            var source = BSimH2FileDBConnectionManager.getDataSourceIfExists(database.getServerInfo());
            if (source != null) {
                source.dispose();
            }
        }
    }
}
]=] @ONLY)
    file(GLOB _native_decompilers "${_ghidra}/Ghidra/Features/Decompiler/os/*/decompile*")
    set(FINGERPRINT_BSIM_DEPENDENCIES
        "${FINGERPRINT_BSIM_EXECUTABLE}"
        "${Java_JAVA_EXECUTABLE}"
        "${_ghidra}/Ghidra/application.properties"
        "${_bsim}/lib/BSim.jar"
        "${_bsim}/data/medium_nosize.xml"
        "${_bsim}/data/lshweights_nosize.xml"
        "${_ghidra}/Ghidra/Features/Decompiler/lib/Decompiler.jar"
        ${_native_decompilers}
        "${_script}")
    if(NOT TARGET fingerprint_bsim)
        add_executable(fingerprint_bsim IMPORTED GLOBAL)
        set_target_properties(fingerprint_bsim PROPERTIES IMPORTED_LOCATION "${FINGERPRINT_BSIM_EXECUTABLE}")
        add_custom_target(fingerprint_bsim_build DEPENDS ${FINGERPRINT_BSIM_DEPENDENCIES})
    endif()
    foreach(variable IN ITEMS FINGERPRINT_BSIM_ROOT FINGERPRINT_BSIM_EXECUTABLE FINGERPRINT_BSIM_DEPENDENCIES)
        set(${variable} "${${variable}}" PARENT_SCOPE)
    endforeach()
endfunction()

if(NOT CMAKE_SCRIPT_MODE_FILE)
    return()
endif()

foreach(_input IN ITEMS INPUT1 INPUT2)
    if(NOT EXISTS "${${_input}}" OR IS_DIRECTORY "${${_input}}")
        message(FATAL_ERROR "BSim input file does not exist: ${${_input}}")
    endif()
endforeach()
if(NOT DEFINED OUTPUT OR OUTPUT STREQUAL "")
    message(FATAL_ERROR "OUTPUT is required for the BSim comparison report")
endif()
set(_script "${FINGERPRINT_BSIM_ROOT}/scripts/FingerprintBSim.java")
foreach(_required IN ITEMS FINGERPRINT_BSIM_EXECUTABLE FINGERPRINT_BSIM_JAVA_EXECUTABLE _script)
    if(NOT EXISTS "${${_required}}")
        message(FATAL_ERROR "BSim dependency was not found: ${_required}=${${_required}}. Configure the project before running this script.")
    endif()
endforeach()
get_filename_component(_support "${FINGERPRINT_BSIM_EXECUTABLE}" DIRECTORY)
get_filename_component(_ghidra "${_support}" DIRECTORY)
set(_bsim "${_ghidra}/Ghidra/Features/BSim")
file(STRINGS "${_ghidra}/Ghidra/application.properties" _version REGEX "^application.version=")
string(REPLACE "application.version=" "" _version "${_version}")
file(GLOB _native_decompilers "${_ghidra}/Ghidra/Features/Decompiler/os/*/decompile*")
set(_tool_hash "")
foreach(_file IN ITEMS
        "${_ghidra}/Ghidra/application.properties" "${_bsim}/lib/BSim.jar"
        "${_bsim}/data/medium_nosize.xml" "${_bsim}/data/lshweights_nosize.xml"
        "${_ghidra}/Ghidra/Features/Decompiler/lib/Decompiler.jar" ${_native_decompilers} "${_script}")
    file(SHA256 "${_file}" _hash)
    string(APPEND _tool_hash "${_hash}")
endforeach()
string(SHA256 _tool_hash "${_tool_hash}")
set(_profile "${FINGERPRINT_BSIM_ROOT}/profile")
file(MAKE_DIRECTORY "${_profile}/cache")
cmake_path(NATIVE_PATH _profile NORMALIZE _native_profile)
set(_java_options "$ENV{JAVA_TOOL_OPTIONS} -Duser.home=\"${_native_profile}\"")
get_filename_component(_java_bin "${FINGERPRINT_BSIM_JAVA_EXECUTABLE}" DIRECTORY)
if(CMAKE_HOST_WIN32)
    set(_java_path "${_java_bin};$ENV{PATH}")
else()
    set(_java_path "${_java_bin}:$ENV{PATH}")
endif()

function(_fingerprint_bsim_run directory description)
    file(MAKE_DIRECTORY "${directory}")
    file(LOCK "${FINGERPRINT_BSIM_ROOT}/ghidra.lock" GUARD FUNCTION TIMEOUT 1 RESULT_VARIABLE status)
    if(NOT status STREQUAL "0")
        message(STATUS "[fingerprint] BSim: waiting for headless Ghidra (${description})")
        file(LOCK "${FINGERPRINT_BSIM_ROOT}/ghidra.lock" GUARD FUNCTION TIMEOUT 900 RESULT_VARIABLE status)
    endif()
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "Failed to lock the BSim Ghidra profile: ${status}")
    endif()
    message(STATUS "[fingerprint] BSim: ${description} with headless Ghidra")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env
            "USERPROFILE=${_native_profile}" "JAVA_TOOL_OPTIONS=${_java_options}"
            "LOCALAPPDATA=${_native_profile}/cache" "PATH=${_java_path}"
            "${FINGERPRINT_BSIM_EXECUTABLE}" "${directory}" project
            -scriptPath "${FINGERPRINT_BSIM_ROOT}/scripts" ${ARGN}
            -deleteProject -overwrite -max-cpu 2
            -log "${directory}/ghidra.log" -scriptlog "${directory}/script.log"
        RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE error TIMEOUT 900)
    file(WRITE "${directory}/stdout.log" "${output}\n${error}")
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "BSim headless Ghidra failed (${status}): ${error}\n${output}")
    endif()
endfunction()

function(_fingerprint_bsim_signatures input out_xml)
    get_filename_component(input "${input}" REALPATH)
    get_filename_component(name "${input}" NAME)
    file(SHA256 "${input}" hash)
    string(SHA256 key "${_tool_hash}|${input}|${hash}")
    set(directory "${_cache}/signatures/${key}")
    set(xml "${directory}/signatures.xml")
    file(MAKE_DIRECTORY "${directory}")
    file(LOCK "${directory}/cache.lock" GUARD FUNCTION TIMEOUT 1 RESULT_VARIABLE status)
    if(NOT status STREQUAL "0")
        message(STATUS "[fingerprint] BSim: waiting for signatures of ${name}")
        file(LOCK "${directory}/cache.lock" GUARD FUNCTION TIMEOUT 900 RESULT_VARIABLE status)
    endif()
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "Failed to lock BSim signatures for ${input}: ${status}")
    endif()
    set(valid FALSE)
    if(EXISTS "${xml}")
        file(READ "${xml}" text)
        if(text MATCHES "^<description[ >]" AND text MATCHES "</description>[ \r\n]*$")
            set(valid TRUE)
        endif()
    endif()
    if(NOT valid)
        file(REMOVE "${xml}.tmp")
        _fingerprint_bsim_run("${directory}" "generating signatures for ${name}" -import "${input}"
            -postScript FingerprintBSim.java generate "${xml}.tmp")
        if(NOT EXISTS "${xml}.tmp")
            message(FATAL_ERROR "BSim did not generate signatures for ${input}; see ${directory}/stdout.log")
        endif()
        file(READ "${xml}.tmp" text)
        if(NOT text MATCHES "^<description[ >]" OR NOT text MATCHES "</description>[ \r\n]*$")
            message(FATAL_ERROR "BSim generated incomplete signatures for ${input}")
        endif()
        file(RENAME "${xml}.tmp" "${xml}")
        message(STATUS "[fingerprint] BSim: signatures ready for ${name}")
    endif()
    set(${out_xml} "${xml}" PARENT_SCOPE)
endfunction()

function(_fingerprint_bsim_result_valid json out_valid)
    set(${out_valid} FALSE PARENT_SCOPE)
    string(JSON count ERROR_VARIABLE error LENGTH "${json}")
    if(error OR NOT count EQUAL 5)
        return()
    endif()
    string(JSON count ERROR_VARIABLE error LENGTH "${json}" functions)
    if(error OR NOT count EQUAL 2)
        return()
    endif()
    string(JSON count ERROR_VARIABLE error LENGTH "${json}" settings)
    if(error OR NOT count EQUAL 4)
        return()
    endif()
    foreach(metric IN ITEMS similarity_percent containment_percent)
        string(JSON type ERROR_VARIABLE error TYPE "${json}" ${metric})
        if(error)
            return()
        endif()
        if(type STREQUAL "NUMBER")
            string(JSON value GET "${json}" ${metric})
            if(value LESS 0 OR value GREATER 100)
                return()
            endif()
        elseif(NOT type STREQUAL "NULL")
            return()
        endif()
    endforeach()
    foreach(index IN ITEMS input1 input2)
        string(JSON value ERROR_VARIABLE error GET "${json}" functions ${index})
        string(JSON type ERROR_VARIABLE type_error TYPE "${json}" functions ${index})
        if(error OR type_error OR NOT type STREQUAL "NUMBER" OR NOT value MATCHES "^[0-9]+$")
            return()
        endif()
    endforeach()
    string(JSON value ERROR_VARIABLE error GET "${json}" ignored_clusters)
    string(JSON type ERROR_VARIABLE type_error TYPE "${json}" ignored_clusters)
    if(error OR type_error OR NOT type STREQUAL "NUMBER" OR NOT value MATCHES "^[0-9]+$")
        return()
    endif()
    string(JSON value ERROR_VARIABLE error GET "${json}" settings template)
    if(error OR NOT value STREQUAL "medium_nosize")
        return()
    endif()
    foreach(setting IN ITEMS similarity_threshold significance_threshold cluster_limit)
        string(JSON value ERROR_VARIABLE error GET "${json}" settings ${setting})
        string(JSON type ERROR_VARIABLE type_error TYPE "${json}" settings ${setting})
        if(error OR type_error OR NOT type STREQUAL "NUMBER")
            return()
        endif()
        if(setting STREQUAL "similarity_threshold" AND NOT value EQUAL 0.7)
            return()
        elseif(setting STREQUAL "significance_threshold" AND NOT value EQUAL 10)
            return()
        elseif(setting STREQUAL "cluster_limit" AND NOT value EQUAL 1000000)
            return()
        endif()
    endforeach()
    set(${out_valid} TRUE PARENT_SCOPE)
endfunction()

function(_fingerprint_bsim_compare first second out_result)
    get_filename_component(name1 "${INPUT1}" NAME)
    get_filename_component(name2 "${INPUT2}" NAME)
    file(SHA256 "${first}" hash1)
    file(SHA256 "${second}" hash2)
    string(SHA256 key "${_tool_hash}|${hash1}|${hash2}")
    set(directory "${_cache}/pairs/${key}")
    set(result "${directory}/result.json")
    file(MAKE_DIRECTORY "${directory}")
    file(LOCK "${directory}/cache.lock" GUARD FUNCTION TIMEOUT 1 RESULT_VARIABLE status)
    if(NOT status STREQUAL "0")
        message(STATUS "[fingerprint] BSim: waiting for comparison of ${name1} and ${name2}")
        file(LOCK "${directory}/cache.lock" GUARD FUNCTION TIMEOUT 900 RESULT_VARIABLE status)
    endif()
    if(NOT status STREQUAL "0")
        message(FATAL_ERROR "Failed to lock the BSim comparison: ${status}")
    endif()
    set(valid FALSE)
    if(EXISTS "${result}")
        file(READ "${result}" json)
        _fingerprint_bsim_result_valid("${json}" valid)
    endif()
    if(NOT valid)
        file(REMOVE "${result}.tmp" "${directory}/database.mv.db" "${directory}/database.trace.db")
        _fingerprint_bsim_run("${directory}" "comparing ${name1} and ${name2}" -preScript FingerprintBSim.java compare
            "${first}" "${second}" "${result}.tmp" "${directory}/database" -noanalysis)
        if(NOT EXISTS "${result}.tmp")
            message(FATAL_ERROR "BSim did not produce comparison results; see ${directory}/stdout.log")
        endif()
        file(READ "${result}.tmp" json)
        _fingerprint_bsim_result_valid("${json}" valid)
        if(NOT valid)
            message(FATAL_ERROR "BSim produced invalid comparison data; see ${directory}/stdout.log")
        endif()
        file(RENAME "${result}.tmp" "${result}")
        message(STATUS "[fingerprint] BSim: comparison ready for ${name1} and ${name2}")
    endif()
    string(JSON json SET "${json}" ghidra_version "\"${_version}\"")
    set(${out_result} "${json}" PARENT_SCOPE)
endfunction()

get_filename_component(_cache "${OUTPUT}" DIRECTORY ABSOLUTE)
set(_cache "${_cache}/.bsim")
_fingerprint_bsim_signatures("${INPUT1}" _xml1)
_fingerprint_bsim_signatures("${INPUT2}" _xml2)
_fingerprint_bsim_compare("${_xml1}" "${_xml2}" _result)
if(EXISTS "${OUTPUT}")
    file(READ "${OUTPUT}" _report)
else()
    set(_report "{\"tools\":{}}")
endif()
string(JSON _report SET "${_report}" tools bsim "${_result}")
file(WRITE "${OUTPUT}" "${_report}\n")
