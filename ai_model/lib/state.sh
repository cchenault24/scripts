#!/bin/bash
#
# state.sh - State management functions for setup-local-llm.sh
#
# Depends on: constants.sh (for STATE_FILE, STATE_DIR), logger.sh, utils.sh

# State management
save_state() {
  mkdir -p "$STATE_DIR"
  
  # Validate state directory is writable
  if [[ ! -w "$STATE_DIR" ]]; then
    log_error "State directory is not writable: $STATE_DIR"
    return 1
  fi
  
  # Guard against unset arrays (set -u compatibility)
  local selected_models=("${SELECTED_MODELS[@]:-}")
  local installed_models=("${INSTALLED_MODELS[@]:-}")
  local continue_profiles=("${CONTINUE_PROFILES[@]:-}")
  
  # Build state JSON with fallback if jq unavailable
  local state_json
  if command -v jq &>/dev/null; then
    state_json=$(cat <<EOF
{
  "hardware_tier": "${HARDWARE_TIER:-}",
  "selected_models": $(printf '%s\n' "${selected_models[@]}" | jq -R . | jq -s .),
  "installed_models": $(printf '%s\n' "${installed_models[@]}" | jq -R . | jq -s .),
  "continue_profiles": $(printf '%s\n' "${continue_profiles[@]}" | jq -R . | jq -s .),
  "vscode_extensions_installed": ${VSCODE_EXTENSIONS_INSTALLED:-false},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    )
  else
    # Fallback: simple JSON without jq (basic structure)
    state_json=$(cat <<EOF
{
  "hardware_tier": "${HARDWARE_TIER:-}",
  "selected_models": [],
  "installed_models": [],
  "continue_profiles": [],
  "vscode_extensions_installed": ${VSCODE_EXTENSIONS_INSTALLED:-false},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    )
    log_warn "jq not available, saving simplified state"
  fi
  
  # Use atomic write for safety
  if command -v atomic_write &>/dev/null; then
    if atomic_write "$STATE_FILE" "$state_json"; then
      log_info "State saved to $STATE_FILE"
      return 0
    else
      log_error "Failed to save state atomically"
      return 1
    fi
  else
    # Fallback: regular write
    if echo "$state_json" > "$STATE_FILE" 2>/dev/null; then
      log_info "State saved to $STATE_FILE"
      return 0
    else
      log_error "Failed to save state to $STATE_FILE"
      return 1
    fi
  fi
}

# Validate state file integrity
validate_state_file() {
  local state_file="${1:-$STATE_FILE}"
  
  if [[ ! -f "$state_file" ]]; then
    log_warn "State file does not exist: $state_file"
    return 1
  fi
  
  # Check if file is readable
  if [[ ! -r "$state_file" ]]; then
    log_error "State file is not readable: $state_file"
    return 1
  fi
  
  # Check if file is empty
  if [[ ! -s "$state_file" ]]; then
    log_warn "State file is empty: $state_file"
    return 1
  fi
  
  # Validate JSON syntax if jq is available
  if command -v jq &>/dev/null; then
    if ! jq empty "$state_file" 2>/dev/null; then
      log_error "State file contains invalid JSON: $state_file"
      return 1
    fi
  else
    # Basic validation: check if it looks like JSON
    if ! grep -q "{" "$state_file" || ! grep -q "}" "$state_file"; then
      log_warn "State file may not be valid JSON (jq not available for validation)"
    fi
  fi
  
  log_info "State file validation passed: $state_file"
  return 0
}

load_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    log_info "No state file found, starting fresh"
    return 0
  fi
  
  # Validate state file before loading
  if ! validate_state_file "$STATE_FILE"; then
    log_warn "State file validation failed, backing up and starting fresh"
    local backup_file="${STATE_FILE}.corrupted-$(date +%Y%m%d-%H%M%S)"
    if mv "$STATE_FILE" "$backup_file" 2>/dev/null; then
      log_info "Corrupted state file backed up to: $backup_file"
      print_warn "Previous state file was corrupted and has been backed up"
      print_info "Starting with fresh state"
    fi
    return 0
  fi
  
  log_info "Loading state from $STATE_FILE"
  
  # Parse JSON state with error handling
  if command -v jq &>/dev/null; then
    # Validate JSON first
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
      log_error "State file contains invalid JSON"
      return 1
    fi
    
    # Load hardware tier
    HARDWARE_TIER=$(jq -r '.hardware_tier // ""' "$STATE_FILE" 2>/dev/null || echo "")
    
    # bash 3.2 compatible: use while read instead of readarray
    SELECTED_MODELS=()
    while IFS= read -r line; do
      if [[ -n "$line" ]] && [[ "$line" != "null" ]]; then
        SELECTED_MODELS+=("$line")
      fi
    done < <(jq -r '.selected_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    INSTALLED_MODELS=()
    while IFS= read -r line; do
      if [[ -n "$line" ]] && [[ "$line" != "null" ]]; then
        INSTALLED_MODELS+=("$line")
      fi
    done < <(jq -r '.installed_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    CONTINUE_PROFILES=()
    while IFS= read -r line; do
      if [[ -n "$line" ]] && [[ "$line" != "null" ]]; then
        CONTINUE_PROFILES+=("$line")
      fi
    done < <(jq -r '.continue_profiles[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    VSCODE_EXTENSIONS_INSTALLED=$(jq -r '.vscode_extensions_installed // false' "$STATE_FILE" 2>/dev/null || echo "false")
    
    log_info "State loaded successfully"
    log_info "  Hardware tier: ${HARDWARE_TIER:-not set}"
    log_info "  Selected models: ${#SELECTED_MODELS[@]}"
    log_info "  Installed models: ${#INSTALLED_MODELS[@]}"
  else
    log_warn "jq not available, cannot load state from JSON file"
    print_warn "State file exists but jq is required to load it"
    return 1
  fi
}
