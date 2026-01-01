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
DRY_RUN=false
LOG_FILE=""
TOTAL_SPACE_SAVED=0
declare -A SPACE_SAVED_BY_OPERATION

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

# Log message to file if logging is enabled
log_message() {
  local level="$1"
  local message="$2"
  if [[ -n "$LOG_FILE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
  fi
}

# Calculate size of a directory or file
calculate_size() {
  local path="$1"
  if [[ -e "$path" ]]; then
    # Use du to get size in human-readable format
    du -sh "$path" 2>/dev/null | awk '{print $1}'
  else
    echo "0B"
  fi
}

# Calculate size in bytes for accurate tracking
calculate_size_bytes() {
  local path="$1"
  if [[ -e "$path" ]]; then
    du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
  else
    echo "0"
  fi
}

# Format bytes to human-readable format
format_bytes() {
  local bytes=$1
  if [[ $bytes -ge 1073741824 ]]; then
    local gb=$((bytes / 1073741824))
    local mb=$(((bytes % 1073741824) / 1048576))
    if [[ $mb -gt 0 ]]; then
      printf "%d.%02d GB" $gb $((mb * 100 / 1024))
    else
      printf "%d GB" $gb
    fi
  elif [[ $bytes -ge 1048576 ]]; then
    local mb=$((bytes / 1048576))
    local kb=$(((bytes % 1048576) / 1024))
    if [[ $kb -gt 0 ]]; then
      printf "%d.%02d MB" $mb $((kb * 100 / 1024))
    else
      printf "%d MB" $mb
    fi
  elif [[ $bytes -ge 1024 ]]; then
    local kb=$((bytes / 1024))
    local b=$((bytes % 1024))
    if [[ $b -gt 0 ]]; then
      printf "%d.%02d KB" $kb $((b * 100 / 1024))
    else
      printf "%d KB" $kb
    fi
  else
    printf "%d B" $bytes
  fi
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

# Detect admin user
detect_admin_user() {
  # Try to get current user's groups
  local current_user=$(whoami)
  
  # Check if current user is in admin group
  if groups | grep -q admin; then
    ADMIN_USERNAME="$current_user"
    log_message "INFO" "Using current user ($current_user) as admin"
    return 0
  fi
  
  # Try to detect admin users from system
  local admin_users=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -d' ' -f2-)
  
  if [[ -n "$admin_users" ]]; then
    # Use first admin user found (prefer current user if in list)
    for user in $admin_users; do
      if [[ "$user" == "$current_user" ]]; then
        ADMIN_USERNAME="$user"
        log_message "INFO" "Detected admin user: $user"
        return 0
      fi
    done
    # If current user not in list, use first admin user
    ADMIN_USERNAME=$(echo $admin_users | awk '{print $1}')
    log_message "INFO" "Detected admin user: $ADMIN_USERNAME"
    return 0
  fi
  
  # Fallback: prompt user
  print_warning "Could not auto-detect admin user."
  print_info "Please enter your administrative account username:"
  read ADMIN_USERNAME
  
  if [[ -z "$ADMIN_USERNAME" ]]; then
    print_error "No admin username provided."
    return 1
  fi
  
  log_message "INFO" "Using manually entered admin user: $ADMIN_USERNAME"
  return 0
}

# Function to run commands as admin using sudo
run_as_admin() {
  local command="$1"
  local description="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would run as admin: $description"
    log_message "DRY_RUN" "Would execute: $command"
    return 0
  fi
  
  # Ensure we have admin user detected
  if [[ -z "$ADMIN_USERNAME" ]]; then
    detect_admin_user || return 1
  fi
  
  print_info "Running $description with administrative privileges..."
  log_message "INFO" "Executing admin command: $description"
  
  # Validate/cache sudo credentials
  if ! sudo -v; then
    print_error "Failed to validate sudo credentials."
    log_message "ERROR" "Sudo credential validation failed"
    return 1
  fi
  
  # Run the command with sudo
  if sudo sh -c "$command"; then
    log_message "SUCCESS" "Admin command completed: $description"
    return 0
  else
    print_error "Failed to execute command as administrator."
    log_message "ERROR" "Admin command failed: $description"
    return 1
  fi
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
        if [[ "$DRY_RUN" == "true" ]]; then
          print_info "[DRY RUN] Would install gum to /usr/local/bin/"
        else
          sudo mv "$TMP_DIR/gum" /usr/local/bin/ || {
            print_error "Failed to install gum. Please install manually: brew install gum"
            exit 1
          }
        fi
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
  
  if [[ "$DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would backup $path ($size) to $backup_name"
    log_message "DRY_RUN" "Would backup: $path -> $backup_name"
    return 0
  fi
  
  if [[ -e "$path" ]]; then
    # Check if directory is empty before backing up
    if [[ -d "$path" ]]; then
      local item_count=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
      if [[ $item_count -eq 0 ]]; then
        print_info "Skipping backup of empty directory: $path"
        log_message "INFO" "Skipped backup of empty directory: $path"
        return 0
      fi
    fi
    
    print_info "Backing up $path..."
    log_message "INFO" "Creating backup: $path -> $backup_name"
    
    if [[ -d "$path" ]]; then
      # Use a background process for large directories
      tar -czf "$BACKUP_DIR/${backup_name}.tar.gz" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null &
      local pid=$!
      show_spinner "Creating backup of $(basename "$path")" $pid
      
      # Verify backup was created successfully
      if [[ -f "$BACKUP_DIR/${backup_name}.tar.gz" ]]; then
        print_success "Backup complete: $backup_name"
        log_message "SUCCESS" "Backup created: $backup_name.tar.gz"
        return 0
      else
        print_warning "Backup verification failed, but continuing with cleanup..."
        log_message "WARNING" "Backup verification failed for: $backup_name"
        return 1
      fi
    else
      if cp "$path" "$BACKUP_DIR/${backup_name}" 2>/dev/null; then
        print_success "Backup complete: $backup_name"
        log_message "SUCCESS" "Backup created: $backup_name"
        return 0
      else
        print_warning "Backup failed, but continuing with cleanup..."
        log_message "WARNING" "Backup failed for: $backup_name"
        return 1
      fi
    fi
  fi
  
  return 0
}

# Safely remove a directory or file
safe_remove() {
  local path="$1"
  local description="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would remove $description ($size)"
    log_message "DRY_RUN" "Would remove: $path"
    return 0
  fi
  
  if [[ -e "$path" ]]; then
    local size_before=$(calculate_size_bytes "$path")
    print_info "Cleaning $description..."
    log_message "INFO" "Removing: $path"
    
    if [[ -d "$path" ]]; then
      rm -rf "$path" 2>/dev/null || true
    else
      rm -f "$path" 2>/dev/null || true
    fi
    
    if [[ ! -e "$path" ]]; then
      print_success "Cleaned $description"
      log_message "SUCCESS" "Removed: $path (freed $(format_bytes $size_before))"
      TOTAL_SPACE_SAVED=$((TOTAL_SPACE_SAVED + size_before))
    else
      print_warning "Failed to completely remove $description"
      log_message "WARNING" "Failed to remove: $path"
    fi
  fi
}

# Safely clean a directory (remove contents but keep the directory)
safe_clean_dir() {
  local path="$1"
  local description="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -d "$path" ]]; then
      local size=$(calculate_size "$path")
      print_info "[DRY RUN] Would clean $description ($size)"
      log_message "DRY_RUN" "Would clean directory: $path"
    fi
    return 0
  fi
  
  if [[ -d "$path" ]]; then
    local size_before=$(calculate_size_bytes "$path")
    print_info "Cleaning $description..."
    log_message "INFO" "Cleaning directory: $path"
    
    # Remove all contents including hidden files
    find "$path" -mindepth 1 -delete 2>/dev/null || {
      rm -rf "${path:?}"/* "${path:?}"/.[!.]* 2>/dev/null || true
    }
    
    print_success "Cleaned $description"
    local size_after=$(calculate_size_bytes "$path")
    local space_freed=$((size_before - size_after))
    log_message "SUCCESS" "Cleaned: $path (freed $(format_bytes $space_freed))"
    TOTAL_SPACE_SAVED=$((TOTAL_SPACE_SAVED + space_freed))
  fi
}

# Cleanup gum if it was installed by this script
cleanup_gum() {
  if [[ "$GUM_INSTALLED_BY_SCRIPT" == "true" ]]; then
    print_info "Cleaning up gum installation..."
    if [[ "$DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would remove gum"
    else
      if command -v brew &> /dev/null; then
        brew uninstall gum 2>/dev/null || true
      else
        sudo rm -f /usr/local/bin/gum 2>/dev/null || true
      fi
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
  local space_before=$(calculate_size_bytes "$cache_dir")
  
  backup "$cache_dir" "user_caches"
  find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") cache"
  done
  
  local space_after=$(calculate_size_bytes "$cache_dir")
  local space_freed=$((space_before - space_after))
  SPACE_SAVED_BY_OPERATION["User Cache"]=$space_freed
  
  print_success "User cache cleaned."
}

# Clean system cache
clean_system_cache() {
  print_header "Cleaning System Cache"
  
  print_warning "This operation requires administrative privileges"
  if [[ "$DRY_RUN" == "true" ]] || gum confirm "Do you want to continue?"; then
    local cache_dir="/Library/Caches"
    local space_before=0
    
    if [[ "$DRY_RUN" != "true" ]]; then
      # Get size before cleanup (requires sudo)
      space_before=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
    fi
    
    backup "$cache_dir" "system_caches"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean system cache"
      log_message "DRY_RUN" "Would clean system cache"
    else
      run_as_admin "find $cache_dir -maxdepth 1 -type d ! -path $cache_dir -exec rm -rf {} + 2>/dev/null || true" "system cache cleanup"
      
      local space_after=$(sudo sh -c "du -sk $cache_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      local space_freed=$((space_before - space_after))
      SPACE_SAVED_BY_OPERATION["System Cache"]=$space_freed
      
      print_success "System cache cleaned."
    fi
  else
    print_info "Skipping system cache cleanup"
  fi
}

# Clean application logs
clean_app_logs() {
  print_header "Cleaning Application Logs"
  
  local logs_dir="$HOME/Library/Logs"
  local space_before=$(calculate_size_bytes "$logs_dir")
  
  backup "$logs_dir" "application_logs"
  find "$logs_dir" -maxdepth 1 -type d ! -path "$logs_dir" | while read dir; do
    safe_clean_dir "$dir" "$(basename "$dir") logs"
  done
  
  local space_after=$(calculate_size_bytes "$logs_dir")
  local space_freed=$((space_before - space_after))
  SPACE_SAVED_BY_OPERATION["Application Logs"]=$space_freed
  
  print_success "Application logs cleaned."
}

# Clean system logs
clean_system_logs() {
  print_header "Cleaning System Logs"
  
  print_warning "⚠️ CAUTION: System logs can be important for troubleshooting system issues"
  print_warning "Only proceed if you understand the potential consequences"
  
  if [[ "$DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to clean system logs?"; then
    print_warning "This operation requires administrative privileges"
    
    if [[ "$DRY_RUN" == "true" ]] || gum confirm "Do you want to continue?"; then
      local logs_dir="/var/log"
      local space_before=0
      
      if [[ "$DRY_RUN" != "true" ]]; then
        space_before=$(sudo sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
      fi
      
      backup "$logs_dir" "system_logs"
      
      if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean system logs"
        log_message "DRY_RUN" "Would clean system logs"
      else
        # Clean log files without removing them (zero their size instead)
        run_as_admin "find $logs_dir -type f -name \"*.log\" -exec truncate -s 0 {} + 2>/dev/null || true" "system logs cleanup (current logs)"
        
        # Clean archived logs
        run_as_admin "find $logs_dir -type f -name \"*.log.*\" -delete 2>/dev/null || true" "system logs cleanup (archived logs)"
        
        local space_after=$(sudo sh -c "du -sk $logs_dir 2>/dev/null | awk '{print \$1 * 1024}'" || echo "0")
        local space_freed=$((space_before - space_after))
        SPACE_SAVED_BY_OPERATION["System Logs"]=$space_freed
        
        print_success "System logs cleaned."
      fi
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
  local total_space_freed=0
  
  for temp_dir in "${temp_dirs[@]}"; do
    if [[ -d "$temp_dir" ]]; then
      local space_before=$(calculate_size_bytes "$temp_dir")
      backup "$temp_dir" "temp_files_$(basename "$temp_dir")"
      
      # Skip certain system files in /tmp
      if [[ "$temp_dir" == "/tmp" ]]; then
        find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" -delete 2>/dev/null || {
          find "$temp_dir" -mindepth 1 ! -name ".X*" ! -name "com.apple.*" | while read item; do
            safe_remove "$item" "$(basename "$item")"
          done
        }
      else
        safe_clean_dir "$temp_dir" "$(basename "$temp_dir")"
      fi
      
      local space_after=$(calculate_size_bytes "$temp_dir")
      local space_freed=$((space_before - space_after))
      total_space_freed=$((total_space_freed + space_freed))
      
      print_success "Cleaned $temp_dir."
    fi
  done
  
  SPACE_SAVED_BY_OPERATION["Temporary Files"]=$total_space_freed
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
  
  local total_space_freed=0
  
  for dir in "${safari_cache_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local space_before=$(calculate_size_bytes "$dir")
      backup "$dir" "safari_$(basename "$dir")"
      safe_clean_dir "$dir" "Safari $(basename "$dir")"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $dir."
    fi
  done
  
  SPACE_SAVED_BY_OPERATION["Safari Cache"]=$total_space_freed
  
  print_warning "You may need to restart Safari for changes to take effect"
}

# Clean Chrome cache
clean_chrome_cache() {
  print_header "Cleaning Chrome Cache"
  
  local chrome_base="$HOME/Library/Application Support/Google/Chrome"
  local chrome_found=false
  
  # Clean main Chrome cache
  local chrome_cache_dir="$HOME/Library/Caches/Google/Chrome"
  local total_space_freed=0
  
  if [[ -d "$chrome_cache_dir" ]]; then
    chrome_found=true
    local space_before=$(calculate_size_bytes "$chrome_cache_dir")
    backup "$chrome_cache_dir" "chrome_cache"
    safe_clean_dir "$chrome_cache_dir" "Chrome cache"
    local space_after=$(calculate_size_bytes "$chrome_cache_dir")
    total_space_freed=$((total_space_freed + space_before - space_after))
    print_success "Cleaned Chrome cache."
  fi
  
  # Find and clean all Chrome profiles (not just Default)
  if [[ -d "$chrome_base" ]]; then
    chrome_found=true
    # Find all profile directories
    for profile_dir in "$chrome_base"/*/; do
      if [[ -d "$profile_dir" ]]; then
        local profile_name=$(basename "$profile_dir")
        local profile_dirs=(
          "$profile_dir/Cache"
          "$profile_dir/Code Cache"
          "$profile_dir/Service Worker"
        )
        
        for dir in "${profile_dirs[@]}"; do
          if [[ -d "$dir" ]]; then
            local space_before=$(calculate_size_bytes "$dir")
            backup "$dir" "chrome_${profile_name}_$(basename "$dir")"
            safe_clean_dir "$dir" "Chrome $profile_name $(basename "$dir")"
            local space_after=$(calculate_size_bytes "$dir")
            total_space_freed=$((total_space_freed + space_before - space_after))
            print_success "Cleaned Chrome $profile_name $(basename "$dir")."
          fi
        done
      fi
    done
  fi
  
  if [[ "$chrome_found" == false ]]; then
    print_warning "Chrome does not appear to be installed or has never been run."
  else
    SPACE_SAVED_BY_OPERATION["Chrome Cache"]=$total_space_freed
    print_warning "You may need to restart Chrome for changes to take effect"
  fi
}

# Clean Application Container Caches
clean_container_caches() {
  print_header "Cleaning Application Container Caches"
  
  local containers_dir="$HOME/Library/Containers"
  local total_space_freed=0
  
  if [[ -d "$containers_dir" ]]; then
    backup "$containers_dir" "app_containers"
    
    find "$containers_dir" -type d -name "Caches" | while read dir; do
      local app_name=$(echo "$dir" | awk -F'/' '{print $(NF-2)}')
      local space_before=$(calculate_size_bytes "$dir")
      safe_clean_dir "$dir" "$app_name container cache"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $app_name container cache."
    done
    
    SPACE_SAVED_BY_OPERATION["Application Container Caches"]=$total_space_freed
  else
    print_warning "No application containers found."
  fi
}

# Clean Saved Application States
clean_saved_states() {
  print_header "Cleaning Saved Application States"
  
  local saved_states_dir="$HOME/Library/Saved Application State"
  
  if [[ -d "$saved_states_dir" ]]; then
    local space_before=$(calculate_size_bytes "$saved_states_dir")
    backup "$saved_states_dir" "saved_app_states"
    safe_clean_dir "$saved_states_dir" "saved application states"
    local space_after=$(calculate_size_bytes "$saved_states_dir")
    SPACE_SAVED_BY_OPERATION["Saved Application States"]=$((space_before - space_after))
    print_success "Cleaned saved application states."
  else
    print_warning "No saved application states found."
  fi
}

# Clean Developer Tool Temporary Files
clean_dev_tool_temp() {
  print_header "Cleaning Developer Tool Temporary Files"
  
  local total_space_freed=0
  
  # IntelliJ IDEA
  local idea_dirs=(
    "$HOME/Library/Caches/JetBrains"
    "$HOME/Library/Application Support/JetBrains"
    "$HOME/Library/Logs/JetBrains"
  )
  
  for base_dir in "${idea_dirs[@]}"; do
    if [[ -d "$base_dir" ]]; then
      find "$base_dir" -type d -name "caches" -o -type d -maxdepth 1 | while read dir; do
        if [[ -d "$dir" ]]; then
          local space_before=$(calculate_size_bytes "$dir")
          backup "$dir" "intellij_$(basename "$dir")"
          safe_clean_dir "$dir" "IntelliJ $(basename "$dir")"
          local space_after=$(calculate_size_bytes "$dir")
          total_space_freed=$((total_space_freed + space_before - space_after))
          print_success "Cleaned $dir."
        fi
      done
    fi
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
      local space_before=$(calculate_size_bytes "$dir")
      backup "$dir" "vscode_$(basename "$dir")"
      safe_clean_dir "$dir" "VS Code $(basename "$dir")"
      local space_after=$(calculate_size_bytes "$dir")
      total_space_freed=$((total_space_freed + space_before - space_after))
      print_success "Cleaned $dir."
    fi
  done
  
  SPACE_SAVED_BY_OPERATION["Developer Tool Temp Files"]=$total_space_freed
}

# Clean Corrupted Preference Lockfiles
clean_pref_lockfiles() {
  print_header "Cleaning Corrupted Preference Lockfiles"
  
  local plist_locks=($(find "$HOME/Library/Preferences" -name "*.plist.lockfile" 2>/dev/null))
  local total_space_freed=0
  
  if [[ ${#plist_locks[@]} -eq 0 ]]; then
    print_warning "No preference lockfiles found."
    return
  fi
  
  print_info "Found ${#plist_locks[@]} preference lockfiles"
  
  for lock in "${plist_locks[@]}"; do
    local plist_file="${lock%.lockfile}"
    
    # Check if the plist file exists
    if [[ ! -f "$plist_file" ]]; then
      local space_before=$(calculate_size_bytes "$lock")
      backup "$lock" "$(basename "$lock")"
      safe_remove "$lock" "orphaned lockfile $(basename "$lock")"
      total_space_freed=$((total_space_freed + space_before))
    fi
  done
  
  SPACE_SAVED_BY_OPERATION["Corrupted Preference Lockfiles"]=$total_space_freed
  print_success "Cleaned corrupted preference lockfiles."
}

# Empty Trash
empty_trash() {
  print_header "Emptying Trash"
  
  local trash_dir="$HOME/.Trash"
  
  if [[ -d "$trash_dir" && "$(ls -A "$trash_dir" 2>/dev/null)" ]]; then
    local space_before=$(calculate_size_bytes "$trash_dir")
    print_warning "This will permanently delete all items in your Trash"
    if [[ "$DRY_RUN" == "true" ]] || gum confirm "Are you sure you want to empty the Trash?"; then
      if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would empty Trash ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would empty Trash"
      else
        rm -rf "$trash_dir"/* "$trash_dir"/.[!.]* 2>/dev/null || true
        print_success "Trash emptied."
        SPACE_SAVED_BY_OPERATION["Empty Trash"]=$space_before
        log_message "SUCCESS" "Emptied Trash (freed $(format_bytes $space_before))"
      fi
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
  
  if [[ "$DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would clean Homebrew cache"
    log_message "DRY_RUN" "Would clean Homebrew cache"
  else
    print_info "Cleaning Homebrew cache..."
    log_message "INFO" "Cleaning Homebrew cache"
    
    brew cleanup -s 2>&1 | log_message "INFO"
    
    print_success "Homebrew cache cleaned."
    log_message "SUCCESS" "Homebrew cache cleaned"
  fi
}

# Flush DNS Cache
flush_dns_cache() {
  print_header "Flushing DNS Cache"
  
  print_info "Flushing DNS Cache..."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would flush DNS cache"
    log_message "DRY_RUN" "Would flush DNS cache"
  else
    run_as_admin "dscacheutil -flushcache; killall -HUP mDNSResponder" "DNS cache flush"
    print_success "DNS Cache flushed"
  fi
}

# --------------------------------------------------------------------------
# MAIN SCRIPT
# --------------------------------------------------------------------------

# Parse command line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Preview operations without making changes"
        echo "  --help, -h   Show this help message"
        exit 0
        ;;
      *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done
}

main() {
  # Parse command line arguments
  parse_arguments "$@"
  
  print_header "macOS Cleanup Utility"
  print_info "This script will help you safely clean up your macOS system."
  
  if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "DRY RUN MODE: No changes will be made"
  fi
  
  # Check dependencies
  check_dependencies
  
  # Initialize admin username variable
  ADMIN_USERNAME=""
  
  # Check for gum and install if needed
  check_gum
  
  # Create backup directory
  create_backup_dir
  
  # Initialize log file
  LOG_FILE="$BACKUP_DIR/cleanup.log"
  log_message "INFO" "Starting macOS cleanup utility"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_message "INFO" "DRY RUN MODE enabled"
  fi
  
  # Add script cleanup to exit trap
  trap cleanup_script EXIT
  
  # Use associative array for cleaner option matching
  declare -A cleanup_functions
  cleanup_functions["User Cache"]="clean_user_cache"
  cleanup_functions["System Cache"]="clean_system_cache"
  cleanup_functions["Application Logs"]="clean_app_logs"
  cleanup_functions["System Logs"]="clean_system_logs"
  cleanup_functions["Temporary Files"]="clean_temp_files"
  cleanup_functions["Safari Cache"]="clean_safari_cache"
  cleanup_functions["Chrome Cache"]="clean_chrome_cache"
  cleanup_functions["Application Container Caches"]="clean_container_caches"
  cleanup_functions["Saved Application States"]="clean_saved_states"
  cleanup_functions["Developer Tool Temp Files"]="clean_dev_tool_temp"
  cleanup_functions["Corrupted Preference Lockfiles"]="clean_pref_lockfiles"
  cleanup_functions["Empty Trash"]="empty_trash"
  cleanup_functions["Homebrew Cache"]="clean_homebrew_cache"
  cleanup_functions["Flush DNS Cache"]="flush_dns_cache"
  
  # Build option list with sizes for display
  local option_names=()
  local option_list=()
  
  for option_name in "${(@k)cleanup_functions}"; do
    # Calculate size for each option
    local size=""
    case "$option_name" in
      "User Cache")
        size=$(calculate_size "$HOME/Library/Caches")
        ;;
      "System Cache")
        size=$(calculate_size "/Library/Caches")
        ;;
      "Application Logs")
        size=$(calculate_size "$HOME/Library/Logs")
        ;;
      "System Logs")
        size=$(calculate_size "/var/log")
        ;;
      "Temporary Files")
        local temp_size=0
        for temp_dir in "/tmp" "$TMPDIR" "$HOME/Library/Application Support/Temp"; do
          if [[ -d "$temp_dir" ]]; then
            temp_size=$((temp_size + $(calculate_size_bytes "$temp_dir")))
          fi
        done
        size=$(format_bytes $temp_size)
        ;;
      "Safari Cache")
        size=$(calculate_size "$HOME/Library/Caches/com.apple.Safari")
        ;;
      "Chrome Cache")
        local chrome_size=0
        if [[ -d "$HOME/Library/Caches/Google/Chrome" ]]; then
          chrome_size=$(calculate_size_bytes "$HOME/Library/Caches/Google/Chrome")
        fi
        if [[ -d "$HOME/Library/Application Support/Google/Chrome" ]]; then
          for profile_dir in "$HOME/Library/Application Support/Google/Chrome"/*/; do
            if [[ -d "$profile_dir" ]]; then
              local cache_size=$(calculate_size_bytes "$profile_dir/Cache" 2>/dev/null || echo "0")
              local code_cache_size=$(calculate_size_bytes "$profile_dir/Code Cache" 2>/dev/null || echo "0")
              local sw_size=$(calculate_size_bytes "$profile_dir/Service Worker" 2>/dev/null || echo "0")
              chrome_size=$((chrome_size + cache_size + code_cache_size + sw_size))
            fi
          done
        fi
        if [[ $chrome_size -gt 0 ]]; then
          size=$(format_bytes $chrome_size)
        else
          size="0B"
        fi
        ;;
      "Application Container Caches")
        size=$(calculate_size "$HOME/Library/Containers")
        ;;
      "Saved Application States")
        size=$(calculate_size "$HOME/Library/Saved Application State")
        ;;
      "Empty Trash")
        size=$(calculate_size "$HOME/.Trash")
        ;;
      *)
        size="N/A"
        ;;
    esac
    
    if [[ "$size" != "0B" && "$size" != "N/A" && -n "$size" ]]; then
      option_list+=("$option_name ($size)")
    else
      option_list+=("$option_name")
    fi
    option_names+=("$option_name")
  done
  
  # Allow user to select options
  print_info "Please select the cleanup operations you'd like to perform (space to select, enter to confirm):"
  
  # Calculate appropriate height for the selection list
  local height=$((${#option_list[@]} + 2))
  height=$((height > 20 ? 20 : height)) # Cap height at 20
  
  # Use printf to send the options to gum to prevent word splitting
  local selected_display=($(printf "%s\n" "${option_list[@]}" | gum choose --no-limit --height="$height"))
  
  # Check if any options were selected
  if [[ ${#selected_display[@]} -eq 0 ]]; then
    print_warning "No cleanup options selected. Exiting."
    cleanup_gum
    exit 0
  fi
  
  # Extract option names from display strings (remove size info)
  local selected_options=()
  for display in "${selected_display[@]}"; do
    # Remove size in parentheses if present
    local option_name=$(echo "$display" | sed 's/ (.*)$//')
    selected_options+=("$option_name")
  done
  
  # Get list of selected operations
  print_info "You've selected the following cleanup operations:"
  for option in "${selected_options[@]}"; do
    print_message "$CYAN" "  - $option"
    log_message "INFO" "Selected operation: $option"
  done
  
  if ! gum confirm "Do you want to proceed with these cleanup operations?"; then
    print_warning "Cleanup cancelled. Exiting."
    cleanup_gum
    exit 0
  fi
  
  # Perform selected cleanup operations
  for option in "${selected_options[@]}"; do
    local function="${cleanup_functions[$option]}"
    if [[ -n "$function" ]]; then
      $function
    else
      print_error "Unknown cleanup function for: $option"
      log_message "ERROR" "Unknown cleanup function for: $option"
    fi
  done
  
  print_header "Cleanup Summary"
  print_success "Cleanup completed successfully!"
  
  # Display space saved summary
  if [[ $TOTAL_SPACE_SAVED -gt 0 ]]; then
    echo ""
    print_info "Space freed: $(format_bytes $TOTAL_SPACE_SAVED)"
    log_message "INFO" "Total space freed: $(format_bytes $TOTAL_SPACE_SAVED)"
    
    # Show breakdown by operation
    if [[ ${#SPACE_SAVED_BY_OPERATION[@]} -gt 0 ]]; then
      echo ""
      print_info "Breakdown by operation:"
      for operation in "${(@k)SPACE_SAVED_BY_OPERATION}"; do
        local space=${SPACE_SAVED_BY_OPERATION[$operation]}
        if [[ $space -gt 0 ]]; then
          print_message "$CYAN" "  - $operation: $(format_bytes $space)"
        fi
      done
    fi
  else
    print_info "No space was freed (directories were empty or dry-run mode)"
  fi
  
  if [[ "$DRY_RUN" != "true" ]]; then
    print_info "Backups saved to: $BACKUP_DIR"
    print_info "Log file: $LOG_FILE"
  fi
  
  # Clean up gum if it was installed by this script
  cleanup_gum
  
  log_message "INFO" "Cleanup completed"
}

# Run main function
main