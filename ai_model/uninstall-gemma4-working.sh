#!/bin/bash
#
# Uninstaller for Gemma 4 26B + llama.cpp + OpenCode Setup
#
# Removes all components installed by setup-gemma4-working.sh:
# - llama.cpp build directory
# - OpenCode custom build (restores backup)
# - OpenCode build directory
# - Configuration files
# - Downloaded Gemma 4 models
# - HuggingFace CLI (pipx installation)
# - launchd service
# - Running llama-server processes
# - Log files and PID files
#
# Author: AI-Generated
# License: MIT
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Configuration (must match setup script)
LLAMA_BUILD_DIR="/tmp/llama-cpp-build"
OPENCODE_BUILD_DIR="/tmp/opencode-build"
PORT="3456"
MODEL_REPO="ggml-org/gemma-4-26B-A4B-it-GGUF"

# Print functions
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-true}"

    if [ "$default" = "true" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        read -p "$prompt" response
        case "${response:-}" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            "" )
                if [ "$default" = "true" ]; then
                    return 0
                else
                    return 1
                fi
                ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

get_size_mb() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "0"
        return
    fi

    if [ -f "$path" ]; then
        du -sm "$path" 2>/dev/null | awk '{print $1}' || echo "0"
    elif [ -d "$path" ]; then
        du -sm "$path" 2>/dev/null | awk '{print $1}' || echo "0"
    else
        echo "0"
    fi
}

format_size() {
    local size_mb="$1"
    if [ "$size_mb" -lt 1024 ]; then
        echo "${size_mb}MB"
    else
        local size_gb=$((size_mb / 1024))
        echo "${size_gb}GB"
    fi
}

# Main header
print_header "Gemma 4 Working Setup Uninstaller"

echo "This script will remove components installed by setup-gemma4-working.sh"
echo ""

# Scan system
print_info "Scanning system for installed components..."
echo ""

# Track what we find
declare -A FOUND_COMPONENTS
TOTAL_SIZE_MB=0

# Check llama.cpp build
if [ -d "$LLAMA_BUILD_DIR" ]; then
    SIZE=$(get_size_mb "$LLAMA_BUILD_DIR")
    TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
    FOUND_COMPONENTS["llama_build"]="$SIZE"
    print_status "llama.cpp build found ($(format_size $SIZE)): $LLAMA_BUILD_DIR"
fi

# Check OpenCode build directory
if [ -d "$OPENCODE_BUILD_DIR" ]; then
    SIZE=$(get_size_mb "$OPENCODE_BUILD_DIR")
    TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
    FOUND_COMPONENTS["opencode_build"]="$SIZE"
    print_status "OpenCode build directory found ($(format_size $SIZE)): $OPENCODE_BUILD_DIR"
fi

# Check OpenCode custom build
CUSTOM_BUILD_MARKER="$HOME/.opencode/bin/.custom-build-pr16531"
if [ -f "$CUSTOM_BUILD_MARKER" ]; then
    FOUND_COMPONENTS["opencode_custom"]="1"
    print_status "OpenCode custom build marker found"
fi

if [ -f "$HOME/.opencode/bin/opencode.backup" ]; then
    FOUND_COMPONENTS["opencode_backup"]="1"
    print_status "OpenCode backup found"
fi

# Check configuration files
CONFIG_FILES=()
if [ -f "$HOME/.config/opencode/opencode.jsonc" ]; then
    CONFIG_FILES+=("$HOME/.config/opencode/opencode.jsonc")
fi
if [ -f "$HOME/.config/opencode/AGENTS.md" ]; then
    CONFIG_FILES+=("$HOME/.config/opencode/AGENTS.md")
fi
if [ -f "$HOME/.config/opencode/prompts/build.txt" ]; then
    CONFIG_FILES+=("$HOME/.config/opencode/prompts/build.txt")
fi

