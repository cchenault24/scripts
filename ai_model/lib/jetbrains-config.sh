#!/bin/bash
# lib/jetbrains-config.sh - JetBrains AI Assistant configuration
#
# Provides:
# - JetBrains AI Assistant settings configuration
# - Ollama provider setup for JetBrains IDEs
# - Compatible with IntelliJ IDEA, PyCharm, WebStorm, etc.
#
# JetBrains AI Assistant Model Configuration:
# - Core features: Gemma4 (in-editor code generation, commit messages)
# - Instant helpers: Gemma4 (chat context, title generation, name suggestions)
# - Completion model: CodeGemma (inline code completion via FIM)

set -euo pipefail

# Configure JetBrains AI Assistant with Ollama provider
#
# Globals read:
#   - CUSTOM_MODEL_NAME: Name of custom model
#   - GEMMA_MODEL: Base model name
#   - CODEGEMMA_MODEL: CodeGemma model for FIM
#   - OLLAMA_HOST: Ollama server URL
#   - NUM_CTX: Context length
#   - AUTO_MODE: Whether in auto mode
configure_jetbrains() {
    print_header "Configuring JetBrains AI Assistant"

    # JetBrains stores settings in IDE-specific locations
    # For AI Assistant, we need to configure the LLM provider
    local jetbrains_base="$HOME/Library/Application Support/JetBrains"

    print_info "JetBrains AI Assistant setup requires manual configuration"
    echo ""
    echo -e "${BLUE}Configuration Instructions:${NC}"
    echo ""
    echo "JetBrains AI Assistant uses 3 model slots:"
    echo ""
    echo -e "  ${YELLOW}1. Core features:${NC}"
    echo "     Used for: In-editor code generation, commit messages, etc."
    echo "     Model: ${CUSTOM_MODEL_NAME} (Gemma4)"
    echo ""
    echo -e "  ${YELLOW}2. Instant helpers:${NC}"
    echo "     Used for: Chat context collection, title generation, name suggestions"
    echo "     Model: ${CUSTOM_MODEL_NAME} (Gemma4) - same as Core"
    echo ""
    if [[ -n "$CODEGEMMA_MODEL" ]]; then
        echo -e "  ${YELLOW}3. Completion model:${NC}"
        echo "     Used for: Inline code completion (requires FIM)"
        echo "     Model: ${CODEGEMMA_MODEL} (CodeGemma)"
        echo ""
    else
        echo -e "  ${YELLOW}3. Completion model:${NC}"
        echo "     Not configured - CodeGemma needed for FIM completion"
        echo ""
    fi
    echo -e "${GREEN}Setup Steps:${NC}"
    echo ""
    echo "1. Open your JetBrains IDE (IntelliJ IDEA, PyCharm, WebStorm, etc.)"
    echo "2. Go to: Preferences/Settings → Tools → AI Assistant"
    echo "3. Under 'Language Models', click '+' to add a custom provider"
    echo ""
    echo -e "${GREEN}Configure Ollama Provider:${NC}"
    echo -e "   Provider Type:    ${BLUE}OpenAI-compatible${NC}"
    echo -e "   API Base URL:     ${BLUE}${OLLAMA_HOST}/v1${NC}"
    echo -e "   API Key:          ${BLUE}ollama${NC} (or leave empty)"
    echo ""
    echo "4. Assign models to each slot:"
    echo -e "   ${YELLOW}Core features:${NC}      ${CUSTOM_MODEL_NAME}"
    echo -e "   ${YELLOW}Instant helpers:${NC}    ${CUSTOM_MODEL_NAME}"
    if [[ -n "$CODEGEMMA_MODEL" ]]; then
        echo -e "   ${YELLOW}Completion model:${NC}   ${CODEGEMMA_MODEL}"
    else
        echo -e "   ${YELLOW}Completion model:${NC}   (not configured)"
    fi
    echo ""
    echo "5. Click 'Test Connection' to verify"
    echo "6. Save settings"
    echo ""

    # Create a reference file with these settings
    local config_ref="$HOME/.config/gemma4-setup/jetbrains-config-reference.txt"
    mkdir -p "$(dirname "$config_ref")"

    cat > "$config_ref" << EOF
JetBrains AI Assistant Configuration Reference
==============================================
Generated: $(date)

JetBrains AI Assistant uses 3 model slots:

1. Core Features Model (Gemma4):
--------------------------------
Provider Type:    OpenAI-compatible
API Base URL:     ${OLLAMA_HOST}/v1
Model Name:       ${CUSTOM_MODEL_NAME}
Base Model:       ${GEMMA_MODEL}
Context Window:   $(printf "%'d" "$NUM_CTX") tokens
API Key:          ollama (or leave empty)
Purpose:          In-editor code generation, commit message generation, etc.

2. Instant Helpers Model (Gemma4):
----------------------------------
Provider Type:    OpenAI-compatible
API Base URL:     ${OLLAMA_HOST}/v1
Model Name:       ${CUSTOM_MODEL_NAME}
Base Model:       ${GEMMA_MODEL}
Context Window:   $(printf "%'d" "$NUM_CTX") tokens
API Key:          ollama (or leave empty)
Purpose:          Chat context collection, chat title generation, name suggestions
Note:             Use the same model as Core Features for consistency

EOF

    if [[ -n "$CODEGEMMA_MODEL" ]]; then
        cat >> "$config_ref" << EOF
3. Completion Model (CodeGemma FIM):
------------------------------------
Provider Type:    OpenAI-compatible
API Base URL:     ${OLLAMA_HOST}/v1
Model Name:       ${CODEGEMMA_MODEL}
Context:          8K tokens (optimized for FIM)
API Key:          ollama (or leave empty)
Purpose:          Inline code completion in the main editor
Requirements:     Must support Fill-In-the-Middle (FIM)
Features:         • Real-time code completion
                  • Code infilling
                  • Context-aware suggestions

EOF
    else
        cat >> "$config_ref" << EOF
3. Completion Model:
--------------------
Status:           Not configured
Note:             CodeGemma needed for FIM-based inline code completion
                  Run setup again and select JetBrains to configure CodeGemma

EOF
    fi

    cat >> "$config_ref" << EOF
Configuration Steps:
-------------------
1. Open JetBrains IDE (IntelliJ IDEA, PyCharm, WebStorm, etc.)
2. Navigate to: Preferences/Settings → Tools → AI Assistant
3. Click '+' to add custom provider
4. Configure provider:
   - Provider Type: OpenAI-compatible
   - API Base URL: ${OLLAMA_HOST}/v1
   - API Key: ollama (or leave empty)
5. Assign models to the 3 slots:
   • Core features:      ${CUSTOM_MODEL_NAME}
   • Instant helpers:    ${CUSTOM_MODEL_NAME}
EOF

    if [[ -n "$CODEGEMMA_MODEL" ]]; then
        cat >> "$config_ref" << EOF
   • Completion model:   ${CODEGEMMA_MODEL}
6. Test connection for each model
7. Save settings and start using AI Assistant
EOF
    else
        cat >> "$config_ref" << EOF
   • Completion model:   (skip for now, or configure later)
6. Test connection
7. Save settings
   Note: Without CodeGemma, inline completion will not be available
EOF
    fi

    cat >> "$config_ref" << EOF

Troubleshooting:
---------------
• Ensure Ollama is running: ollama list
• Test chat model: ollama run ${CUSTOM_MODEL_NAME}
EOF

    if [[ -n "$CODEGEMMA_MODEL" ]]; then
        cat >> "$config_ref" << EOF
• Test CodeGemma: ollama run ${CODEGEMMA_MODEL}
EOF
    fi

    cat >> "$config_ref" << EOF
• Check Ollama logs: ~/Library/Logs/Ollama/server.log
• Verify endpoint: curl ${OLLAMA_HOST}/v1/models

Documentation:
-------------
• JetBrains AI Assistant: https://www.jetbrains.com/ai/
• Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md
• CodeGemma FIM: https://ai.google.dev/gemma/docs/codegemma
EOF

    print_status "Configuration reference saved to:"
    print_status "  $config_ref"
    echo ""

    # Optional: Open the config reference
    if [[ "$AUTO_MODE" != true ]]; then
        read -p "Open configuration reference now? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if command -v open &> /dev/null; then
                open "$config_ref"
            else
                cat "$config_ref"
            fi
        fi
    fi

    print_status "JetBrains AI Assistant configuration instructions provided"
    print_info "You can reference these settings anytime at: $config_ref"
}
