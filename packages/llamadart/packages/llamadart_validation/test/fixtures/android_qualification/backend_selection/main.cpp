#include "backend_selection.h"
#include <iostream>
#include <vector>

struct ggml_backend_reg { const char * name; };
struct ggml_backend_device {
    enum ggml_backend_dev_type type;
    ggml_backend_reg_t registry;
    const char * name;
};
static std::vector<ggml_backend_dev_t> devices;
size_t ggml_backend_dev_count() { return devices.size(); }
ggml_backend_dev_t ggml_backend_dev_get(size_t index) { return devices.at(index); }
enum ggml_backend_dev_type ggml_backend_dev_type(ggml_backend_dev_t device) { return device->type; }
ggml_backend_reg_t ggml_backend_dev_backend_reg(ggml_backend_dev_t device) { return device->registry; }
const char * ggml_backend_reg_name(ggml_backend_reg_t registry) { return registry->name; }

int main(int argc, char ** argv) {
    if (argc != 2) return 2;
    const std::string test = argv[1];
    ggml_backend_reg vulkan{"Vulkan"}, opencl{"OpenCL"}, cpu_registry{"CPU"}, missing{nullptr};
    ggml_backend_device mali{GGML_BACKEND_DEVICE_TYPE_IGPU, &vulkan, "Mali-G68"};
    ggml_backend_device discrete{GGML_BACKEND_DEVICE_TYPE_GPU, &vulkan, "Discrete GPU"};
    ggml_backend_device other_mali{GGML_BACKEND_DEVICE_TYPE_IGPU, &opencl, "Mali-G68"};
    ggml_backend_device cpu{GGML_BACKEND_DEVICE_TYPE_CPU, &cpu_registry, "CPU"};
    ggml_backend_device misleading_cpu{GGML_BACKEND_DEVICE_TYPE_CPU, &vulkan, "Vulkan0"};
    ggml_backend_device accelerator{GGML_BACKEND_DEVICE_TYPE_ACCEL, &vulkan, "Vulkan0"};
    ggml_backend_device meta{GGML_BACKEND_DEVICE_TYPE_META, &vulkan, "Vulkan0"};
    ggml_backend_device unnamed{GGML_BACKEND_DEVICE_TYPE_IGPU, &missing, "Mali-G68"};
    ggml_backend_dev_t expected = nullptr;
    bool ambiguous = false;
    if (test == "mali-integrated") { devices = {&mali}; expected = &mali; }
    else if (test == "discrete") { devices = {&discrete}; expected = &discrete; }
    else if (test == "shared-device-name") { devices = {&other_mali, &mali}; expected = &mali; }
    else if (test == "cpu-plus-mali") { devices = {&cpu, &mali}; expected = &mali; }
    else if (test == "cpu-only") devices = {&cpu};
    else if (test == "cpu-with-vulkan-registry") devices = {&misleading_cpu};
    else if (test == "opencl-only") devices = {&other_mali};
    else if (test == "accelerator") devices = {&accelerator};
    else if (test == "meta") devices = {&meta};
    else if (test == "missing-registry-name") devices = {&unnamed};
    else if (test == "no-devices") devices = {};
    else if (test == "multiple-integrated") { devices = {&mali, &mali}; ambiguous = true; }
    else if (test == "multiple-discrete") { devices = {&discrete, &discrete}; ambiguous = true; }
    else if (test == "mixed-vulkan-gpus") { devices = {&mali, &discrete}; ambiguous = true; }
    else return 2;
    try {
        auto selected = android_qualification::select_vulkan_device();
        if (ambiguous || selected != expected) return 1;
    } catch (const std::runtime_error & error) {
        if (!ambiguous || std::string(error.what()) != "multiple Vulkan devices require explicit admission") return 1;
    }
    std::cout << test << " passed\n";
    return 0;
}
