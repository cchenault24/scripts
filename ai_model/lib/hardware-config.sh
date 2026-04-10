#!/bin/bash
# lib/hardware-config.sh - Hardware optimization calculations and constants
#
# Provides:
# - Hardware optimization constants
# - Dynamic configuration calculation functions

set -euo pipefail

# Get directory of this file for sourcing registry
HARDWARE_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HARDWARE_CONFIG_DIR/model-registry.sh"

#############################################
# Hardware Optimization Constants
#############################################

# Metal memory allocation strategy
readonly MAX_METAL_GB=80              # Cap for very high-RAM systems (leave room for OS)

# Parallel request thresholds (RAM GB -> parallel count)
readonly PARALLEL_TIER_ULTRA=64       # 64GB+ → 6 parallel requests
readonly PARALLEL_TIER_HIGH=48        # 48GB+ → 4 parallel requests
readonly PARALLEL_TIER_MED=32         # 32GB+ → 3 parallel requests
readonly PARALLEL_TIER_LOW=24         # 24GB+ → 2 parallel requests

# Model recommendation thresholds (minimum RAM in GB)
readonly MODEL_31B_MIN_RAM=48
readonly MODEL_26B_MIN_RAM=32
readonly MODEL_LATEST_MIN_RAM=16

#############################################
# Model Specifications
#############################################

# NOTE: Using case statements instead of associative arrays for bash 3.2 compatibility
# (macOS ships with bash 3.2 which doesn't support declare -A)

#############################################
# Hardware Optimization Functions
#############################################

# Calculate optimal Metal memory allocation (bytes)
calculate_metal_memory() {
    local ram_gb=$1
    local ram_bytes=$((ram_gb * BYTES_PER_GB))

    # Use 95% of RAM for Metal on systems with 32GB+ (leave 5% for OS)
    # Use 90% on smaller systems (more conservative)
    local metal_percent
    if [[ $ram_gb -ge 32 ]]; then
        metal_percent=95
    else
        metal_percent=90
    fi

    local metal_memory=$((ram_bytes * metal_percent / 100))

    # Cap at MAX_METAL_GB to leave room for OS
    local max_metal=$((MAX_METAL_GB * BYTES_PER_GB))
    if [[ $metal_memory -gt $max_metal ]]; then
        metal_memory=$max_metal
    fi

    echo "$metal_memory"
}

# Model size specifications (weights only, in GB)
# Delegates to model registry
get_model_weight_gb() {
    local model_key=$1
    get_registry_model_weight_gb "$model_key"
}

# Estimate KV cache size for a given context length
# Per-token KV cache size varies by model architecture
# Delegates to model registry for bytes_per_token values
calculate_kv_cache_gb() {
    local model_key=$1
    local context_tokens=$2

    # Get bytes per token from registry
    local bytes_per_token
    bytes_per_token=$(get_registry_kv_bytes_per_token "$model_key")

    # Calculate total KV cache in bytes
    # Divide by 1024^3 to get GB, but do intermediate steps to avoid overflow
    local kv_cache_mb=$(( (context_tokens / 1024) * (bytes_per_token / 1024) ))
    local kv_cache_gb=$(( kv_cache_mb / 1024 ))

    echo "$kv_cache_gb"
}

# Check if model + context fits in GPU memory
# Returns 0 if fits, 1 if doesn't fit
validate_gpu_fit() {
    local ram_gb=$1
    local model_key=$2
    local context_tokens=$3

    local metal_bytes
    metal_bytes=$(calculate_metal_memory "$ram_gb")
    local metal_gb=$((metal_bytes / BYTES_PER_GB))

    local model_weight_gb
    model_weight_gb=$(get_model_weight_gb "$model_key")

    local kv_cache_gb
    kv_cache_gb=$(calculate_kv_cache_gb "$model_key" "$context_tokens")

    local total_needed_gb=$((model_weight_gb + kv_cache_gb))

    # Add 5% overhead for runtime memory (connections, temporary buffers, etc.)
    local total_with_overhead=$((total_needed_gb * 105 / 100))

    if [[ $total_with_overhead -le $metal_gb ]]; then
        return 0  # Fits
    else
        return 1  # Doesn't fit
    fi
}

# Calculate optimal parallel requests based on available RAM
calculate_num_parallel() {
    local ram_gb=$1

    if [[ $ram_gb -ge $PARALLEL_TIER_ULTRA ]]; then
        echo "6"
    elif [[ $ram_gb -ge $PARALLEL_TIER_HIGH ]]; then
        echo "4"
    elif [[ $ram_gb -ge $PARALLEL_TIER_MED ]]; then
        echo "3"
    elif [[ $ram_gb -ge $PARALLEL_TIER_LOW ]]; then
        echo "2"
    else
        echo "1"
    fi
}

