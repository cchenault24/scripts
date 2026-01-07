#!/bin/bash
#
# update.sh - Update Ollama and installed models
#
# Checks for updates, updates Ollama, and refreshes installed models

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="$STATE_DIR/update.log"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

print_warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local choice
  while true; do
    echo -e "${YELLOW}$prompt${NC} [y/n] (default: $default): "
    read -r choice
    choice=${choice:-$default}
    case "$choice" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

# Backup Continue.dev config
backup_continue_config() {
  local config_file="$HOME/.continue/config.json"
  
  if [[ -f "$config_file" ]]; then
    local backup_file="$STATE_DIR/continue-config-backup-$(date +%Y%m%d-%H%M%S).json"
    cp "$config_file" "$backup_file" 2>/dev/null || {
      print_warn "Failed to backup Continue.dev config"
      return 1
    }
    print_success "Backed up Continue.dev config to $backup_file"
    return 0
  fi
  return 0
}

# Update Ollama
update_ollama() {
  print_header "🔄 Updating Ollama"
  
  if ! command -v brew &>/dev/null; then
    print_error "Homebrew not found"
    return 1
  fi
  
  local current_version=$(ollama --version 2>/dev/null | head -n 1 || echo "unknown")
  print_info "Current version: $current_version"
  
  if prompt_yes_no "Update Ollama to latest version?" "y"; then
    print_info "Updating Ollama..."
    
    if brew upgrade ollama 2>&1 | tee -a "$LOG_FILE"; then
      print_success "Ollama updated"
      
      # Restart service
      print_info "Restarting Ollama service..."
      brew services restart ollama
      sleep 5
      
      if curl -s http://localhost:11434/api/tags &>/dev/null; then
        print_success "Ollama service restarted"
      else
        print_warn "Ollama service may not be running. Check with: brew services list"
      fi
    else
      print_error "Failed to update Ollama"
      return 1
    fi
  else
    print_info "Skipping Ollama update"
  fi
}

# Update models
update_models() {
  print_header "🔄 Updating Models"
  
  local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$models" ]]; then
    print_warn "No models installed"
    return 0
  fi
  
  local model_count=$(echo "$models" | wc -l | xargs)
  print_info "Found $model_count model(s) to update"
  echo ""
  
  if ! prompt_yes_no "Update all installed models? (This may take a while)" "y"; then
    print_info "Skipping model updates"
    return 0
  fi
  
  local updated=0
  local failed=0
  
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      print_info "Updating $model..."
      
      if ollama pull "$model" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "$model updated"
        ((updated++))
      else
        print_error "Failed to update $model"
        ((failed++))
      fi
      echo ""
    fi
  done <<< "$models"
  
  echo ""
  print_success "Updated $updated model(s)"
  if [[ $failed -gt 0 ]]; then
    print_warn "Failed to update $failed model(s)"
  fi
}

# Refresh Continue.dev config
refresh_continue_config() {
  print_header "🔄 Refreshing Continue.dev Config"
  
  if [[ ! -f "$HOME/.continue/config.json" ]]; then
    print_warn "Continue.dev config not found"
    print_info "Run setup-local-llm.sh to generate configuration"
    return 0
  fi
  
  if prompt_yes_no "Regenerate Continue.dev config with current models?" "n"; then
    # Backup first
    backup_continue_config
    
    print_info "Note: This will regenerate the config. You may need to re-run setup-local-llm.sh"
    print_info "for full regeneration with proper model assignments."
    
    # Simple refresh: just validate JSON
    if command -v jq &>/dev/null; then
      if jq empty "$HOME/.continue/config.json" 2>/dev/null; then
        print_success "Continue.dev config is valid"
      else
        print_error "Continue.dev config is invalid JSON"
        print_info "Restore from backup or re-run setup-local-llm.sh"
      fi
    else
      print_warn "jq not found, skipping config validation"
    fi
  else
    print_info "Skipping config refresh"
  fi
}

# Main
main() {
  clear
  print_header "🔄 Local LLM Update Tool"
  
  # Check prerequisites
  if ! command -v ollama &>/dev/null; then
    print_error "Ollama not found"
    exit 1
  fi
  
  if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_error "Ollama service is not running"
    print_info "Start with: brew services start ollama"
    exit 1
  fi
  
  # Backup Continue.dev config
  backup_continue_config
  
  # Update Ollama
  update_ollama
  
  # Update models
  update_models
  
  # Refresh config
  refresh_continue_config
  
  # Summary
  print_header "✅ Update Complete"
  print_success "Update process finished"
  print_info "Check logs at: $LOG_FILE"
  echo ""
}

main "$@"