if [ ${#CONFIG_FILES[@]} -gt 0 ]; then
    FOUND_COMPONENTS["config_files"]="${#CONFIG_FILES[@]}"
    print_status "Configuration files found: ${#CONFIG_FILES[@]}"
fi

# Check for downloaded models
HF_CACHE="$HOME/.cache/huggingface/hub"
MODEL_CACHE_PATH="$HF_CACHE/models--ggml-org--gemma-4-26B-A4B-it-GGUF"

if [ -d "$MODEL_CACHE_PATH" ]; then
    SIZE=$(get_size_mb "$MODEL_CACHE_PATH")
    TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
    FOUND_COMPONENTS["model_cache"]="$SIZE"
    print_status "Gemma 4 26B model found ($(format_size $SIZE)): $MODEL_CACHE_PATH"
fi

# Check for running llama-server
LLAMA_RUNNING=false
if lsof -ti:$PORT >/dev/null 2>&1; then
    LLAMA_RUNNING=true
    FOUND_COMPONENTS["llama_running"]="1"
    print_status "llama-server running on port $PORT"
fi

# Check for PID file
if [ -f "$HOME/.local/var/llama-server.pid" ]; then
    FOUND_COMPONENTS["pid_file"]="1"
    print_status "PID file found: $HOME/.local/var/llama-server.pid"
fi

# Check for log file
if [ -f "$HOME/.local/var/log/llama-server.log" ]; then
    SIZE=$(get_size_mb "$HOME/.local/var/log/llama-server.log")
    FOUND_COMPONENTS["log_file"]="$SIZE"
    print_status "Log file found ($(format_size $SIZE)): $HOME/.local/var/log/llama-server.log"
fi

# Check for launchd service
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.llamacpp.server.plist"
if [ -f "$LAUNCHD_PLIST" ]; then
    FOUND_COMPONENTS["launchd_plist"]="1"
    print_status "launchd service found: $LAUNCHD_PLIST"
fi

# Check for pipx huggingface-hub
if command -v pipx >/dev/null 2>&1; then
    if pipx list 2>/dev/null | grep -q "huggingface-hub"; then
        FOUND_COMPONENTS["pipx_hf"]="1"
        print_status "HuggingFace CLI (pipx) installed"
    fi
fi

echo ""

# Check if anything was found
if [ ${#FOUND_COMPONENTS[@]} -eq 0 ]; then
    print_info "No components found - system is clean"
    exit 0
fi

# Show total size
if [ $TOTAL_SIZE_MB -gt 0 ]; then
    print_info "Total disk space to reclaim: $(format_size $TOTAL_SIZE_MB)"
    echo ""
fi

# Prompt for each component
print_header "Select Components to Remove"

REMOVE_LLAMA_BUILD=false
REMOVE_OPENCODE_BUILD=false
REMOVE_OPENCODE_CUSTOM=false
RESTORE_OPENCODE_BACKUP=false
REMOVE_CONFIG=false
REMOVE_MODEL=false
REMOVE_LOGS=false
REMOVE_LAUNCHD=false
REMOVE_PIPX_HF=false

# llama.cpp build
if [ -n "${FOUND_COMPONENTS[llama_build]:-}" ]; then
    if prompt_yes_no "Remove llama.cpp build? ($(format_size ${FOUND_COMPONENTS[llama_build]}))" true; then
        REMOVE_LLAMA_BUILD=true
    fi
fi

# OpenCode build directory
if [ -n "${FOUND_COMPONENTS[opencode_build]:-}" ]; then
    if prompt_yes_no "Remove OpenCode build directory? ($(format_size ${FOUND_COMPONENTS[opencode_build]}))" true; then
        REMOVE_OPENCODE_BUILD=true
    fi
fi

# OpenCode custom build
if [ -n "${FOUND_COMPONENTS[opencode_custom]:-}" ]; then
    echo ""
    if [ -n "${FOUND_COMPONENTS[opencode_backup]:-}" ]; then
        print_info "You have a backup of the original OpenCode"
        if prompt_yes_no "Remove custom OpenCode build?" true; then
            REMOVE_OPENCODE_CUSTOM=true
            if prompt_yes_no "Restore original OpenCode from backup?" true; then
                RESTORE_OPENCODE_BACKUP=true
            fi
        fi
    else
        print_warning "No backup found - removing will uninstall OpenCode completely"
        if prompt_yes_no "Remove custom OpenCode build?" false; then
            REMOVE_OPENCODE_CUSTOM=true
        fi
    fi
fi

# Configuration files
if [ -n "${FOUND_COMPONENTS[config_files]:-}" ]; then
    echo ""
    if prompt_yes_no "Remove configuration files? (${FOUND_COMPONENTS[config_files]} files)" true; then
        REMOVE_CONFIG=true
    fi
fi

# Model cache
if [ -n "${FOUND_COMPONENTS[model_cache]:-}" ]; then
    echo ""
    print_warning "Model cache: $(format_size ${FOUND_COMPONENTS[model_cache]})"
    print_info "Models are stored in HuggingFace cache and can be reused"
    if prompt_yes_no "Remove downloaded Gemma 4 26B model?" false; then
        REMOVE_MODEL=true
    fi
fi

# Log files
if [ -n "${FOUND_COMPONENTS[log_file]:-}" ] || [ -n "${FOUND_COMPONENTS[pid_file]:-}" ]; then
    echo ""
    if prompt_yes_no "Remove log files and PID files?" true; then
        REMOVE_LOGS=true
    fi
fi

# launchd service
if [ -n "${FOUND_COMPONENTS[launchd_plist]:-}" ]; then
    echo ""
    if prompt_yes_no "Remove launchd service (auto-start on login)?" true; then
        REMOVE_LAUNCHD=true
    fi
fi

# pipx huggingface-hub
if [ -n "${FOUND_COMPONENTS[pipx_hf]:-}" ]; then
    echo ""
    print_info "HuggingFace CLI may be used by other tools"
    if prompt_yes_no "Uninstall HuggingFace CLI (pipx)?" false; then
        REMOVE_PIPX_HF=true
    fi
fi

# Show summary
echo ""
print_header "Uninstall Summary"

ACTIONS=()
if [ "$REMOVE_LLAMA_BUILD" = true ]; then
    ACTIONS+=("Remove llama.cpp build ($(format_size ${FOUND_COMPONENTS[llama_build]}))")
fi
if [ "$REMOVE_OPENCODE_BUILD" = true ]; then
    ACTIONS+=("Remove OpenCode build directory ($(format_size ${FOUND_COMPONENTS[opencode_build]}))")
fi
if [ "$REMOVE_OPENCODE_CUSTOM" = true ]; then
    if [ "$RESTORE_OPENCODE_BACKUP" = true ]; then
        ACTIONS+=("Remove custom OpenCode and restore backup")
    else
        ACTIONS+=("Remove custom OpenCode build")
    fi
fi
if [ "$REMOVE_CONFIG" = true ]; then
    ACTIONS+=("Remove ${FOUND_COMPONENTS[config_files]} configuration files")
fi
if [ "$REMOVE_MODEL" = true ]; then
    ACTIONS+=("Remove Gemma 4 26B model ($(format_size ${FOUND_COMPONENTS[model_cache]}))")
fi
if [ "$REMOVE_LOGS" = true ]; then
    ACTIONS+=("Remove log files and PID files")
fi
if [ "$REMOVE_LAUNCHD" = true ]; then
    ACTIONS+=("Remove launchd service")
fi
if [ "$REMOVE_PIPX_HF" = true ]; then
    ACTIONS+=("Uninstall HuggingFace CLI (pipx)")
fi

if [ ${#ACTIONS[@]} -eq 0 ]; then
    print_info "No actions selected"
    exit 0
fi

echo "The following actions will be performed:"
for action in "${ACTIONS[@]}"; do
    echo "  • $action"
done

echo ""
if ! prompt_yes_no "Proceed with uninstallation?" true; then
    print_info "Uninstall cancelled"
    exit 0
fi

echo ""

# Execute uninstallation
SUCCESS_COUNT=0
ERROR_COUNT=0

# Stop llama-server if running
if [ "$LLAMA_RUNNING" = true ]; then
    print_header "Stopping llama-server"
    if lsof -ti:$PORT | xargs kill -9 2>/dev/null; then
        print_status "llama-server stopped"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_warning "Could not stop llama-server (may already be stopped)"
    fi
    echo ""
fi

# Remove launchd service
if [ "$REMOVE_LAUNCHD" = true ]; then
    print_header "Removing launchd Service"

    # Unload if loaded
    if launchctl list | grep -q "com.llamacpp.server" 2>/dev/null; then
        if launchctl unload "$LAUNCHD_PLIST" 2>/dev/null; then
            print_status "Unloaded launchd service"
        fi
    fi

    # Remove plist file
    if rm -f "$LAUNCHD_PLIST"; then
        print_status "Removed: $LAUNCHD_PLIST"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove launchd plist"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Remove llama.cpp build
if [ "$REMOVE_LLAMA_BUILD" = true ]; then
    print_header "Removing llama.cpp Build"
    if rm -rf "$LLAMA_BUILD_DIR"; then
        print_status "Removed: $LLAMA_BUILD_DIR"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove llama.cpp build"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Remove OpenCode build directory
if [ "$REMOVE_OPENCODE_BUILD" = true ]; then
    print_header "Removing OpenCode Build Directory"
    if rm -rf "$OPENCODE_BUILD_DIR"; then
        print_status "Removed: $OPENCODE_BUILD_DIR"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove OpenCode build directory"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Remove OpenCode custom build
if [ "$REMOVE_OPENCODE_CUSTOM" = true ]; then
    print_header "Removing Custom OpenCode Build"

    # Remove marker file
    if [ -f "$CUSTOM_BUILD_MARKER" ]; then
        rm -f "$CUSTOM_BUILD_MARKER"
        print_status "Removed custom build marker"
    fi

    # Restore backup if requested
    if [ "$RESTORE_OPENCODE_BACKUP" = true ] && [ -f "$HOME/.opencode/bin/opencode.backup" ]; then
        if cp "$HOME/.opencode/bin/opencode.backup" "$HOME/.opencode/bin/opencode" && \
           rm -f "$HOME/.opencode/bin/opencode.backup"; then
            print_status "Restored original OpenCode from backup"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print_error "Failed to restore OpenCode backup"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    elif [ "$REMOVE_OPENCODE_CUSTOM" = true ]; then
        # Just remove custom build
        if rm -f "$HOME/.opencode/bin/opencode"; then
            print_status "Removed custom OpenCode binary"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print_error "Failed to remove custom OpenCode binary"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    fi
    echo ""
fi

# Remove configuration files
if [ "$REMOVE_CONFIG" = true ]; then
    print_header "Removing Configuration Files"

    for config_file in "${CONFIG_FILES[@]}"; do
        if rm -f "$config_file"; then
            print_status "Removed: ${config_file/#$HOME/~}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print_error "Failed to remove: $config_file"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    done

    # Remove empty directories
    if [ -d "$HOME/.config/opencode/prompts" ]; then
        rmdir "$HOME/.config/opencode/prompts" 2>/dev/null || true
    fi
    if [ -d "$HOME/.config/opencode" ]; then
        rmdir "$HOME/.config/opencode" 2>/dev/null || true
        if [ ! -d "$HOME/.config/opencode" ]; then
            print_info "Removed empty config directory"
        fi
    fi
    echo ""
fi

# Remove model cache
if [ "$REMOVE_MODEL" = true ]; then
    print_header "Removing Gemma 4 26B Model"
    if rm -rf "$MODEL_CACHE_PATH"; then
        print_status "Removed: $MODEL_CACHE_PATH"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove model cache"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Remove log files
if [ "$REMOVE_LOGS" = true ]; then
    print_header "Removing Log Files"

    if [ -f "$HOME/.local/var/llama-server.pid" ]; then
        if rm -f "$HOME/.local/var/llama-server.pid"; then
            print_status "Removed PID file"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi

    if [ -f "$HOME/.local/var/log/llama-server.log" ]; then
        if rm -f "$HOME/.local/var/log/llama-server.log"; then
            print_status "Removed log file"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi

    # Remove empty directories
    rmdir "$HOME/.local/var/log" 2>/dev/null || true
    rmdir "$HOME/.local/var" 2>/dev/null || true
    echo ""
fi

# Uninstall pipx huggingface-hub
if [ "$REMOVE_PIPX_HF" = true ]; then
    print_header "Uninstalling HuggingFace CLI"
    if pipx uninstall huggingface-hub 2>/dev/null; then
        print_status "Uninstalled HuggingFace CLI (pipx)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to uninstall HuggingFace CLI"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Final summary
print_header "Uninstall Complete"

if [ $SUCCESS_COUNT -gt 0 ]; then
    print_status "Successfully removed $SUCCESS_COUNT component(s)"
fi

if [ $ERROR_COUNT -gt 0 ]; then
    echo ""
    print_warning "$ERROR_COUNT error(s) occurred"
fi

echo ""
print_info "You can run setup-gemma4-working.sh to reinstall"
echo ""

exit 0
