#!/bin/bash
#
# Model selection with RAM-based recommendations
#

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

select_model() {
    print_header "Model Selection"

    print_info "Detected system RAM: ${TOTAL_RAM_GB}GB"
    echo ""

    # Check for already installed models
    INSTALLED_MODELS=""
    if curl -s http://127.0.0.1:$PORT/api/tags >/dev/null 2>&1; then
        print_info "Checking already installed models..."
        INSTALLED_MODELS=$(curl -s http://127.0.0.1:$PORT/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^gemma4:" || true)

        if [ -n "$INSTALLED_MODELS" ]; then
            echo ""
            echo -e "${GREEN}Already Installed:${NC}"
            echo "$INSTALLED_MODELS" | while IFS= read -r model; do
                # Check if optimized variant exists
                if echo "$model" | grep -q "\-128k\|\-256k"; then
                    echo "  ✓ $model ${DIM}(optimized)${NC}"
                else
                    echo "  ✓ $model"
                fi
            done
            echo ""
        fi
    fi

    # Define available models with sizes and recommendations
    echo -e "${YELLOW}Available Gemma 4 Models (https://ollama.com/library/gemma4/tags):${NC}"
    echo ""

    # Function to check if model is installed
    is_installed() {
        echo "$INSTALLED_MODELS" | grep -q "^$1$" && echo " ${GREEN}[INSTALLED]${NC}" || echo ""
    }

    echo -e "${BLUE}Small Models (128K context):${NC}"
    echo -e "  1)  gemma4:e2b-it-q4_K_M    (7.2GB)  - Smallest quantized$(is_installed 'gemma4:e2b-it-q4_K_M')"
    echo -e "  2)  gemma4:e2b-it-q8_0      (8.1GB)  - Better quality$(is_installed 'gemma4:e2b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Medium Models (128K context):${NC}"
    echo -e "  3)  gemma4:e4b-it-q4_K_M    (9.6GB)  - Balanced size/quality$(is_installed 'gemma4:e4b-it-q4_K_M')"
    echo -e "  4)  gemma4:e4b-it-q8_0      (12GB)   - Higher quality$(is_installed 'gemma4:e4b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Large Models (256K context):${NC}"
    echo -e "  5)  gemma4:26b-a4b-it-q4_K_M (18GB)  - Large quantized$(is_installed 'gemma4:26b-a4b-it-q4_K_M')"
    echo -e "  6)  gemma4:26b-a4b-it-q8_0   (28GB)  - Large high quality$(is_installed 'gemma4:26b-a4b-it-q8_0')"
    echo ""
    echo -e "${BLUE}Extra Large Models (256K context):${NC}"
    echo -e "  7)  gemma4:31b-it-q4_K_M    (20GB)  - XL quantized$(is_installed 'gemma4:31b-it-q4_K_M')"
    echo -e "  8)  gemma4:31b-it-q8_0      (34GB)  - XL high quality$(is_installed 'gemma4:31b-it-q8_0')"
    echo ""

    # Provide recommendations based on RAM
    echo -e "${GREEN}Recommendations for ${TOTAL_RAM_GB}GB RAM:${NC}"
    if [ "$TOTAL_RAM_GB" -ge 48 ]; then
        echo "  • Best: gemma4:31b-it-q8_0 (34GB, excellent quality, 256K context)"
        echo "  • Alt:  gemma4:31b-it-q4_K_M (20GB, good quality)"
    elif [ "$TOTAL_RAM_GB" -ge 32 ]; then
        echo "  • Best: gemma4:26b-a4b-it-q8_0 (28GB, high quality, 256K context)"
        echo "  • Alt:  gemma4:31b-it-q4_K_M (20GB, larger model, quantized)"
    elif [ "$TOTAL_RAM_GB" -ge 24 ]; then
        echo "  • Best: gemma4:26b-a4b-it-q4_K_M (18GB, good balance, 256K context)"
        echo "  • Alt:  gemma4:e4b-it-q8_0 (12GB, smaller model, higher quality)"
    elif [ "$TOTAL_RAM_GB" -ge 16 ]; then
        echo "  • Best: gemma4:e4b-it-q8_0 (12GB, good quality)"
        echo "  • Alt:  gemma4:e4b-it-q4_K_M (9.6GB, balanced)"
    else
        echo "  • Best: gemma4:e2b-it-q4_K_M (7.2GB, smallest)"
        print_warning "Your system has ${TOTAL_RAM_GB}GB RAM. 16GB+ recommended for better models."
    fi
    echo ""
    echo "  Context sizes: Small/Medium (128K), Large/XL (256K)"
    echo "  Quantization: q4_K_M (smaller, faster) < q8_0 (larger, better quality)"
    echo ""

    # Prompt for selection
    while true; do
        read -p "Select model (1-8) or enter custom model name: " choice
        case $choice in
            1)  export OLLAMA_MODEL="gemma4:e2b-it-q4_K_M"; break ;;
            2)  export OLLAMA_MODEL="gemma4:e2b-it-q8_0"; break ;;
            3)  export OLLAMA_MODEL="gemma4:e4b-it-q4_K_M"; break ;;
            4)  export OLLAMA_MODEL="gemma4:e4b-it-q8_0"; break ;;
            5)  export OLLAMA_MODEL="gemma4:26b-a4b-it-q4_K_M"; break ;;
            6)  export OLLAMA_MODEL="gemma4:26b-a4b-it-q8_0"; break ;;
            7)  export OLLAMA_MODEL="gemma4:31b-it-q4_K_M"; break ;;
            8)  export OLLAMA_MODEL="gemma4:31b-it-q8_0"; break ;;
            gemma4:*)
                export OLLAMA_MODEL="$choice"
                print_info "Using custom model: $OLLAMA_MODEL"
                break
                ;;
            *)
                print_error "Invalid selection. Please choose 1-8 or enter a model name starting with 'gemma4:'"
                ;;
        esac
    done

    echo ""
    print_status "Selected model: $OLLAMA_MODEL"
    echo ""
}
