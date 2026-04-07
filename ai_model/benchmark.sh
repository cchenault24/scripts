#!/bin/bash
# benchmark.sh - Performance testing script for AI models

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the required libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Test Prompts Configuration
#############################################

# Test 1: Code Generation
CODE_GEN_PROMPT="Write a Python function to calculate fibonacci numbers recursively"
CODE_GEN_EXPECTED_TOKENS=100

# Test 2: Reasoning
REASONING_PROMPT="Explain why the sky is blue in simple terms"
REASONING_EXPECTED_TOKENS=150

# Test 3: Long Context
LONG_CONTEXT_TEXT="The field of artificial intelligence has experienced remarkable growth over the past decade, driven by advances in machine learning algorithms, increased computational power, and the availability of large datasets. Deep learning, a subset of machine learning based on artificial neural networks, has been particularly transformative. These neural networks, inspired by the structure and function of the human brain, consist of layers of interconnected nodes that process information in a hierarchical manner. The breakthrough in deep learning came with the development of more efficient training algorithms, such as backpropagation, and the use of specialized hardware like GPUs that can perform the massive parallel computations required for training large neural networks. Natural language processing, computer vision, and reinforcement learning have all benefited from these advances. Language models like GPT and BERT have achieved human-level performance on many language understanding tasks. In computer vision, convolutional neural networks can now classify images with greater accuracy than humans in many scenarios. Reinforcement learning algorithms have mastered complex games like Go and Chess, demonstrating superhuman performance. The applications of AI span numerous industries: healthcare systems use AI for diagnosis and treatment recommendations, autonomous vehicles rely on AI for perception and decision-making, financial institutions employ AI for fraud detection and algorithmic trading, and recommendation systems powered by AI shape our online experiences. However, the rapid advancement of AI also raises important ethical and societal questions. Issues of algorithmic bias, privacy concerns, job displacement, and the need for AI safety and alignment remain active areas of research and policy discussion. As AI systems become more capable and ubiquitous, ensuring they are developed and deployed responsibly becomes increasingly critical. The future of AI likely involves continued progress in making systems more efficient, interpretable, and aligned with human values, as well as addressing the broader societal implications of this transformative technology."
LONG_CONTEXT_PROMPT="Summarize: $LONG_CONTEXT_TEXT"
LONG_CONTEXT_EXPECTED_TOKENS=200

# Test 4: Speed Test
SPEED_TEST_PROMPT="Say 'hi'"
SPEED_TEST_EXPECTED_TOKENS=1

#############################################
# Test Execution Functions
#############################################

# Run a single test and measure performance
run_test() {
    local model="$1"
    local prompt="$2"
    local expected_tokens="$3"

    # Start time measurement
    local start=$(date +%s.%N)

    # Make API call
    local response=$(curl -s "http://127.0.0.1:$PORT/api/generate" \
        -d "{\"model\":\"$model\",\"prompt\":\"$prompt\",\"stream\":false}")

    # End time measurement
    local end=$(date +%s.%N)
    local duration=$(echo "$end - $start" | bc)

    # Extract token count from response
    local tokens=$(echo "$response" | jq -r '.eval_count // 0')

    # Calculate tokens per second
    local tokens_per_sec=0
    if [[ "$tokens" -gt 0 ]] && [[ $(echo "$duration > 0" | bc) -eq 1 ]]; then
        tokens_per_sec=$(echo "scale=2; $tokens / $duration" | bc)
    fi

    # Return results as JSON-like string
    echo "$tokens_per_sec|$duration|$tokens"
}

# Format number with proper alignment
format_number() {
    local num="$1"
    local width="${2:-10}"
    printf "%-${width}s" "$num"
}

# Draw table border
draw_border() {
    local char="$1"
    printf "$char"
    printf '%.0s─' {1..18}
    printf "$char"
    printf '%.0s─' {1..12}
    printf "$char"
    printf '%.0s─' {1..12}
    printf "$char"
    printf '%.0s─' {1..11}
    printf "$char\n"
}

