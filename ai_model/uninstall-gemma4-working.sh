#!/bin/bash
#
# Uninstaller for Gemma 4 + Ollama + OpenCode Setup
#
# Removes all components installed by setup-gemma4-working.sh:
# - Ollama build directory
# - OpenCode custom build (restores backup)
# - OpenCode build directory
# - Configuration files
# - Ollama models
# - launchd service
# - Running Ollama server processes
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
OLLAMA_BUILD_DIR="/tmp/ollama-build"
OPENCODE_BUILD_DIR="/tmp/opencode-build"
PORT="3456"

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
print_header "Gemma 4 + Ollama + OpenCode Uninstaller"

echo "This script will remove components installed by setup-gemma4-working.sh"
echo ""

# Scan system
print_info "Scanning system for installed components..."
echo ""

# Track what we find (simple variables for bash 3.2 compatibility)
FOUND_OLLAMA_BUILD=""
FOUND_OPENCODE_BUILD=""
FOUND_OPENCODE_CUSTOM=false
FOUND_OPENCODE_BACKUP=false
FOUND_CONFIG_FILES=0
FOUND_OLLAMA_MODELS=""
FOUND_OLLAMA_RUNNING=false
FOUND_PID_FILE=false
FOUND_LOG_FILE=""
FOUND_LAUNCHD=false
TOTAL_SIZE_MB=0
COMPONENT_COUNT=0

# Check Ollama build
if [ -d "$OLLAMA_BUILD_DIR" ]; then
    SIZE=$(get_size_mb "$OLLAMA_BUILD_DIR")
    TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
    FOUND_OLLAMA_BUILD="$SIZE"
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "Ollama build found ($(format_size $SIZE)): $OLLAMA_BUILD_DIR"
fi

# Check OpenCode build directory
if [ -d "$OPENCODE_BUILD_DIR" ]; then
    SIZE=$(get_size_mb "$OPENCODE_BUILD_DIR")
    TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
    FOUND_OPENCODE_BUILD="$SIZE"
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "OpenCode build directory found ($(format_size $SIZE)): $OPENCODE_BUILD_DIR"
fi

# Check OpenCode custom build
CUSTOM_BUILD_MARKER="$HOME/.opencode/bin/.custom-build-dev"
if [ -f "$CUSTOM_BUILD_MARKER" ]; then
    FOUND_OPENCODE_CUSTOM=true
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "OpenCode custom build marker found (dev branch)"
fi

