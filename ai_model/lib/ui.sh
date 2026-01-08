#!/bin/bash
#
# ui.sh - UI and printing functions for setup-local-llm.sh
#
# Depends on: constants.sh (for colors), logger.sh

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Print error with actionable suggestion
print_error_with_suggestion() {
  local error_msg="$1"
  local suggestion="$2"
  print_error "$error_msg"
  if [[ -n "$suggestion" ]]; then
    echo -e "${CYAN}💡 Suggestion:${NC} $suggestion"
  fi
}

# Progress indicator (simple spinner)
show_progress() {
  local message="$1"
  local pid="$2"
  
  if [[ -z "$pid" ]]; then
    # No PID provided, just show message
    echo -e "${CYAN}⏳${NC} $message"
    return
  fi
  
  # Show spinner while process is running
  local spinner='|/-\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    local char="${spinner:$((i % 4)):1}"
    echo -ne "\r${CYAN}${char}${NC} $message"
    sleep 0.1
    ((i++))
  done
  echo -ne "\r${GREEN}✓${NC} $message\n"
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

prompt_choice() {
  local prompt="$1"
  local default="$2"
  local choice
  echo -e "${YELLOW}$prompt${NC}"
  read -p "Choice [${default}]: " choice
  echo "${choice:-$default}"
}

# Check and install gum if missing (better terminal UI than fzf)
check_gum() {
  if ! command -v gum &>/dev/null; then
    log_error "gum not found. gum is required for interactive selection."
    echo ""
    if prompt_yes_no "Would you like the script to install gum now?" "y"; then
      print_info "Installing gum..."
      if brew install gum; then
        print_success "gum installed"
      else
        log_error "Failed to install gum"
        log_error "gum is required for this setup. Please install it manually and run this script again."
        echo ""
        echo "To install gum manually, run:"
        echo "  brew install gum"
        exit 1
      fi
    else
      log_error "gum is required. Please install it manually and run this script again."
      echo ""
      echo "To install gum manually, run:"
      echo "  brew install gum"
      exit 1
    fi
  else
    print_success "gum found"
  fi
}

# Format model info for gum display with fixed-width columns
format_model_for_gum() {
  local model="$1"
  local tier="$2"
  local is_recommended="${3:-false}"
  local model_width="${4:-25}"  # Width for model name (including checkmark space)
  local ram_width="${5:-8}"      # Width for RAM column
  
  local ram=$(get_model_ram "$model")
  local desc=$(get_model_desc "$model")
  local eligible=false
  
  if is_model_eligible "$model" "$tier"; then
    eligible=true
  fi
  
  local suffix=""
  local tier_label=""
  
  # Get tier label
  case "$tier" in
    S) tier_label="Tier S (≥49GB RAM)" ;;
    A) tier_label="Tier A (33-48GB RAM)" ;;
    B) tier_label="Tier B (17-32GB RAM)" ;;
    C) tier_label="Tier C (<17GB RAM)" ;;
  esac
  
  if [[ "$eligible" == "false" ]]; then
    suffix=" ⚠ Not recommended"
  fi
  
  # Format with fixed-width columns for perfect alignment
  # No checkmark in the list - just align the separators
  printf "%-${model_width}s | %-${ram_width}s | %s%s\n" "$model" "${ram}GB" "$desc" "$suffix"
}

# Format extension info for gum display with fixed-width columns
format_extension_for_gum() {
  local ext_id="$1"
  local friendly_name="$2"
  local is_installed="${3:-false}"
  local name_width="${4:-30}"  # Default width for name column
  
  local suffix=""
  if [[ "$is_installed" == "true" ]]; then
    suffix=" (installed)"
  fi
  
  # Format with fixed-width column for alignment
  # No checkmark in the list - just align the separators
  printf "%-${name_width}s | %s%s\n" "$friendly_name" "$ext_id" "$suffix"
}
