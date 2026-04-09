#!/bin/bash
# setup-gemma4-opencode.sh - Idempotent setup for Gemma4 + OpenCode via Ollama (Homebrew)
#
# One-stop shop for team deployment:
# - Installs Ollama and OpenCode via Homebrew
# - Dynamically optimizes configuration based on detected hardware
# - Pulls and configures Gemma4 models with native context windows
# - Sets up OpenCode integration
#
# Safe to run multiple times - idempotent design
#
# Available Gemma4 Models (https://ollama.com/library/gemma4/tags):
# ┌──────────────┬────────┬─────────┬──────────────┬──────────────┐
# │ Model        │ Size   │ Context │ RAM Required │ Best For     │
# ├──────────────┼────────┼─────────┼──────────────┼──────────────┤
# │ gemma4:e2b   │ 7.2GB  │ 128K    │ 12GB+        │ Minimal RAM  │
# │ gemma4:latest│ 9.6GB  │ 128K    │ 16GB+        │ Balanced     │
# │ gemma4:26b   │ 18GB   │ 256K    │ 32GB+        │ Large Context│
# │ gemma4:31b   │ 20GB   │ 256K    │ 48GB+        │ Best Quality │
# └──────────────┴────────┴─────────┴──────────────┴──────────────┘
#
# Usage: ./setup-gemma4-opencode.sh [--model MODEL] [--auto]
#
# Options:
#   --model MODEL    Specify Gemma4 variant (auto-detected by default)
#                    Available: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b
#                    See: https://ollama.com/library/gemma4/tags
#   --auto           Skip model recommendation, use auto-detected model
#
# Requirements:
#   - macOS with Apple Silicon (M1 or later recommended)
#   - Homebrew installed
#   - RAM varies by model:
#       e2b: 12GB+ (7.2GB model, 128K context)
#       latest/e4b: 16GB+ (9.6GB model, 128K context)
#       26b: 32GB+ (18GB model, 256K context)
#       31b: 48GB+ (20GB model, 256K context)

set -euo pipefail

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    # Remove temporary modelfile if it exists
    [[ -n "${modelfile_path:-}" && -f "$modelfile_path" ]] && rm -f "$modelfile_path"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# Source library modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/hardware-config.sh"

#############################################
# Configuration
#############################################

# Detect hardware (batched for efficiency - single subprocess call)
read -r DETECTED_M_CHIP DETECTED_RAM_GB DETECTED_CPU_CORES <<< "$(detect_hardware_profile)"

# Model configuration (can be overridden via --model flag)
RECOMMENDED_MODEL=$(recommend_model "$DETECTED_RAM_GB")
GEMMA_MODEL="${GEMMA_MODEL:-}"  # Will be set after arg parsing
AUTO_MODE=false

# LaunchAgent configuration
LAUNCHAGENT_LABEL="com.ollama.custom"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"

# Custom model name will be set after model selection (e.g., gemma4-optimized-31b)
CUSTOM_MODEL_NAME=""

# Ollama configuration
OLLAMA_HOST="http://localhost:11434"

# Cache for ollama list output (avoid multiple subprocess calls)
OLLAMA_LIST_CACHE=""

