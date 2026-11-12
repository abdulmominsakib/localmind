#pragma once

#include "ggml-backend.h"
#include <stdexcept>
#include <string>

namespace android_qualification {

inline ggml_backend_dev_t select_vulkan_device() {
    ggml_backend_dev_t selected = nullptr;
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        auto device = ggml_backend_dev_get(i);
        const auto type = ggml_backend_dev_type(device);
        // Mobile Vulkan GPUs use host memory and are reported as IGPU.
        if (type != GGML_BACKEND_DEVICE_TYPE_GPU && type != GGML_BACKEND_DEVICE_TYPE_IGPU) continue;
        const auto * registry = ggml_backend_reg_name(ggml_backend_dev_backend_reg(device));
        if (!registry || std::string(registry) != "Vulkan") continue;
        if (selected) throw std::runtime_error("multiple Vulkan devices require explicit admission");
        selected = device;
    }
    return selected;
}

} // namespace android_qualification
