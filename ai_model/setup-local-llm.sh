#!/bin/bash
#
# setup-local-llm.sh - Production-grade VS Code + Continue.dev Local LLM Setup
#
# Installs and configures Ollama with hardware-aware auto-tuning for VS Code
# integration via Continue.dev. Optimized for React+TypeScript+Redux-Saga+MUI stack.
#
# Requirements: macOS Apple Silicon, Homebrew, Xcode Command Line Tools
# Author: Generated for local AI coding environment
# License: MIT
#
# Compatible with bash 3.2+

# Check bash version (requires 3.2+)
if [[ "${BASH_VERSION%%.*}" -lt 3 ]] || [[ "${BASH_VERSION%%.*}" -eq 3 && "${BASH_VERSION#*.}" < 2 ]]; then
  echo "Error: This script requires bash 3.2 or later. Current version: $BASH_VERSION" >&2
  exit 1
fi

set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize global arrays (set -u compatibility)
SELECTED_MODELS=()
INSTALLED_MODELS=()
CONTINUE_PROFILES=()
SELECTED_EXTENSIONS=()

# Load library modules in dependency order
source "$SCRIPT_DIR/lib/constants.sh"
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/hardware.sh"
source "$SCRIPT_DIR/lib/ollama.sh"
source "$SCRIPT_DIR/lib/models.sh"
source "$SCRIPT_DIR/lib/continue.sh"
source "$SCRIPT_DIR/lib/vscode.sh"
source "$SCRIPT_DIR/lib/prerequisites.sh"

# Cleanup function for trap
cleanup_on_exit() {
  # Unload all models on exit to free memory
  if command -v ollama &>/dev/null && curl -s http://localhost:11434/api/tags &>/dev/null 2>/dev/null; then
    unload_all_models 2>/dev/null || true
  fi
}

