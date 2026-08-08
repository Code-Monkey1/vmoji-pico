// Telemetry emitter for the vmoji scan loop.
//
// Design constraints that shaped this file:
//
//  - The matrix scan loop is the real-time task. Nothing here may block for
//    longer than a row dwell, or the display visibly tears. So statistics are
//    accumulated with a handful of integer operations per scan and only
//    serialised once per reporting interval.
//  - No dynamic allocation and no floating point in the per-scan path.
//  - Frames go to both USB CDC and UART0, so the dashboard works whether the
//    board is on /dev/ttyACM0 or behind a TTL adapter on GP0/GP1.

#include "telemetry.h"

#include "led-matrix.h"
#include "telemetry_frame.h"

#include "hardware/adc.h"
#include "hardware/uart.h"
#include "pico/stdio.h"
#include "pico/time.h"

#include <cstdio>

namespace {

// Matches the UART configured in blink.c.
//
// This is a function rather than a `constexpr` constant because the SDK's
// `uart0` macro expands to a reinterpret_cast of a fixed peripheral address, and
// a cast from an integer to a pointer is not a constant expression. Wrapping it
// in an inline accessor keeps it free at runtime while avoiding a dynamically
// initialised global, which is worth avoiding on a microcontroller.
inline uart_inst_t *telemetry_uart() { return uart0; }

constexpr std::uint64_t kStatusIntervalUs = 100000u;      // 10 Hz
constexpr std::uint64_t kFrameBufIntervalUs = 500000u;    // 2 Hz

constexpr std::uint8_t kTempAdcInput = 4u;  // RP2040 on-die temperature sensor

struct IntervalStats {
    std::uint32_t count;
    std::uint32_t sum_us;
    std::uint16_t min_us;
    std::uint16_t max_us;

    void reset() {
        count = 0;
        sum_us = 0;
        min_us = 0xFFFFu;
        max_us = 0;
    }

    void add(std::uint32_t period_us) {
        // Clamp rather than wrap: a garbage 70000 us reading is less misleading
        // than a wrapped 4 us one, and it stays visible on the plot.
        const std::uint16_t clamped =
            period_us > 0xFFFFu ? 0xFFFFu : static_cast<std::uint16_t>(period_us);
        ++count;
        sum_us += clamped;
        if (clamped < min_us) {
            min_us = clamped;
        }
        if (clamped > max_us) {
            max_us = clamped;
        }
    }
};

struct State {
    IntervalStats interval;
    std::uint64_t last_scan_us;
    std::uint64_t last_status_us;
    std::uint64_t last_framebuf_us;
    std::uint32_t scan_count;
    std::uint32_t rx_bytes;
    std::uint16_t cmd_ok;
    std::uint16_t cmd_err;
    std::uint16_t row_dwell_us;
    std::uint8_t glyph_id;
    std::uint8_t flags;
    std::uint8_t seq;
    vmoji::FrameBufferPayload framebuffer;
    bool temp_ready;
};

State g{};

void write_bytes(const std::uint8_t *data, std::size_t size) {
    // Raw writes on both links: putchar_raw bypasses the newline translation
    // that stdio would otherwise apply, which would corrupt binary payloads.
    for (std::size_t i = 0; i < size; ++i) {
        putchar_raw(static_cast<int>(data[i]));
    }
    uart_write_blocking(telemetry_uart(), data, size);
}

void send(vmoji::MsgId id, const void *payload, std::size_t payload_size) {
    std::uint8_t buffer[vmoji::kMaxFrame];
    const std::size_t length =
        vmoji::encode_frame(buffer, sizeof(buffer), id, g.seq++, payload, payload_size);
    if (length > 0) {
        write_bytes(buffer, length);
    }
}

/**
 * RP2040 datasheet: T = 27 - (V - 0.706) / 0.001721, with a 12-bit ADC over a
 * 3.3 V reference. Returned in hundredths of a degree so the wire format stays
 * integer-only.
 */
std::int16_t read_die_temp_c_x100() {
    if (!g.temp_ready) {
        return 0;
    }
    adc_select_input(kTempAdcInput);
    const std::uint16_t raw = adc_read();
    const float volts = static_cast<float>(raw) * 3.3f / 4095.0f;
    const float celsius = 27.0f - (volts - 0.706f) / 0.001721f;
    return static_cast<std::int16_t>(celsius * 100.0f);
}

void send_status(std::uint64_t now_us, std::uint32_t elapsed_us) {
    vmoji::StatusPayload status{};
    status.uptime_ms = static_cast<std::uint32_t>(now_us / 1000u);
    status.scan_count = g.scan_count;

    const IntervalStats &s = g.interval;
    if (s.count > 0) {
        status.period_mean_us = static_cast<std::uint16_t>(s.sum_us / s.count);
        status.period_min_us = s.min_us;
        status.period_max_us = s.max_us;
        status.jitter_pp_us = static_cast<std::uint16_t>(s.max_us - s.min_us);
        // Scans per second in centi-hertz, computed from the observed window
        // rather than from the mean period, so a stalled interval reads as a
        // rate drop instead of silently holding the last good value.
        if (elapsed_us > 0) {
            const std::uint64_t chz =
                (static_cast<std::uint64_t>(s.count) * 100000000ull) / elapsed_us;
            status.refresh_chz = chz > 0xFFFFu ? 0xFFFFu : static_cast<std::uint16_t>(chz);
        }
    }

    status.die_temp_c_x100 = read_die_temp_c_x100();
    status.cmd_ok = g.cmd_ok;
    status.cmd_err = g.cmd_err;
    status.rx_bytes = g.rx_bytes;
    status.row_dwell_us = g.row_dwell_us;
    status.glyph_id = g.glyph_id;
    status.flags = g.flags;

    send(vmoji::MsgId::Status, &status, sizeof(status));
}

}  // namespace

