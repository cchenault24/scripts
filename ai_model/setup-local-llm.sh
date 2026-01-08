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
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/hardware.sh"
source "$SCRIPT_DIR/lib/ollama.sh"
source "$SCRIPT_DIR/lib/models.sh"
source "$SCRIPT_DIR/lib/optimization.sh"
source "$SCRIPT_DIR/lib/continue.sh"
source "$SCRIPT_DIR/lib/vscode.sh"
source "$SCRIPT_DIR/lib/prerequisites.sh"

# Cleanup function for trap
cleanup_on_exit() {
  # Unload all models on exit to free memory
  if command -v ollama &>/dev/null && curl -s http://localhost:11434/api/tags &>/dev/null 2>/dev/null; then
    # Use smart unloading if available, otherwise fallback to regular unloading
    if command -v smart_unload_idle_models &>/dev/null; then
      smart_unload_idle_models 2>/dev/null || unload_all_models 2>/dev/null || true
    else
      unload_all_models 2>/dev/null || true
    fi
  fi
}

# Pre-flight checks before starting installation
preflight_checks() {
  print_header "🔍 Pre-Flight Checks"
  
  local checks_passed=0
  local checks_failed=0
  
  # Check disk space (require at least 20GB for model downloads)
  print_info "Checking disk space..."
  if validate_disk_space 20 "$HOME"; then
    print_success "Disk space check passed"
    ((checks_passed++))
  else
    print_error "Insufficient disk space (required: 20GB)"
    print_info "Free up space or choose smaller models"
    ((checks_failed++))
  fi
  
  # Check network connectivity (if models will be downloaded)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    print_info "Checking network connectivity..."
    if check_network_connectivity "https://ollama.com" 2 5 2; then
      print_success "Network connectivity check passed"
      ((checks_passed++))
    else
      print_warn "Network connectivity check failed"
      print_info "Model downloads may fail. Continuing anyway..."
      ((checks_failed++))
    fi
  fi
  
  # Check state directory permissions
  print_info "Checking state directory permissions..."
  if mkdir -p "$STATE_DIR" 2>/dev/null && [[ -w "$STATE_DIR" ]]; then
    print_success "State directory is writable"
    ((checks_passed++))
  else
    print_error "State directory is not writable: $STATE_DIR"
    ((checks_failed++))
  fi
  
  # Check Continue.dev config directory
  print_info "Checking Continue.dev config directory..."
  local continue_dir="$HOME/.continue"
  if mkdir -p "$continue_dir" 2>/dev/null && [[ -w "$continue_dir" ]]; then
    print_success "Continue.dev directory is writable"
    ((checks_passed++))
  else
    print_error "Continue.dev directory is not writable: $continue_dir"
    ((checks_failed++))
  fi
  
  echo ""
  if [[ $checks_failed -gt 0 ]]; then
    print_warn "$checks_failed check(s) failed, $checks_passed check(s) passed"
    if ! prompt_yes_no "Continue despite failed checks?" "n"; then
      log_error "Pre-flight checks failed, user chose to abort"
      exit 1
    fi
  else
    print_success "All pre-flight checks passed ($checks_passed checks)"
  fi
  
  echo ""
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
  # Collect all user responses first
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
  
  # Pre-flight checks (after prerequisites, before installations)
  preflight_checks
  
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
  # Show summary and confirm before starting
  # ============================================
  print_header "📋 Installation Summary"
  echo -e "${CYAN}Please review your selections before installation begins:${NC}"
  echo ""
  echo -e "  ${BOLD}Hardware Tier:${NC} $TIER_LABEL"
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    echo -e "  ${BOLD}Models to install:${NC}"
    for model in "${SELECTED_MODELS[@]}"; do
      local ram=$(get_model_ram "$model")
      echo -e "    • $model (~${ram}GB RAM)"
    done
  else
    echo -e "  ${BOLD}Models:${NC} None selected"
  fi
  if [[ ${#SELECTED_EXTENSIONS[@]} -gt 0 ]]; then
    echo -e "  ${BOLD}VS Code Extensions:${NC} ${#SELECTED_EXTENSIONS[@]} selected"
  else
    echo -e "  ${BOLD}VS Code Extensions:${NC} None selected"
  fi
  echo ""
  
  if ! prompt_yes_no "Proceed with installation?" "y"; then
    print_info "Installation cancelled by user"
    exit 0
  fi
  echo ""
  
  # ============================================
  # Begin all installations/setup
  # ============================================
  print_header "🚀 Starting Installation"
  echo -e "${CYAN}All configurations collected. Beginning installations and setup...${NC}"
  echo ""
  
  # Install models (only if models were selected)
  local failed_models=()
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    print_header "📥 Installing Models"
    print_info "This may take 10-30 minutes depending on your internet connection..."
    echo ""
    
    # Check network before starting downloads
    if ! check_network_connectivity "https://ollama.com" 2 5 2; then
      print_warn "Network connectivity check failed"
      if ! prompt_yes_no "Continue with model downloads anyway?" "n"; then
        print_info "Skipping model installation due to network issues"
        SELECTED_MODELS=()
        failed_models=()
      fi
    fi
    
    # Automatically install embedding model for code indexing (after network check)
    if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
      print_info "Installing embedding model for code indexing (nomic-embed-text)..."
      if install_model "nomic-embed-text"; then
        print_success "Embedding model installed for code indexing"
        # Add to SELECTED_MODELS so it gets included in config
        SELECTED_MODELS+=("nomic-embed-text")
        echo ""
      else
        print_warn "Failed to install embedding model. Code indexing may not work."
        print_info "You can install it manually later with: ollama pull nomic-embed-text"
        echo ""
      fi
    fi
    
    # Estimate total disk space needed
    local total_size=0
    for model in "${SELECTED_MODELS[@]}"; do
      local model_size
      model_size=$(estimate_model_size "$model")
      if command -v bc &>/dev/null; then
        total_size=$(echo "scale=2; $total_size + $model_size" | bc 2>/dev/null || echo "$total_size")
      else
        local size_int=${model_size%%.*}
        local total_int=${total_size%%.*}
        total_size=$((total_int + size_int))
      fi
    done
    
    if [[ -n "$total_size" ]] && [[ "$total_size" != "0" ]]; then
      print_info "Estimated total download size: ~${total_size}GB"
      if ! validate_disk_space "$total_size" "$HOME"; then
        print_warn "Insufficient disk space for all models"
        if ! prompt_yes_no "Continue anyway? (Some models may fail to install)" "n"; then
          print_info "Skipping model installation due to insufficient disk space"
          SELECTED_MODELS=()
          failed_models=()
        fi
      fi
    fi
    
    for model in "${SELECTED_MODELS[@]}"; do
      # Sanitize and validate model name
      local sanitized_model
      sanitized_model=$(sanitize_model_name "$model")
      if [[ -z "$sanitized_model" ]] || ! validate_model_name "$sanitized_model"; then
        log_error "Invalid model name: $model"
        failed_models+=("$model")
        continue
      fi
      
      # Check disk space for this specific model
      local model_size
      model_size=$(estimate_model_size "$sanitized_model")
      if ! validate_disk_space "$model_size" "$HOME"; then
        print_warn "Insufficient disk space for $sanitized_model (~${model_size}GB required)"
        if ! prompt_yes_no "Skip $sanitized_model and continue with other models?" "y"; then
          failed_models+=("$sanitized_model")
          continue
        fi
      fi
      
      if install_model "$sanitized_model"; then
        # Get the actual installed model name (may be optimized variant)
        local installed_model=$(resolve_installed_model "$sanitized_model")
        print_success "$installed_model downloaded"
        echo ""
        
        # Verify model is actually installed
        if ! is_model_installed "$installed_model"; then
          log_warn "Model $installed_model may not be fully installed"
          print_warn "Installation verification failed for $installed_model"
        fi
        
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
  
  # Start optimization services (only if models were installed)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    print_header "🚀 Advanced Optimizations"
    
    # Check if auto-start is disabled
    local auto_start_was_disabled=false
    if is_auto_start_disabled 2>/dev/null; then
      auto_start_was_disabled=true
      print_info "Auto-start is currently disabled."
      if prompt_yes_no "Re-enable auto-start and start optimization services?" "y"; then
        enable_auto_start
        print_info "Auto-start re-enabled"
        auto_start_was_disabled=false
      else
        print_info "Auto-start remains disabled. Config will use direct Ollama connection."
        echo ""
      fi
    fi
    
    # Ask user if they want to enable optimizations (unless already disabled and user chose not to re-enable)
    if ! is_auto_start_disabled 2>/dev/null && ! [[ "$auto_start_was_disabled" == "true" ]]; then
      if prompt_yes_no "Enable advanced optimizations (model routing, request queuing, performance tracking)?" "y"; then
        print_info "Starting optimization services..."
        
        # Use wrapper script to ensure services are running
        if [[ -f "$SCRIPT_DIR/tools/ensure-optimizations.sh" ]]; then
          if "$SCRIPT_DIR/tools/ensure-optimizations.sh" 2>/dev/null; then
            print_success "Optimization services started"
            print_info "Config will be generated with proxy enabled (port 11435)"
          else
            print_warn "Failed to start optimization services. Check logs: $HOME/.local-llm-setup/ensure-optimizations.log"
            print_info "Config will use direct Ollama connection"
          fi
        else
          # Fallback to start-optimizations.sh if wrapper doesn't exist
          if [[ -f "$SCRIPT_DIR/tools/start-optimizations.sh" ]]; then
            "$SCRIPT_DIR/tools/start-optimizations.sh" --all
            print_success "Optimization services started"
            print_info "Config will be generated with proxy enabled (port 11435)"
          else
            print_warn "Optimization scripts not found, skipping optimization services"
            print_info "Config will use direct Ollama connection"
          fi
        fi
        echo ""
      else
        print_info "Advanced optimizations disabled. Config will use direct Ollama connection."
        echo ""
      fi
    fi
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
  # Use smart unloading if available, otherwise fallback to regular unloading
  if command -v smart_unload_idle_models &>/dev/null; then
    smart_unload_idle_models || unload_all_models
  else
    unload_all_models
  fi
  
  # Final summary
  print_header "✅ Setup Complete!"
  
  echo -e "${GREEN}${BOLD}Installation Summary:${NC}"
  echo ""
  echo -e "  ${CYAN}Hardware Tier:${NC} $TIER_LABEL"
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    echo -e "  ${CYAN}Selected Models:${NC} ${SELECTED_MODELS[*]}"
    echo -e "  ${CYAN}Installed Models:${NC} ${INSTALLED_MODELS[*]}"
    echo -e "  ${CYAN}Continue.dev Profiles:${NC} ${CONTINUE_PROFILES[*]}"
    # Check if embedding model is installed
    if printf '%s\n' "${INSTALLED_MODELS[@]}" | grep -q "nomic-embed-text"; then
      echo -e "  ${CYAN}Code Indexing:${NC} Enabled (nomic-embed-text installed)"
    fi
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
    # Check if embedding model is installed and mention code indexing
    if printf '%s\n' "${INSTALLED_MODELS[@]}" | grep -q "nomic-embed-text"; then
      echo -e "  ${CYAN}Code Indexing:${NC} Enabled! You can use ${BOLD}@Codebase${NC} in Continue.dev chat"
      echo -e "  for semantic search across your codebase."
      echo ""
    fi
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