#############################################
# Parse Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            validate_model_name "$2" || exit 1
            GEMMA_MODEL="$2"
            shift 2
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set model if not specified
if [[ -z "$GEMMA_MODEL" ]]; then
    GEMMA_MODEL="$RECOMMENDED_MODEL"

    # Show recommendation to user (unless --auto mode)
    if [[ "$AUTO_MODE" != true ]]; then
        print_header "Hardware Detection & Model Recommendation"
        echo -e "${BLUE}Detected Hardware:${NC}"
        echo "  • Chip:      $DETECTED_M_CHIP"
        echo "  • RAM:       ${DETECTED_RAM_GB}GB"
        echo "  • CPU Cores: $DETECTED_CPU_CORES"
        echo ""
        echo -e "${GREEN}Recommended Model: $RECOMMENDED_MODEL${NC}"
        echo ""

        # Show available options with GPU compatibility indicators
        echo "Available Gemma4 models (✓ = 100% GPU, ⚠ = CPU/GPU split):"
        echo ""

        # Check each model's GPU fit
        test_31b_context=$(calculate_context_length "$DETECTED_RAM_GB" "31b")
        test_26b_context=$(calculate_context_length "$DETECTED_RAM_GB" "26b")
        test_latest_context=$(calculate_context_length "$DETECTED_RAM_GB" "latest")
        test_e2b_context=$(calculate_context_length "$DETECTED_RAM_GB" "e2b")

        if [[ $DETECTED_RAM_GB -ge 48 ]]; then
            if validate_gpu_fit "$DETECTED_RAM_GB" "31b" "$test_31b_context"; then
                echo "  ✓ gemma4:31b    (19GB model, $((test_31b_context/1024))K context, 100% GPU)"
            else
                echo "  ⚠ gemma4:31b    (19GB model, $((test_31b_context/1024))K context, CPU/GPU split - not recommended)"
            fi

            if validate_gpu_fit "$DETECTED_RAM_GB" "26b" "$test_26b_context"; then
                echo "  ✓ gemma4:26b    (17GB model, $((test_26b_context/1024))K context, 100% GPU)"
            else
                echo "  ⚠ gemma4:26b    (17GB model, $((test_26b_context/1024))K context, CPU/GPU split)"
            fi

            echo "  ✓ gemma4:latest (10GB model, $((test_latest_context/1024))K context, 100% GPU)"
            echo "  ✓ gemma4:e2b    (7GB model, $((test_e2b_context/1024))K context, 100% GPU)"
        elif [[ $DETECTED_RAM_GB -ge 32 ]]; then
            if validate_gpu_fit "$DETECTED_RAM_GB" "26b" "$test_26b_context"; then
                echo "  ✓ gemma4:26b    (17GB model, $((test_26b_context/1024))K context, 100% GPU)"
            else
                echo "  ⚠ gemma4:26b    (17GB model, $((test_26b_context/1024))K context, CPU/GPU split)"
            fi
            echo "  ✓ gemma4:latest (10GB model, $((test_latest_context/1024))K context, 100% GPU)"
            echo "  ✓ gemma4:e2b    (7GB model, $((test_e2b_context/1024))K context, 100% GPU)"
        elif [[ $DETECTED_RAM_GB -ge 16 ]]; then
            echo "  ✓ gemma4:latest (10GB model, $((test_latest_context/1024))K context, 100% GPU)"
            echo "  ✓ gemma4:e2b    (7GB model, $((test_e2b_context/1024))K context, 100% GPU)"
        else
            echo "  ✓ gemma4:e2b    (7GB model, $((test_e2b_context/1024))K context, 100% GPU)"
        fi
        echo ""
        print_info "Models marked with ⚠ will use CPU fallback (slower performance)"
        echo ""

        read -p "Use recommended model $RECOMMENDED_MODEL? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            while true; do
                read -r -p "Enter model name (e.g., gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b): " GEMMA_MODEL
                if [[ -z "$GEMMA_MODEL" ]]; then
                    print_error "No model specified, using recommendation"
                    GEMMA_MODEL="$RECOMMENDED_MODEL"
                    break
                fi
                if validate_model_name "$GEMMA_MODEL"; then
                    break
                fi
            done
        fi
    fi
fi

# Extract model size for dynamic configuration
MODEL_SIZE=$(get_model_size "$GEMMA_MODEL")

# Custom model name will be set after context selection
CUSTOM_MODEL_NAME=""

# Calculate optimal settings based on hardware
METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
NUM_PARALLEL=$(calculate_num_parallel "$DETECTED_RAM_GB")
RECOMMENDED_CONTEXT=$(calculate_context_length "$DETECTED_RAM_GB" "$MODEL_SIZE")
CONTEXT_LENGTH=$RECOMMENDED_CONTEXT  # Default to recommended