# Calculate optimal context length based on model and available RAM
# Different models have different native context windows - retrieved from registry
#
# Context window sizing considers both model weights AND KV cache memory
# Setting too large context causes CPU/GPU split and poor GPU utilization
#
# IMPORTANT: This function validates GPU fit and automatically reduces context
# until 100% GPU usage is achieved. Never returns a context that causes CPU/GPU split.
calculate_context_length() {
    local ram_gb=$1
    local model_key=$2  # e.g., "gemma4:31b", "phi4:latest"

    # Get model's native max context from registry (upper bound)
    local max_context
    max_context=$(get_registry_max_context "$model_key")

    # Get model weight for initial heuristics
    local model_weight_gb
    model_weight_gb=$(get_model_weight_gb "$model_key")

    # Start with optimistic context based on RAM and model size heuristics
    # Use model weight as a proxy for complexity
    local candidate_context
    if [[ $model_weight_gb -ge 30 ]]; then
        # Very large models (40GB+) - e.g., llama3.1:70b
        if [[ $ram_gb -ge 80 ]]; then
            candidate_context="65536"   # 64K context
        elif [[ $ram_gb -ge 64 ]]; then
            candidate_context="32768"   # 32K context
        else
            candidate_context="16384"   # 16K context
        fi
    elif [[ $model_weight_gb -ge 15 ]]; then
        # Large models (15-30GB) - e.g., gemma4:31b, gemma4:26b, granite-code:34b
        if [[ $ram_gb -ge 80 ]]; then
            candidate_context="131072"  # 128K context
        elif [[ $ram_gb -ge 64 ]]; then
            candidate_context="65536"   # 64K context
        elif [[ $ram_gb -ge 48 ]]; then
            candidate_context="32768"   # 32K context
        else
            candidate_context="16384"   # 16K context
        fi
    elif [[ $model_weight_gb -ge 8 ]]; then
        # Medium models (8-15GB) - e.g., gemma4:latest, phi4:latest, mistral-small
        if [[ $ram_gb -ge 48 ]]; then
            candidate_context="131072"  # 128K context
        elif [[ $ram_gb -ge 32 ]]; then
            candidate_context="65536"   # 64K context
        elif [[ $ram_gb -ge 16 ]]; then
            candidate_context="32768"   # 32K context
        else
            candidate_context="16384"   # 16K context
        fi
    else
        # Small models (<8GB) - e.g., gemma4:e2b, phi4-mini, mistral, llama3.1:8b
        if [[ $ram_gb -ge 32 ]]; then
            candidate_context="131072"  # 128K context
        elif [[ $ram_gb -ge 24 ]]; then
            candidate_context="65536"   # 64K context
        elif [[ $ram_gb -ge 16 ]]; then
            candidate_context="32768"   # 32K context
        else
            candidate_context="16384"   # 16K context
        fi
    fi

    # Cap candidate at model's native max
    if [[ $candidate_context -gt $max_context ]]; then
        candidate_context=$max_context
    fi

    # Validate GPU fit and reduce context until it fits at 100% GPU
    # This ensures we NEVER recommend a context that causes CPU/GPU split
    local min_context=8192  # 8K minimum (practical lower bound for coding)

    while [[ $candidate_context -ge $min_context ]]; do
        if validate_gpu_fit "$ram_gb" "$model_key" "$candidate_context"; then
            # Found a context that fits on GPU!
            echo "$candidate_context"
            return 0
        fi

        # Didn't fit, try half the context
        candidate_context=$((candidate_context / 2))
    done

    # If we get here, even minimum context doesn't fit (very low RAM scenario)
    # Return minimum context anyway - user will see warning in validation step
    echo "$min_context"
}

# Recommend best model based on available RAM AND GPU fit
# Only recommends models that can run at 100% GPU with a reasonable context window
# Requires minimum 32K context for practical coding work
# Iterates over all models in registry and picks the best fit
recommend_model() {
    local ram_gb=$1
    local min_useful_context=32768  # 32K minimum for practical coding

    # Get all models from registry and test each one
    local best_model=""
    local best_weight=0

    while IFS= read -r model_key; do
        # Get model's minimum RAM requirement
        local min_ram
        min_ram=$(get_registry_min_ram "$model_key")

        # Skip if insufficient RAM
        if [[ $ram_gb -lt $min_ram ]]; then
            continue
        fi

        # Calculate what context this model would get
        local context
        context=$(calculate_context_length "$ram_gb" "$model_key")

        # Skip if context too small for practical use
        if [[ $context -lt $min_useful_context ]]; then
            continue
        fi

        # Verify GPU fit
        if ! validate_gpu_fit "$ram_gb" "$model_key" "$context"; then
            continue
        fi

        # This model fits! Track the largest one (proxy for capability)
        local weight
        weight=$(get_model_weight_gb "$model_key")
        if [[ $weight -gt $best_weight ]]; then
            best_model="$model_key"
            best_weight=$weight
        fi
    done < <(list_all_models)

    # Return best model, or fallback to first model if none fit
    if [[ -n "$best_model" ]]; then
        echo "$best_model"
    else
        # Fallback: return first small model (gemma4:e2b)
        echo "gemma4:e2b"
    fi
}

# Recommend best CodeGemma model based on available RAM
# CodeGemma is optimized for FIM (Fill-In-Middle) code completion in JetBrains
# Models: codegemma:2b (1.6GB, 8K) and codegemma:7b (5.0GB, 8K)
recommend_codegemma() {
    local ram_gb=$1

    # CodeGemma models are smaller and focused on code completion
    # 7b is better for 16GB+ systems, 2b works for constrained systems
    if [[ $ram_gb -ge 16 ]]; then
        echo "codegemma:7b"
    else
        echo "codegemma:2b"
    fi
}

# Get model variant from model name (e.g., "gemma4:26b" -> "26b", "phi4:latest" -> "latest")
get_model_variant() {
    local model=$1
    local variant="${model#*:}"
    # If no colon found, return the whole string
    if [[ "$variant" == "$model" ]]; then
        echo "latest"
    else
        echo "$variant"
    fi
}
