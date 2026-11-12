#pragma once

#include <cstddef>

// The model-free fake implements only the pinned backend selection boundary.
enum ggml_backend_dev_type {
    GGML_BACKEND_DEVICE_TYPE_CPU,
    GGML_BACKEND_DEVICE_TYPE_GPU,
    GGML_BACKEND_DEVICE_TYPE_IGPU,
    GGML_BACKEND_DEVICE_TYPE_ACCEL,
    GGML_BACKEND_DEVICE_TYPE_META,
};
using ggml_backend_dev_t = struct ggml_backend_device *;
using ggml_backend_reg_t = struct ggml_backend_reg *;
size_t ggml_backend_dev_count();
ggml_backend_dev_t ggml_backend_dev_get(size_t index);
enum ggml_backend_dev_type ggml_backend_dev_type(ggml_backend_dev_t device);
ggml_backend_reg_t ggml_backend_dev_backend_reg(ggml_backend_dev_t device);
const char * ggml_backend_reg_name(ggml_backend_reg_t registry);
