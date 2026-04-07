#!/bin/bash
# diagnose.sh - Auto-detect common issues with Ollama setup
# Diagnoses server, port, RAM, GPU, and model issues

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Diagnostic Checks
#############################################

# Check if Ollama server process is running
check_server() {
    print_info "Checking if Ollama server is running..."

    if pgrep -f "ollama serve" >/dev/null 2>&1; then
        print_status "Server process is running"
        return 0
    else
        print_error "Server not running"
        echo "Fix: Start server with: source lib/ollama-setup.sh && start_ollama_server"
        return 1
    fi
}

# Check if server is responsive to API calls
check_responsive() {
    print_info "Checking if server is responsive..."

    if curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
        print_status "Server is responding to API calls"
        return 0
    else
        print_error "Server not responding at http://127.0.0.1:$OLLAMA_PORT"
        echo "Fix: Restart server with: source lib/ollama-setup.sh && stop_ollama_server && start_ollama_server"
        return 1
    fi
}

# Check for port conflicts
check_port() {
    print_info "Checking for port conflicts on port $OLLAMA_PORT..."

    # Check if anything is listening on the port
    if lsof -i ":$OLLAMA_PORT" >/dev/null 2>&1; then
        # Check if it's Ollama
        if lsof -i ":$OLLAMA_PORT" | grep -q ollama; then
            print_status "Port $OLLAMA_PORT is correctly used by Ollama"
            return 0
        else
            print_error "Port $OLLAMA_PORT is in use by another process"
            echo "Conflicting process:"
            lsof -i ":$OLLAMA_PORT" | grep -v COMMAND
            echo "Fix: Change OLLAMA_PORT in lib/ollama-setup.sh or kill the other process"
            return 1
        fi
    else
        print_warning "Port $OLLAMA_PORT is not in use (server may not be running)"
        return 1
    fi
}

