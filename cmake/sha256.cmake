include_guard(GLOBAL)

file(SHA256 "${INPUT1}" hash1)
file(SHA256 "${INPUT2}" hash2)
if(hash1 STREQUAL hash2)
    set(identical true)
else()
    set(identical false)
endif()
file(WRITE "${OUTPUT}"
    "{\n"
    "  \"tool\": \"sha256\",\n"
    "  \"hash1\": \"${hash1}\",\n"
    "  \"hash2\": \"${hash2}\",\n"
    "  \"identical\": ${identical}\n"
    "}\n")