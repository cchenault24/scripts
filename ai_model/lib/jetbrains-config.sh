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
# - Instant helpers: CodeGemma (chat context, title generation, name suggestions)
# - Completion model: CodeGemma (inline code completion via FIM)

set -euo pipefail

# Configure JetBrains AI Assistant with Ollama provider
#
# Globals read:
#   - CUSTOM_MODEL_NAME: Name of custom model
#   - SELECTED_MODEL: Base model name
#   - CODESELECTED_MODEL: CodeGemma model for FIM
#   - OLLAMA_HOST: Ollama server URL
#   - NUM_CTX: Context length
#   - AUTO_MODE: Whether in auto mode
configure_jetbrains() {
    print_step "6/6" "Configuring JetBrains AI Assistant"

    # JetBrains stores settings in IDE-specific locations
    # For AI Assistant, we need to configure the LLM provider
    local jetbrains_base="$HOME/Library/Application Support/JetBrains"

    print_info "Manual configuration required"
    echo ""
    echo -e "${BLUE}Configuration Instructions:${NC}"
    echo ""
    echo "JetBrains AI Assistant uses 3 model slots:"
    echo ""
    echo -e "  ${YELLOW}1. Core features:${NC}"
    echo "     Used for: In-editor code generation, commit messages, etc."
    echo "     Model: ${CUSTOM_MODEL_NAME} (Gemma4)"
    echo ""
    if [[ -n "$CODESELECTED_MODEL" ]]; then
        echo -e "  ${YELLOW}2. Instant helpers:${NC}"
        echo "     Used for: Chat context collection, title generation, name suggestions"
        echo "     Model: ${CODESELECTED_MODEL} (CodeGemma)"
        echo ""
        echo -e "  ${YELLOW}3. Completion model:${NC}"
        echo "     Used for: Inline code completion (requires FIM)"
        echo "     Model: ${CODESELECTED_MODEL} (CodeGemma)"
        echo ""
    else
        echo -e "  ${YELLOW}2. Instant helpers:${NC}"
        echo "     Not configured - CodeGemma needed"
        echo ""
        echo -e "  ${YELLOW}3. Completion model:${NC}"
        echo "     Not configured - CodeGemma needed for FIM completion"
        echo ""
    fi
    echo -e "${GREEN}Setup Steps:${NC}"
    echo ""
    echo "1. Open your JetBrains IDE (IntelliJ IDEA, PyCharm, WebStorm, etc.)"
    echo "2. Go to: Preferences/Settings → Tools → AI Assistant"
    echo ""
    echo -e "${YELLOW}3. IMPORTANT - Disable Cloud Features (for local-only operation):${NC}"
    echo "   □ Uncheck 'Enable cloud completion suggestions'"
    echo "   □ Uncheck 'Enable next edit suggestions'"
    echo -e "   ${GRAY}These features send data to JetBrains cloud - disable for privacy/compliance${NC}"
    echo ""
    echo "4. Under 'Language Models', click '+' to add a custom provider"
    echo ""
    echo -e "${GREEN}Configure Ollama Provider:${NC}"
    echo -e "   Provider Type:    ${BLUE}OpenAI-compatible${NC}"
    echo -e "   API Base URL:     ${BLUE}${OLLAMA_HOST}/v1${NC}"
    echo -e "   API Key:          ${BLUE}ollama${NC} (or leave empty)"
    echo ""
    echo "5. Assign models to each slot:"
    echo -e "   ${YELLOW}Core features:${NC}      ${CUSTOM_MODEL_NAME}"
    if [[ -n "$CODESELECTED_MODEL" ]]; then
        echo -e "   ${YELLOW}Instant helpers:${NC}    ${CODESELECTED_MODEL}"
        echo -e "   ${YELLOW}Completion model:${NC}   ${CODESELECTED_MODEL}"
    else
        echo -e "   ${YELLOW}Instant helpers:${NC}    (not configured)"
        echo -e "   ${YELLOW}Completion model:${NC}   (not configured)"
    fi
    echo ""
    echo "6. Click 'Test Connection' to verify"
    echo "7. Save settings"
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
Base Model:       ${SELECTED_MODEL}
Context Window:   $(printf "%'d" "$NUM_CTX") tokens
API Key:          ollama (or leave empty)
Purpose:          In-editor code generation, commit message generation, etc.

EOF

    if [[ -n "$CODESELECTED_MODEL" ]]; then
        cat >> "$config_ref" << EOF
2. Instant Helpers Model (CodeGemma):
--------------------------------------
Provider Type:    OpenAI-compatible
API Base URL:     ${OLLAMA_HOST}/v1
Model Name:       ${CODESELECTED_MODEL}
Context:          8K tokens (optimized for fast responses)
API Key:          ollama (or leave empty)
Purpose:          Chat context collection, chat title generation, name suggestions
Note:             Lightweight model for fast helper tasks

3. Completion Model (CodeGemma FIM):
------------------------------------
Provider Type:    OpenAI-compatible
API Base URL:     ${OLLAMA_HOST}/v1
Model Name:       ${CODESELECTED_MODEL}
Context:          8K tokens (optimized for FIM)
API Key:          ollama (or leave empty)
Purpose:          Inline code completion in the main editor
Requirements:     Must support Fill-In-the-Middle (FIM)
Features:         • Real-time code completion
                  • Code infilling
                  • Context-aware suggestions
Note:             Same CodeGemma model used for both Instant helpers and Completion

EOF
    else
        cat >> "$config_ref" << EOF
2. Instant Helpers Model:
--------------------------
Status:           Not configured
Note:             CodeGemma needed for fast helper tasks
                  Run setup again and select JetBrains to configure CodeGemma

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

3. IMPORTANT - Disable Cloud Features (for local-only operation):
   ⚠️  Uncheck 'Enable cloud completion suggestions'
   ⚠️  Uncheck 'Enable next edit suggestions'

   Why: These features send your code to JetBrains cloud servers. Disable them
        to ensure all AI operations stay 100% local for privacy/compliance.

4. Click '+' to add custom provider

5. Configure provider:
   - Provider Type: OpenAI-compatible
   - API Base URL: ${OLLAMA_HOST}/v1
   - API Key: ollama (or leave empty)

6. Assign models to the 3 slots:
   • Core features:      ${CUSTOM_MODEL_NAME}
EOF

    if [[ -n "$CODESELECTED_MODEL" ]]; then
        cat >> "$config_ref" << EOF
   • Instant helpers:    ${CODESELECTED_MODEL}
   • Completion model:   ${CODESELECTED_MODEL}

7. Test connection for each model

8. Save settings and start using AI Assistant

Notes:
- Core features uses Gemma4 for complex code generation tasks
- Instant helpers and Completion both use CodeGemma for speed and FIM support
- Always keep cloud features disabled to ensure 100% local operation
EOF
    else
        cat >> "$config_ref" << EOF
   • Instant helpers:    (not configured - needs CodeGemma)
   • Completion model:   (not configured - needs CodeGemma)

7. Test connection

8. Save settings
   Note: Without CodeGemma, instant helpers and inline completion will not be available

IMPORTANT: Always keep cloud features disabled to ensure 100% local operation
EOF
    fi

    cat >> "$config_ref" << EOF

Privacy & Compliance:
--------------------
🔒 For 100% Local Operation (No Data Leaves Your Machine):

CRITICAL: Disable these JetBrains cloud features in AI Assistant settings:
  ❌ Enable cloud completion suggestions
  ❌ Enable next edit suggestions

These features send your code to JetBrains cloud servers for analysis. When
disabled, all AI operations run exclusively through your local Ollama instance.

Benefits of Local-Only Setup:
  ✓ Complete data privacy - no code leaves your machine
  ✓ Compliance-friendly for sensitive codebases
  ✓ No internet required after initial model download
  ✓ Lower latency (no round-trip to cloud)
  ✓ No usage limits or API rate limiting

Troubleshooting:
---------------
• Ensure Ollama is running: ollama list
• Test chat model: ollama run ${CUSTOM_MODEL_NAME}
EOF

    if [[ -n "$CODESELECTED_MODEL" ]]; then
        cat >> "$config_ref" << EOF
• Test CodeGemma: ollama run ${CODESELECTED_MODEL}
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

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        print_status "Configuration reference saved to:"
        print_status "  $config_ref"
        echo ""
    else
        print_status "JetBrains config saved"
        print_verbose "Reference: $config_ref"
    fi

    # Optional: Open the config reference
    if [[ "$AUTO_MODE" != true ]] && [[ $VERBOSITY_LEVEL -ge 1 ]]; then
        echo ""
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

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        print_info "You can reference these settings anytime at: $config_ref"
    fi
}
