#!/bin/zsh
#
# lib/ui.sh - UI functions for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Set color variables
MC_RED='\033[0;31m'
MC_GREEN='\033[0;32m'
MC_YELLOW='\033[0;33m'
MC_BLUE='\033[0;34m'
MC_PURPLE='\033[0;35m'
MC_CYAN='\033[0;36m'
MC_NC='\033[0m' # No Color

# Export colors for backward compatibility
RED="$MC_RED"
GREEN="$MC_GREEN"
YELLOW="$MC_YELLOW"
BLUE="$MC_BLUE"
PURPLE="$MC_PURPLE"
CYAN="$MC_CYAN"
NC="$MC_NC"

# Print a message with color
print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Print a header
print_header() {
  echo ""
  print_message "$PURPLE" "=============================================="
  print_message "$PURPLE" "  $1"
  print_message "$PURPLE" "=============================================="
}

# Print success message
print_success() {
  print_message "$GREEN" "✓ $1"
}

# Print error message
print_error() {
  print_message "$RED" "✗ $1"
}

# Print warning message
print_warning() {
  print_message "$YELLOW" "⚠ $1"
}

# Print info message
print_info() {
  print_message "$BLUE" "ℹ $1"
}

# Show a spinner for long-running operations
show_spinner() {
  local message="$1"
  local pid=$2
  
  # Use a basic spinner
  if [[ -n "$pid" ]]; then
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3
    local i=0
    while kill -0 $pid 2>/dev/null; do
      i=$(((i + charwidth) % ${#spin}))
      printf "\r$message %s" "${spin:$i:$charwidth}"
      sleep 0.1
    done
    wait $pid
    printf "\r\033[K"
  fi
}

# Show progress bar for long operations
show_progress() {
  local current=$1
  local total=$2
  local message="${3:-Progress}"
  
  local percent=$((current * 100 / total))
  local filled=$((percent / 2))
  local empty=$((50 - filled))
  printf "\r$message ["
  printf "%${filled}s" | tr ' ' '='
  printf "%${empty}s" | tr ' ' ' '
  printf "] %d%%" $percent
  if [[ $current -eq $total ]]; then
    echo ""
  fi
}

# Show detailed progress bar with operation name
show_detailed_progress() {
  local current=$1
  local total=$2
  local operation="$3"
  
  local percent=$((current * 100 / total))
  local filled=$((percent / 2))
  local empty=$((50 - filled))
  
  # Truncate operation name if too long
  local display_op="$operation"
  if [[ ${#display_op} -gt 40 ]]; then
    display_op="${display_op:0:37}..."
  fi
  
  printf "\r\033[K"
  printf "\r${CYAN}Cleaning:${NC} %-40s [%s%s] %d%% (%d/%d)" \
    "$display_op" \
    "$(printf "%${filled}s" | tr ' ' '=')" \
    "$(printf "%${empty}s" | tr ' ' ' ')" \
    "$percent" \
    "$current" \
    "$total"
}

# Determine which selection tool to use (fzf required)
mc_get_selection_tool() {
  if command -v fzf &> /dev/null; then
    echo "fzf"
  else
    echo "none"
  fi
}

# Check if a selection tool is available, install if needed
mc_check_selection_tool() {
  local tool=$(mc_get_selection_tool)
  
  if [[ "$tool" == "none" ]]; then
    print_warning "No interactive selection tool found (fzf required)."
    echo ""
    
    if [ -t 0 ] && read -q "?Do you want to install fzf now? (y/n) "; then
      echo ""
      print_info "Installing fzf..."
      
      if command -v brew &> /dev/null; then
        brew install fzf
        MC_SELECTION_TOOL_INSTALLED_BY_SCRIPT=true
        MC_SELECTION_TOOL="fzf"
        print_success "fzf installed successfully!"
        return 0
      else
        print_error "Homebrew not found. Cannot install fzf automatically."
        print_info "Please install manually: brew install fzf"
        exit 1
      fi
    else
      echo ""
      print_error "fzf is required for this script to work."
      print_info "Install with: brew install fzf"
      exit 1
    fi
  fi
}

# Legacy function name for backward compatibility
mc_check_gum() {
  mc_check_selection_tool
}

# Cleanup selection tool if it was installed by this script
mc_cleanup_selection_tool() {
  if [[ "$MC_SELECTION_TOOL_INSTALLED_BY_SCRIPT" == "true" ]]; then
    print_info "Cleaning up selection tool installation..."
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would remove $MC_SELECTION_TOOL"
    else
      if command -v brew &> /dev/null; then
        brew uninstall "$MC_SELECTION_TOOL" 2>/dev/null || true
      fi
    fi
    MC_SELECTION_TOOL_INSTALLED_BY_SCRIPT=false
    print_success "Selection tool cleaned up"
  fi
}

# Legacy function name for backward compatibility
mc_cleanup_gum() {
  mc_cleanup_selection_tool
}

# Export cleanup_gum for backward compatibility
cleanup_gum() {
  mc_cleanup_gum
}

# Confirmation prompt function (replaces gum confirm)
# Phase 4: Enhanced with better non-interactive detection and timeout handling
mc_confirm() {
  local prompt="$1"
  local default="${2:-}"  # Optional default value: "y" or "n"
  local timeout="${3:-10}"  # Timeout in seconds (default 10)
  local response
  
  # Phase 4.1: Check for explicit non-interactive mode first
  if [[ -n "${MC_NON_INTERACTIVE:-}" ]] || [[ "${MC_NON_INTERACTIVE:-}" == "true" ]]; then
    # Non-interactive mode: use default if provided, otherwise return false
    if [[ "$default" == "y" || "$default" == "Y" ]]; then
      log_message "INFO" "Non-interactive mode: auto-confirming '$prompt' (default: yes)"
      return 0
    else
      log_message "INFO" "Non-interactive mode: auto-rejecting '$prompt' (default: no)"
      return 1
    fi
  fi
  
  # Phase 4.1: Check if stdin is available and we're in an interactive terminal
  # Also check if we're in a background job or have piped input
  if [[ -t 0 ]] && [[ -t 1 ]] && [[ -z "${MC_NON_INTERACTIVE:-}" ]]; then
    # Phase 4.1: Check for piped input (e.g., echo "y" | script.sh)
    # If stdin is a pipe, try to read from it first
    if [[ -p /dev/stdin ]] || [[ -S /dev/stdin ]]; then
      # Piped input detected - read one character
      if IFS= read -r -t 1 response 2>/dev/null; then
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | cut -c1)
        if [[ "$response" == "y" ]]; then
          log_message "INFO" "Piped input confirmed: '$prompt'"
          return 0
        else
          log_message "INFO" "Piped input rejected: '$prompt'"
          return 1
        fi
      fi
    fi
    
    # Phase 4.1: Try to read from terminal with timeout
    # Use read -t with timeout to prevent hanging in background processes
    # In background processes, read will hang even if -t 0 returns true
    if read -t "$timeout" -q "?$prompt (y/n)${default:+ [default: ${default}]} " response 2>/dev/null; then
      echo ""
      response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
      if [[ "$response" == "y" || "$response" == "Y" ]]; then
        return 0
      else
        return 1
      fi
    else
      # Phase 4.1: Timeout or read failed - use default if provided
      echo ""
      if [[ "$default" == "y" || "$default" == "Y" ]]; then
        log_message "WARNING" "Input timeout for '$prompt', using default: yes"
        return 0
      else
        log_message "WARNING" "Input timeout for '$prompt', using default: no"
        return 1
      fi
    fi
  else
    # Phase 4.1: Non-interactive context detected
    # Use default if provided, otherwise return false (safe default)
    if [[ "$default" == "y" || "$default" == "Y" ]]; then
      log_message "INFO" "Non-interactive context: auto-confirming '$prompt' (default: yes)"
      return 0
    else
      log_message "INFO" "Non-interactive context: auto-rejecting '$prompt' (default: no)"
      return 1
    fi
  fi
}
