#!/bin/bash
# lib/verification.sh - Installation verification and usage instructions
#
# Provides:
# - Component verification (Ollama, OpenCode, LaunchAgent, models)
# - Usage instructions display

set -euo pipefail

# Verify all components are correctly installed and configured
#
# Globals read:
#   - OLLAMA_HOST: Ollama server URL
#   - LAUNCHAGENT_LABEL: LaunchAgent identifier
#   - GEMMA_MODEL: Base model name
#   - CUSTOM_MODEL_NAME: Custom model name
verify_setup() {
    [[ $VERBOSITY_LEVEL -eq 0 ]] && return 0  # Skip in quiet mode

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        # Verbose: show all checks
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
    else
        # Normal: quick verification
        local all_good=true

        # Silent checks
        command -v ollama &> /dev/null || all_good=false
        command -v opencode &> /dev/null || all_good=false
        curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1 || all_good=false

        if [[ "$all_good" != true ]]; then
            print_error "Verification failed - run with -v for details"
            return 1
        fi
    fi
}

# Display usage instructions and quick start guide
#
# Globals read:
#   - DETECTED_M_CHIP: Detected chip model
#   - DETECTED_RAM_GB: Detected RAM
#   - DETECTED_CPU_CORES: Detected CPU cores
#   - METAL_MEMORY: Calculated Metal memory
#   - NUM_PARALLEL: Calculated parallel requests
#   - CUSTOM_MODEL_NAME: Custom model name
#   - GEMMA_MODEL: Base model name
#   - NUM_CTX: Context length
#   - OLLAMA_HOST: Ollama server URL
#   - LAUNCHAGENT_PLIST: Path to LaunchAgent plist
#   - CODEGEMMA_MODEL: CodeGemma model (if configured)
#   - IDE_TOOLS: Array of selected IDE tools
#   - AUTO_MODE: Whether in auto mode
print_usage_instructions() {
    # Format context for display
    local context_display
    context_display=$(format_context_display "$NUM_CTX")
    local context_k=$((NUM_CTX / 1024))

    # Format IDE tools for display
    local ide_display=""
    if [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]] && [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
        ide_display="OpenCode + JetBrains"
    elif [[ " ${IDE_TOOLS[*]} " =~ " opencode " ]]; then
        ide_display="OpenCode"
    elif [[ " ${IDE_TOOLS[*]} " =~ " jetbrains " ]]; then
        ide_display="JetBrains AI Assistant"
    else
        ide_display="None"
    fi

    # Use compact summary in normal mode, detailed in verbose mode
    # Skip summary in normal interactive mode (final menu will be shown instead)
    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        # Verbose mode: show full details
        print_header "Setup Complete! 🚀"

        cat << EOF
Your Gemma4 + OpenCode environment is ready to use!

Hardware Configuration:
----------------------
- Chip:           $DETECTED_M_CHIP
- RAM:            ${DETECTED_RAM_GB}GB
- CPU Cores:      $DETECTED_CPU_CORES
- Metal Memory:   $(format_bytes "$METAL_MEMORY")
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

# Verbose mode (show all details):
  $ ./setup-gemma4-opencode.sh -v

# Quiet mode (minimal output):
  $ ./setup-gemma4-opencode.sh -q

Happy coding! 🎉
EOF
    else
        # Normal mode: only show summary if interactive menu won't be shown
        # (i.e., in auto mode or when explicitly skipping the menu)
        if [[ "$AUTO_MODE" == true ]]; then
            print_setup_summary \
                "$DETECTED_M_CHIP" \
                "$DETECTED_RAM_GB" \
                "$DETECTED_CPU_CORES" \
                "$CUSTOM_MODEL_NAME" \
                "$context_k" \
                "${CODEGEMMA_MODEL:-}" \
                "$ide_display"
        fi
        # If not auto mode, the interactive menu will be shown next, so skip summary
    fi
}
