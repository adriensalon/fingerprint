foreach(name IN ITEMS baseline variant extended)
    add_executable(demo_${name} main.cpp pipeline.cpp)
    target_compile_features(demo_${name} PRIVATE cxx_std_20)
endforeach()
target_compile_definitions(demo_variant PRIVATE DEMO_VARIANT)
target_compile_definitions(demo_extended PRIVATE DEMO_EXTENDED)
target_sources(demo_extended PRIVATE extended.cpp)

add_executable(demo_routes routes.cpp)
target_compile_features(demo_routes PRIVATE cxx_std_20)
foreach(target IN ITEMS demo_baseline demo_variant demo_extended demo_routes)
    set_target_properties(${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>")
endforeach()

set(copy "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/demo_identical${CMAKE_EXECUTABLE_SUFFIX}")
add_custom_command(OUTPUT "${copy}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:demo_baseline>" "${copy}"
    DEPENDS demo_baseline "$<TARGET_FILE:demo_baseline>"
    VERBATIM)
add_executable(demo_identical IMPORTED)
set_target_properties(demo_identical PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_BUILD_TYPE}/demo_identical${CMAKE_EXECUTABLE_SUFFIX}")
foreach(config IN LISTS CMAKE_CONFIGURATION_TYPES)
    string(TOUPPER "${config}" upper_config)
    set_property(TARGET demo_identical APPEND PROPERTY IMPORTED_CONFIGURATIONS "${config}")
    set_property(TARGET demo_identical PROPERTY "IMPORTED_LOCATION_${upper_config}"
        "${CMAKE_CURRENT_BINARY_DIR}/${config}/demo_identical${CMAKE_EXECUTABLE_SUFFIX}")
endforeach()

fingerprint_compare(demo_baseline demo_identical demo_variant demo_extended demo_routes GHIDRA_DIR "C:/libs/ghidra")
target_sources(fingerprint_compare PRIVATE "${copy}")
