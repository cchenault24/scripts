#!/bin/zsh
#
# lib/ui.sh - UI functions for mac-cleanup
#

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
  
  if command -v gum &> /dev/null; then
    # Use gum spinner if available - wait for the actual process
    if [[ -n "$pid" ]]; then
      while kill -0 $pid 2>/dev/null; do
        sleep 0.1
      done
      wait $pid
    else
      gum spin --spinner dot --title "$message" -- sleep 0.5
    fi
    return
  fi
  
  # Otherwise use a basic spinner
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
  
  if command -v gum &> /dev/null && [[ -t 1 ]]; then
    local percent=$((current * 100 / total))
    echo "$percent" | gum progress --title "$message" --width 50 --percent
  else
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
  fi
}

# Check if gum is installed, install if not
mc_check_gum() {
  if ! command -v gum &> /dev/null; then
    print_warning "gum is not installed. This tool is required for interactive selection."
    echo ""
    
    if [ -t 0 ] && read -q "?Do you want to install gum now? (y/n) "; then
      echo ""
      print_info "Installing gum..."
      
      # Check for Homebrew
      if command -v brew &> /dev/null; then
        brew install gum
      else
        # Download and install gum binary if Homebrew is not available
        TMP_DIR=$(mktemp -d)
        GUM_VERSION="0.11.0"
        GUM_URL="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Darwin_x86_64.tar.gz"
        
        curl -sL "$GUM_URL" | tar xz -C "$TMP_DIR"
        if [[ "$MC_DRY_RUN" == "true" ]]; then
          print_info "[DRY RUN] Would install gum to /usr/local/bin/"
        else
          sudo mv "$TMP_DIR/gum" /usr/local/bin/ || {
            print_error "Failed to install gum. Please install manually: brew install gum"
            exit 1
          }
        fi
        rm -rf "$TMP_DIR"
      fi
      
      MC_GUM_INSTALLED_BY_SCRIPT=true
      print_success "gum installed successfully!"
    else
      echo ""
      print_error "gum is required for this script to work."
      print_info "You can install it with: brew install gum"
      exit 1
    fi
  fi
}

# Cleanup gum if it was installed by this script
mc_cleanup_gum() {
  if [[ "$MC_GUM_INSTALLED_BY_SCRIPT" == "true" ]]; then
    print_info "Cleaning up gum installation..."
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would remove gum"
    else
      if command -v brew &> /dev/null; then
        brew uninstall gum 2>/dev/null || true
      else
        sudo rm -f /usr/local/bin/gum 2>/dev/null || true
      fi
    fi
    MC_GUM_INSTALLED_BY_SCRIPT=false
    print_success "gum cleaned up"
  fi
}

# Export cleanup_gum for backward compatibility
cleanup_gum() {
  mc_cleanup_gum
}
