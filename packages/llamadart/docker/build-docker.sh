#!/bin/bash

# Build and run llamadart examples using Docker
# This script is intended to be run from the docker/ directory or the project root.

set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"

SHOW_HELP() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  basic-run    Build and run the CLI basic example"
    echo "  chat-build   Build the Flutter Chat app for Linux"
    echo "  clean        Remove Docker images and local build artifacts"
    echo "  help         Show this help message"
}

case "$1" in
    basic-run)
        echo "Building and running CLI basic example..."
        docker compose -f "$COMPOSE_FILE" run --rm basic-app
        ;;
    chat-build)
        echo "Building Flutter Chat app for Linux..."
        docker compose -f "$COMPOSE_FILE" build chat-app
        echo "Build complete. The binary is inside the docker image."
        echo "To run it, you need an X11 server and appropriate permissions."
        ;;
    clean)
        echo "Cleaning up..."
        docker compose -f "$COMPOSE_FILE" down --rmi local
        ;;
    *)
        SHOW_HELP
        ;;
esac