# Main installation flow
main() {
  clear
  print_header "🚀 VS Code + Continue.dev Local LLM Setup"
  
  # Set up trap to cleanup on exit/interrupt
  trap cleanup_on_exit EXIT INT TERM
  
  # Initialize
  mkdir -p "$STATE_DIR"
  INSTALLED_MODELS=()
  CONTINUE_PROFILES=()
  VSCODE_EXTENSIONS_INSTALLED=false
  
  # ============================================
  # PHASE 1: Collect all user responses first
  # ============================================
  print_header "📋 Configuration"
  echo -e "${CYAN}Please answer the following questions. All installations will begin after you've completed all prompts.${NC}"
  echo ""
  
  # Load previous state if resuming
  local resume_installation=false
  if [[ -f "$STATE_FILE" ]]; then
    if prompt_yes_no "Previous installation detected. Resume?" "y"; then
      resume_installation=true
      load_state
    fi
  fi
  
  # Detection and checks (no prompts, just detection)
  detect_hardware
  check_prerequisites
  
  # Ask if user wants to install models
  local install_models=true
  if [[ "$resume_installation" != "true" ]]; then
    if ! prompt_yes_no "Would you like to install AI models for Continue.dev?" "y"; then
      install_models=false
      print_info "Skipping model installation. You can install models later by running this script again."
      SELECTED_MODELS=()
    fi
  fi
  
  # Model selection (contains prompts)
  if [[ "$resume_installation" != "true" && "$install_models" == "true" ]]; then
    select_models
  fi
  
  # Ask if user wants to install VS Code extensions
  local install_extensions=true
  if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
    if ! prompt_yes_no "Would you like to install recommended extensions for VS Code?" "y"; then
      install_extensions=false
      print_info "Skipping VS Code extension installation."
      SELECTED_EXTENSIONS=()
    fi
  else
    install_extensions=false
    SELECTED_EXTENSIONS=()
  fi
  
  # Prompt for VS Code extensions (only if user wants to install)
  if [[ "$install_extensions" == "true" ]]; then
    SELECTED_EXTENSIONS=()
    prompt_vscode_extensions
  fi
  
  # ============================================
  # PHASE 2: Begin all installations/setup
  # ============================================
  print_header "🚀 Starting Installation"
  echo -e "${CYAN}All configurations collected. Beginning installations and setup...${NC}"
  echo ""
  
  # Install models (only if models were selected)
  local failed_models=()
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    print_header "📥 Installing Models"
    print_info "This may take 10-30 minutes depending on your connection..."
    echo ""
    
    for model in "${SELECTED_MODELS[@]}"; do
      if install_model "$model"; then
        # Get the actual installed model name (may be optimized variant)
        local installed_model=$(resolve_installed_model "$model")
        print_success "$installed_model downloaded"
        echo ""
        
        # Prompt for validation
        if prompt_yes_no "Would you like to validate $installed_model?" "y"; then
          if validate_model_simple "$installed_model"; then
            print_success "$installed_model validated"
            # Unload model after validation to free memory
            unload_model "$installed_model" 1  # Silent mode
          else
            log_warn "$installed_model validation failed"
            failed_models+=("$model")
            # Unload model even on failure
            unload_model "$installed_model" 1  # Silent mode
          fi
          echo ""
        else
          print_info "Validation skipped for $installed_model"
          echo ""
        fi
        
        # Prompt for benchmarking
        if prompt_yes_no "Would you like to benchmark $installed_model?" "y"; then
          if benchmark_model_performance "$installed_model"; then
            print_success "$installed_model benchmarked"
            # Unload model after benchmarking to free memory
            unload_model "$installed_model" 1  # Silent mode
          else
            log_warn "$installed_model benchmarking had issues"
            # Unload model even on failure
            unload_model "$installed_model" 1  # Silent mode
          fi
          echo ""
        else
          print_info "Benchmarking skipped for $installed_model"
          echo ""
        fi
      else
        failed_models+=("$model")
      fi
    done
  else
    print_info "No models selected for installation. Skipping model installation."
  fi
  
  # Generate configurations (only if models were installed)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    generate_continue_config
  else
    print_info "Skipping Continue.dev configuration (no models installed)."
  fi
  
  # Install VS Code extensions (only if extensions were selected)
  if [[ ${#SELECTED_EXTENSIONS[@]} -gt 0 ]]; then
    setup_vscode_extensions "${SELECTED_EXTENSIONS[@]}"
  else
    print_info "No VS Code extensions selected for installation. Skipping extension installation."
    VSCODE_EXTENSIONS_INSTALLED=false
  fi
  generate_vscode_settings
  copy_vscode_settings
  
  # Optionally install Continue CLI for better verification
  if command -v npm &>/dev/null; then
    install_continue_cli
  fi
  
  # Verify Continue.dev setup (only if models were installed)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    verify_continue_setup
  else
    print_info "Skipping Continue.dev verification (no models installed)."
  fi
  
  # Save state
  save_state
  
  # Final cleanup - unload all models to free memory
  print_info "Cleaning up: unloading models from memory..."
  unload_all_models
  
  # Final summary
  print_header "✅ Setup Complete!"
  
  echo -e "${GREEN}${BOLD}Installation Summary:${NC}"
  echo ""
  echo -e "  ${CYAN}Hardware Tier:${NC} $TIER_LABEL"
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Selected Models:${NC} ${SELECTED_MODELS[*]}"
    echo -e "  ${CYAN}Installed Models:${NC} ${INSTALLED_MODELS[*]}"
    echo -e "  ${CYAN}Continue.dev Profiles:${NC} ${CONTINUE_PROFILES[*]}"
  else
    echo -e "  ${CYAN}Models:${NC} None selected"
  fi
  echo ""
  
  if [[ ${#failed_models[@]} -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Failed/Skipped Models:${NC} ${failed_models[*]}"
    echo ""
  fi
  
  echo -e "${YELLOW}${BOLD}📋 Next Steps:${NC}"
  echo ""
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    # Check if Continue.dev extension is actually installed
    local continue_extension_installed=false
    if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
      local continue_check=$(code --list-extensions 2>/dev/null | grep -i "Continue.continue" || echo "")
      if [[ -n "$continue_check" ]]; then
        continue_extension_installed=true
      fi
    fi
    
    if [[ "$continue_extension_installed" == "true" ]] || [[ "$VSCODE_EXTENSIONS_INSTALLED" == "true" ]]; then
      echo -e "  ${BOLD}IMPORTANT:${NC} You must ${BOLD}fully quit and restart VS Code${NC} (Cmd+Q, not just reload)"
      echo "  for Continue.dev to detect the configuration."
      echo ""
      echo -e "  1. ${BOLD}Quit VS Code completely${NC} (Cmd+Q on macOS)"
      echo -e "  2. ${BOLD}Reopen VS Code${NC}"
      echo -e "  3. Press ${BOLD}Cmd+L${NC} (or ${BOLD}Ctrl+L${NC}) to open Continue.dev chat"
    else
      echo "  1. Install Continue.dev extension in VS Code:"
      echo -e "     - Open Extensions view (${BOLD}Cmd+Shift+X${NC})"
      echo "     - Search for 'Continue' and install 'Continue.dev' by Continue"
      echo -e "  2. ${BOLD}Quit VS Code completely${NC} (Cmd+Q on macOS)"
      echo -e "  3. ${BOLD}Reopen VS Code${NC}"
      echo -e "  4. Press ${BOLD}Cmd+L${NC} (or ${BOLD}Ctrl+L${NC}) to open Continue.dev chat"
    fi
    echo ""
    echo -e "  Continue.dev will automatically use the config at: ${BOLD}~/.continue/config.yaml${NC}"
    echo ""
    echo -e "  ${CYAN}Verification:${NC}"
    echo -e "  - Ensure Ollama is running: ${BOLD}brew services start ollama${NC}"
    echo -e "  - Check config: ${BOLD}ls -la ~/.continue/config.yaml${NC}"
    echo ""
    echo -e "  ${CYAN}Continue CLI (Optional):${NC}"
    if check_continue_cli; then
      echo -e "  - Continue CLI (${BOLD}cn${NC}) is installed and ready to use"
    else
      echo -e "  - Install: ${BOLD}npm i -g @continuedev/cli${NC}"
      echo -e "  - Then use ${BOLD}cn${NC} in terminal for interactive workflows"
    fi
  else
    echo "  To install models later, run this script again and select 'yes' when prompted."
    echo ""
    if [[ "$VSCODE_EXTENSIONS_INSTALLED" == "true" ]]; then
      echo "  VS Code extensions have been installed. Restart VS Code to activate them."
    elif [[ ${#SELECTED_EXTENSIONS[@]} -eq 0 && "$VSCODE_AVAILABLE" == "true" ]]; then
      echo "  To install VS Code extensions later, run this script again and select 'yes' when prompted."
    fi
  fi
  echo ""
  if [[ -f ".vscode/settings.json" ]]; then
    echo -e "  ${GREEN}✓${NC} VS Code settings automatically copied/merged to .vscode/settings.json"
  fi
  echo ""
  
  echo -e "${BLUE}${BOLD}📄 Documentation:${NC}"
  echo "  See README.md for detailed usage and troubleshooting"
  echo ""
  
  log_success "Setup completed successfully"
}

# Run main
main "$@"
