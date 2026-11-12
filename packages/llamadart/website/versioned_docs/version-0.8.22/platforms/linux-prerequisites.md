---
title: Linux Prerequisites
---

Linux runtime requirements depend on selected backend modules.

## Dependency mapping

- `cpu`: no extra GPU runtime dependency.
- `vulkan`: Vulkan loader and valid GPU driver/ICD.
- `blas`: OpenBLAS runtime (`libopenblas.so.0`).
- `cuda`: NVIDIA driver + compatible CUDA runtime libs.
- `hip`: ROCm runtime libs (for example `libhipblas.so.2`).

## Package examples

Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y libvulkan1 vulkan-tools libopenblas0
```

Fedora/RHEL/CentOS:

```bash
sudo dnf install -y vulkan-loader vulkan-tools openblas
```

Arch Linux:

```bash
sudo pacman -S --needed vulkan-icd-loader vulkan-tools openblas
```

## Quick link check

```bash
for f in .dart_tool/lib/libggml-*.so; do
  LD_LIBRARY_PATH=.dart_tool/lib ldd "$f" | grep "not found" || true
done
```

For containerized checks, see repository scripts under `docker/validation` and
`scripts/check_native_link_deps.sh`.
