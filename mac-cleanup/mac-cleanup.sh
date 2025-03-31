#!/bin/zsh
#
# mac-cleanup.zsh - Interactive macOS system cleanup utility
# 
# This script safely cleans temporary files, caches, and logs on macOS
# with interactive selection using gum, color-coded output, and safety measures.
#
# Author: Generated with Claude
# Date: March 24, 2025
# License: MIT
#

# --------------------------------------------------------------------------
# SCRIPT CONFIGURATION
# --------------------------------------------------------------------------

# Handle script interruptions gracefully
handle_interrupt() {
  echo ""
  print_warning "Script interrupted by user."
  print_info "Cleaning up and exiting..."
  
  # Clean up gum if it was installed by this script
  cleanup_gum
  
  # Exit with non-zero status
  exit 1
}

# Set up trap for CTRL+C and other signals
trap handle_interrupt INT TERM HUP

# Show a spinner for long-running operations
show_spinner() {
  local message="$1"
  local pid=$2
  local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
  local charwidth=3
  
  if command -v gum &> /dev/null; then
    # Use gum spinner if available
    gum spin --spinner dot --title "$message" -- sleep 0.5
    return
  fi
  
  # Otherwise use a basic spinner
  while kill -0 $pid 2>/dev/null; do
    local i=$(((i + charwidth) % ${#spin}))
    printf "\r$message %s" "${spin:$i:$charwidth}"
    sleep 0.1
  done
  printf "\r\033[K"
}

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set backup directory
BACKUP_DIR="$HOME/.mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
GUM_INSTALLED_BY_SCRIPT=false

# --------------------------------------------------------------------------
# UTILITY FUNCTIONS
# --------------------------------------------------------------------------

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

# Check for tools the script depends on
check_dependencies() {
  local missing_deps=()
  
  for cmd in find; do
    if ! command -v $cmd &>/dev/null; then
      missing_deps+=($cmd)
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    print_error "Missing required dependencies: ${missing_deps[*]}"
    print_info "Please install these tools before running the script."
    exit 1
  fi
}

# Function to run commands as admin
run_as_admin() {
  local command="$1"
  local description="$2"
  local max_attempts=3
  local attempt=1
  
  print_info "Running $description with administrative privileges..."
  
  # Loop until successful or max attempts reached
  while [[ $attempt -le $max_attempts ]]; do
    # Ask for d_account username if not yet provided
    if [[ -z "$ADMIN_USERNAME" ]]; then
      print_info "Please enter your administrative account username (d_account):"
      read ADMIN_USERNAME
    fi
    
    # Run the command with su
    if su "$ADMIN_USERNAME" -c "$command" 2>/dev/null; then
      return 0
    else
      print_error "Failed to execute command as administrator (attempt $attempt of $max_attempts)."
      print_warning "Please check your administrative username."
      
      # Reset admin username for next attempt
      ADMIN_USERNAME=""
      
      # Exit if we've reached max attempts
      if [[ $attempt -eq $max_attempts ]]; then
        print_error "Maximum attempts reached. Skipping administrative operation."
        return 1
      fi
      
      attempt=$((attempt + 1))
    fi
  done
  
  return 1
}

# Check if gum is installed, install if not
check_gum() {
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
        sudo mv "$TMP_DIR/gum" /usr/local/bin/ || run_as_admin "mv $TMP_DIR/gum /usr/local/bin/" "installing gum"
        rm -rf "$TMP_DIR"
      fi
      
      GUM_INSTALLED_BY_SCRIPT=true
      print_success "gum installed successfully!"
    else
      echo ""
      print_error "gum is required for this script to work."
      print_info "You can install it with: brew install gum"
      exit 1
    fi
  fi
}

# Clean up any temporary files created by the script
cleanup_script() {
  # Perform any necessary cleanup before exiting
  print_info "Cleaning up script resources..."
  
  # Remove any temp files
  rm -f /tmp/mac-cleanup-temp-*(/N) 2>/dev/null
  
  # Clean up gum if it was installed by this script
  cleanup_gum
  
  # Compress backup logs if they exist
  if [[ -d "$BACKUP_DIR" && $(find "$BACKUP_DIR" -type f | wc -l) -gt 0 ]]; then
    find "$BACKUP_DIR" -type f -name "*.log" -exec gzip {} \; 2>/dev/null
  fi
}

# Create backup directory if it doesn't exist
create_backup_dir() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR" 2>/dev/null || {
      print_error "Failed to create backup directory at $BACKUP_DIR"
      print_info "Creating backup directory in /tmp instead..."
      BACKUP_DIR="/tmp/mac-cleanup-backups/$(date +%Y-%m-%d-%H-%M-%S)"
      mkdir -p "$BACKUP_DIR"
    }
    print_success "Created backup directory at $BACKUP_DIR"
  fi
}

# Backup a directory or file before cleaning
backup() {
  local path="$1"
  local backup_name="$2"
  
  if [[ -e "$path" ]]; then
    print_info "Backing up $path..."
    
    if [[ -d "$path" ]]; then
      # Use a background process for large directories
      tar -czf "$BACKUP_DIR/${backup_name}.tar.gz" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null &
      local pid=$!
      show_spinner "Creating backup of $(basename "$path")" $pid
      wait $pid
    else
      cp "$path" "$BACKUP_DIR/${backup_name}" 2>/dev/null || {
        print_warning "Backup failed, but continuing with cleanup..."
        return 1
      }
    fi
    
    print_success "Backup complete: $backup_name"
    return 0
  fi
  
  return 0
}

# Safely remove a directory or file
safe_remove() {
  local path="$1"
  local description="$2"
  
  if [[ -e "$path" ]]; then
    print_info "Cleaning $description..."
    if [[ -d "$path" ]]; then
      rm -rf "$path" 2>/dev/null || true
    else
      rm -f "$path" 2>/dev/null || true
    fi
    print_success "Cleaned $description"
  fi
}

# Safely clean a directory (remove contents but keep the directory)
safe_clean_dir() {
  local path="$1"
  local description="$2"
  
  if [[ -d "$path" ]]; then
    print_info "Cleaning $description..."
    rm -rf "${path:?}"/* "${path:?}"/.[!.]* 2>/dev/null || true
    print_success "Cleaned $description"
  fi
}

# Cleanup gum if it was installed by this script
cleanup_gum() {
  if [[ "$GUM_INSTALLED_BY_SCRIPT" == "true" ]]; then
    print_info "Cleaning up gum installation..."
    if command -v brew &> /dev/null; then
      brew uninstall gum
    else
      sudo rm -f /usr/local/bin/gum || run_as_admin "rm -f /usr/local/bin/gum" "removing gum"
    fi
    GUM_INSTALLED_BY_SCRIPT=false
    print_success "gum cleaned up"
  fi
}

# --------------------------------------------------------------------------
# CLEANUP FUNCTIONS
# --------------------------------------------------------------------------

# Clean user cache
clean_user_cache() {
  print_header "Cleaning User Cache"
  
  local cache_dir="$HOME/Library/Caches"
  
  backup "$cache_dir" "user_caches"
  find "$cache_dir" -depth 1 -not -path "*.DS_Store" | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") cache"
  done
  
  print_success "User cache cleaned."
}

# Clean system cache
clean_system_cache() {
  print_header "Cleaning System Cache"
  
  print_warning "This operation requires administrative privileges"
  if gum confirm "Do you want to continue?"; then
    local cache_dir="/Library/Caches"
    
    backup "$cache_dir" "system_caches"
    
    run_as_admin "find $cache_dir -depth 1 | while read dir; do rm -rf \"\$dir\" 2>/dev/null || true; echo \"Cleaned \$(basename \"\$dir\") cache\"; done" "system cache cleanup"
    
    print_success "System cache cleaned."
  else
    print_info "Skipping system cache cleanup"
  fi
}

# Clean application logs
clean_app_logs() {
  print_header "Cleaning Application Logs"
  
  local logs_dir="$HOME/Library/Logs"
  
  backup "$logs_dir" "application_logs"
  find "$logs_dir" -depth 1 | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") logs"
  done
  
  print_success "Application logs cleaned."
}

# Clean system logs
clean_system_logs() {
  print_header "Cleaning System Logs"
  
  print_warning "⚠️ CAUTION: System logs can be important for troubleshooting system issues"
  print_warning "Only proceed if you understand the potential consequences"
  
  if gum confirm "Are you sure you want to clean system logs?"; then
    print_warning "This operation requires administrative privileges"
    
    if gum confirm "Do you want to continue?"; then
      local logs_dir="/var/log"
      
      backup "$logs_dir" "system_logs"
      
      # Clean log files without removing them (zero their size instead)
      run_as_admin "find $logs_dir -type f -name \"*.log\" | while read file; do truncate -s 0 \"\$file\" 2>/dev/null || true; echo \"Cleaned \$(basename \"\$file\")\"; done" "system logs cleanup (current logs)"
      
      # Clean archived logs
      run_as_admin "find $logs_dir -type f -name \"*.log.*\" | while read file; do rm -f \"\$file\" 2>/dev/null || true; echo \"Removed \$(basename \"\$file\")\"; done" "system logs cleanup (archived logs)"
      
      print_success "System logs cleaned."
    else
      print_info "Skipping system logs cleanup"
    fi
  else
    print_info "Skipping system logs cleanup"
  fi
}

# Clean temp files
clean_temp_files() {
  print_header "Cleaning Temporary Files"
  
  local temp_dirs=("/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp")
  
  for temp_dir in "${temp_dirs[@]}"; do
    if [[ -d "$temp_dir" ]]; then
      backup "$temp_dir" "temp_files_$(basename "$temp_dir")"
      
      # Skip certain system files in /tmp
      if [[ "$temp_dir" == "/tmp" ]]; then
        find "$temp_dir" -mindepth 1 -not -name ".X*" -not -name "com.apple.*" | while read item; do
          safe_remove "$item" "$(basename "$item")"
        done
      else
        safe_clean_dir "$temp_dir" "$(basename "$temp_dir")"
      fi
      
      print_success "Cleaned $temp_dir."
    fi
  done
}

# Clean Safari cache
clean_safari_cache() {
  print_header "Cleaning Safari Cache"
  
  if ! command -v safaridriver &> /dev/null && [[ ! -d "$HOME/Library/Safari" ]]; then
    print_warning "Safari does not appear to be installed or has never been run."
    return
  fi
  
  local safari_cache_dirs=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Safari/LocalStorage"
    "$HOME/Library/Safari/Databases"
    "$HOME/Library/Safari/ServiceWorkers"
  )
  
  for dir in "${safari_cache_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      backup "$dir" "safari_$(basename "$dir")"
      safe_clean_dir "$dir" "Safari $(basename "$dir")"
      print_success "Cleaned $dir."
    fi
  done
  
  print_warning "You may need to restart Safari for changes to take effect"
}

# Clean Chrome cache
clean_chrome_cache() {
  print_header "Cleaning Chrome Cache"
  
  local chrome_dirs=(
    "$HOME/Library/Caches/Google/Chrome"
    "$HOME/Library/Application Support/Google/Chrome/Default/Cache"
    "$HOME/Library/Application Support/Google/Chrome/Default/Code Cache"
    "$HOME/Library/Application Support/Google/Chrome/Default/Service Worker"
  )
  
  local chrome_found=false
  
  for dir in "${chrome_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      chrome_found=true
      backup "$dir" "chrome_$(basename "$dir")"
      safe_clean_dir "$dir" "Chrome $(basename "$dir")"
      print_success "Cleaned $dir."
    fi
  done
  
  if [[ "$chrome_found" == false ]]; then
    print_warning "Chrome does not appear to be installed or has never been run."
  else
    print_warning "You may need to restart Chrome for changes to take effect"
  fi
}

# Clean Application Container Caches
clean_container_caches() {
  print_header "Cleaning Application Container Caches"
  
  local containers_dir="$HOME/Library/Containers"
  
  if [[ -d "$containers_dir" ]]; then
    backup "$containers_dir" "app_containers"
    
    find "$containers_dir" -type d -name "Caches" | while read dir; do
      local app_name=$(echo "$dir" | awk -F'/' '{print $(NF-2)}')
      safe_clean_dir "$dir" "$app_name container cache"
      print_success "Cleaned $app_name container cache."
    done
  else
    print_warning "No application containers found."
  fi
}

# Clean Saved Application States
clean_saved_states() {
  print_header "Cleaning Saved Application States"
  
  local saved_states_dir="$HOME/Library/Saved Application State"
  
  if [[ -d "$saved_states_dir" ]]; then
    backup "$saved_states_dir" "saved_app_states"
    safe_clean_dir "$saved_states_dir" "saved application states"
    print_success "Cleaned saved application states."
  else
    print_warning "No saved application states found."
  fi
}

# Clean Developer Tool Temporary Files
clean_dev_tool_temp() {
  print_header "Cleaning Developer Tool Temporary Files"
  
  # IntelliJ IDEA
  local idea_dirs=(
    "$HOME/Library/Caches/JetBrains"
    "$HOME/Library/Application Support/JetBrains/*/caches"
    "$HOME/Library/Logs/JetBrains"
  )
  
  for dir_pattern in "${idea_dirs[@]}"; do
    for dir in $(find "$HOME" -path "$dir_pattern" 2>/dev/null); do
      if [[ -d "$dir" ]]; then
        backup "$dir" "intellij_$(basename "$dir")"
        safe_clean_dir "$dir" "IntelliJ $(basename "$dir")"
        print_success "Cleaned $dir."
      fi
    done
  done
  
  # VS Code
  local vscode_dirs=(
    "$HOME/Library/Application Support/Code/Cache"
    "$HOME/Library/Application Support/Code/CachedData"
    "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Code/Code Cache"
    "$HOME/Library/Caches/com.microsoft.VSCode"
    "$HOME/Library/Caches/com.microsoft.VSCode.ShipIt"
  )
  
  for dir in "${vscode_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      backup "$dir" "vscode_$(basename "$dir")"
      safe_clean_dir "$dir" "VS Code $(basename "$dir")"
      print_success "Cleaned $dir."
    fi
  done
}

