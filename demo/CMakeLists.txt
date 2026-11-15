cmake_minimum_required(VERSION 3.25)

set(demo_targets)
foreach(index RANGE 1 5)
    add_executable(demo_main${index} "main${index}.cpp")
    list(APPEND demo_targets "demo_main${index}")
endforeach()

fingerprint_compare(${demo_targets})