# Ask about context window (skip in auto mode)
if [[ "$AUTO_MODE" != true ]]; then
    print_header "Context Window Selection"

    # Determine model's native max context
    # e2b and latest: 128K max, 26b and 31b: 256K max
    max_context=""
    case "$MODEL_SIZE" in
        e2b|latest|e4b)
            max_context=131072  # 128K
            ;;
        26b|31b)
            max_context=262144  # 256K
            ;;
        *)
            max_context=131072  # Default to 128K
            ;;
    esac

    echo -e "${BLUE}Model: ${GEMMA_MODEL} (native max: $((max_context / 1024))K context)${NC}"
    echo -e "${BLUE}Recommended context for your hardware: $((RECOMMENDED_CONTEXT / 1024))K tokens${NC}"
    echo ""
    echo "Available context window sizes:"
    echo ""

    # Calculate GPU fit for each context size
    metal_gb=$((METAL_MEMORY / BYTES_PER_GB))
    model_weight_gb=$(get_model_weight_gb "$MODEL_SIZE")

    # Context options to display (only up to model's max)
    declare -a context_options=(32768 65536 131072 262144)
    declare -a context_labels=("32K" "64K" "128K" "256K")

    for i in "${!context_options[@]}"; do
        ctx="${context_options[$i]}"
        label="${context_labels[$i]}"

        # Skip options beyond model's native max context
        if [[ $ctx -gt $max_context ]]; then
            continue
        fi

        # Calculate if it fits
        kv_gb=$(calculate_kv_cache_gb "$MODEL_SIZE" "$ctx")
        total_gb=$((model_weight_gb + kv_gb))

        if validate_gpu_fit "$DETECTED_RAM_GB" "$MODEL_SIZE" "$ctx"; then
            if [[ $ctx -eq $RECOMMENDED_CONTEXT ]]; then
                echo -e "  ${GREEN}✓ ${label} (${ctx} tokens) - Recommended${NC}"
            else
                echo -e "  ${GREEN}✓ ${label} (${ctx} tokens) - 100% GPU${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ ${label} (${ctx} tokens) - CPU/GPU split (slower)${NC}"
        fi
    done

    echo ""
    read -p "Use recommended $((RECOMMENDED_CONTEXT / 1024))K context? (Y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        # Build valid options string based on model max
        valid_options=""
        if [[ $max_context -eq 262144 ]]; then
            valid_options="32K, 64K, 128K, or 256K"
        else
            valid_options="32K, 64K, or 128K"
        fi

        while true; do
            echo ""
            read -r -p "Enter context size ($valid_options): " context_input

            # Parse input (use tr for bash 3.2 compatibility)
            context_lower=$(echo "$context_input" | tr '[:upper:]' '[:lower:]')
            case "$context_lower" in
                32k|32)
                    CONTEXT_LENGTH=32768
                    break
                    ;;
                64k|64)
                    CONTEXT_LENGTH=65536
                    break
                    ;;
                128k|128)
                    CONTEXT_LENGTH=131072
                    break
                    ;;
                256k|256)
                    if [[ $max_context -lt 262144 ]]; then
                        print_error "256K exceeds model's native max context ($((max_context / 1024))K)"
                        print_info "This model supports up to $((max_context / 1024))K context"
                    else
                        CONTEXT_LENGTH=262144
                        break
                    fi
                    ;;
                "")
                    print_info "No input, using recommended $((RECOMMENDED_CONTEXT / 1024))K"
                    CONTEXT_LENGTH=$RECOMMENDED_CONTEXT
                    break
                    ;;
                *)
                    print_error "Invalid input. Please enter $valid_options"
                    ;;
            esac
        done
    fi
fi

NUM_CTX=$CONTEXT_LENGTH  # Ollama uses num_ctx parameter name

