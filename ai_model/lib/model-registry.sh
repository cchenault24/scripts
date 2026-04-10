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
# Coding Priority Scoring
#############################################

# Get coding performance score based on real benchmarks
# Based on LiveCodeBench v6, HumanEval, and reasoning benchmarks
# Higher scores = better coding quality
# Args: model_key (format: "family:variant")
# Returns: integer score (0-15, inverted rank where 1st place = 15 points)
#
# Benchmark Sources:
#   - gemma4:31b: 80.0% LiveCodeBench v6 (Rank #1)
#   - gemma4:26b: 77.1% LiveCodeBench v6 (Rank #2)
#   - phi4-reasoning:plus: ~65% est, best reasoning depth (Rank #3)
#   - phi4-reasoning:latest: Exceeds DeepSeek-R1 Distill 70B (Rank #4)
#   - phi4:latest: ~58% est, fastest Phi4 (Rank #5)
#   - gemma4:latest: 52.0% LiveCodeBench (Rank #6)
#   - granite-code:34b: ~48% est, gov/enterprise (Rank #7)
#   - mistral-small:latest: ~45% est (Rank #8)
#   - llama3.1:70b: 88% HumanEval but impractical on <64GB (Rank #9)
#   - granite-code:8b: ~42% est, FIM bonus (Rank #10)
#   - gemma4:e2b: 44.0% LiveCodeBench (Rank #11)
#   - codegemma:7b: ~38% est, FIM only (Rank #12)
#   - llama3.1:8b: 68.1% HumanEval, general purpose (Rank #13)
#   - mistral:latest: 43.6% HumanEval (Rank #14)
#   - phi4-mini:latest: ~35% est, too small (Rank #15)
get_registry_coding_priority() {
    local model_key="$1"

    case "$model_key" in
        # Rank 1-2: Exceptional coding quality (15-14 points)
        gemma4:31b) echo "15" ;;                    # 80.0% LCB, #1
        gemma4:26b) echo "14" ;;                    # 77.1% LCB, #2

        # Rank 3-4: Excellent reasoning + coding (13-12 points)
        phi4-reasoning:plus) echo "13" ;;           # ~65%, best reasoning
        phi4-reasoning:latest) echo "12" ;;         # Beats DSR1-70B

        # Rank 5-6: Very good (11-10 points)
        phi4:latest) echo "11" ;;                   # ~58%, fastest Phi4
        gemma4:latest) echo "10" ;;                 # 52.0% LCB

        # Rank 7-8: Good (9-8 points)
        granite-code:34b) echo "9" ;;               # ~48%, gov/enterprise
        mistral-small:latest) echo "8" ;;           # ~45%

        # Rank 9-10: Decent (7-6 points)
        llama3.1:70b) echo "7" ;;                   # 88% HE, impractical <64GB
        granite-code:8b) echo "6" ;;                # ~42%, FIM bonus

        # Rank 11-12: Adequate (5-4 points)
        gemma4:e2b) echo "5" ;;                     # 44.0% LCB
        codegemma:7b) echo "4" ;;                   # ~38%, FIM only

        # Rank 13-14: Fair (3-2 points)
        llama3.1:8b) echo "3" ;;                    # 68.1% HE, general purpose
        mistral:latest) echo "2" ;;                 # 43.6% HE

        # Rank 15: Basic (1 point)
        phi4-mini:latest) echo "1" ;;               # ~35%, too small

        *)
            echo "ERROR: Unknown model '$model_key' in get_registry_coding_priority" >&2
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

#############################################
# FIM Model Registry
#############################################

# List all FIM-capable models
# Returns: newline-separated list of model keys
list_fim_models() {
    cat <<EOF
codegemma:7b-code
codegemma:2b-code
codestral:latest
ibm/granite3.3:8b
granite4:latest
codellama:7b-code
codellama:13b-code
EOF
}

# Get FIM model weight in GB
# Args: model_key (format: "family:variant" or "provider/family:variant")
# Returns: integer GB
get_fim_model_weight_gb() {
    local model_key="$1"

    case "$model_key" in
        codegemma:7b-code) echo "5" ;;
        codegemma:2b-code) echo "2" ;;
        codestral:latest) echo "12" ;;
        ibm/granite3.3:8b) echo "5" ;;
        granite4:latest) echo "5" ;;
        codellama:7b-code) echo "4" ;;
        codellama:13b-code) echo "8" ;;

        *)
            echo "ERROR: Unknown FIM model '$model_key' in get_fim_model_weight_gb" >&2
            return 1
            ;;
    esac
}

# Get FIM model display name for menu display
# Args: model_key (format: "family:variant" or "provider/family:variant")
# Returns: string for display in menus
get_fim_model_display_name() {
    local model_key="$1"

    case "$model_key" in
        codegemma:7b-code) echo "CodeGemma 7B" ;;
        codegemma:2b-code) echo "CodeGemma 2B" ;;
        codestral:latest) echo "Codestral" ;;
        ibm/granite3.3:8b) echo "Granite 3.3 8B" ;;
        granite4:latest) echo "Granite 4.0" ;;
        codellama:7b-code) echo "CodeLlama 7B" ;;
        codellama:13b-code) echo "CodeLlama 13B" ;;

        *)
            echo "ERROR: Unknown FIM model '$model_key' in get_fim_model_display_name" >&2
            return 1
            ;;
    esac
}

# Get FIM model description/notes
# Args: model_key (format: "family:variant" or "provider/family:variant")
# Returns: string describing capabilities and provider
get_fim_model_description() {
    local model_key="$1"

    case "$model_key" in
        codegemma:7b-code) echo "Best FIM quality (Google)" ;;
        codegemma:2b-code) echo "Fastest (Google)" ;;
        codestral:latest) echo "FIM + test generation (Mistral AI)" ;;
        ibm/granite3.3:8b) echo "FIM + chat capable (IBM)" ;;
        granite4:latest) echo "Newest, FIM + instruct (IBM)" ;;
        codellama:7b-code) echo "Proven FIM support (Meta)" ;;
        codellama:13b-code) echo "Better quality than 7B (Meta)" ;;

        *)
            echo "ERROR: Unknown FIM model '$model_key' in get_fim_model_description" >&2
            return 1
            ;;
    esac
}
