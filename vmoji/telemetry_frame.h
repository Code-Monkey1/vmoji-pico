// Binary telemetry framing shared by the RP2040 firmware and the host dashboard.
//
// The frame layout deliberately follows the same shape as GNSS receiver binary
// protocols (u-blox UBX, RTCM 3.x): a sync word so a listener can lock onto a
// byte stream mid-flight, an explicit length so the reader knows when a message
// ends, a message id for dispatch, a sequence number so the host can detect
// gaps, and a CRC so corrupted frames are dropped rather than misinterpreted.
//
//   offset  size  field
//   0       2     sync word 0xAA 0x55
//   2       2     payload length, u16 little-endian (payload only)
//   4       1     message id
//   5       1     sequence number, wraps at 256
//   6       N     payload
//   6+N     2     CRC-16/CCITT-FALSE over offsets [2, 6+N), u16 little-endian
//
// The CRC covers the length and id but not the sync word, so a false sync word
// appearing inside payload data cannot produce a frame that also passes the CRC.
//
// This header is C++17 and compiles both for the Pico (arm-none-eabi-g++) and
// for the host (see tools/protocol_selftest.cpp). Firmware C translation units
// reach it through the extern "C" wrapper in telemetry.h.

#ifndef VMOJI_TELEMETRY_FRAME_H
#define VMOJI_TELEMETRY_FRAME_H

