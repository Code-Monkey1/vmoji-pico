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
//  - Emitting a frame must not block the scan loop. Both links are fed through
//    ring buffers: UART0 drains under its TX interrupt, USB drains in bounded
//    batches from the main loop. Measuring your own timing with a blocking
//    write means the measurement changes what it measures - the earlier
//    version of this file cost ~1.4 ms of peak-to-peak jitter on every
//    reporting interval, which is larger than a row dwell.

#include "telemetry.h"

#include "led-matrix.h"
#include "telemetry_frame.h"
#include "vmoji_version.h"

#include "hardware/adc.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "hardware/uart.h"
#include "pico/stdio.h"
#include "pico/stdio_usb.h"
#include "pico/time.h"
#include "pico/unique_id.h"

#include <cstdio>
#include <cstring>

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

// Re-announced rather than sent only at boot, because a host almost always
// attaches after the board has been powered for a while - and on USB the stack
// discards anything written before the port is opened.
constexpr std::uint64_t kIdentityIntervalUs = 10000000u;  // 10 s

constexpr std::uint8_t kTempAdcInput = 4u;  // RP2040 on-die temperature sensor

// Power of two so the wrap is a mask. Sized to hold roughly a second of
// telemetry, which is far more slack than a healthy link needs and enough to
// ride out a host that stops reading for a moment.
constexpr std::size_t kTxRingSize = 1024u;
constexpr std::size_t kTxRingMask = kTxRingSize - 1u;

// How much to hand to the USB stack per pump. The main loop runs hundreds of
// times a second, so this is ample throughput while bounding the time any one
// call can spend inside the CDC write.
constexpr std::size_t kUsbChunk = 128u;

/**
 * Single-producer, single-consumer byte ring.
 *
 * The scan loop is the only producer and the drain (ISR for UART, main loop for
 * USB) is the only consumer, so the indices need no lock: each is written by
 * exactly one side and read by the other. `volatile` plus that discipline is
 * what makes this safe against an interrupt landing mid-push.
 */
class TxRing {
public:
    void reset() {
        head_ = 0;
        tail_ = 0;
    }

    std::size_t used() const {
        return (head_ - tail_) & kTxRingMask;
    }

    bool empty() const { return head_ == tail_; }

    /** All-or-nothing: a partially written frame is worse than no frame, since
     *  the host would have to resynchronise past the truncated one. */
    bool push(const std::uint8_t *data, std::size_t size) {
        if (size > (kTxRingSize - 1u) - used()) {
            return false;
        }
        std::uint32_t head = head_;
        for (std::size_t i = 0; i < size; ++i) {
            buffer_[head] = data[i];
            head = (head + 1u) & kTxRingMask;
        }
        head_ = head;  // publish only once the bytes are in place
        return true;
    }

    bool pop(std::uint8_t &out) {
        if (empty()) {
            return false;
        }
        out = buffer_[tail_];
        tail_ = (tail_ + 1u) & kTxRingMask;
        return true;
    }

private:
    std::uint8_t buffer_[kTxRingSize];
    volatile std::uint32_t head_ = 0;
    volatile std::uint32_t tail_ = 0;
};

TxRing g_uart_tx;
TxRing g_usb_tx;

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
    std::uint64_t last_identity_us;
    std::uint32_t scan_count;
    std::uint32_t rx_bytes;
    std::uint16_t cmd_ok;
    std::uint16_t cmd_err;
    std::uint16_t row_dwell_us;
    std::uint8_t glyph_id;
    std::uint8_t flags;
    std::uint8_t seq;
    vmoji::FrameBufferPayload framebuffer;
    std::uint16_t tx_dropped_uart;
    std::uint16_t tx_dropped_usb;
    bool temp_ready;
};

State g{};

/** Start, or restart, transmission of whatever is queued for the UART.
 *
 * The whole thing runs with interrupts off because the ISR pops from the same
 * ring and clears TXIM as it empties it; interleaving with either would leave
 * bytes in the buffer with no interrupt scheduled to move them. */
void uart_tx_kick() {
    uart_hw_t *hw = uart_get_hw(telemetry_uart());
    const std::uint32_t ints = save_and_disable_interrupts();

    // The PL011 raises TXIM as the FIFO *drains past* its trigger level, so
    // arming it on an already-empty FIFO never fires and the queue sits there
    // forever. Writing the first bytes by hand creates the level to fall from;
    // after that the ISR keeps it fed. Without this the link only came alive
    // because the boot banner happened to prime the FIFO first.
    std::uint8_t byte;
    while ((hw->fr & UART_UARTFR_TXFF_BITS) == 0u && g_uart_tx.pop(byte)) {
        hw->dr = byte;
    }
    if (!g_uart_tx.empty()) {
        hw_set_bits(&hw->imsc, UART_UARTIMSC_TXIM_BITS);
    }

    restore_interrupts(ints);
}

