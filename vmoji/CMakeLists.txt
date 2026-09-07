# Generated Cmake Pico project file

cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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

add_executable(vmoji
    main.c
    matrix.c
    uart_link.c
    commands.c
    telemetry.cpp
    volume.c
    volume_codec.c
    volumes_builtin.c
    rotation_estimator.c
    rotation_sync.c
    scan_timing.c
    pio_scan.c
    pov_service.c
    pov_runtime.c
    )

pico_generate_pio_header(vmoji ${CMAKE_CURRENT_LIST_DIR}/pio_scan.pio)

set_source_files_properties(
    main.c matrix.c uart_link.c commands.c telemetry.cpp
    volume.c volume_codec.c volumes_builtin.c
    rotation_estimator.c rotation_sync.c scan_timing.c
    pio_scan.c pov_service.c pov_runtime.c
    PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra"
)

set(VMOJI_VERSION "1.2.0")
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

target_link_libraries(vmoji
    pico_stdlib
    pico_multicore
    hardware_adc
    hardware_watchdog
    hardware_pio
    hardware_dma
    hardware_irq
    pico_unique_id
)

if (PICO_CYW43_SUPPORTED)
    target_link_libraries(vmoji pico_cyw43_arch_none)
endif()

pico_enable_stdio_usb(vmoji 1)
pico_enable_stdio_uart(vmoji 0)

target_compile_definitions(vmoji PRIVATE PICO_STDIO_USB_STDOUT_TIMEOUT_US=1000)

pico_add_extra_outputs(vmoji)
