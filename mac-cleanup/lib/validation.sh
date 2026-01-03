#!/bin/zsh
#
# lib/validation.sh - Input validation functions for mac-cleanup
#

# Validate that a path exists
mc_validate_path_exists() {
  local path="$1"
  local description="${2:-Path}"
  
  if [[ -z "$path" ]]; then
    print_error "${description} is empty"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is empty"
    return 1
  fi
  
  if [[ ! -e "$path" ]]; then
    print_error "${description} does not exist: $path"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} does not exist: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is a directory
mc_validate_directory() {
  local path="$1"
  local description="${2:-Directory}"
  
  if ! mc_validate_path_exists "$path" "$description"; then
    return 1
  fi
  
  if [[ ! -d "$path" ]]; then
    print_error "${description} is not a directory: $path"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a directory: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is a file
mc_validate_file() {
  local path="$1"
  local description="${2:-File}"
  
  if ! mc_validate_path_exists "$path" "$description"; then
    return 1
  fi
  
  if [[ ! -f "$path" ]]; then
    print_error "${description} is not a file: $path"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a file: $path"
    return 1
  fi
  
  return 0
}

# Validate that a path is writable
mc_validate_writable() {
  local path="$1"
  local description="${2:-Path}"
  
  if [[ ! -w "$path" ]]; then
    print_error "${description} is not writable: $path"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not writable: $path"
    return 1
  fi
  
  return 0
}

# Validate that a numeric value is positive
mc_validate_positive_number() {
  local value="$1"
  local description="${2:-Value}"
  
  if [[ -z "$value" ]]; then
    print_error "${description} is empty"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is empty"
    return 1
  fi
  
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    print_error "${description} is not a valid positive number: $value"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: ${description} is not a valid number: $value"
    return 1
  fi
  
  return 0
}

# Validate plugin function exists
mc_validate_plugin_function() {
  local function_name="$1"
  local plugin_name="${2:-Unknown}"
  
  if [[ -z "$function_name" ]]; then
    print_error "Plugin function name is empty for plugin: $plugin_name"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: Plugin function name is empty for: $plugin_name"
    return 1
  fi
  
  if ! type "$function_name" &>/dev/null; then
    print_error "Plugin function not found: $function_name (plugin: $plugin_name)"
    log_message "$MC_LOG_LEVEL_ERROR" "Validation failed: Plugin function not found: $function_name (plugin: $plugin_name)"
    return 1
  fi
  
  return 0
}

# Validate that a directory is not empty (has content)
mc_validate_directory_has_content() {
  local path="$1"
  local description="${2:-Directory}"
  
  if ! mc_validate_directory "$path" "$description"; then
    return 1
  fi
  
  local item_count=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l 2>/dev/null | tr -d ' ' || echo "0")
  if [[ $item_count -eq 0 ]]; then
    print_warning "${description} is empty: $path"
    return 1
  fi
  
  return 0
}
