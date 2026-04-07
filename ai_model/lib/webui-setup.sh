#!/bin/bash

# webui-setup.sh - Install and configure Open WebUI
# Part of the AI Model Setup Scripts

set -e

# Source common utilities if not already loaded
if ! declare -f print_header >/dev/null 2>&1; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
        source "$SCRIPT_DIR/common.sh"
    else
        # Fallback: define minimal functions
        print_info() { echo "[INFO] $1"; }
        print_status() { echo "[SUCCESS] $1"; }
        print_warning() { echo "[WARNING] $1"; }
        print_error() { echo "[ERROR] $1"; }
        print_header() { echo -e "\n========================================\n$1\n========================================\n"; }
    fi
fi

# Define print_success as alias for print_status if needed
if ! declare -f print_success >/dev/null 2>&1; then
    print_success() { print_status "$1"; }
fi

# Configuration
WEBUI_PORT=38080
OLLAMA_URL="http://host.docker.internal:31434"
CONTAINER_NAME="open-webui"
WEBUI_IMAGE="ghcr.io/open-webui/open-webui:webui_main"
HEALTH_CHECK_TIMEOUT=60

# Check if Docker is installed and running
check_docker() {
    print_info "Checking Docker installation..."

    # Check if Docker.app exists on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ ! -d "/Applications/Docker.app" ]; then
            print_error "Docker.app not found in /Applications/"
            print_info "Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
            return 1
        fi
    fi

    # Check if docker command is available
    if ! command -v docker &> /dev/null; then
        print_error "docker command not found in PATH"
        print_info "Please ensure Docker is properly installed"
        return 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_warning "Docker daemon is not running"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            print_info "Starting Docker Desktop..."
            open -a Docker

            print_info "Waiting for Docker daemon to start..."
            local wait_time=0
            local max_wait=60

            while ! docker info &> /dev/null; do
                if [ $wait_time -ge $max_wait ]; then
                    print_error "Docker daemon failed to start within ${max_wait} seconds"
                    return 1
                fi

                echo -n "."
                sleep 2
                wait_time=$((wait_time + 2))
            done
            echo ""

            print_success "Docker daemon started successfully"
        else
            print_error "Please start Docker manually"
            return 1
        fi
    else
        print_success "Docker is installed and running"
    fi

    return 0
}

# Install Open WebUI container
install_open_webui() {
    print_info "Installing Open WebUI..."

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warning "Container '${CONTAINER_NAME}' already exists"

        # Check if it's running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            print_info "Container is already running"
            return 0
        else
            print_info "Starting existing container..."
            if docker start "${CONTAINER_NAME}" &> /dev/null; then
                print_success "Container started successfully"
                return 0
            else
                print_warning "Failed to start existing container, removing it..."
                docker rm -f "${CONTAINER_NAME}" &> /dev/null
            fi
        fi
    fi

    # Pull the latest image
    print_info "Pulling Open WebUI image..."
    if ! docker pull "${WEBUI_IMAGE}"; then
        print_error "Failed to pull Open WebUI image"
        return 1
    fi

    # Run the container
    print_info "Starting Open WebUI container..."
    if docker run -d \
        --name "${CONTAINER_NAME}" \
        -p "${WEBUI_PORT}:8080" \
        -e OLLAMA_BASE_URL="${OLLAMA_URL}" \
        -v open-webui:/app/backend/data \
        --restart unless-stopped \
        "${WEBUI_IMAGE}" &> /dev/null; then
        print_success "Open WebUI container started successfully"
        return 0
    else
        print_error "Failed to start Open WebUI container"
        return 1
    fi
}

# Check if WebUI is accessible
check_webui_health() {
    print_info "Checking Open WebUI health..."

    local wait_time=0
    local webui_url="http://localhost:${WEBUI_PORT}"

    print_info "Waiting for Open WebUI to become accessible (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."

    while [ $wait_time -lt $HEALTH_CHECK_TIMEOUT ]; do
        if curl -s -o /dev/null -w "%{http_code}" "${webui_url}" | grep -q "200\|302\|401"; then
            echo ""
            print_success "Open WebUI is accessible at ${webui_url}"
            return 0
        fi

        echo -n "."
        sleep 2
        wait_time=$((wait_time + 2))
    done

    echo ""
    print_error "Open WebUI failed to become accessible within ${HEALTH_CHECK_TIMEOUT} seconds"
    print_info "You can check the logs with: docker logs ${CONTAINER_NAME}"
    return 1
}

# Configure Open WebUI
configure_webui() {
    print_info "Configuring Open WebUI..."

    # Print configuration instructions
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Open WebUI Configuration${NC}                                   ${BLUE}║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  1. Open http://localhost:${WEBUI_PORT} in your browser            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  2. Create an admin account (first user becomes admin)    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  3. The WebUI is already connected to Ollama at:          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}     ${OLLAMA_URL}                 ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  4. Your models should automatically appear in the UI     ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_success "Open WebUI is ready to use!"
}

# Main execution
webui_main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}          ${GREEN}Open WebUI Setup${NC}                                    ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check Docker
    if ! check_docker; then
        print_error "Docker check failed"
        exit 1
    fi

    echo ""

    # Install Open WebUI
    if ! install_open_webui; then
        print_error "Open WebUI installation failed"
        exit 1
    fi

    echo ""

    # Health check
    if ! check_webui_health; then
        print_error "Open WebUI health check failed"
        exit 1
    fi

    echo ""

    # Configure
    configure_webui

    echo ""
    print_success "Open WebUI setup completed successfully!"
    echo ""
}

# Wrapper function to be called from orchestrator
setup_webui() {
    webui_main "$@"
}

# Only run webui_main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    webui_main "$@"
fi