# Ask about custom model name (skip in auto mode)
if [[ "$AUTO_MODE" != true ]]; then
    print_header "Custom Model Naming"

    # Suggest default name with context
    context_k=$((CONTEXT_LENGTH / 1024))
    default_name="gemma4-optimized-${MODEL_SIZE}-${context_k}k"

    echo -e "${BLUE}Suggested name: ${default_name}${NC}"
    echo ""
    echo "This is the name you'll use with 'ollama run' and OpenCode."
    echo "Examples of custom names:"
    echo "  • gemma4-coding-fast    (for quick coding tasks)"
    echo "  • gemma4-research-deep  (for research with large context)"
    echo "  • gemma4-31b-balanced   (descriptive of model + purpose)"
    echo ""
    echo "Name requirements:"
    echo "  • Lowercase letters, numbers, hyphens (-), underscores (_), dots (.)"
    echo "  • No spaces or special characters"
    echo "  • Should be memorable and descriptive"
    echo ""
    read -p "Use suggested name? (Y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        while true; do
            echo ""
            read -r -p "Enter custom model name: " custom_input

            # Use default if empty
            if [[ -z "$custom_input" ]]; then
                print_info "No input, using suggested name"
                CUSTOM_MODEL_NAME="$default_name"
                break
            fi

            # Validate format: lowercase alphanumeric + hyphens, underscores, dots only
            # No spaces, no special chars that could break shell/ollama
            if [[ "$custom_input" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
                # Additional validation: reasonable length
                if [[ ${#custom_input} -gt 64 ]]; then
                    print_error "Name too long (max 64 characters)"
                    continue
                fi

                # Warn if no prefix (recommended to start with "gemma" for clarity)
                if [[ ! "$custom_input" =~ ^gemma ]]; then
                    echo ""
                    print_warning "Name doesn't start with 'gemma' - may be unclear this is a Gemma model"
                    read -p "Use this name anyway? (y/N) " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        continue
                    fi
                fi

                CUSTOM_MODEL_NAME="$custom_input"
                print_status "Using custom name: $CUSTOM_MODEL_NAME"
                break
            else
                print_error "Invalid name format"
                echo "  • Must start with a letter or number"
                echo "  • Can only contain: a-z, 0-9, hyphens (-), underscores (_), dots (.)"
                echo "  • No uppercase, spaces, or special characters"
            fi
        done
    else
        CUSTOM_MODEL_NAME="$default_name"
    fi
else
    # Auto mode: use default naming with context
    context_k=$((CONTEXT_LENGTH / 1024))
    CUSTOM_MODEL_NAME="gemma4-optimized-${MODEL_SIZE}-${context_k}k"
fi

# Validate that selected model will fit on GPU
print_header "Validating GPU Compatibility"

metal_gb=$((METAL_MEMORY / BYTES_PER_GB))
model_weight_gb=$(get_model_weight_gb "$MODEL_SIZE")
kv_cache_gb=$(calculate_kv_cache_gb "$MODEL_SIZE" "$CONTEXT_LENGTH")
total_needed_gb=$((model_weight_gb + kv_cache_gb))

echo "Selected Model: $GEMMA_MODEL"
echo "Context Window: $((CONTEXT_LENGTH / 1024))K tokens"
echo ""
echo "GPU Memory Requirements:"
echo "  • Model weights:     ${model_weight_gb}GB"
echo "  • KV cache:          ${kv_cache_gb}GB"
echo "  • Total needed:      ${total_needed_gb}GB"
echo "  • Available Metal:   ${metal_gb}GB"
echo ""

if ! validate_gpu_fit "$DETECTED_RAM_GB" "$MODEL_SIZE" "$CONTEXT_LENGTH"; then
    print_error "Model $GEMMA_MODEL will NOT fit entirely on GPU!"
    print_warning "This will result in CPU/GPU split and poor performance"
    echo ""
    echo "Recommended alternative: $RECOMMENDED_MODEL"

    if [[ "$AUTO_MODE" != true ]]; then
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using recommended model instead"
            GEMMA_MODEL="$RECOMMENDED_MODEL"
            MODEL_SIZE=$(get_model_size "$GEMMA_MODEL")
            CONTEXT_LENGTH=$(calculate_context_length "$DETECTED_RAM_GB" "$MODEL_SIZE")
            NUM_CTX=$CONTEXT_LENGTH
            METAL_MEMORY=$(calculate_metal_memory "$DETECTED_RAM_GB")
            # Regenerate custom model name with new context
            context_k=$((CONTEXT_LENGTH / 1024))
            CUSTOM_MODEL_NAME="gemma4-optimized-${MODEL_SIZE}-${context_k}k"
        fi
    else
        print_error "Cannot proceed in --auto mode with incompatible model"
        exit 1
    fi
else
    print_status "Model will run at 100% GPU - optimal performance!"

    # Check for tight fit (less than 10% headroom)
    headroom_gb=$((metal_gb - total_needed_gb))
    min_headroom=$((metal_gb / 10))
    if [[ $headroom_gb -lt $min_headroom ]]; then
        print_warning "Running close to GPU memory limit (${headroom_gb}GB headroom)"
        print_info "Performance may degrade under memory pressure or with concurrent apps"
        print_info "Consider closing other apps or using a smaller model for best stability"
    fi
fi

#############################################
# Helper Functions
#############################################

# Validate model name against allowed list
validate_model_name() {
    local model="$1"

    # First check against allowed patterns
    case "$model" in
        gemma4:e2b|gemma4:latest|gemma4:26b|gemma4:31b)
            # Verify exact length to detect null bytes or other hidden characters
            # gemma4:e2b=10, gemma4:latest=13, gemma4:26b=10, gemma4:31b=10
            # Bash preserves null bytes in length, so 'gemma4:e2b\0' would be length 11
            local expected_len
            case "$model" in
                gemma4:latest) expected_len=13 ;;
                gemma4:e2b|gemma4:26b|gemma4:31b) expected_len=10 ;;
            esac

            if [ ${#model} -ne "$expected_len" ]; then
                print_error "Invalid model name: contains invalid characters"
                return 1
            fi
            return 0
            ;;
        *)
            print_error "Invalid model name: $model"
            print_info "Allowed models: gemma4:e2b, gemma4:latest, gemma4:26b, gemma4:31b"
            return 1
            ;;
    esac
}

# Get ollama list output (cached to avoid multiple subprocess calls)
get_ollama_list() {
    if [[ -z "$OLLAMA_LIST_CACHE" ]]; then
        OLLAMA_LIST_CACHE=$(ollama list 2>/dev/null || echo "")
    fi
    echo "$OLLAMA_LIST_CACHE"
}

# Clear ollama list cache (call after pulling new models)
clear_ollama_cache() {
    OLLAMA_LIST_CACHE=""
}

#############################################
# Validation Functions
#############################################

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script requires macOS"
        exit 1
    fi
}

check_apple_silicon() {
    if ! sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple"; then
        print_warning "This script is optimized for Apple Silicon (M1/M2/M3/M4)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew is not installed"
        print_info "Install Homebrew: https://brew.sh"
        exit 1
    fi
    print_status "Homebrew found: $(brew --version | head -1)"
}

#############################################
# Installation Functions
#############################################

install_ollama() {
    print_header "Step 1: Installing Ollama"

    if command -v ollama &> /dev/null; then
        local ollama_version
        ollama_version=$(ollama --version 2>/dev/null || echo "unknown")
        print_status "Ollama already installed: $ollama_version"

        # Check if it's outdated (disable auto-update to avoid hang)
        print_info "Checking for Ollama updates..."
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated ollama &> /dev/null; then
            print_info "Upgrading Ollama to latest version..."
            brew upgrade ollama
            print_status "Ollama upgraded"
        else
            print_info "Ollama is up to date"
        fi
    else
        print_info "Installing Ollama via Homebrew..."
        brew install ollama
        print_status "Ollama installed"
    fi

    # Stop any existing Homebrew service
    if brew services list | grep -q "ollama.*started"; then
        print_info "Stopping Homebrew-managed ollama service..."
        brew services stop ollama 2>/dev/null || true
        print_status "Homebrew ollama service stopped"
    fi

    # Stop any running ollama processes
    if pgrep -x ollama > /dev/null; then
        print_info "Stopping running ollama processes..."
        pkill -x ollama || true
        sleep 2
        print_status "Ollama processes stopped"
    fi
}

install_opencode() {
    print_header "Step 2: Installing OpenCode"

    if command -v opencode &> /dev/null; then
        local opencode_version
        opencode_version=$(opencode --version 2>/dev/null || echo "unknown")
        print_status "OpenCode already installed: $opencode_version"

        # Check if anomalyco tap is added
        if ! brew tap | grep -q "anomalyco/tap"; then
            print_info "Adding anomalyco/tap..."
            brew tap anomalyco/tap
        fi

        # Check if it's outdated (disable auto-update to avoid hang)
        print_info "Checking for OpenCode updates..."
        if HOMEBREW_NO_AUTO_UPDATE=1 brew outdated opencode &> /dev/null; then
            print_info "Upgrading OpenCode to latest version..."
            brew upgrade opencode
            print_status "OpenCode upgraded"
        else
            print_info "OpenCode is up to date"
        fi
    else
        print_info "Adding anomalyco/tap..."
        brew tap anomalyco/tap

        print_info "Installing OpenCode via Homebrew..."
        brew install anomalyco/tap/opencode
        print_status "OpenCode installed"
    fi
}

#############################################
# LaunchAgent Configuration
#############################################

create_launchagent() {
    print_header "Step 3: Configuring Ollama LaunchAgent"

    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$HOME/Library/LaunchAgents"

    # Check if LaunchAgent already exists and is loaded
    local needs_reload=false
    if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
        print_info "LaunchAgent already exists at $LAUNCHAGENT_PLIST"

        # Check if it's already loaded
        if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
            print_info "Unloading existing LaunchAgent..."
            launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true
            sleep 2
        fi
        needs_reload=true
    fi

    # Detect Homebrew prefix (handles both Intel and Apple Silicon)
    local brew_prefix
    brew_prefix=$(brew --prefix)

    print_info "Creating dynamically optimized LaunchAgent configuration..."
    print_info "Optimizations based on your hardware:"
    echo "  • Metal Memory:     $(numfmt --to=iec-i --suffix=B "$METAL_MEMORY" 2>/dev/null || echo "${METAL_MEMORY} bytes")"
    echo "  • Parallel Requests: $NUM_PARALLEL"
    echo "  • Context Length:    $(printf "%'d" "$CONTEXT_LENGTH") tokens"
    echo "  • GPU Layers:        All (999)"
    echo ""

    # Create log directory
    mkdir -p "$HOME/.local/var/log"

    cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCHAGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${brew_prefix}/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:11434</string>
        <key>OLLAMA_METAL_MEMORY</key>
        <string>${METAL_MEMORY}</string>
        <key>OLLAMA_KEEP_ALIVE</key>
        <string>-1</string>
        <key>OLLAMA_NUM_PARALLEL</key>
        <string>${NUM_PARALLEL}</string>
        <key>OLLAMA_FLASH_ATTENTION</key>
        <string>1</string>
        <key>OLLAMA_GPU_LAYERS</key>
        <string>999</string>
        <key>OLLAMA_CONTEXT_LENGTH</key>
        <string>${CONTEXT_LENGTH}</string>
        <key>OLLAMA_NUM_CTX</key>
        <string>${NUM_CTX}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/.local/var/log/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/var/log/ollama.stderr.log</string>
</dict>
</plist>
EOF

    print_status "LaunchAgent configuration created with hardware-optimized settings"

    # Load the LaunchAgent
    print_info "Loading LaunchAgent (starts Ollama)..."
    launchctl load "$LAUNCHAGENT_PLIST"

    if [[ "$needs_reload" == true ]]; then
        print_status "LaunchAgent reloaded with new configuration"
    else
        print_status "LaunchAgent loaded - Ollama will start automatically on boot"
    fi

    # Wait for Ollama to be ready
    print_info "Waiting for Ollama server to be ready..."
    local max_attempts=60
    local attempt=0
    while ! curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            print_error "Ollama server failed to start after ${max_attempts} seconds"
            print_info "Check logs: tail -f $HOME/.local/var/log/ollama.stdout.log $HOME/.local/var/log/ollama.stderr.log"
            exit 1
        fi
        sleep 1
    done
    print_status "Ollama server is ready"
}

#############################################
# Model Setup
#############################################

pull_model() {
    print_header "Step 4: Pulling Gemma4 Model"

    # Check if model already exists (using cached list)
    if get_ollama_list | grep -q "^${GEMMA_MODEL}"; then
        print_status "Model $GEMMA_MODEL already pulled"
        return 0
    fi

    print_info "Pulling model: $GEMMA_MODEL"
    print_warning "This may take 15-30 minutes depending on your internet connection..."

    # Get model specifications from data structure
    local model_variant="${GEMMA_MODEL#*:}"
    local specs
    specs=$(get_model_specs "$model_variant")

    if [[ -n "$specs" ]]; then
        # Parse specifications
        read -r size_gb context_k min_ram_gb <<< "$specs"

        print_info "Model: gemma4:${model_variant} (${size_gb}GB download, ${context_k}K context)"
        print_info "Recommended RAM: ${min_ram_gb}GB+"

        if [[ $DETECTED_RAM_GB -lt $min_ram_gb ]]; then
            print_warning "Your system has ${DETECTED_RAM_GB}GB RAM - ${min_ram_gb}GB+ recommended"
        else
            print_status "Your ${DETECTED_RAM_GB}GB RAM is sufficient for this model"
        fi
    else
        print_info "Downloading ${GEMMA_MODEL}..."
    fi

    if ollama pull "$GEMMA_MODEL"; then
        print_status "Model $GEMMA_MODEL pulled successfully"
        clear_ollama_cache  # Invalidate cache after pulling new model
    else
        print_error "Failed to pull model $GEMMA_MODEL"
        exit 1
    fi
}

create_custom_model() {
    print_header "Step 5: Creating High-Context Model Variant"

    # Check if custom model already exists (using cached list)
    if get_ollama_list | grep -q "^${CUSTOM_MODEL_NAME}"; then
        print_status "Custom model $CUSTOM_MODEL_NAME already exists"

        # Ask if user wants to recreate it (skip in auto mode)
        if [[ "$AUTO_MODE" != true ]]; then
            read -p "Recreate $CUSTOM_MODEL_NAME with latest settings? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 0
            fi
        else
            print_info "Auto mode: skipping recreation of existing model"
            return 0
        fi

        print_info "Removing existing $CUSTOM_MODEL_NAME..."
        ollama rm "$CUSTOM_MODEL_NAME" 2>/dev/null || true
        clear_ollama_cache  # Invalidate cache after removing model
    fi

    # Format context window for display
    local context_display
    if [[ $NUM_CTX -ge 100000 ]]; then
        context_display="$((NUM_CTX / 1024))K"
    else
        context_display="$NUM_CTX"
    fi

    print_info "Creating $CUSTOM_MODEL_NAME with ${context_display} token context window..."
    print_info "Configuration optimized for ${DETECTED_RAM_GB}GB RAM"

    # Create temporary Modelfile
    local modelfile_path
    modelfile_path=$(mktemp "/tmp/Modelfile.XXXXXX") || {
        print_error "Failed to create temporary file"
        exit 1
    }
    cat > "$modelfile_path" << EOF
FROM ${GEMMA_MODEL}

# Set context window optimized for ${DETECTED_RAM_GB}GB RAM
PARAMETER num_ctx ${NUM_CTX}

# Optimize for code generation
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40

# System prompt optimized for coding
SYSTEM """
You are a helpful AI coding assistant. You provide clear, accurate, and well-documented code solutions.
Focus on code quality, best practices, and security.
"""
EOF

    # Create the custom model
    if ollama create "$CUSTOM_MODEL_NAME" -f "$modelfile_path"; then
        print_status "Custom model $CUSTOM_MODEL_NAME created successfully"
        print_status "Context: ${context_display} tokens (optimized for your ${DETECTED_RAM_GB}GB RAM)"
        rm "$modelfile_path"
        clear_ollama_cache  # Invalidate cache after creating new model
    else
        print_error "Failed to create custom model $CUSTOM_MODEL_NAME"
        rm "$modelfile_path"
        exit 1
    fi

    # Verify the model
    print_info "Verifying model configuration..."
    if ollama show "$CUSTOM_MODEL_NAME" &> /dev/null; then
        print_status "Model verified: $CUSTOM_MODEL_NAME"
    else
        print_error "Model verification failed"
        exit 1
    fi
}

#############################################
# OpenCode Configuration
#############################################

configure_opencode() {
    print_header "Step 6: Configuring OpenCode"

    local opencode_config="$HOME/.config/opencode/opencode.json"

    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$opencode_config")"

    # Check if config already exists
    if [[ -f "$opencode_config" ]]; then
        print_info "OpenCode config already exists"

        # Backup existing config
        local backup_path
        backup_path="${opencode_config}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$opencode_config" "$backup_path"
        print_info "Existing config backed up to: $backup_path"
    fi

    # Ask about superpowers plugin (skip in auto mode)
    local install_plugin=false
    if [[ "$AUTO_MODE" != true ]]; then
        echo ""
        echo -e "${BLUE}Optional: Superpowers Plugin${NC}"
        echo "The superpowers plugin adds enhanced OpenCode capabilities:"
        echo "  • Advanced workflows and skills"
        echo "  • Extended tool integrations"
        echo "  • Source: https://github.com/obra/superpowers"
        echo ""
        read -p "Install superpowers plugin? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_plugin=true
        fi
    fi

    print_info "Creating OpenCode configuration..."
    print_info "Model: ollama/$CUSTOM_MODEL_NAME"
    print_info "Context window: $(printf "%'d" "$NUM_CTX") tokens"

    # OpenCode uses model format: "ollama/model-name"
    # Ollama API URL needs /v1 suffix for OpenAI-compatible endpoint
    if [[ "$install_plugin" == true ]]; then
        # Config with plugin
        cat > "$opencode_config" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${CUSTOM_MODEL_NAME}",
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ],
  "provider": {
    "ollama": {
      "name": "Ollama",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${OLLAMA_HOST}/v1"
      },
      "models": {
        "${GEMMA_MODEL}": {
          "name": "${GEMMA_MODEL}"
        },
        "${CUSTOM_MODEL_NAME}": {
          "name": "${CUSTOM_MODEL_NAME}:latest"
        }
      }
    }
  }
}
EOF
    else
        # Config without plugin
        cat > "$opencode_config" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/${CUSTOM_MODEL_NAME}",
  "provider": {
    "ollama": {
      "name": "Ollama",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${OLLAMA_HOST}/v1"
      },
      "models": {
        "${GEMMA_MODEL}": {
          "name": "${GEMMA_MODEL}"
        },
        "${CUSTOM_MODEL_NAME}": {
          "name": "${CUSTOM_MODEL_NAME}:latest"
        }
      }
    }
  }
}
EOF
    fi

    print_status "OpenCode configured to use ollama/$CUSTOM_MODEL_NAME"
    print_status "Ollama endpoint: ${OLLAMA_HOST}/v1"
    print_status "Context: $(printf "%'d" "$NUM_CTX") tokens"

    if [[ "$install_plugin" == true ]]; then
        print_status "Plugin: superpowers (github.com/obra/superpowers)"
    else
        print_info "No plugins configured (you can add them later to opencode.json)"
    fi
}

