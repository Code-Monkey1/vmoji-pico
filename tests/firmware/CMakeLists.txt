# Host-side firmware tests (no Pico SDK).
cmake_minimum_required(VERSION 3.16)
project(vmoji_firmware_tests C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

enable_testing()

set(VMOJI_ROOT ${CMAKE_CURRENT_LIST_DIR}/../../vmoji)

add_library(vmoji_host_core STATIC
    ${VMOJI_ROOT}/volume.c
    ${VMOJI_ROOT}/volume_codec.c
    ${VMOJI_ROOT}/volumes_builtin.c
    ${VMOJI_ROOT}/rotation_estimator.c
    ${VMOJI_ROOT}/scan_timing.c
    ${VMOJI_ROOT}/pov_service.c
    ${VMOJI_ROOT}/commands.c
)
target_include_directories(vmoji_host_core PUBLIC ${VMOJI_ROOT})
target_compile_definitions(vmoji_host_core PUBLIC VMOJI_HOST_TEST=1)
target_compile_options(vmoji_host_core PRIVATE -Wall -Wextra)

add_library(vmoji_test_harness STATIC
    harness/fake_time.c
    harness/fake_platform.c
)
target_include_directories(vmoji_test_harness PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/harness
    ${VMOJI_ROOT}
)
target_link_libraries(vmoji_test_harness PUBLIC vmoji_host_core)

function(vmoji_add_test name src)
    add_executable(${name} ${src})
    target_include_directories(${name} PRIVATE
        ${CMAKE_CURRENT_LIST_DIR}/harness
        ${VMOJI_ROOT}
    )
    target_link_libraries(${name} PRIVATE vmoji_host_core vmoji_test_harness)
    target_compile_definitions(${name} PRIVATE VMOJI_HOST_TEST=1)
    target_compile_options(${name} PRIVATE -Wall -Wextra)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

vmoji_add_test(test_geometry unit/test_geometry.c)
vmoji_add_test(test_volume unit/test_volume.c)
vmoji_add_test(test_volumes_builtin unit/test_volumes_builtin.c)
vmoji_add_test(test_volume_codec unit/test_volume_codec.c)
vmoji_add_test(test_rotation_estimator unit/test_rotation_estimator.c)
vmoji_add_test(test_scan_timing unit/test_scan_timing.c)
vmoji_add_test(test_commands unit/test_commands.c)
vmoji_add_test(test_pov_service integration/test_pov_service.c)

# Protocol framing self-test (C++), shared with dashboard vectors.
add_executable(protocol_selftest ${CMAKE_CURRENT_LIST_DIR}/../../tools/protocol_selftest.cpp)
target_include_directories(protocol_selftest PRIVATE ${VMOJI_ROOT})
target_compile_options(protocol_selftest PRIVATE -Wall -Wextra)
add_test(NAME protocol_selftest COMMAND protocol_selftest)
