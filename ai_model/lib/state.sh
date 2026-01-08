#!/bin/bash
#
# state.sh - State management functions for setup-local-llm.sh
#
# Depends on: constants.sh (for STATE_FILE, STATE_DIR), logger.sh

# State management
save_state() {
  mkdir -p "$STATE_DIR"
  # Guard against unset arrays (set -u compatibility)
  local selected_models=("${SELECTED_MODELS[@]:-}")
  local installed_models=("${INSTALLED_MODELS[@]:-}")
  local continue_profiles=("${CONTINUE_PROFILES[@]:-}")
  local state_json=$(cat <<EOF
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
  echo "$state_json" > "$STATE_FILE"
  log_info "State saved to $STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    log_info "Loading state from $STATE_FILE"
    # Parse JSON state (basic parsing, assumes jq available or manual parsing)
    if command -v jq &>/dev/null; then
      HARDWARE_TIER=$(jq -r '.hardware_tier // ""' "$STATE_FILE" 2>/dev/null || echo "")
      # bash 3.2 compatible: use while read instead of readarray
      SELECTED_MODELS=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && SELECTED_MODELS+=("$line")
      done < <(jq -r '.selected_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
      INSTALLED_MODELS=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && INSTALLED_MODELS+=("$line")
      done < <(jq -r '.installed_models[]? // empty' "$STATE_FILE" 2>/dev/null || echo "")
    fi
  fi
}
