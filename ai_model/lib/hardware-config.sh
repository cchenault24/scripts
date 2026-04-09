#!/bin/bash
# lib/hardware-config.sh - Hardware optimization calculations and constants
#
# Provides:
# - Hardware optimization constants
# - Model specifications
# - Dynamic configuration calculation functions

set -euo pipefail

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
get_model_weight_gb() {
    local model_size=$1
    case "$model_size" in
        e2b) echo "7" ;;
        latest|e4b) echo "10" ;;
        26b) echo "17" ;;
        31b) echo "19" ;;
        *) echo "10" ;;
    esac
}

# Estimate KV cache size for a given context length
# Formula based on actual Gemma4 architecture: 2 (K+V) × layers × hidden_dim × context × fp16
# Gemma4 27B: 46 layers × 4608 hidden_dim
# Gemma4 9B:  42 layers × 3584 hidden_dim
# Per-token KV cache size (in bytes) - conservative real-world values:
#   31b: ~524,288 bytes/token (~512 KB/token, 128K ctx = ~65GB KV cache)
#   26b: ~400,000 bytes/token (~391 KB/token, 128K ctx = ~50GB KV cache)
#   latest/e4b: ~295,000 bytes/token (~288 KB/token, 128K ctx = ~36GB KV cache)
#   e2b: ~197,000 bytes/token (~192 KB/token, 128K ctx = ~24GB KV cache)
calculate_kv_cache_gb() {
    local model_size=$1
    local context_tokens=$2

    # Bytes per token for KV cache (conservative real-world values)
    # These match the memory usage observed in calculate_context_length comments
    local bytes_per_token
    case "$model_size" in
        31b) bytes_per_token=524288 ;;   # ~512 KB per token (128K ctx = ~65GB KV)
        26b) bytes_per_token=400000 ;;   # ~391 KB per token (128K ctx = ~50GB KV)
        latest|e4b) bytes_per_token=295000 ;;  # ~288 KB per token (128K ctx = ~36GB KV)
        e2b) bytes_per_token=197000 ;;   # ~192 KB per token (128K ctx = ~24GB KV)
        *) bytes_per_token=295000 ;;
    esac

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
    local model_size=$2
    local context_tokens=$3

    local metal_bytes
    metal_bytes=$(calculate_metal_memory "$ram_gb")
    local metal_gb=$((metal_bytes / BYTES_PER_GB))

    local model_weight_gb
    model_weight_gb=$(get_model_weight_gb "$model_size")

    local kv_cache_gb
    kv_cache_gb=$(calculate_kv_cache_gb "$model_size" "$context_tokens")

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
# Gemma4 models have different native context windows:
# - e2b, latest/e4b: 128K (131,072 tokens)
# - 26b, 31b: 256K (262,144 tokens)
#
# Context window sizing considers both model weights AND KV cache memory:
# - 31b model: ~19GB weights + KV cache (256K=~100GB, 128K=~50GB, 64K=~25GB)
# - Setting too large context causes CPU/GPU split and poor GPU utilization
calculate_context_length() {
    local ram_gb=$1
    local model_size=$2  # e.g., "e2b", "latest", "e4b", "26b", "31b"

    case "$model_size" in
        31b)
            # 31b: Very large model, conservative context for GPU fit
            # Model: 19GB, KV cache: ~512 KB/token (524,288 bytes/token)
            if [[ $ram_gb -ge 80 ]]; then
                echo "131072"  # 128K context (~65GB KV = ~84GB total)
            elif [[ $ram_gb -ge 64 ]]; then
                echo "65536"   # 64K context (~32GB KV = ~51GB total)
            elif [[ $ram_gb -ge 48 ]]; then
                echo "32768"   # 32K context (~16GB KV = ~35GB total)
            else
                echo "16384"   # 16K context (~8GB KV = ~27GB total)
            fi
            ;;
        26b)
            # 26b: Large model, better GPU fit than 31b
            # Model: 17GB, KV cache: ~390 KB/token (400,000 bytes/token)
            if [[ $ram_gb -ge 64 ]]; then
                echo "131072"  # 128K context (~50GB KV = ~67GB total)
            elif [[ $ram_gb -ge 48 ]]; then
                echo "65536"   # 64K context (~25GB KV = ~42GB total)
            elif [[ $ram_gb -ge 32 ]]; then
                echo "32768"   # 32K context (~12GB KV = ~29GB total)
            else
                echo "16384"   # 16K context (~6GB KV = ~23GB total)
            fi
            ;;
        e2b|latest|e4b)
            # Smaller models: ~10GB weights
            # e2b: ~192 KB/token (197,000 bytes), latest/e4b: ~288 KB/token (295,000 bytes)
            if [[ $ram_gb -ge 48 ]]; then
                echo "131072"  # 128K context (latest: ~36GB KV = ~46GB total, e2b: ~24GB KV = ~31GB total)
            elif [[ $ram_gb -ge 32 ]]; then
                echo "65536"   # 64K context (latest: ~18GB KV = ~28GB total, e2b: ~12GB KV = ~19GB total)
            elif [[ $ram_gb -ge 24 ]]; then
                echo "65536"   # 64K context
            elif [[ $ram_gb -ge 16 ]]; then
                echo "32768"   # 32K context
            else
                echo "16384"   # 16K context
            fi
            ;;
        *)
            echo "65536"  # 64K context default
            ;;
    esac
}

