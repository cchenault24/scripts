#!/bin/bash
#
# prerequisites.sh - Prerequisites checking for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh, hardware.sh, ollama.sh

# Prerequisites check
check_prerequisites() {
  print_header "🔧 Prerequisites Check"
  
  # macOS version
  local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  print_info "macOS Version: $macos_version"
  
  # Homebrew
  if ! command -v brew &>/dev/null; then
    log_error "Homebrew not found. Please install from https://brew.sh"
    exit 1
  fi
  print_success "Homebrew found"
  
  # Xcode Command Line Tools
  if ! xcode-select -p &>/dev/null; then
    log_error "Xcode Command Line Tools not found. Install with: xcode-select --install"
    exit 1
  fi
  print_success "Xcode Command Line Tools found"
  
  # Ollama check
  if command -v ollama &>/dev/null; then
    local ollama_version=$(ollama --version 2>/dev/null | head -n 1 || echo "unknown")
    print_success "Ollama found: $ollama_version"
    
    # Verify Ollama version supports Metal (should be 0.1.0+)
    local version_check=$(echo "$ollama_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo "0.0.0")
    if [[ -n "$version_check" ]]; then
      print_info "Ollama version: $version_check"
    fi
    
    # Configure Metal acceleration before starting service
    configure_metal_acceleration
    
    # Check if Ollama service is running
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
      print_success "Ollama service is running"
      # Restart to apply environment variables if needed
      configure_ollama_service
    else
      print_info "Starting Ollama service..."
      configure_ollama_service
      sleep 5
      if curl -s http://localhost:11434/api/tags &>/dev/null; then
        print_success "Ollama service started"
      else
        log_error "Failed to start Ollama service"
        exit 1
      fi
    fi
    
    # Verify Metal GPU usage
    verify_metal_usage
  else
    log_error "Ollama not found."
    echo ""
    echo "Ollama is required for this setup. The script can install it using Homebrew."
    echo ""
    if prompt_yes_no "Would you like the script to install Ollama now?" "y"; then
      print_info "Installing Ollama..."
      if brew install ollama; then
        print_success "Ollama installed"
        # Configure Metal acceleration
        configure_metal_acceleration
        # Start service with configuration
        configure_ollama_service
        sleep 5
      else
        log_error "Failed to install Ollama"
        exit 1
      fi
    else
      log_error "Ollama is required. Please install it manually and run this script again."
      echo ""
      echo "To install Ollama manually, run:"
      echo "  brew install ollama"
      echo ""
      echo "Or visit: https://ollama.com"
      exit 1
    fi
  fi
  
  # VS Code check (optional)
  if command -v code &>/dev/null; then
    print_success "VS Code CLI found"
    VSCODE_AVAILABLE=true
  else
    print_warn "VS Code CLI not found. Extension installation will be skipped."
    VSCODE_AVAILABLE=false
  fi
  
  # jq check (for JSON parsing)
  if ! command -v jq &>/dev/null; then
    log_error "jq not found. jq is required for JSON processing."
    echo ""
    if prompt_yes_no "Would you like the script to install jq now?" "y"; then
      print_info "Installing jq..."
      if brew install jq; then
        print_success "jq installed"
      else
        log_error "Failed to install jq"
        log_warn "Some features may be limited without jq."
      fi
    else
      log_error "jq is required. Please install it manually and run this script again."
      echo ""
      echo "To install jq manually, run:"
      echo "  brew install jq"
      exit 1
    fi
  else
    print_success "jq found"
  fi
  
  # gum check (for interactive selection)
  check_gum
}
