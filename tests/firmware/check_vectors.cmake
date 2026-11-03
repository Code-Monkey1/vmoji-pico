# Fails when protocol_selftest --vectors no longer matches the committed file.
# Usage: cmake -DSELFTEST=<exe> -DVECTORS=<file> -P check_vectors.cmake
execute_process(
    COMMAND ${SELFTEST} --vectors
    OUTPUT_VARIABLE actual
    RESULT_VARIABLE rc
)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "protocol_selftest --vectors failed (exit ${rc})")
endif()
if(NOT EXISTS ${VECTORS})
    message(FATAL_ERROR "Missing ${VECTORS}: run tools/update-protocol-vectors.sh")
endif()
file(READ ${VECTORS} expected)
if(NOT actual STREQUAL expected)
    message(FATAL_ERROR
        "The C++ telemetry vectors changed but ${VECTORS} was not regenerated.\n"
        "Run tools/update-protocol-vectors.sh, then update tools/dashboard/protocol.py "
        "until the Python tests pass.\n"
        "--- committed ---\n${expected}--- actual ---\n${actual}")
endif()