# Recommend best Gemma4 model based on available RAM AND GPU fit
# Only recommends models that can run at 100% GPU with a reasonable context window
# Requires minimum 32K context for practical coding work (relaxed from 64K for 16GB systems)
recommend_model() {
    local ram_gb=$1
    local min_useful_context=32768  # 32K minimum for practical coding (was 64K, too strict for 16GB)

    # Try models in order of capability, ensure they fit on GPU with useful context
    # Test with the context length that would be set for that model

    # Try 31b (best quality)
    if [[ $ram_gb -ge $MODEL_31B_MIN_RAM ]]; then
        local context_31b
        context_31b=$(calculate_context_length "$ram_gb" "31b")
        if [[ $context_31b -ge $min_useful_context ]] && validate_gpu_fit "$ram_gb" "31b" "$context_31b"; then
            echo "gemma4:31b"
            return 0
        fi
    fi

    # Try 26b (excellent quality, better GPU fit)
    if [[ $ram_gb -ge $MODEL_26B_MIN_RAM ]]; then
        local context_26b
        context_26b=$(calculate_context_length "$ram_gb" "26b")
        if [[ $context_26b -ge $min_useful_context ]] && validate_gpu_fit "$ram_gb" "26b" "$context_26b"; then
            echo "gemma4:26b"
            return 0
        fi
    fi

    # Try latest (good quality, smaller)
    if [[ $ram_gb -ge $MODEL_LATEST_MIN_RAM ]]; then
        local context_latest
        context_latest=$(calculate_context_length "$ram_gb" "latest")
        if [[ $context_latest -ge $min_useful_context ]] && validate_gpu_fit "$ram_gb" "latest" "$context_latest"; then
            echo "gemma4:latest"
            return 0
        fi
    fi

    # Fallback to e2b (smallest) - relax context requirement for low RAM systems
    echo "gemma4:e2b"
}

# Get model variant from model name (e.g., "gemma4:26b" -> "26b")
get_model_size() {
    local model=$1
    local variant="${model#*:}"
    # If it's just "gemma4" without variant, default to latest
    if [[ "$variant" == "gemma4" ]] || [[ -z "$variant" ]]; then
        echo "latest"
    else
        echo "$variant"
    fi
}

# Get model specifications (size, context, min_ram)
# Returns: "size_gb context_k min_ram_gb" or empty if model not found
get_model_specs() {
    local model_variant=$1

    case "$model_variant" in
        e2b)
            echo "7.2 128 12"
            ;;
        latest|e4b)
            echo "9.6 128 16"
            ;;
        26b)
            echo "18 256 32"
            ;;
        31b)
            echo "20 256 48"
            ;;
        *)
            echo ""
            ;;
    esac
}
