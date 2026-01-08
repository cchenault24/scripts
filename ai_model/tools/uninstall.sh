#!/bin/bash
#
# uninstall.sh - Uninstall tool for local LLM setup
#
# Removes models, cleans Continue.dev configs, and optionally removes Ollama

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
LOG_FILE="$STATE_DIR/uninstall.log"

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

# Remove models
remove_models() {
  print_header "🗑️  Remove Models"
  
  # Check if Ollama is installed
  if ! command -v ollama &>/dev/null; then
    print_warn "Ollama not found in PATH"
    print_info "Skipping model removal"
    return 0
  fi
  
  # Check if Ollama service is running
  if ! curl -s --max-time 2 http://localhost:11434/api/tags &>/dev/null; then
    print_warn "Ollama service is not running"
    print_info "Cannot list models. Start Ollama with: brew services start ollama"
    print_info "Skipping model removal"
    return 0
  fi
  
  # Get list of models - use API for more reliable parsing
  local models
  models=$(curl -s --max-time 5 http://localhost:11434/api/tags 2>/dev/null | \
    grep -o '"name":"[^"]*"' | \
    sed 's/"name":"//g' | \
    sed 's/"//g' | \
    sort -u || echo "")
  
  # Fallback to ollama list if API fails
  if [[ -z "$models" ]]; then
    models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$' || echo "")
  fi
  
  if [[ -z "$models" ]]; then
    print_info "No models installed"
    return 0
  fi
  
  # Filter out empty lines and count
  local model_count
  model_count=$(echo "$models" | grep -v '^$' | wc -l | xargs)
  print_info "Found $model_count installed model(s)"
  echo ""
  
  # Check if gum is available for interactive selection
  if ! command -v gum &>/dev/null; then
    print_warn "gum not found. Falling back to remove-all prompt."
    echo ""
    echo "Installed models:"
    echo "$models" | grep -v '^$' | while read -r model; do
      if [[ -n "$model" ]]; then
        echo "  • $model"
      fi
    done
    echo ""
    
    if ! prompt_yes_no "Remove all installed models?" "n"; then
      print_info "Skipping model removal"
      return 0
    fi
    
    # Confirm again
    if ! prompt_yes_no "This will delete all models. Are you sure?" "n"; then
      print_info "Model removal cancelled"
      return 0
    fi
    
    # Build model array for removal
    local model_array=()
    while IFS= read -r model; do
      if [[ -n "$model" ]] && [[ "$model" != "" ]]; then
        model_array+=("$model")
      fi
    done <<< "$models"
  else
    # Use gum for interactive model selection
    local model_array=()
    local gum_items=()
    local model_map=()
    
    # Build arrays for gum selection
    while IFS= read -r model; do
      if [[ -n "$model" ]] && [[ "$model" != "" ]]; then
        model_array+=("$model")
        gum_items+=("$model")
        model_map+=("$model")
      fi
    done <<< "$models"
    
    if [[ ${#gum_items[@]} -eq 0 ]]; then
      print_info "No models to remove"
      return 0
    fi
    
    echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to toggle selection, ${BOLD}Enter${NC} to confirm"
    echo ""
    
    local selected_lines
    # Use gum choose for multi-select
    selected_lines=$(printf '%s\n' "${gum_items[@]}" | gum choose \
      --limit=100 \
      --height=15 \
      --cursor="→ " \
      --selected-prefix="" \
      --unselected-prefix="" \
      --selected.foreground="2" \
      --selected.background="0" \
      --cursor.foreground="6" \
      --header="🗑️  Select Models to Remove" \
      --header.foreground="6")
    
    if [[ -z "$selected_lines" ]]; then
      print_info "No models selected. Skipping model removal."
      return 0
    fi
    
    # Parse selected models from gum output
    local selected_models=()
    while IFS= read -r line; do
      if [[ -z "$line" ]]; then
        continue
      fi
      
      # Strip any leading whitespace or cursor symbols
      local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
      line_clean="${line_clean#→ }"  # Remove cursor if present
      
      # Find matching model from the map
      local i=0
      for item in "${gum_items[@]}"; do
        if [[ "$item" == "$line_clean" ]]; then
          selected_models+=("${model_map[$i]}")
          break
        fi
        ((i++))
      done
    done <<< "$selected_lines"
    
    if [[ ${#selected_models[@]} -eq 0 ]]; then
      print_info "No models selected. Skipping model removal."
      return 0
    fi
    
    # Confirm removal of selected models
    echo ""
    echo "Selected models for removal:"
    for model in "${selected_models[@]}"; do
      echo "  • $model"
    done
    echo ""
    
    if ! prompt_yes_no "Remove the selected models?" "n"; then
      print_info "Model removal cancelled"
      return 0
    fi
    
    # Use selected models for removal
    model_array=("${selected_models[@]}")
  fi
  
  # Ensure log directory exists
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  
  local removed=0
  local failed=0
  
  # Process each model
  for model in "${model_array[@]}"; do
    if [[ -n "$model" ]]; then
      print_info "Removing $model..."
      
      # Capture remove output and exit code separately
      # This prevents tee failures from masking successful removals
      local remove_output remove_exit_code
      remove_output=$(ollama rm "$model" 2>&1)
      remove_exit_code=$?
      
      # Log output to file, but don't echo to stdout to avoid duplicates
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Removing $model:" >> "$LOG_FILE" 2>/dev/null || true
      echo "$remove_output" >> "$LOG_FILE" 2>/dev/null || true
      
      if [ $remove_exit_code -eq 0 ]; then
        print_success "$model removed"
        ((removed++))
      else
        print_error "Failed to remove $model"
        # Show error output for failed removals
        if [[ -n "$remove_output" ]]; then
          echo "$remove_output" | sed 's/^/  /'
        fi
        ((failed++))
      fi
    fi
  done
  
  # Re-count after removal to verify
  local remaining_models
  remaining_models=$(curl -s --max-time 5 http://localhost:11434/api/tags 2>/dev/null | \
    grep -o '"name":"[^"]*"' | \
    sed 's/"name":"//g' | \
    sed 's/"//g' | \
    wc -l | tr -d '[:space:]' || echo "0")
  
  # Ensure it's a valid integer (default to 0 if not)
  if ! [[ "$remaining_models" =~ ^[0-9]+$ ]]; then
    remaining_models=0
  fi
  
  echo ""
  if [[ $removed -gt 0 ]]; then
    print_success "Removed $removed model(s)"
  fi
  if [[ $failed -gt 0 ]]; then
    print_warn "Failed to remove $failed model(s)"
  fi
  if [[ $remaining_models -gt 0 ]]; then
    print_warn "$remaining_models model(s) still remain"
    print_info "You may need to remove them manually with: ollama rm <model-name>"
  elif [[ $removed -gt 0 ]] && [[ $failed -eq 0 ]]; then
    print_success "All selected models removed successfully"
  fi
}

# Clean Continue.dev config
clean_continue_config() {
  print_header "🗑️  Clean Continue.dev Config"
  
  local config_file="$HOME/.continue/config.json"
  
  if [[ ! -f "$config_file" ]]; then
    print_info "Continue.dev config not found"
    return 0
  fi
  
  if prompt_yes_no "Remove Continue.dev config file?" "n"; then
    # Backup first
    local backup_file="$STATE_DIR/continue-config-backup-$(date +%Y%m%d-%H%M%S).json"
    cp "$config_file" "$backup_file" 2>/dev/null || true
    
    if rm "$config_file" 2>/dev/null; then
      print_success "Continue.dev config removed"
      print_info "Backup saved to: $backup_file"
    else
      print_error "Failed to remove Continue.dev config"
    fi
  else
    print_info "Keeping Continue.dev config"
  fi
}

# Remove VS Code extensions
remove_vscode_extensions() {
  print_header "🗑️  Remove VS Code Extensions"
  
  # Check if VS Code CLI is available
  if ! command -v code &>/dev/null; then
    print_warn "VS Code CLI (code) not found in PATH"
    print_info "Skipping extension removal"
    print_info "You can manually remove extensions from VS Code"
    return 0
  fi
  
  local extensions_file="$SCRIPT_DIR/../vscode/extensions.json"
  
  if [[ ! -f "$extensions_file" ]]; then
    print_info "Extensions file not found"
    return 0
  fi
  
  # Extract extension IDs from extensions.json
  local extensions
  if command -v jq &>/dev/null; then
    extensions=$(jq -r '.recommendations[]?' "$extensions_file" 2>/dev/null || echo "")
  else
    # Fallback: use grep to extract extension IDs from the recommendations array
    extensions=$(grep -A 100 '"recommendations"' "$extensions_file" | \
                 grep -o '"[^"]*"' | \
                 grep -v "recommendations" | \
                 tr -d '"' | \
                 grep -v '^$' || echo "")
  fi
  
  if [[ -z "$extensions" ]]; then
    print_info "No extensions found in extensions.json"
    return 0
  fi
  
  # Filter to only installed extensions and build arrays
  local installed_extensions_array=()
  while IFS= read -r ext; do
    if [[ -n "$ext" ]]; then
      # Check if extension is installed
      if code --list-extensions 2>/dev/null | grep -q "^${ext}$"; then
        installed_extensions_array+=("$ext")
      fi
    fi
  done <<< "$extensions"
  
  if [[ ${#installed_extensions_array[@]} -eq 0 ]]; then
    print_info "No installed extensions found from recommendations"
    return 0
  fi
  
  # Count installed extensions
  local ext_count=${#installed_extensions_array[@]}
  print_info "Found $ext_count installed extension(s)"
  echo ""
  
  # Check if gum is available for interactive selection
  if ! command -v gum &>/dev/null; then
    print_warn "gum not found. Falling back to uninstall-all prompt."
    echo ""
    echo "Installed extensions:"
    for ext in "${installed_extensions_array[@]}"; do
      echo "  • $ext"
    done
    echo ""
    
    if ! prompt_yes_no "Uninstall all installed extensions?" "n"; then
      print_info "Skipping extension removal"
      return 0
    fi
  else
    # Use gum for interactive extension selection
    local gum_items=()
    local ext_map=()
    
    # Build arrays for gum selection
    for ext in "${installed_extensions_array[@]}"; do
      gum_items+=("$ext")
      ext_map+=("$ext")
    done
    
    echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to toggle selection, ${BOLD}Enter${NC} to confirm"
    echo ""
    
    local selected_lines
    # Use gum choose for multi-select
    selected_lines=$(printf '%s\n' "${gum_items[@]}" | gum choose \
      --limit=100 \
      --height=15 \
      --cursor="→ " \
      --selected-prefix="" \
      --unselected-prefix="" \
      --selected.foreground="2" \
      --selected.background="0" \
      --cursor.foreground="6" \
      --header="🗑️  Select Extensions to Remove" \
      --header.foreground="6")
    
    if [[ -z "$selected_lines" ]]; then
      print_info "No extensions selected. Skipping extension removal."
      return 0
    fi
    
    # Parse selected extensions from gum output
    local selected_extensions=()
    while IFS= read -r line; do
      if [[ -z "$line" ]]; then
        continue
      fi
      
      # Strip any leading whitespace or cursor symbols
      local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
      line_clean="${line_clean#→ }"  # Remove cursor if present
      
      # Find matching extension from the map
      local i=0
      for item in "${gum_items[@]}"; do
        if [[ "$item" == "$line_clean" ]]; then
          selected_extensions+=("${ext_map[$i]}")
          break
        fi
        ((i++))
      done
    done <<< "$selected_lines"
    
    if [[ ${#selected_extensions[@]} -eq 0 ]]; then
      print_info "No extensions selected. Skipping extension removal."
      return 0
    fi
    
    # Confirm removal of selected extensions
    echo ""
    echo "Selected extensions for removal:"
    for ext in "${selected_extensions[@]}"; do
      echo "  • $ext"
    done
    echo ""
    
    if ! prompt_yes_no "Uninstall the selected extensions?" "n"; then
      print_info "Extension removal cancelled"
      return 0
    fi
    
    # Use selected extensions for removal
    installed_extensions_array=("${selected_extensions[@]}")
  fi
  
  local removed=0
  local failed=0
  
  # Ensure log directory exists
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  
  for ext in "${installed_extensions_array[@]}"; do
    if [[ -n "$ext" ]]; then
      print_info "Uninstalling $ext..."
      
      # Capture uninstall output and exit code separately
      # This prevents tee failures from masking successful uninstalls
      local uninstall_output uninstall_exit_code
      uninstall_output=$(code --uninstall-extension "$ext" 2>&1)
      uninstall_exit_code=$?
      
      # Log output to file, but don't echo to stdout to avoid duplicates
      echo "$uninstall_output" >> "$LOG_FILE" 2>/dev/null || true
      
      if [ $uninstall_exit_code -eq 0 ]; then
        print_success "$ext uninstalled"
        ((removed++))
      else
        print_error "Failed to uninstall $ext"
        # Show error output for failed uninstalls
        if [[ -n "$uninstall_output" ]]; then
          echo "$uninstall_output" | sed 's/^/  /'
        fi
        ((failed++))
      fi
    fi
  done
  
  echo ""
  if [[ $removed -gt 0 ]]; then
    print_success "Uninstalled $removed extension(s)"
  fi
  if [[ $failed -gt 0 ]]; then
    print_warn "Failed to uninstall $failed extension(s)"
  fi
}

# Clean VS Code settings
clean_vscode_settings() {
  print_header "🗑️  Clean VS Code Settings"
  
  local settings_file="$SCRIPT_DIR/../vscode/settings.json"
  local found_files=0
  
  if [[ -f "$settings_file" ]]; then
    ((found_files++))
  fi
  
  if [[ $found_files -eq 0 ]]; then
    print_info "VS Code settings file not found"
    return 0
  fi
  
  if prompt_yes_no "Remove generated VS Code settings file?" "n"; then
    if [[ -f "$settings_file" ]]; then
      if rm "$settings_file" 2>/dev/null; then
        print_success "VS Code settings file removed"
      else
        print_error "Failed to remove VS Code settings file"
      fi
    fi
  else
    print_info "Keeping VS Code settings file"
  fi
}

# Clean state files
clean_state_files() {
  print_header "🗑️  Clean State Files"
  
  if [[ ! -d "$STATE_DIR" ]]; then
    print_info "No state directory found"
    return 0
  fi
  
  if prompt_yes_no "Remove all state files and logs?" "n"; then
    if rm -rf "$STATE_DIR" 2>/dev/null; then
      print_success "State files removed"
    else
      print_error "Failed to remove state files"
    fi
  else
    print_info "Keeping state files"
  fi
}

# Remove Ollama (optional)
remove_ollama() {
  print_header "🗑️  Remove Ollama"
  
  if ! command -v ollama &>/dev/null; then
    print_info "Ollama not found"
    return 0
  fi
  
  if prompt_yes_no "Remove Ollama completely? (This will uninstall Ollama via Homebrew)" "n"; then
    # Confirm again
    if ! prompt_yes_no "This will uninstall Ollama. Are you absolutely sure?" "n"; then
      print_info "Ollama removal cancelled"
      return 0
    fi
    
    # Stop service
    print_info "Stopping Ollama service..."
    brew services stop ollama 2>/dev/null || true
    
    # Ensure log directory exists
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    
    # Uninstall
    print_info "Uninstalling Ollama..."
    
    # Capture uninstall output and exit code separately
    # This prevents tee failures from masking successful uninstalls
    local uninstall_output uninstall_exit_code
    uninstall_output=$(brew uninstall ollama 2>&1)
    uninstall_exit_code=$?
    
    # Log output to file, but don't echo to stdout to avoid duplicates
    echo "$uninstall_output" >> "$LOG_FILE" 2>/dev/null || true
    
    if [ $uninstall_exit_code -eq 0 ]; then
      print_success "Ollama uninstalled"
    else
      print_error "Failed to uninstall Ollama"
      # Show error output for failed uninstalls
      if [[ -n "$uninstall_output" ]]; then
        echo "$uninstall_output" | sed 's/^/  /'
      fi
    fi
  else
    print_info "Keeping Ollama installed"
  fi
}

# Main
main() {
  clear
  print_header "🗑️  Local LLM Uninstall Tool"
  
  # Ensure state directory exists for logging
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  
  print_warn "This tool will help you remove components of your local LLM setup."
  print_warn "You can choose what to remove."
  echo ""
  
  # Remove models
  remove_models
  
  # Clean Continue.dev config
  clean_continue_config
  
  # Remove VS Code extensions
  remove_vscode_extensions
  
  # Clean VS Code settings
  clean_vscode_settings
  
  # Clean state files
  clean_state_files
  
  # Remove Ollama (optional, last)
  remove_ollama
  
  # Summary
  print_header "✅ Uninstall Complete"
  print_success "Uninstall process finished"
  print_info "Some files may remain. Check manually if needed."
  echo ""
}

main "$@"