# Clean Corrupted Preference Lockfiles
clean_pref_lockfiles() {
  print_header "Cleaning Corrupted Preference Lockfiles"
  
  local plist_locks=($(find "$HOME/Library/Preferences" -name "*.plist.lockfile" 2>/dev/null))
  
  if [[ ${#plist_locks[@]} -eq 0 ]]; then
    print_warning "No preference lockfiles found."
    return
  fi
  
  print_info "Found ${#plist_locks[@]} preference lockfiles"
  
  for lock in "${plist_locks[@]}"; do
    local plist_file="${lock%.lockfile}"
    
    # Check if the plist file exists
    if [[ ! -f "$plist_file" ]]; then
      backup "$lock" "$(basename "$lock")"
      safe_remove "$lock" "orphaned lockfile $(basename "$lock")"
    fi
  done
  
  print_success "Cleaned corrupted preference lockfiles."
}

# Empty Trash
empty_trash() {
  print_header "Emptying Trash"
  
  local trash_dir="$HOME/.Trash"
  
  if [[ -d "$trash_dir" && "$(ls -A "$trash_dir" 2>/dev/null)" ]]; then
    print_warning "This will permanently delete all items in your Trash"
    if gum confirm "Are you sure you want to empty the Trash?"; then
      rm -rf "$trash_dir"/* 2>/dev/null || true
      print_success "Trash emptied."
    else
      print_info "Skipping Trash cleanup"
    fi
  else
    print_info "Trash is already empty"
  fi
}

# Clean Homebrew Cache
clean_homebrew_cache() {
  print_header "Cleaning Homebrew Cache"
  
  if ! command -v brew &> /dev/null; then
    print_warning "Homebrew is not installed."
    return
  fi
  
  print_info "Cleaning Homebrew cache..."
  
  brew cleanup -s
  
  print_success "Homebrew cache cleaned."
}

# Flush DNS Cache
flush_dns_cache() {
  print_header "Flushing DNS Cache"
  
  print_info "Flushing DNS Cache..."
  
  run_as_admin "dscacheutil -flushcache; killall -HUP mDNSResponder" "DNS cache flush"
  
  print_success "DNS Cache flushed"
}

# --------------------------------------------------------------------------
# MAIN SCRIPT
# --------------------------------------------------------------------------

main() {
  print_header "macOS Cleanup Utility"
  print_info "This script will help you safely clean up your macOS system."
  
  # Check dependencies
  check_dependencies
  
  # Initialize admin username variable
  ADMIN_USERNAME=""
  
  # Check for gum and install if needed
  check_gum
  
  # Create backup directory
  create_backup_dir
  
  # Add script cleanup to exit trap
  trap cleanup_script EXIT
  
  # Define cleanup options
  local cleanup_options=(
    "User Cache:clean_user_cache"
    "System Cache:clean_system_cache"
    "Application Logs:clean_app_logs"
    "System Logs:clean_system_logs"
    "Temporary Files:clean_temp_files"
    "Safari Cache:clean_safari_cache"
    "Chrome Cache:clean_chrome_cache"
    "Application Container Caches:clean_container_caches"
    "Saved Application States:clean_saved_states"
    "Developer Tool Temp Files:clean_dev_tool_temp"
    "Corrupted Preference Lockfiles:clean_pref_lockfiles"
    "Empty Trash:empty_trash"
    "Homebrew Cache:clean_homebrew_cache"
    "Flush DNS Cache:flush_dns_cache"
  )
  
  # Extract just the names for selection
  local option_names=()
  for option in "${cleanup_options[@]}"; do
    # Get full text before the colon
    option_names+=("$(echo "$option" | cut -d':' -f1)")
  done
  
  # Allow user to select options
  print_info "Please select the cleanup operations you'd like to perform (space to select, enter to confirm):"
  
  # Calculate appropriate height for the selection list
  local height=$((${#option_names[@]} + 2))
  height=$((height > 20 ? 20 : height)) # Cap height at 20
  
  # Use printf to send the options to gum to prevent word splitting
  local selected_options=($(printf "%s\n" "${option_names[@]}" | gum choose --no-limit --height="$height"))
  
  # Check if any options were selected
  if [[ ${#selected_options[@]} -eq 0 ]]; then
    print_warning "No cleanup options selected. Exiting."
    cleanup_gum
    exit 0
  fi
  
  # Get list of selected operations
  print_info "You've selected the following cleanup operations:"
  for option in "${selected_options[@]}"; do
    # Find the matching option in the original array to preserve exact matching
    for cleanup_option in "${cleanup_options[@]}"; do
      if [[ "$cleanup_option" == "$option:"* || "$cleanup_option" == "${option}:"* ]]; then
        print_message "$CYAN" "  - $option"
        break
      fi
    done
  done
  
  if ! gum confirm "Do you want to proceed with these cleanup operations?"; then
    print_warning "Cleanup cancelled. Exiting."
    cleanup_gum
    exit 0
  fi
  
  # Perform selected cleanup operations
  for option in "${selected_options[@]}"; do
    for cleanup_option in "${cleanup_options[@]}"; do
      local name=$(echo "$cleanup_option" | cut -d':' -f1)
      local function=$(echo "$cleanup_option" | cut -d':' -f2)
      
      if [[ "$name" == "$option" ]]; then
        $function
        break
      fi
    done
  done
  
  print_header "Cleanup Summary"
  print_success "Cleanup completed successfully!"
  print_info "Backups saved to: $BACKUP_DIR"
  
  # Clean up gum if it was installed by this script
  cleanup_gum
}

# Run main function
main