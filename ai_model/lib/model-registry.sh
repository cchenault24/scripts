#!/bin/bash
# lib/model-registry.sh - Single source of truth for model specifications
#
# Provides lookup functions for model properties across multiple model families.
# All model specifications are centralized here to enable easy addition of new models.
#
# Supported model families:
# - Gemma4 (Google)
# - Phi-4 (Microsoft)
# - Llama 3.1 (Meta)
# - Mistral (Mistral AI)
# - CodeGemma (Google)
# - Granite Code (IBM)
#
# Note: No Chinese-derived models (Qwen, DeepSeek, Yi, Baichuan) per government/defense requirements.

set -euo pipefail

#############################################
# Model Weight Lookup (GB)
#############################################

# Get model weight in GB
# Args: model_key (format: "family:variant", e.g., "gemma4:31b")
# Returns: integer GB
get_registry_model_weight_gb() {
    local model_key="$1"

    case "$model_key" in
        # Gemma4 models
        gemma4:e2b) echo "7" ;;
        gemma4:latest) echo "10" ;;
        gemma4:26b) echo "17" ;;
        gemma4:31b) echo "19" ;;

        # Phi-4 models
        phi4:latest) echo "9" ;;
        phi4-reasoning:latest) echo "9" ;;
        phi4-reasoning:plus) echo "9" ;;
        phi4-mini:latest) echo "3" ;;

        # Llama 3.1 models
        llama3.1:8b) echo "5" ;;
        llama3.1:70b) echo "40" ;;

        # Mistral models
        mistral:latest) echo "4" ;;
        mistral-small:latest) echo "12" ;;

        # CodeGemma models
        codegemma:7b) echo "5" ;;

        # IBM Granite models
        granite-code:8b) echo "5" ;;
        granite-code:34b) echo "20" ;;

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_model_weight_gb" >&2
            return 1
            ;;
    esac
}

#############################################
# Max Context Lookup (tokens)
#############################################

# Get model's maximum context window in tokens
# Args: model_key (format: "family:variant")
# Returns: integer tokens
get_registry_max_context() {
    local model_key="$1"

    case "$model_key" in
        # Gemma4 models
        gemma4:e2b) echo "131072" ;;
        gemma4:latest) echo "131072" ;;
        gemma4:26b) echo "262144" ;;
        gemma4:31b) echo "262144" ;;

        # Phi-4 models
        phi4:latest) echo "16384" ;;
        phi4-reasoning:latest) echo "32768" ;;
        phi4-reasoning:plus) echo "32768" ;;
        phi4-mini:latest) echo "131072" ;;

        # Llama 3.1 models
        llama3.1:8b) echo "131072" ;;
        llama3.1:70b) echo "131072" ;;

        # Mistral models
        mistral:latest) echo "32768" ;;
        mistral-small:latest) echo "131072" ;;

        # CodeGemma models
        codegemma:7b) echo "8192" ;;

        # IBM Granite models
        granite-code:8b) echo "131072" ;;
        granite-code:34b) echo "131072" ;;

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_max_context" >&2
            return 1
            ;;
    esac
}

#############################################
# Minimum RAM Lookup (GB)
#############################################

# Get minimum RAM required for model
# Args: model_key (format: "family:variant")
# Returns: integer GB
get_registry_min_ram() {
    local model_key="$1"

    case "$model_key" in
        # Gemma4 models
        gemma4:e2b) echo "12" ;;
        gemma4:latest) echo "16" ;;
        gemma4:26b) echo "32" ;;
        gemma4:31b) echo "48" ;;

        # Phi-4 models
        phi4:latest) echo "16" ;;
        phi4-reasoning:latest) echo "16" ;;
        phi4-reasoning:plus) echo "16" ;;
        phi4-mini:latest) echo "8" ;;

        # Llama 3.1 models
        llama3.1:8b) echo "8" ;;
        llama3.1:70b) echo "48" ;;

        # Mistral models
        mistral:latest) echo "8" ;;
        mistral-small:latest) echo "16" ;;

        # CodeGemma models
        codegemma:7b) echo "8" ;;

        # IBM Granite models
        granite-code:8b) echo "8" ;;
        granite-code:34b) echo "24" ;;

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_min_ram" >&2
            return 1
            ;;
    esac
}