# Check if models exceed available RAM
check_ram() {
    print_info "Checking RAM usage vs model requirements..."

    # Get available RAM
    local available_ram_gb=$TOTAL_RAM_GB
    print_info "Available RAM: ${available_ram_gb}GB"

    # Check if server is running to get model list
    if ! curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
        print_warning "Cannot check model sizes (server not responding)"
        return 1
    fi

    # Get list of models
    local models_json
    models_json=$(curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" 2>/dev/null || echo '{"models":[]}')

    # Check if we got valid JSON
    if ! echo "$models_json" | grep -q '"models"'; then
        print_warning "Unable to retrieve model list"
        return 1
    fi

    # Count models
    local model_count
    model_count=$(echo "$models_json" | grep -o '"name"' | wc -l | tr -d ' ')

    if [[ "$model_count" -eq 0 ]]; then
        print_status "No models installed yet"
        return 0
    fi

    print_info "Found $model_count model(s) installed"

    # Estimate RAM usage (rough calculation)
    # 7B models ~8GB, 13B models ~16GB, 34B models ~40GB
    local estimated_ram=0

    if echo "$models_json" | grep -qi "7b"; then
        estimated_ram=$((estimated_ram + 8))
    fi
    if echo "$models_json" | grep -qi "13b"; then
        estimated_ram=$((estimated_ram + 16))
    fi
    if echo "$models_json" | grep -qi "34b"; then
        estimated_ram=$((estimated_ram + 40))
    fi
    if echo "$models_json" | grep -qi "70b"; then
        estimated_ram=$((estimated_ram + 80))
    fi

    if [[ $estimated_ram -gt 0 ]]; then
        print_info "Estimated model RAM usage: ~${estimated_ram}GB"

        if [[ $estimated_ram -gt $available_ram_gb ]]; then
            print_error "Models may exceed available RAM (${estimated_ram}GB > ${available_ram_gb}GB)"
            echo "Fix: Use smaller quantization (Q4 instead of Q8) or unload some models"
            return 1
        else
            local remaining=$((available_ram_gb - estimated_ram))
            print_status "RAM check passed (${remaining}GB headroom)"
            return 0
        fi
    else
        print_status "RAM check passed (unable to estimate usage)"
        return 0
    fi
}

# Check GPU offload configuration
check_gpu() {
    print_info "Checking GPU offload configuration..."

    # Check if OLLAMA_NUM_GPU is set correctly
    if [[ "$OLLAMA_NUM_GPU" == "999" ]]; then
        print_status "OLLAMA_NUM_GPU=999 (all layers offloaded to GPU)"
    else
        print_warning "OLLAMA_NUM_GPU is set to $OLLAMA_NUM_GPU (should be 999 for full GPU offload)"
        echo "Fix: Ensure OLLAMA_NUM_GPU=999 is set in lib/ollama-setup.sh"
        return 1
    fi

    # Check if log file exists to verify GPU usage
    if [[ -f "$OLLAMA_LOG_FILE" ]]; then
        # Look for Metal/GPU indicators in recent logs
        if tail -n 100 "$OLLAMA_LOG_FILE" 2>/dev/null | grep -qi "metal\|gpu"; then
            print_status "GPU/Metal framework detected in logs"
            return 0
        else
            print_warning "No GPU/Metal indicators found in recent logs"
            echo "Check: Review $OLLAMA_LOG_FILE for GPU initialization"
            return 1
        fi
    else
        print_warning "Log file not found at $OLLAMA_LOG_FILE"
        return 1
    fi
}

# Check for model corruption by testing model loading
check_models() {
    print_info "Checking model integrity..."

    # Check if server is running
    if ! curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
        print_warning "Cannot test models (server not responding)"
        return 1
    fi

    # Get list of models
    local models_json
    models_json=$(curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" 2>/dev/null || echo '{"models":[]}')

    # Extract model names
    local model_names
    model_names=$(echo "$models_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$model_names" ]]; then
        print_status "No models to check"
        return 0
    fi

    local corrupted=0

    # Test each model with a simple generate request
    while IFS= read -r model; do
        [[ -z "$model" ]] && continue

        print_info "Testing model: $model"

        # Send a minimal test prompt with 5 second timeout
        local response
        response=$(timeout 10 curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/generate" \
            -d "{\"model\":\"$model\",\"prompt\":\"test\",\"stream\":false}" 2>/dev/null || echo "")

        if echo "$response" | grep -q '"response"'; then
            print_status "Model $model is working"
        else
            print_error "Model $model appears corrupted or unresponsive"
            echo "Fix: Re-download with: ollama pull $model"
            ((corrupted++))
        fi
    done <<< "$model_names"

    if [[ $corrupted -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Check for stale PID files
check_pid_file() {
    print_info "Checking for stale PID files..."

    if [[ -f "$OLLAMA_PID_FILE" ]]; then
        local pid
        pid=$(cat "$OLLAMA_PID_FILE")

        if ps -p "$pid" >/dev/null 2>&1; then
            print_status "PID file valid (process $pid is running)"
            return 0
        else
            print_warning "Stale PID file found (process $pid not running)"
            echo "Fix: Remove stale PID file with: rm $OLLAMA_PID_FILE"
            return 1
        fi
    else
        if pgrep -f "ollama serve" >/dev/null 2>&1; then
            print_warning "Server is running but no PID file found"
            echo "Info: This may be normal if server was started manually"
        else
            print_info "No PID file (server not running)"
        fi
        return 0
    fi
}

# Check disk space for model storage
check_disk_space() {
    print_info "Checking disk space for model storage..."

    # Get Ollama model directory (default ~/.ollama/models)
    local model_dir="${OLLAMA_MODELS:-$HOME/.ollama/models}"

    # Get available disk space in GB
    local available_gb
    if [[ -d "$model_dir" ]]; then
        available_gb=$(df -g "$model_dir" | tail -1 | awk '{print $4}')
    else
        available_gb=$(df -g "$HOME" | tail -1 | awk '{print $4}')
    fi

    print_info "Available disk space: ${available_gb}GB"

    if [[ $available_gb -lt 10 ]]; then
        print_error "Low disk space (${available_gb}GB available)"
        echo "Warning: Models can be 4-40GB each. Consider freeing up space."
        return 1
    elif [[ $available_gb -lt 50 ]]; then
        print_warning "Moderate disk space (${available_gb}GB available)"
        echo "Info: You may want to free up space before downloading large models"
        return 0
    else
        print_status "Sufficient disk space (${available_gb}GB available)"
        return 0
    fi
}

# Display system information
show_system_info() {
    print_header "System Information"

    print_info "Chip: $M_CHIP"
    print_info "GPU Cores: $GPU_CORES"
    print_info "Total RAM: ${TOTAL_RAM_GB}GB"
    print_info "RAM Tier: $RAM_TIER"
    print_info "Ollama Port: $OLLAMA_PORT"
    print_info "Ollama Host: $OLLAMA_HOST"

    echo ""
}

#############################################
# Main Diagnostic Flow
#############################################

main() {
    print_header "Ollama Diagnostics"
    echo "Running automated diagnostics to detect common issues..."
    echo ""

    # Show system info first
    show_system_info

    # Track number of issues found
    local issues=0

    # Run all diagnostic checks
    check_pid_file || ((issues++))
    echo ""

    check_server || ((issues++))
    echo ""

    check_port || ((issues++))
    echo ""

    check_responsive || ((issues++))
    echo ""

    check_disk_space || ((issues++))
    echo ""

    check_ram || ((issues++))
    echo ""

    check_gpu || ((issues++))
    echo ""

    check_models || ((issues++))
    echo ""

    # Summary
    print_header "Diagnostic Summary"

    if [[ $issues -eq 0 ]]; then
        print_status "All checks passed! No issues detected."
        echo ""
        echo "Your Ollama setup appears to be working correctly."
        exit 0
    else
        print_error "$issues issue(s) found"
        echo ""
        echo "Review the diagnostic output above for fixes."
        echo "Common fixes:"
        echo "  - Start server: source lib/ollama-setup.sh && start_ollama_server"
        echo "  - Restart server: source lib/ollama-setup.sh && stop_ollama_server && start_ollama_server"
        echo "  - Check logs: tail -f $OLLAMA_LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
