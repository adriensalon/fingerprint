include_guard(GLOBAL)

file(SHA256 "${INPUT1}" hash1)
file(SHA256 "${INPUT2}" hash2)
if(hash1 STREQUAL hash2)
    set(identical true)
else()
    set(identical false)
endif()
string(CONCAT _result
    "{\n"
    "  \"hash1\": \"${hash1}\",\n"
    "  \"hash2\": \"${hash2}\",\n"
    "  \"identical\": ${identical}\n"
    "}\n")
if(EXISTS "${OUTPUT}")
    file(READ "${OUTPUT}" _report)
else()
    set(_report "{}")
endif()
string(JSON _report SET "${_report}" sha256 "${_result}")
file(WRITE "${OUTPUT}" "${_report}\n")
