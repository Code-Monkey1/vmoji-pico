# Generated Cmake Pico project file

cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Initialise pico_sdk from installed location
# (note this can come from environment, CMake cache etc)

# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.3.0)
set(toolchainVersion 14_2_Rel1)
set(picotoolVersion 2.3.0)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
set(PICO_BOARD pico CACHE STRING "Board type")

# Pull in Raspberry Pi Pico SDK (must be before project)
include(pico_sdk_import.cmake)

project(vmoji C CXX ASM)

# Initialise the Raspberry Pi Pico SDK
pico_sdk_init()

# One translation unit per job: the scan-out, the UART link, the command
# grammar, and the binary downlink.
add_executable(vmoji
    main.c
    matrix.c
    uart_link.c
    commands.c
    telemetry.cpp
    )

# Warnings on, but only for our own translation units: the SDK and TinyUSB are
# compiled into this same target and are not warning-clean, so a target-wide
# flag would bury our own diagnostics in someone else's.
set_source_files_properties(
    main.c matrix.c uart_link.c commands.c telemetry.cpp
    PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra"
)

# Build provenance, reported at boot. Regenerated at configure time; a dirty or
# absent git tree degrades to "unknown" rather than failing the build.
set(VMOJI_VERSION "1.1.0")
execute_process(
    COMMAND git rev-parse --short=8 HEAD
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    OUTPUT_VARIABLE VMOJI_GIT_SHA
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT VMOJI_GIT_SHA)
    set(VMOJI_GIT_SHA "unknown")
endif()
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/vmoji_version.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/vmoji_generated/vmoji_version.h
    @ONLY
)
target_include_directories(vmoji PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/vmoji_generated)

# pull in common dependencies
# hardware_adc drives the RP2040 on-die temperature sensor used by telemetry.
# pico_unique_id reports the chip serial, which identifies a specific board.
target_link_libraries(vmoji pico_stdlib hardware_adc hardware_watchdog pico_unique_id)

if (PICO_CYW43_SUPPORTED)
    target_link_libraries(vmoji pico_cyw43_arch_none)
endif()

pico_enable_stdio_usb(vmoji 1)
pico_enable_stdio_uart(vmoji 0)

# The USB CDC write blocks while the host is not draining the endpoint. The SDK
# default gives up after half a second, which is an eternity for a scan loop
# whose row dwell is measured in hundreds of microseconds; 1 ms bounds the worst
# case that a stalled host can inflict on the display.
target_compile_definitions(vmoji PRIVATE PICO_STDIO_USB_STDOUT_TIMEOUT_US=1000)

# create map/bin/hex file etc.
pico_add_extra_outputs(vmoji)

# add url via pico_set_program_url