#############################################
# Verification & Usage Instructions
#############################################

verify_setup() {
    print_header "Verification"

    local all_good=true

    # Check Ollama
    if command -v ollama &> /dev/null; then
        print_status "Ollama: $(ollama --version 2>/dev/null | head -1)"
    else
        print_error "Ollama: NOT FOUND"
        all_good=false
    fi

    # Check OpenCode
    if command -v opencode &> /dev/null; then
        print_status "OpenCode: $(opencode --version 2>/dev/null || echo 'installed')"
    else
        print_error "OpenCode: NOT FOUND"
        all_good=false
    fi

    # Check Ollama server
    if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        print_status "Ollama Server: Running at $OLLAMA_HOST"
    else
        print_error "Ollama Server: NOT RUNNING"
        all_good=false
    fi

    # Check LaunchAgent
    if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
        print_status "LaunchAgent: Loaded and active"
    else
        print_error "LaunchAgent: NOT LOADED"
        all_good=false
    fi

    # Check models (using cached list for efficiency)
    local model_list
    model_list=$(get_ollama_list)

    if echo "$model_list" | grep -q "^${GEMMA_MODEL}"; then
        print_status "Base Model: $GEMMA_MODEL"
    else
        print_error "Base Model: $GEMMA_MODEL NOT FOUND"
        all_good=false
    fi

    if echo "$model_list" | grep -q "^${CUSTOM_MODEL_NAME}"; then
        print_status "Custom Model: $CUSTOM_MODEL_NAME"
    else
        print_error "Custom Model: $CUSTOM_MODEL_NAME NOT FOUND"
        all_good=false
    fi

    # Check OpenCode config
    if [[ -f "$HOME/.config/opencode/opencode.json" ]]; then
        print_status "OpenCode Config: $HOME/.config/opencode/opencode.json"
    else
        print_error "OpenCode Config: NOT FOUND"
        all_good=false
    fi

    echo
    if [[ "$all_good" == true ]]; then
        print_status "All checks passed! ✨"
    else
        print_error "Some checks failed - review output above"
        return 1
    fi
}

