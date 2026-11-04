# syntax=docker/dockerfile:1
FROM ghcr.io/cirruslabs/flutter:stable AS base

USER root

# Install Linux build dependencies for Flutter and llamadart
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    build-essential \
    clang \
    git \
    libglu1-mesa \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    pkg-config \
    unzip \
    libvulkan1 \
    mesa-vulkan-drivers \
    vulkan-tools \
    lld \
    && rm -rf /var/lib/apt/lists/*

# Fix for Flutter Linux build: Link lld to llvm bin directory
RUN ln -s /usr/bin/ld.lld /usr/lib/llvm-18/bin/ld.lld || true
RUN ln -s /usr/bin/ld.lld /usr/lib/llvm-18/bin/ld || true

WORKDIR /app
COPY . .

# Initialize dependencies and binaries
RUN flutter pub get
RUN flutter precache --linux
WORKDIR /app/example/basic_app
RUN flutter pub get
WORKDIR /app/example/chat_app
RUN flutter pub get
WORKDIR /app

# ---------------------------------------------------------
# CLI Example Stage
# ---------------------------------------------------------
FROM base AS basic-app
WORKDIR /app/example/basic_app
CMD ["dart", "run", "bin/llamadart_basic_example.dart"]

# ---------------------------------------------------------
# Chat App Build Stage
# ---------------------------------------------------------
FROM base AS chat-app-build
WORKDIR /app/example/chat_app
RUN flutter create --platforms=linux .
RUN flutter pub get
RUN flutter build linux --release

# ---------------------------------------------------------
# Final runtime for Chat App (requires X11/Wayland)
# ---------------------------------------------------------
FROM ubuntu:22.04 AS chat-app-run
RUN apt-get update && apt-get install -y \
    libgtk-3-0 \
    libglu1-mesa \
    libvulkan1 \
    mesa-vulkan-drivers \
    libcanberra-gtk3-module \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Copy the compiled bundle from the build stage
COPY --from=chat-app-build /app/example/chat_app/build/linux/*/release/bundle /app/bundle

# The app needs an X server to run
CMD ["./bundle/llamadart_chat_example"]