# Run all tests for a single model
benchmark_model() {
    local model="$1"

    print_header "Benchmarking $model"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Start the server first with: start_ollama_server"
        return 1
    fi

    # Verify model exists
    print_info "Verifying model availability..."
    if ! curl -s "http://127.0.0.1:$PORT/api/tags" | jq -r '.models[].name' | grep -q "^${model}$"; then
        print_error "Model not found: $model"
        print_info "Available models:"
        curl -s "http://127.0.0.1:$PORT/api/tags" | jq -r '.models[].name'
        return 1
    fi

    print_status "Model verified"
    echo ""

    # Run tests
    print_info "Running Test 1/4: Code Generation..."
    local code_gen_result=$(run_test "$model" "$CODE_GEN_PROMPT" "$CODE_GEN_EXPECTED_TOKENS")

    print_info "Running Test 2/4: Reasoning..."
    local reasoning_result=$(run_test "$model" "$REASONING_PROMPT" "$REASONING_EXPECTED_TOKENS")

    print_info "Running Test 3/4: Long Context..."
    local long_context_result=$(run_test "$model" "$LONG_CONTEXT_PROMPT" "$LONG_CONTEXT_EXPECTED_TOKENS")

    print_info "Running Test 4/4: Speed Test..."
    local speed_test_result=$(run_test "$model" "$SPEED_TEST_PROMPT" "$SPEED_TEST_EXPECTED_TOKENS")

    # Parse results
    IFS='|' read -r code_tps code_dur code_tok <<< "$code_gen_result"
    IFS='|' read -r reas_tps reas_dur reas_tok <<< "$reasoning_result"
    IFS='|' read -r long_tps long_dur long_tok <<< "$long_context_result"
    IFS='|' read -r speed_tps speed_dur speed_tok <<< "$speed_test_result"

    # Calculate average
    local avg_tps=$(echo "scale=2; ($code_tps + $reas_tps + $long_tps + $speed_tps) / 4" | bc)

    # Display results
    echo ""
    print_header "Test Results"

    draw_border "┌"
    printf "│ %-16s │ %-10s │ %-10s │ %-9s │\n" "Test" "Tokens/sec" "Total Time" "Tokens"
    draw_border "├"
    printf "│ %-16s │ %-10s │ %-9ss │ %-9s │\n" "Code Generation" "$code_tps" "$code_dur" "$code_tok"
    printf "│ %-16s │ %-10s │ %-9ss │ %-9s │\n" "Reasoning" "$reas_tps" "$reas_dur" "$reas_tok"
    printf "│ %-16s │ %-10s │ %-9ss │ %-9s │\n" "Long Context" "$long_tps" "$long_dur" "$long_tok"
    printf "│ %-16s │ %-10s │ %-9ss │ %-9s │\n" "Speed Test" "$speed_tps" "$speed_dur" "$speed_tok"
    draw_border "└"

    echo ""
    print_status "Average: $avg_tps tokens/sec"

    # Return average for comparison mode
    echo "$avg_tps"
}

#############################################
# Comparison Mode
#############################################

