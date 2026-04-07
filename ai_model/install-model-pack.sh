#!/bin/bash
# install-model-pack.sh - Install preset model packs based on RAM tier
# Usage: ./install-model-pack.sh [minimal|balanced|comprehensive]

set -euo pipefail

#############################################
# Source Dependencies
#############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-families.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Model Pack Definitions
#############################################

# Get models for pack type and tier
get_pack_models() {
    local pack_type="$1"
    local ram_tier="$2"

    case "${pack_type}_${ram_tier}" in
        # Minimal packs: 1 model per tier (best single model for RAM)
        minimal_tier1) echo "llama3.2:3b-instruct-q8_0" ;;
        minimal_tier2) echo "llama3.2:11b-instruct-q8_0" ;;
        minimal_tier3) echo "llama3.3:70b-instruct-q4_K_M" ;;

        # Balanced packs: 3 models per tier (mix of speed and capability)
        balanced_tier1) echo "llama3.2:3b-instruct-q8_0 phi3.5:3.8b-mini-instruct-q8_0 gemma4:e2b-it-q4_K_M" ;;
        balanced_tier2) echo "llama3.2:11b-instruct-q8_0 codestral:22b-v0.1-q4_K_M phi4:14b-q8_0" ;;
        balanced_tier3) echo "llama3.3:70b-instruct-q4_K_M codestral:22b-v0.1-q8_0 gemma4:31b-it-q8_0" ;;

        # Comprehensive packs: 5+ models per tier (full range)
        comprehensive_tier1) echo "llama3.2:3b-instruct-q8_0 phi3.5:3.8b-mini-instruct-q8_0 gemma4:e2b-it-q4_K_M llama3.2:11b-instruct-q4_K_M gemma4:e4b-it-q8_0" ;;
        comprehensive_tier2) echo "llama3.2:3b-instruct-q8_0 phi3.5:3.8b-mini-instruct-q8_0 llama3.2:11b-instruct-q8_0 codestral:22b-v0.1-q4_K_M phi4:14b-q8_0 mistral-nemo:12b-instruct-q8_0 gemma4:e2b-it-q4_K_M gemma4:e4b-it-q8_0" ;;
        comprehensive_tier3) echo "llama3.2:3b-instruct-q8_0 phi3.5:3.8b-mini-instruct-q8_0 llama3.2:11b-instruct-q8_0 codestral:22b-v0.1-q8_0 phi4:14b-q8_0 mistral-nemo:12b-instruct-q8_0 llama3.3:70b-instruct-q4_K_M gemma4:31b-it-q8_0 gemma4:26b-a4b-it-q4_K_M gemma4:e4b-it-q8_0" ;;

        *)
            print_error "Unknown pack type or tier: ${pack_type}_${ram_tier}"
            return 1
            ;;
    esac
}

#############################################
# Helper Functions
#############################################

# Calculate total size for a pack
calculate_pack_size() {
    local pack_type="$1"
    local ram_tier="$2"
    local total_size=0
    local models=""

    models=$(get_pack_models "$pack_type" "$ram_tier")

    # Calculate total size from model metadata
    for model in $models; do
        # Find model in family arrays
        local found=false
        for model_line in "${LLAMA_MODELS[@]}" "${MISTRAL_MODELS[@]}" "${PHI_MODELS[@]}" "${GEMMA_MODELS[@]}"; do
            local model_name model_size
            IFS='|' read -r model_name model_size _ _ _ _ <<< "$model_line"
            if [[ "$model_name" == "$model" ]]; then
                total_size=$((total_size + model_size))
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            print_warning "Model not found in metadata: $model (assuming 10GB)"
            total_size=$((total_size + 10))
        fi
    done

    echo "$total_size"
}

# Check if model is already installed
is_model_installed() {
    local model="$1"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        return 1
    fi

    # Check if model exists in list
    if "$OLLAMA_BUILD_DIR/ollama" list 2>/dev/null | grep -q "^${model%:*}"; then
        return 0
    else
        return 1
    fi
}