#############################################
# KV Cache Bytes Per Token Lookup
#############################################

# Get KV cache memory requirement per token (bytes)
# Args: model_key (format: "family:variant")
# Returns: integer bytes per token
get_registry_kv_bytes_per_token() {
    local model_key="$1"

    case "$model_key" in
        # Gemma4 models
        gemma4:e2b) echo "197000" ;;
        gemma4:latest) echo "295000" ;;
        gemma4:26b) echo "400000" ;;
        gemma4:31b) echo "524288" ;;

        # Phi-4 models
        phi4:latest) echo "115000" ;;
        phi4-reasoning:latest) echo "115000" ;;
        phi4-reasoning:plus) echo "115000" ;;
        phi4-mini:latest) echo "65000" ;;

        # Llama 3.1 models
        llama3.1:8b) echo "131000" ;;
        llama3.1:70b) echo "393000" ;;

        # Mistral models
        mistral:latest) echo "131000" ;;
        mistral-small:latest) echo "200000" ;;

        # CodeGemma models
        codegemma:7b) echo "131000" ;;

        # IBM Granite models
        granite-code:8b) echo "131000" ;;
        granite-code:34b) echo "350000" ;;

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_kv_bytes_per_token" >&2
            return 1
            ;;
    esac
}

#############################################
# Display Name Lookup
#############################################

# Get human-readable display name for menu display
# Args: model_key (format: "family:variant")
# Returns: string for display in menus
get_registry_display_name() {
    local model_key="$1"

    case "$model_key" in
        # Gemma4 models
        gemma4:e2b) echo "Gemma4 e2b (7GB, 128K context)" ;;
        gemma4:latest) echo "Gemma4 latest (10GB, 128K context)" ;;
        gemma4:26b) echo "Gemma4 26b (17GB, 256K context)" ;;
        gemma4:31b) echo "Gemma4 31b (19GB, 256K context)" ;;

        # Phi-4 models
        phi4:latest) echo "Phi-4 latest (9GB, 16K context)" ;;
        phi4-reasoning:latest) echo "Phi-4 Reasoning (9GB, 32K context)" ;;
        phi4-reasoning:plus) echo "Phi-4 Reasoning Plus (9GB, 32K context)" ;;
        phi4-mini:latest) echo "Phi-4 Mini (3GB, 128K context)" ;;

        # Llama 3.1 models
        llama3.1:8b) echo "Llama 3.1 8B (5GB, 128K context)" ;;
        llama3.1:70b) echo "Llama 3.1 70B (40GB, 128K context)" ;;

        # Mistral models
        mistral:latest) echo "Mistral latest (4GB, 32K context)" ;;
        mistral-small:latest) echo "Mistral Small (12GB, 128K context)" ;;

        # CodeGemma models
        codegemma:7b) echo "CodeGemma 7B (5GB, 8K context)" ;;

        # IBM Granite models
        granite-code:8b) echo "Granite Code 8B (5GB, 128K context)" ;;
        granite-code:34b) echo "Granite Code 34B (20GB, 128K context)" ;;

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_display_name" >&2
            return 1
            ;;
    esac
}

#############################################
# List All Models
#############################################

# List all available model keys
# Returns: newline-separated list of model keys
list_all_models() {
    cat <<EOF
gemma4:e2b
gemma4:latest
gemma4:26b
gemma4:31b
phi4:latest
phi4-reasoning:latest
phi4-reasoning:plus
phi4-mini:latest
llama3.1:8b
llama3.1:70b
mistral:latest
mistral-small:latest
codegemma:7b
granite-code:8b
granite-code:34b
EOF
}