inline void count_drop(std::uint16_t &counter) {
    if (counter < 0xFFFFu) {
        ++counter;
    }
    g.flags = static_cast<std::uint8_t>(g.flags | VMOJI_FLAG_TX_DROP);
}

void write_bytes(const std::uint8_t *data, std::size_t size) {
    // Queue, never block. A full ring means the link cannot keep up, so drop
    // the whole frame and count it: reporting a gap the host can see beats
    // stalling the scan loop the telemetry exists to measure.
    if (!g_uart_tx.push(data, size)) {
        count_drop(g.tx_dropped_uart);
    }

    // With no USB host attached there is nothing to fall behind, so bytes are
    // discarded without counting them. Counting them would light TX_DROP
    // permanently on any UART-only setup and make the flag mean nothing.
    if (stdio_usb_connected()) {
        if (!g_usb_tx.push(data, size)) {
            count_drop(g.tx_dropped_usb);
        }
    }

    uart_tx_kick();
}

/** Move queued bytes onto the wire without ever waiting for either link. */
void pump_links() {
    uart_tx_kick();

    if (g_usb_tx.empty()) {
        return;
    }
    if (!stdio_usb_connected()) {
        // The host went away mid-frame. Discard the remainder rather than let
        // a full ring make every later frame look like a drop.
        std::uint8_t discard;
        while (g_usb_tx.pop(discard)) {
        }
        return;
    }
    std::uint8_t chunk[kUsbChunk];
    std::size_t count = 0;
    while (count < kUsbChunk && g_usb_tx.pop(chunk[count])) {
        ++count;
    }
    if (count > 0) {
        // One call for the whole chunk, with CR translation off so binary
        // payloads survive. The previous per-byte putchar_raw ran the entire
        // stdio and TinyUSB path once per byte.
        //
        // Residual gap: a host that is attached but not draining its endpoint
        // makes this give up after PICO_STDIO_USB_STDOUT_TIMEOUT_US and discard
        // the chunk silently, so those bytes are lost without raising TX_DROP.
        // Bounding the wait is the point, and the host sees the resulting gap
        // in sequence numbers either way.
        stdio_put_string(reinterpret_cast<const char *>(chunk),
                         static_cast<int>(count), false, false);
    }
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
    g_uart_tx.reset();
    g_usb_tx.reset();

    adc_init();
    adc_set_temp_sensor_enabled(true);
    g.temp_ready = true;

    const std::uint64_t now = time_us_64();
    g.last_scan_us = now;
    g.last_status_us = now;
    g.last_framebuf_us = now;
    g.last_identity_us = now;
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
    g.tx_dropped_uart = 0;
    g.tx_dropped_usb = 0;
    g.flags = static_cast<std::uint8_t>(g.flags & ~VMOJI_FLAG_TX_DROP);
}

void telemetry_uart_irq(void) {
    uart_hw_t *hw = uart_get_hw(telemetry_uart());
    if ((hw->mis & UART_UARTMIS_TXMIS_BITS) == 0u) {
        return;
    }
    while ((hw->fr & UART_UARTFR_TXFF_BITS) == 0u) {
        std::uint8_t byte;
        if (!g_uart_tx.pop(byte)) {
            // Nothing left: stop asking to be interrupted, or this fires
            // continuously for as long as the FIFO has room.
            hw_clear_bits(&hw->imsc, UART_UARTIMSC_TXIM_BITS);
            return;
        }
        hw->dr = byte;
    }
}

void telemetry_service(void) {
    pump_links();

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

    if (now - g.last_identity_us >= kIdentityIntervalUs) {
        telemetry_send_identity();
        g.last_identity_us = now;
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

void telemetry_send_identity(void) {
    // Fixed "ID " prefix so the host can recognise this without guessing. The
    // chip serial is the useful part: it names one physical board, which is
    // what distinguishes a live demo from a convincing simulation.
    char board_id[2 * PICO_UNIQUE_BOARD_ID_SIZE_BYTES + 1] = {0};
    pico_get_unique_board_id_string(board_id, sizeof(board_id));

    char line[96];
    std::snprintf(line, sizeof(line), "ID vmoji %s sha=%s board=%s",
                  VMOJI_VERSION, VMOJI_GIT_SHA, board_id);
    telemetry_log(line);
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