print_usage_instructions() {
    print_header "Setup Complete! 🚀"

    # Format context for display
    local context_display
    if [[ $NUM_CTX -ge 100000 ]]; then
        context_display="$((NUM_CTX / 1024))K"
    else
        context_display="$(printf "%'d" "$NUM_CTX")"
    fi

    cat << EOF
Your Gemma4 + OpenCode environment is ready to use!

Hardware Configuration:
----------------------
- Chip:           $DETECTED_M_CHIP
- RAM:            ${DETECTED_RAM_GB}GB
- CPU Cores:      $DETECTED_CPU_CORES
- Metal Memory:   $(numfmt --to=iec-i --suffix=B "$METAL_MEMORY" 2>/dev/null || echo "$((METAL_MEMORY / 1024 / 1024 / 1024))GB")
- Parallel Reqs:  $NUM_PARALLEL

Quick Start:
-----------
1. Launch OpenCode:
   $ opencode

2. Test the model:
   $ ollama run ${CUSTOM_MODEL_NAME}

3. Check installed models:
   $ ollama list

Server Management:
------------------
- View logs:       tail -f $HOME/.local/var/log/ollama.stdout.log
- Server status:   curl ${OLLAMA_HOST}/api/tags
- Restart server:  launchctl unload "$LAUNCHAGENT_PLIST" && launchctl load "$LAUNCHAGENT_PLIST"
- Stop server:     launchctl unload "$LAUNCHAGENT_PLIST"
- Start server:    launchctl load "$LAUNCHAGENT_PLIST"

Model Information:
-----------------
- Base Model:      ${GEMMA_MODEL}
- Custom Model:    ${CUSTOM_MODEL_NAME}
- Context Window:  ${context_display} tokens (optimized for ${DETECTED_RAM_GB}GB RAM)
- Optimizations:   Metal GPU, Flash Attention, Keep Alive, ${NUM_PARALLEL}x Parallel

OpenCode Configuration:
----------------------
- Config:          $HOME/.config/opencode/opencode.json
- Provider:        Ollama (local)
- Endpoint:        ${OLLAMA_HOST}/v1
- Context:         ${context_display} tokens

Performance Tips:
----------------
- Models stay loaded in memory (OLLAMA_KEEP_ALIVE=-1)
- All GPU layers enabled for maximum speed (OLLAMA_GPU_LAYERS=999)
- Monitor Activity Monitor → GPU → ollama for GPU usage (should be high during inference)
- First query after restart may be slower (model loading into RAM)
- Parallel requests: ${NUM_PARALLEL} (optimized for your ${DETECTED_RAM_GB}GB RAM)

Troubleshooting:
---------------
- If OpenCode can't connect: curl ${OLLAMA_HOST}/api/tags
- If model is slow: Check GPU usage in Activity Monitor
- If out of memory: Try a smaller model (./setup-gemma4-opencode.sh --model gemma4:e2b)
- View errors: tail -f $HOME/.local/var/log/ollama.stderr.log

Documentation:
-------------
- Ollama:   https://docs.ollama.com/
- OpenCode: https://opencode.ai/docs/
- Gemma:    https://ai.google.dev/gemma

Share With Your Team:
--------------------
# Auto-detect and setup:
  $ ./setup-gemma4-opencode.sh --auto

# Specify a model:
  $ ./setup-gemma4-opencode.sh --model gemma4:26b

# Interactive (shows recommendations):
  $ ./setup-gemma4-opencode.sh

Happy coding! 🎉
EOF
}

#############################################
# Main Execution
#############################################

main() {
    print_header "Gemma4 + OpenCode Setup for Teams"
    print_info "Hardware-optimized setup with dynamic configuration"
    print_info "This script is idempotent - safe to run multiple times"
    echo

    # Validation
    check_macos
    check_apple_silicon
    check_homebrew

    # Installation
    install_ollama
    install_opencode

    # Configuration (uses dynamic values based on hardware)
    create_launchagent

    # Model setup
    pull_model
    create_custom_model

    # OpenCode setup
    configure_opencode

    # Verification and instructions
    verify_setup
    print_usage_instructions
}

# Run main function
main "$@"