extern "C" {

void telemetry_init(void) {
    g = State{};
    g.interval.reset();
    g.row_dwell_us = MATRIX_ROW_DWELL_US;

    adc_init();
    adc_set_temp_sensor_enabled(true);
    g.temp_ready = true;

    const std::uint64_t now = time_us_64();
    g.last_scan_us = now;
    g.last_status_us = now;
    g.last_framebuf_us = now;
}

void telemetry_note_scan(void) {
    const std::uint64_t now = time_us_64();
    if (g.last_scan_us != 0) {
        g.interval.add(static_cast<std::uint32_t>(now - g.last_scan_us));
    }
    g.last_scan_us = now;
    ++g.scan_count;
}

void telemetry_note_rx_bytes(uint32_t count) { g.rx_bytes += count; }

void telemetry_note_command(bool accepted) {
    if (accepted) {
        ++g.cmd_ok;
    } else {
        ++g.cmd_err;
    }
}

void telemetry_set_glyph(uint8_t glyph_id) { g.glyph_id = glyph_id; }

void telemetry_set_row_dwell(uint16_t microseconds) { g.row_dwell_us = microseconds; }

uint16_t telemetry_row_dwell(void) { return g.row_dwell_us; }

void telemetry_set_flag(uint8_t flag, bool on) {
    if (on) {
        g.flags = static_cast<std::uint8_t>(g.flags | flag);
    } else {
        g.flags = static_cast<std::uint8_t>(g.flags & ~flag);
    }
}

void telemetry_set_framebuffer(const bool *framebuffer) {
    if (framebuffer == nullptr) {
        return;
    }
    for (std::size_t r = 0; r < 8; ++r) {
        std::uint8_t bits = 0;
        for (std::size_t c = 0; c < 8; ++c) {
            if (framebuffer[r * 8 + c]) {
                bits = static_cast<std::uint8_t>(bits | (0x80u >> c));
            }
        }
        g.framebuffer.row[r] = bits;
    }
}

void telemetry_reset_counters(void) {
    g.interval.reset();
    g.scan_count = 0;
    g.rx_bytes = 0;
    g.cmd_ok = 0;
    g.cmd_err = 0;
}

void telemetry_service(void) {
    const std::uint64_t now = time_us_64();

    const std::uint64_t since_status = now - g.last_status_us;
    if (since_status >= kStatusIntervalUs) {
        send_status(now, static_cast<std::uint32_t>(since_status));
        g.interval.reset();
        g.last_status_us = now;
    }

    if (now - g.last_framebuf_us >= kFrameBufIntervalUs) {
        send(vmoji::MsgId::FrameBuffer, &g.framebuffer, sizeof(g.framebuffer));
        g.last_framebuf_us = now;
    }
}

void telemetry_log(const char *text) {
    if (text == nullptr) {
        return;
    }
    std::size_t length = 0;
    while (text[length] != '\0' && length < vmoji::kMaxPayload) {
        ++length;
    }
    send(vmoji::MsgId::Log, text, length);
}

void telemetry_ack(const char *text) {
    if (text == nullptr) {
        return;
    }
    std::size_t length = 0;
    while (text[length] != '\0' && length < vmoji::kMaxPayload) {
        ++length;
    }
    send(vmoji::MsgId::Ack, text, length);
}

}  // extern "C"