compare_models() {
    local model1="$1"
    local model2="$2"

    print_header "Comparing Models"
    print_info "Model 1: $model1"
    print_info "Model 2: $model2"
    echo ""

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Start the server first with: start_ollama_server"
        return 1
    fi

    # Verify both models exist
    print_info "Verifying models..."
    local available_models=$(curl -s "http://127.0.0.1:$PORT/api/tags" | jq -r '.models[].name')

    if ! echo "$available_models" | grep -q "^${model1}$"; then
        print_error "Model not found: $model1"
        return 1
    fi

    if ! echo "$available_models" | grep -q "^${model2}$"; then
        print_error "Model not found: $model2"
        return 1
    fi

    print_status "Both models verified"
    echo ""

    # Run tests for model 1
    print_info "Testing $model1..."
    echo ""

    print_info "Running Test 1/4: Code Generation..."
    local m1_code_result=$(run_test "$model1" "$CODE_GEN_PROMPT" "$CODE_GEN_EXPECTED_TOKENS")

    print_info "Running Test 2/4: Reasoning..."
    local m1_reas_result=$(run_test "$model1" "$REASONING_PROMPT" "$REASONING_EXPECTED_TOKENS")

    print_info "Running Test 3/4: Long Context..."
    local m1_long_result=$(run_test "$model1" "$LONG_CONTEXT_PROMPT" "$LONG_CONTEXT_EXPECTED_TOKENS")

    print_info "Running Test 4/4: Speed Test..."
    local m1_speed_result=$(run_test "$model1" "$SPEED_TEST_PROMPT" "$SPEED_TEST_EXPECTED_TOKENS")

    echo ""
    print_info "Testing $model2..."
    echo ""

    print_info "Running Test 1/4: Code Generation..."
    local m2_code_result=$(run_test "$model2" "$CODE_GEN_PROMPT" "$CODE_GEN_EXPECTED_TOKENS")

    print_info "Running Test 2/4: Reasoning..."
    local m2_reas_result=$(run_test "$model2" "$REASONING_PROMPT" "$REASONING_EXPECTED_TOKENS")

    print_info "Running Test 3/4: Long Context..."
    local m2_long_result=$(run_test "$model2" "$LONG_CONTEXT_PROMPT" "$LONG_CONTEXT_EXPECTED_TOKENS")

    print_info "Running Test 4/4: Speed Test..."
    local m2_speed_result=$(run_test "$model2" "$SPEED_TEST_PROMPT" "$SPEED_TEST_EXPECTED_TOKENS")

    # Parse results
    IFS='|' read -r m1_code_tps m1_code_dur m1_code_tok <<< "$m1_code_result"
    IFS='|' read -r m1_reas_tps m1_reas_dur m1_reas_tok <<< "$m1_reas_result"
    IFS='|' read -r m1_long_tps m1_long_dur m1_long_tok <<< "$m1_long_result"
    IFS='|' read -r m1_speed_tps m1_speed_dur m1_speed_tok <<< "$m1_speed_result"

    IFS='|' read -r m2_code_tps m2_code_dur m2_code_tok <<< "$m2_code_result"
    IFS='|' read -r m2_reas_tps m2_reas_dur m2_reas_tok <<< "$m2_reas_result"
    IFS='|' read -r m2_long_tps m2_long_dur m2_long_tok <<< "$m2_long_result"
    IFS='|' read -r m2_speed_tps m2_speed_dur m2_speed_tok <<< "$m2_speed_result"

    # Determine winners
    local code_winner=$(echo "$m1_code_tps > $m2_code_tps" | bc -l)
    [[ "$code_winner" -eq 1 ]] && code_winner="$model1" || code_winner="$model2"

    local reas_winner=$(echo "$m1_reas_tps > $m2_reas_tps" | bc -l)
    [[ "$reas_winner" -eq 1 ]] && reas_winner="$model1" || reas_winner="$model2"

    local long_winner=$(echo "$m1_long_tps > $m2_long_tps" | bc -l)
    [[ "$long_winner" -eq 1 ]] && long_winner="$model1" || long_winner="$model2"

    local speed_winner=$(echo "$m1_speed_tps > $m2_speed_tps" | bc -l)
    [[ "$speed_winner" -eq 1 ]] && speed_winner="$model1" || speed_winner="$model2"

    # Calculate averages
    local m1_avg=$(echo "scale=2; ($m1_code_tps + $m1_reas_tps + $m1_long_tps + $m1_speed_tps) / 4" | bc)
    local m2_avg=$(echo "scale=2; ($m2_code_tps + $m2_reas_tps + $m2_long_tps + $m2_speed_tps) / 4" | bc)

    local avg_winner=$(echo "$m1_avg > $m2_avg" | bc -l)
    [[ "$avg_winner" -eq 1 ]] && avg_winner="$model1" || avg_winner="$model2"

    # Display comparison table
    echo ""
    print_header "Comparison Results"

    # Calculate column widths
    local m1_len=${#model1}
    local m2_len=${#model2}
    local max_model_len=$((m1_len > m2_len ? m1_len : m2_len))
    [[ $max_model_len -lt 10 ]] && max_model_len=10

    # Print header
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | Winner\n" "Test" "$model1" "$model2"
    printf "%.0s-" {1..60}
    echo ""

    # Print results
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | %s\n" \
        "Code Generation" "$m1_code_tps" "$m2_code_tps" "$code_winner"
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | %s\n" \
        "Reasoning" "$m1_reas_tps" "$m2_reas_tps" "$reas_winner"
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | %s\n" \
        "Long Context" "$m1_long_tps" "$m2_long_tps" "$long_winner"
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | %s\n" \
        "Speed Test" "$m1_speed_tps" "$m2_speed_tps" "$speed_winner"
    printf "%.0s-" {1..60}
    echo ""
    printf "%-20s | %-${max_model_len}s | %-${max_model_len}s | %s\n" \
        "Average" "$m1_avg" "$m2_avg" "$avg_winner"

    echo ""
    print_status "Overall Winner: $avg_winner"
}

#############################################
# Usage Information
#############################################

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <model_name>
       $0 --compare <model1> <model2>

Options:
    --compare    Compare two models side-by-side
    -h, --help   Show this help message

Examples:
    # Benchmark a single model
    $0 llama3.3:70b-instruct-q4_K_M

    # Compare two models
    $0 --compare llama3.3:70b-instruct-q4_K_M codellama:7b

Description:
    This script benchmarks AI models using 4 standard tests:
    1. Code Generation (~100 tokens)
    2. Reasoning (~150 tokens)
    3. Long Context (~200 tokens)
    4. Speed Test (1 token)

    Results include tokens/second, total time, and token count for each test.

Prerequisites:
    - Ollama server must be running (start_ollama_server)
    - Model must be pulled and available

EOF
}

#############################################
# Main Entry Point
#############################################

main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        print_error "No arguments provided"
        echo ""
        show_usage
        exit 1
    fi

    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --compare)
            if [[ $# -lt 3 ]]; then
                print_error "Compare mode requires two model names"
                echo ""
                show_usage
                exit 1
            fi
            compare_models "$2" "$3"
            ;;
        *)
            if [[ $# -eq 1 ]]; then
                benchmark_model "$1"
            else
                print_error "Invalid arguments"
                echo ""
                show_usage
                exit 1
            fi
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