if [ -f "$HOME/.opencode/bin/opencode.backup" ]; then
    FOUND_OPENCODE_BACKUP=true
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
    FOUND_CONFIG_FILES=${#CONFIG_FILES[@]}
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "Configuration files found: ${#CONFIG_FILES[@]}"
fi

# Check for Ollama models
OLLAMA_MODELS_DIR="$HOME/.ollama/models"
if [ -d "$OLLAMA_MODELS_DIR" ]; then
    SIZE=$(get_size_mb "$OLLAMA_MODELS_DIR")
    if [ "$SIZE" -gt 0 ]; then
        TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + SIZE))
        FOUND_OLLAMA_MODELS="$SIZE"
        COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
        print_status "Ollama models found ($(format_size $SIZE)): $OLLAMA_MODELS_DIR"

        # List models if Ollama binary exists
        if [ -f "$OLLAMA_BUILD_DIR/ollama" ]; then
            print_info "Installed models:"
            # Temporarily disable exit on error for this command
            set +e
            MODEL_LIST=$("$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null)
            LIST_EXIT=$?
            set -e

            if [ $LIST_EXIT -eq 0 ] && [ -n "$MODEL_LIST" ]; then
                echo "$MODEL_LIST" | tail -n +2 | while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        MODEL_NAME=$(echo "$line" | awk '{print $1}')
                        if [ -n "$MODEL_NAME" ]; then
                            echo "    - $MODEL_NAME"
                        fi
                    fi
                done
            else
                print_info "    (Unable to list models - use 'ollama list' to view)"
            fi
        fi
    fi
fi

# Check for running Ollama server
OLLAMA_RUNNING=false
if lsof -ti:$PORT >/dev/null 2>&1; then
    OLLAMA_RUNNING=true
    FOUND_OLLAMA_RUNNING=true
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "Ollama server running on port $PORT"
fi

# Check for PID file
if [ -f "$HOME/.local/var/ollama-server.pid" ]; then
    FOUND_PID_FILE=true
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "PID file found: $HOME/.local/var/ollama-server.pid"
fi

# Check for log file
if [ -f "$HOME/.local/var/log/ollama-server.log" ]; then
    SIZE=$(get_size_mb "$HOME/.local/var/log/ollama-server.log")
    FOUND_LOG_FILE="$SIZE"
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "Log file found ($(format_size $SIZE)): $HOME/.local/var/log/ollama-server.log"
fi

# Check for launchd service
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.ollama.server.plist"
if [ -f "$LAUNCHD_PLIST" ]; then
    FOUND_LAUNCHD=true
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    print_status "launchd service found: $LAUNCHD_PLIST"
fi

echo ""

# Check if anything was found
if [ $COMPONENT_COUNT -eq 0 ]; then
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

REMOVE_OLLAMA_BUILD=false
REMOVE_OPENCODE_BUILD=false
REMOVE_OPENCODE_CUSTOM=false
RESTORE_OPENCODE_BACKUP=false
REMOVE_CONFIG=false
REMOVE_MODELS=false
REMOVE_LOGS=false
REMOVE_LAUNCHD=false

# Ollama build
if [ -n "$FOUND_OLLAMA_BUILD" ]; then
    if prompt_yes_no "Remove Ollama build? ($(format_size $FOUND_OLLAMA_BUILD))" true; then
        REMOVE_OLLAMA_BUILD=true
    fi
fi

# OpenCode build directory
if [ -n "$FOUND_OPENCODE_BUILD" ]; then
    if prompt_yes_no "Remove OpenCode build directory? ($(format_size $FOUND_OPENCODE_BUILD))" true; then
        REMOVE_OPENCODE_BUILD=true
    fi
fi

# OpenCode custom build
if [ "$FOUND_OPENCODE_CUSTOM" = true ]; then
    echo ""
    if [ "$FOUND_OPENCODE_BACKUP" = true ]; then
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
if [ $FOUND_CONFIG_FILES -gt 0 ]; then
    echo ""
    if prompt_yes_no "Remove configuration files? ($FOUND_CONFIG_FILES files)" true; then
        REMOVE_CONFIG=true
    fi
fi

# Ollama models
if [ -n "$FOUND_OLLAMA_MODELS" ]; then
    echo ""
    print_warning "Ollama models: $(format_size $FOUND_OLLAMA_MODELS)"
    print_info "Models can be large (16GB-52GB each) and take time to re-download"
    if prompt_yes_no "Remove ALL Ollama models?" false; then
        REMOVE_MODELS=true
    fi
fi

# Log files
if [ -n "$FOUND_LOG_FILE" ] || [ "$FOUND_PID_FILE" = true ]; then
    echo ""
    if prompt_yes_no "Remove log files and PID files?" true; then
        REMOVE_LOGS=true
    fi
fi

# launchd service
if [ "$FOUND_LAUNCHD" = true ]; then
    echo ""
    if prompt_yes_no "Remove launchd service (auto-start on login)?" true; then
        REMOVE_LAUNCHD=true
    fi
fi

# Show summary
echo ""
print_header "Uninstall Summary"

ACTIONS=()
if [ "$REMOVE_OLLAMA_BUILD" = true ]; then
    ACTIONS+=("Remove Ollama build ($(format_size $FOUND_OLLAMA_BUILD))")
fi
if [ "$REMOVE_OPENCODE_BUILD" = true ]; then
    ACTIONS+=("Remove OpenCode build directory ($(format_size $FOUND_OPENCODE_BUILD))")
fi
if [ "$REMOVE_OPENCODE_CUSTOM" = true ]; then
    if [ "$RESTORE_OPENCODE_BACKUP" = true ]; then
        ACTIONS+=("Remove custom OpenCode and restore backup")
    else
        ACTIONS+=("Remove custom OpenCode build")
    fi
fi
if [ "$REMOVE_CONFIG" = true ]; then
    ACTIONS+=("Remove $FOUND_CONFIG_FILES configuration files")
fi
if [ "$REMOVE_MODELS" = true ]; then
    ACTIONS+=("Remove ALL Ollama models ($(format_size $FOUND_OLLAMA_MODELS))")
fi
if [ "$REMOVE_LOGS" = true ]; then
    ACTIONS+=("Remove log files and PID files")
fi
if [ "$REMOVE_LAUNCHD" = true ]; then
    ACTIONS+=("Remove launchd service")
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

# Stop Ollama server if running
if [ "$OLLAMA_RUNNING" = true ]; then
    print_header "Stopping Ollama Server"
    if lsof -ti:$PORT | xargs kill -9 2>/dev/null; then
        print_status "Ollama server stopped"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_warning "Could not stop Ollama server (may already be stopped)"
    fi
    echo ""
fi

# Remove launchd service
if [ "$REMOVE_LAUNCHD" = true ]; then
    print_header "Removing launchd Service"

    # Unload if loaded
    if launchctl list | grep -q "com.ollama.server" 2>/dev/null; then
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

# Remove Ollama build
if [ "$REMOVE_OLLAMA_BUILD" = true ]; then
    print_header "Removing Ollama Build"
    if rm -rf "$OLLAMA_BUILD_DIR"; then
        print_status "Removed: $OLLAMA_BUILD_DIR"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove Ollama build"
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

# Remove Ollama models
if [ "$REMOVE_MODELS" = true ]; then
    print_header "Removing Ollama Models"
    if rm -rf "$OLLAMA_MODELS_DIR"; then
        print_status "Removed: $OLLAMA_MODELS_DIR"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_error "Failed to remove Ollama models"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    echo ""
fi

# Remove log files
if [ "$REMOVE_LOGS" = true ]; then
    print_header "Removing Log Files"

    if [ -f "$HOME/.local/var/ollama-server.pid" ]; then
        if rm -f "$HOME/.local/var/ollama-server.pid"; then
            print_status "Removed PID file"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi

    if [ -f "$HOME/.local/var/log/ollama-server.log" ]; then
        if rm -f "$HOME/.local/var/log/ollama-server.log"; then
            print_status "Removed log file"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi

    # Remove empty directories
    rmdir "$HOME/.local/var/log" 2>/dev/null || true
    rmdir "$HOME/.local/var" 2>/dev/null || true
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