# Display pack information
display_pack_info() {
    local pack_type="$1"
    local ram_tier="$2"
    local models=""

    models=$(get_pack_models "$pack_type" "$ram_tier")

    print_header "Pack Information"
    echo -e "${BLUE}Pack Type:${NC} $pack_type"
    echo -e "${BLUE}RAM Tier:${NC} $ram_tier (${TOTAL_RAM_GB}GB)"
    echo -e "${BLUE}Models:${NC}"

    local count=0
    for model in $models; do
        ((count++))
        echo -e "  ${GREEN}$count.${NC} $model"
    done

    local total_size
    total_size=$(calculate_pack_size "$pack_type" "$ram_tier")
    echo -e "\n${BLUE}Estimated Total Size:${NC} ~${total_size}GB"
    echo ""
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [minimal|balanced|comprehensive]

Install preset model packs optimized for your RAM tier.

Pack Types:
  minimal        - 1 best model for your RAM (fastest setup)
  balanced       - 3 models balancing speed and capability
  comprehensive  - 5-10 models covering full range

Your System:
  RAM: ${TOTAL_RAM_GB}GB
  Tier: $RAM_TIER
  Chip: $M_CHIP
  GPU Cores: $GPU_CORES

Examples:
  $0 minimal        # Install 1 model
  $0 balanced       # Install 3 models
  $0 comprehensive  # Install 5-10 models

EOF
    exit 1
}

#############################################
# Main Installation Function
#############################################

install_pack() {
    local pack_type="$1"
    local ram_tier="$RAM_TIER"

    # Validate pack type
    case "$pack_type" in
        minimal|balanced|comprehensive) ;;
        *)
            print_error "Invalid pack type: $pack_type"
            show_usage
            ;;
    esac

    # Display pack information
    display_pack_info "$pack_type" "$ram_tier"

    # Validate RAM
    local total_size
    total_size=$(calculate_pack_size "$pack_type" "$ram_tier")
    local available_ram=$((TOTAL_RAM_GB * 70 / 100))  # Use 70% of RAM

    if [[ "$total_size" -gt "$available_ram" ]]; then
        print_warning "Pack requires ~${total_size}GB but you have ${TOTAL_RAM_GB}GB RAM"
        print_warning "Recommended usable RAM: ~${available_ram}GB (70% of total)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    else
        print_status "RAM check passed: ${total_size}GB fits in ${available_ram}GB available"
    fi

    # Check server status
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Please start the server first with:"
        print_info "  cd $SCRIPT_DIR && ./lib/ollama-setup.sh"
        print_info "  source lib/ollama-setup.sh && start_ollama_server"
        exit 1
    fi

    print_status "Ollama server is running"

    # Get model list for pack
    local models=""
    models=$(get_pack_models "$pack_type" "$ram_tier")

    # Convert space-separated string to array
    local -a model_array=($models)
    local total=${#model_array[@]}
    local current=0
    local installed=0
    local skipped=0
    local failed=0

    print_header "Installing Models"

    # Install each model with progress
    for model in "${model_array[@]}"; do
        ((current++))

        echo ""
        print_info "[$current/$total] Processing: $model"

        # Check if already installed
        if is_model_installed "$model"; then
            print_status "Already installed, skipping"
            ((skipped++))
            continue
        fi

        # Pull the model
        print_info "Pulling model..."
        if pull_model "$model"; then
            ((installed++))
        else
            print_error "Failed to pull $model"
            ((failed++))
        fi
    done

    # Display summary
    echo ""
    print_header "Installation Summary"
    echo -e "${BLUE}Pack Type:${NC} $pack_type"
    echo -e "${BLUE}Total Models:${NC} $total"
    echo -e "${GREEN}Installed:${NC} $installed"
    echo -e "${YELLOW}Skipped:${NC} $skipped (already installed)"

    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}Failed:${NC} $failed"
        print_warning "Some models failed to install"
        exit 1
    else
        echo ""
        print_status "Pack installation complete!"

        # Show how to list models
        print_info "To see installed models, run:"
        print_info "  source $SCRIPT_DIR/lib/ollama-setup.sh && list_models"
    fi
}

#############################################
# Main Entry Point
#############################################

main() {
    # Check for argument
    if [[ $# -eq 0 ]]; then
        show_usage
    fi

    local pack_type="$1"

    # Display system info
    print_header "System Information"
    echo -e "${BLUE}Chip:${NC} $M_CHIP"
    echo -e "${BLUE}RAM:${NC} ${TOTAL_RAM_GB}GB"
    echo -e "${BLUE}Tier:${NC} $RAM_TIER"
    echo -e "${BLUE}GPU Cores:${NC} $GPU_CORES"
    echo ""

    # Install the pack
    install_pack "$pack_type"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