#include "telemetry_flags.h"

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace vmoji {

// ---------------------------------------------------------------------------
// Framing constants
// ---------------------------------------------------------------------------

constexpr std::uint8_t kSync0 = 0xAAu;
constexpr std::uint8_t kSync1 = 0x55u;

constexpr std::size_t kHeaderSize = 6u;  // sync(2) + length(2) + id(1) + seq(1)
constexpr std::size_t kCrcSize = 2u;
constexpr std::size_t kOverhead = kHeaderSize + kCrcSize;

// Bounded so both sides can use fixed buffers with no dynamic allocation.
constexpr std::size_t kMaxPayload = 255u;
constexpr std::size_t kMaxFrame = kMaxPayload + kOverhead;

enum class MsgId : std::uint8_t {
    Status = 0x01,     // periodic health and timing metrics
    FrameBuffer = 0x02,  // current 8x8 bitmap
    Log = 0x03,        // free-form ASCII, for human-readable notes
    Ack = 0x10,        // response to a host command
};

// ---------------------------------------------------------------------------
// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no input/output reflection.
//
// The lookup table is built by the compiler, so it costs no startup code and
// lands in flash on the microcontroller.
// ---------------------------------------------------------------------------

namespace detail {

constexpr std::uint16_t crc16_byte(std::uint8_t index) {
    std::uint16_t crc = static_cast<std::uint16_t>(index) << 8;
    for (int bit = 0; bit < 8; ++bit) {
        const bool high_set = (crc & 0x8000u) != 0u;
        crc = static_cast<std::uint16_t>(crc << 1);
        if (high_set) {
            crc = static_cast<std::uint16_t>(crc ^ 0x1021u);
        }
    }
    return crc;
}

struct Crc16Table {
    std::uint16_t entry[256];

    constexpr Crc16Table() : entry{} {
        for (int i = 0; i < 256; ++i) {
            entry[i] = crc16_byte(static_cast<std::uint8_t>(i));
        }
    }
};

constexpr Crc16Table kCrc16Table{};

}  // namespace detail

// A non-owning view over bytes. This is std::span<const std::uint8_t> in C++20;
// spelled out by hand so the header stays C++17 for the Pico toolchain.
struct ByteView {
    const std::uint8_t* data;
    std::size_t size;
};

constexpr std::uint16_t crc16(ByteView bytes, std::uint16_t seed = 0xFFFFu) {
    std::uint16_t crc = seed;
    for (std::size_t i = 0; i < bytes.size; ++i) {
        const std::uint8_t index =
            static_cast<std::uint8_t>((crc >> 8) ^ bytes.data[i]);
        crc = static_cast<std::uint16_t>((crc << 8) ^ detail::kCrc16Table.entry[index]);
    }
    return crc;
}

// ---------------------------------------------------------------------------
// Payloads
//
// Every field is explicitly sized and little-endian, and every struct is
// packed with a static_assert on its size, because the whole point of a wire
// format is that both ends agree byte for byte. Relying on the compiler's
// default padding across two different architectures is how protocols break.
// ---------------------------------------------------------------------------

#pragma pack(push, 1)

// Health and real-time timing metrics for one reporting interval.
struct StatusPayload {
    std::uint32_t uptime_ms;
    std::uint32_t scan_count;       // completed matrix scans since boot
    std::uint16_t refresh_chz;      // measured scan rate, centi-hertz (12345 = 123.45 Hz)
    std::uint16_t period_mean_us;   // per-scan wall time over the interval
    std::uint16_t period_min_us;
    std::uint16_t period_max_us;
    std::uint16_t jitter_pp_us;     // peak-to-peak: max - min
    std::int16_t die_temp_c_x100;   // RP2040 internal sensor, hundredths of a degree
    std::uint16_t cmd_ok;           // commands accepted since boot
    std::uint16_t cmd_err;          // commands rejected since boot
    std::uint32_t rx_bytes;         // bytes received on either link
    std::uint16_t row_dwell_us;     // current per-row lit time
    std::uint8_t glyph_id;
    std::uint8_t flags;
};
static_assert(sizeof(StatusPayload) == 32, "StatusPayload must stay 32 bytes on the wire");

// Bit c of row[r] is pixel (r, c); bit 7 is column 0.
struct FrameBufferPayload {
    std::uint8_t row[8];
};
static_assert(sizeof(FrameBufferPayload) == 8, "FrameBufferPayload must stay 8 bytes");

#pragma pack(pop)

enum StatusFlag : std::uint8_t {
    kFlagActivity = VMOJI_FLAG_ACTIVITY,
    kFlagOverrun = VMOJI_FLAG_OVERRUN,
    kFlagPaused = VMOJI_FLAG_PAUSED,
    kFlagTxDrop = VMOJI_FLAG_TX_DROP,
};

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

inline void put_u16_le(std::uint8_t* out, std::uint16_t value) {
    out[0] = static_cast<std::uint8_t>(value & 0xFFu);
    out[1] = static_cast<std::uint8_t>((value >> 8) & 0xFFu);
}

constexpr std::uint16_t get_u16_le(const std::uint8_t* in) {
    return static_cast<std::uint16_t>(in[0]) |
           static_cast<std::uint16_t>(static_cast<std::uint16_t>(in[1]) << 8);
}

// Writes a complete frame into `out` and returns its total length, or 0 if the
// payload is too large or the buffer too small. Returning a length rather than
// writing to a stream keeps this testable on the host with no I/O.
inline std::size_t encode_frame(std::uint8_t* out, std::size_t out_capacity,
                                MsgId id, std::uint8_t seq,
                                const void* payload, std::size_t payload_size) {
    if (payload_size > kMaxPayload) {
        return 0;
    }
    const std::size_t total = payload_size + kOverhead;
    if (out_capacity < total) {
        return 0;
    }

    out[0] = kSync0;
    out[1] = kSync1;
    put_u16_le(out + 2, static_cast<std::uint16_t>(payload_size));
    out[4] = static_cast<std::uint8_t>(id);
    out[5] = seq;
    if (payload_size > 0 && payload != nullptr) {
        std::memcpy(out + kHeaderSize, payload, payload_size);
    }

    // CRC covers everything except the sync word and the CRC itself.
    const std::uint16_t crc = crc16(ByteView{out + 2, payload_size + kHeaderSize - 2});
    put_u16_le(out + kHeaderSize + payload_size, crc);
    return total;
}

// Convenience overload for a typed payload.
template <typename Payload>
inline std::size_t encode_frame(std::uint8_t* out, std::size_t out_capacity,
                                MsgId id, std::uint8_t seq, const Payload& payload) {
    return encode_frame(out, out_capacity, id, seq, &payload, sizeof(Payload));
}

// ---------------------------------------------------------------------------
// Decoding
//
// Used by the host self-test and available to the firmware. The production host
// parser lives in tools/dashboard/protocol.py; both are validated against the
// same vectors so the two implementations cannot silently diverge.
// ---------------------------------------------------------------------------

enum class DecodeStatus {
    Ok,
    NeedMoreData,   // not enough bytes yet; keep the buffer and wait
    NoSync,         // no sync word in the buffer at all
    BadCrc,         // framing looked right but integrity failed
    BadLength,      // length field exceeds the protocol maximum
};

struct DecodedFrame {
    MsgId id;
    std::uint8_t seq;
    ByteView payload;
    std::size_t consumed;  // bytes to drop from the front of the input
};

// Attempts to decode one frame from the front of `in`. On NoSync or BadCrc the
// caller should advance by `consumed` and try again, which is how a reader
// recovers from joining a stream mid-frame or from line noise.
inline DecodeStatus decode_frame(ByteView in, DecodedFrame& out) {
    std::size_t start = 0;
    for (;;) {
        // Find the sync word.
        while (start + 1 < in.size &&
               !(in.data[start] == kSync0 && in.data[start + 1] == kSync1)) {
            ++start;
        }
        if (start + 1 >= in.size) {
            out.consumed = start;  // keep at most one trailing byte
            return DecodeStatus::NoSync;
        }

        const std::size_t available = in.size - start;
        if (available < kHeaderSize) {
            out.consumed = start;
            return DecodeStatus::NeedMoreData;
        }

        const std::uint16_t payload_size = get_u16_le(in.data + start + 2);
        if (payload_size > kMaxPayload) {
            // Not a real header; skip this sync word and keep looking.
            start += 2;
            continue;
        }

        const std::size_t total = payload_size + kOverhead;
        if (available < total) {
            out.consumed = start;
            return DecodeStatus::NeedMoreData;
        }

        const std::uint16_t expected =
            crc16(ByteView{in.data + start + 2, payload_size + kHeaderSize - 2});
        const std::uint16_t actual = get_u16_le(in.data + start + kHeaderSize + payload_size);
        if (expected != actual) {
            out.consumed = start + 2;  // resync past this false positive
            return DecodeStatus::BadCrc;
        }

        out.id = static_cast<MsgId>(in.data[start + 4]);
        out.seq = in.data[start + 5];
        out.payload = ByteView{in.data + start + kHeaderSize, payload_size};
        out.consumed = start + total;
        return DecodeStatus::Ok;
    }
}

}  // namespace vmoji

#endif  // VMOJI_TELEMETRY_FRAME_H
