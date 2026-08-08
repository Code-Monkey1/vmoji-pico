// Host-side self-test for blink/telemetry_frame.h.
//
// Two jobs:
//
//  1. Prove the framing header compiles and behaves identically off-target, so
//     protocol changes can be tested without flashing hardware.
//  2. Emit reference vectors that tools/dashboard/tests/test_protocol.py checks
//     the Python parser against. A wire format with two independent
//     implementations needs a shared source of truth, or the two drift apart and
//     the bug shows up as "the dashboard is wrong" three weeks later.
//
// Build and run:
//   g++ -std=c++17 -Wall -Wextra -I blink tools/protocol_selftest.cpp -o /tmp/selftest
//   /tmp/selftest              # human-readable checks
//   /tmp/selftest --vectors    # machine-readable vectors for the Python test

#include "telemetry_frame.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void check(bool condition, const char *what) {
    std::printf("[%s] %s\n", condition ? " ok " : "FAIL", what);
    if (!condition) {
        ++g_failures;
    }
}

std::string to_hex(const std::uint8_t *data, std::size_t size) {
    static const char *digits = "0123456789abcdef";
    std::string out;
    out.reserve(size * 2);
    for (std::size_t i = 0; i < size; ++i) {
        out.push_back(digits[data[i] >> 4]);
        out.push_back(digits[data[i] & 0x0Fu]);
    }
    return out;
}

vmoji::StatusPayload sample_status() {
    vmoji::StatusPayload s{};
    s.uptime_ms = 123456u;
    s.scan_count = 98765u;
    s.refresh_chz = 31250u;  // 312.50 Hz
    s.period_mean_us = 3200u;
    s.period_min_us = 3180u;
    s.period_max_us = 3410u;
    s.jitter_pp_us = 230u;
    s.die_temp_c_x100 = 2731;  // 27.31 C
    s.cmd_ok = 12u;
    s.cmd_err = 3u;
    s.rx_bytes = 4096u;
    s.row_dwell_us = 400u;
    s.glyph_id = 2u;
    s.flags = VMOJI_FLAG_ACTIVITY;
    return s;
}

// --------------------------------------------------------------------------

void test_crc_known_vector() {
    // CRC-16/CCITT-FALSE over the ASCII string "123456789" is 0x29B1.
    const char *input = "123456789";
    const std::uint16_t crc = vmoji::crc16(
        vmoji::ByteView{reinterpret_cast<const std::uint8_t *>(input), std::strlen(input)});
    std::printf("       crc16(\"123456789\") = 0x%04X (expected 0x29B1)\n", crc);
    check(crc == 0x29B1u, "CRC-16/CCITT-FALSE matches the standard check value");
}

void test_roundtrip() {
    const vmoji::StatusPayload sent = sample_status();
    std::uint8_t buffer[vmoji::kMaxFrame];
    const std::size_t length =
        vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Status, 7, sent);

    check(length == sizeof(vmoji::StatusPayload) + vmoji::kOverhead,
          "encoded length is payload plus 8 bytes of overhead");

    vmoji::DecodedFrame decoded{};
    const auto status = vmoji::decode_frame(vmoji::ByteView{buffer, length}, decoded);
    check(status == vmoji::DecodeStatus::Ok, "round-trips through the decoder");
    check(decoded.id == vmoji::MsgId::Status, "message id survives");
    check(decoded.seq == 7, "sequence number survives");
    check(decoded.payload.size == sizeof(vmoji::StatusPayload), "payload size survives");
    check(decoded.consumed == length, "decoder consumes exactly the frame");

    vmoji::StatusPayload received{};
    std::memcpy(&received, decoded.payload.data, sizeof(received));
    check(received.uptime_ms == sent.uptime_ms && received.jitter_pp_us == sent.jitter_pp_us &&
              received.die_temp_c_x100 == sent.die_temp_c_x100,
          "payload fields decode to the values that were encoded");
}

void test_resync_after_leading_garbage() {
    // The firmware prints an ASCII banner before telemetry starts, so the very
    // first thing the parser ever sees is unframed noise.
    const char *noise = "===== 8x8 VMOJI =====\r\n";
    std::vector<std::uint8_t> stream(noise, noise + std::strlen(noise));

    std::uint8_t frame[vmoji::kMaxFrame];
    const std::size_t length =
        vmoji::encode_frame(frame, sizeof(frame), vmoji::MsgId::Status, 1, sample_status());
    stream.insert(stream.end(), frame, frame + length);

    vmoji::DecodedFrame decoded{};
    const auto status =
        vmoji::decode_frame(vmoji::ByteView{stream.data(), stream.size()}, decoded);
    check(status == vmoji::DecodeStatus::Ok, "finds a frame after leading ASCII noise");
    check(decoded.consumed == stream.size(), "consumes the noise along with the frame");
}

