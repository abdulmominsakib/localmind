#include "../../../native/android_qualification/vector_serialization.h"
#include <cstdint>
#include <iostream>
#include <limits>
#include <unistd.h>

int main(int argc, char ** argv) {
    if (argc != 3) return 1;
    const uint16_t endian = 1;
    if (*reinterpret_cast<const unsigned char *>(&endian) != 1) return 2;
    int sequence = 0;
    auto emit = [&](const std::string & event, const std::string & fields = "") {
        std::cout << "{\"schema\":1,\"binding\":\"" << argv[1]
            << "\",\"case_id\":\"" << argv[2] << "\",\"pid\":" << getpid()
            << ",\"sequence\":" << sequence++ << ",\"event\":\"" << event << "\""
            << fields << "}\n";
    };
    emit("started");
    for (int input = 0; input < 2; input++) {
        std::vector<float> raw(768);
        for (size_t index = 0; index < raw.size(); index++) {
            if (!input) {
                raw[index] = std::nextafter(float(int(index % 17) - 8) * 0.1234567f,
                                           std::numeric_limits<float>::infinity());
            } else {
                const float values[] = {std::numeric_limits<float>::max() * 0.25f,
                    std::numeric_limits<float>::min() * 2, 0, -1, 2e-20f, -3e20f};
                raw[index] = values[index % 6];
            }
        }
        static const char digits[] = "0123456789abcdef";
        const auto * bytes = reinterpret_cast<const unsigned char *>(raw.data());
        std::string hex;
        for (size_t index = 0; index < raw.size() * sizeof(float); index++) {
            hex += digits[bytes[index] >> 4]; hex += digits[bytes[index] & 15];
        }
        const std::string fields = ",\"input\":" + std::to_string(input) +
            ",\"phase\":\"probe\",\"tokens\":" + (input ? "46" : "9");
        emit("embedding_raw", fields + ",\"vector_f32_le_hex\":\"" + hex + "\"");
        emit("embedding", fields + ",\"operation_ms\":0,\"vector\":[" +
            android_qualification::normalized_vector_json(raw) + "]");
    }
    emit("finished");
    return 0;
}
