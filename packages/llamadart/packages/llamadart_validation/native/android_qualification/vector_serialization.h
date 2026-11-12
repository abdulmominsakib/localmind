#pragma once

#include <cmath>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace android_qualification {
// Shared with the model-free producer fixture so the consumer's transport bound
// is checked against the actual native normalization and serialization precision.
inline std::string normalized_vector_json(const std::vector<float> & raw) {
    if (raw.size() != 768) throw std::runtime_error("embedding width mismatch");
    double norm = 0;
    for (float value : raw) {
        if (!std::isfinite(value)) throw std::runtime_error("nonfinite embedding");
        norm += double(value) * value;
    }
    norm = std::sqrt(norm);
    if (!std::isfinite(norm) || norm <= 0) throw std::runtime_error("invalid embedding norm");
    std::ostringstream vector;
    vector << std::setprecision(17);
    for (size_t index = 0; index < raw.size(); index++) {
        if (index) vector << ",";
        vector << double(raw[index]) / norm;
    }
    return vector.str();
}
} // namespace android_qualification