void test_corrupted_frame_is_rejected() {
    std::uint8_t buffer[vmoji::kMaxFrame];
    const std::size_t length =
        vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Status, 1, sample_status());
    buffer[10] ^= 0xFFu;  // flip a payload byte

    vmoji::DecodedFrame decoded{};
    const auto status = vmoji::decode_frame(vmoji::ByteView{buffer, length}, decoded);
    check(status == vmoji::DecodeStatus::BadCrc, "a single flipped payload bit fails the CRC");
    check(decoded.consumed == 2, "a bad frame advances past the sync word to resync");
}

void test_partial_frame_waits() {
    std::uint8_t buffer[vmoji::kMaxFrame];
    const std::size_t length =
        vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Status, 1, sample_status());

    vmoji::DecodedFrame decoded{};
    const auto status = vmoji::decode_frame(vmoji::ByteView{buffer, length - 3}, decoded);
    check(status == vmoji::DecodeStatus::NeedMoreData,
          "a truncated frame asks for more data instead of failing");
    check(decoded.consumed == 0, "a truncated frame consumes nothing");
}

void test_false_sync_inside_payload() {
    // A payload containing the sync word must not be able to derail the parser.
    std::uint8_t payload[16];
    std::memset(payload, 0, sizeof(payload));
    payload[3] = vmoji::kSync0;
    payload[4] = vmoji::kSync1;

    std::uint8_t buffer[vmoji::kMaxFrame];
    const std::size_t length = vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Log, 9,
                                                   payload, sizeof(payload));

    vmoji::DecodedFrame decoded{};
    const auto status = vmoji::decode_frame(vmoji::ByteView{buffer, length}, decoded);
    check(status == vmoji::DecodeStatus::Ok && decoded.payload.size == sizeof(payload),
          "a sync word inside the payload does not confuse the decoder");
}

void test_struct_layout() {
    check(sizeof(vmoji::StatusPayload) == 32, "StatusPayload is 32 bytes");
    check(sizeof(vmoji::FrameBufferPayload) == 8, "FrameBufferPayload is 8 bytes");
    check(offsetof(vmoji::StatusPayload, die_temp_c_x100) == 18,
          "die_temp_c_x100 sits at offset 18");
}

// --------------------------------------------------------------------------

void print_vectors() {
    std::uint8_t buffer[vmoji::kMaxFrame];

    const char *crc_input = "123456789";
    std::printf("crc16 %s %04x\n", crc_input,
                vmoji::crc16(vmoji::ByteView{
                    reinterpret_cast<const std::uint8_t *>(crc_input), std::strlen(crc_input)}));

    std::size_t length =
        vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Status, 7, sample_status());
    std::printf("status %s\n", to_hex(buffer, length).c_str());

    vmoji::FrameBufferPayload fb{};
    for (int i = 0; i < 8; ++i) {
        fb.row[i] = static_cast<std::uint8_t>(0x81u >> (i % 4));
    }
    length = vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::FrameBuffer, 8, fb);
    std::printf("framebuffer %s\n", to_hex(buffer, length).c_str());

    const char *text = "vmoji telemetry online";
    length = vmoji::encode_frame(buffer, sizeof(buffer), vmoji::MsgId::Log, 9, text,
                                 std::strlen(text));
    std::printf("log %s\n", to_hex(buffer, length).c_str());
}

}  // namespace

int main(int argc, char **argv) {
    if (argc > 1 && std::strcmp(argv[1], "--vectors") == 0) {
        print_vectors();
        return 0;
    }

    test_crc_known_vector();
    test_struct_layout();
    test_roundtrip();
    test_resync_after_leading_garbage();
    test_corrupted_frame_is_rejected();
    test_partial_frame_waits();
    test_false_sync_inside_payload();

    std::printf("\n%s\n", g_failures == 0 ? "all checks passed"
                                          : "FAILURES PRESENT");
    return g_failures == 0 ? 0 : 1;
}
