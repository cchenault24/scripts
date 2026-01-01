#!/bin/bash
# Home Network Monitor - Configuration Management
# Configuration file management (.env, state detection)
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Configuration Management
#------------------------------------------------------------------------------

load_env_if_exists() {
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  : "${BASE_DIR:=${HOME}/home-netmon}"
  
  if [ -f "$ENV_FILE" ]; then
    if command -v log_info >/dev/null 2>&1; then
      log_info "Loading existing .env file"
    fi
    # Source .env file safely (bash 3.2 compatible)
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      case "$key" in
        \#*|"") continue ;;
      esac
      # Remove quotes if present
      value=$(echo "$value" | sed "s/^['\"]//; s/['\"]$//")
      export "$key=$value"
    done < "$ENV_FILE"
  fi
}

get_env_value() {
  local key="$1"
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  
  if [ -f "$ENV_FILE" ]; then
    grep "^${key}=" "$ENV_FILE" | cut -d= -f2- | sed "s/^['\"]//; s/['\"]$//"
  fi
}

upsert_env() {
  local key="$1"
  local value="$2"
  local comment="$3"
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  : "${BASE_DIR:=${HOME}/home-netmon}"
  
  mkdir -p "$BASE_DIR"
  touch "$ENV_FILE"
  
  # Add comment if provided and key doesn't exist
  if [ -n "$comment" ] && ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "# $comment" >> "$ENV_FILE"
  fi
  
  if grep -q "^${key}=" "$ENV_FILE"; then
    # Update existing value (preserve comment if any)
    local temp_file=$(mktemp)
    awk -v key="$key" -v val="$value" '
      /^#.*/ { print; next }
      /^[[:space:]]*#/ { print; next }
      $0 ~ "^" key "=" { print key "=" val; next }
      { print }
    ' "$ENV_FILE" > "$temp_file"
    mv "$temp_file" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Updated .env: ${key}=${value}"
  fi
}

prompt_if_missing() {
  local key="$1"
  local prompt_text="$2"
  local default="$3"
  local validator="${4:-}"
  local comment="$5"
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  
  local existing_value
  existing_value=$(get_env_value "$key")
  
  if [ -n "$existing_value" ]; then
    if command -v say >/dev/null 2>&1; then
      say "Using existing ${key}: ${existing_value}"
    fi
    if command -v log_info >/dev/null 2>&1; then
      log_info "Using existing value for $key: $existing_value"
    fi
    eval "export ${key}=\"${existing_value}\""
    return 0
  fi
  
  # Prompt for new value
  local value=""
  local valid=false
  
  while [ "$valid" = false ]; do
    echo ""
    echo "$prompt_text"
    read -r -p "[default: ${default}]: " value || true
    value="${value:-$default}"
    
    if command -v sanitize_input >/dev/null 2>&1; then
      value=$(sanitize_input "$value")
    fi
    
    if [ -n "$validator" ]; then
      if $validator "$value"; then
        valid=true
      else
        if command -v warn >/dev/null 2>&1; then
          warn "Invalid value. Please try again."
        fi
        continue
      fi
    else
      valid=true
    fi
  done
  
  if command -v log_user_input >/dev/null 2>&1; then
    log_user_input "$key=$value"
  fi
  upsert_env "$key" "$value" "$comment"
  eval "export ${key}=\"${value}\""
}

#------------------------------------------------------------------------------
# State Detection Functions
#------------------------------------------------------------------------------

is_installed() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  : "${COMPOSE_FILE:=${BASE_DIR}/docker-compose.yml}"
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  
  [ -d "$BASE_DIR" ] && [ -f "$COMPOSE_FILE" ] && [ -f "$ENV_FILE" ]
}

containers_running() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  : "${COMPOSE_FILE:=${BASE_DIR}/docker-compose.yml}"
  
  if [ ! -d "$BASE_DIR" ] || [ ! -f "$COMPOSE_FILE" ]; then
    return 1
  fi
  
  if ! command_exists docker; then
    return 1
  fi
  
  # Check if containers are running (bash 3.2 compatible)
  local ps_output
  ps_output=$(cd "$BASE_DIR" && docker compose ps --format json 2>/dev/null || echo "")
  
  if [ -z "$ps_output" ]; then
    return 1
  fi
  
  # Check for running state (simple grep, no jq required)
  echo "$ps_output" | grep -q '"State":"running"' || return 1
  return 0
}

launchagent_installed() {
  : "${LAUNCH_AGENT:=${HOME}/Library/LaunchAgents/com.netmon.startup.plist}"
  [ -f "$LAUNCH_AGENT" ]
}
