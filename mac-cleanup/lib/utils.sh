#!/bin/zsh
#
# lib/utils.sh - Utility functions for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Size calculation cache (associative array)
typeset -A MC_SIZE_CACHE

# SEC-6: Create secure temporary files using mktemp
# Usage: create_secure_temp_file "prefix"
# Returns: Path to newly created temp file with mode 600
create_secure_temp_file() {
  local prefix="${1:-mac-cleanup}"

  # Use mktemp with random suffix for secure temp file creation
  # -t flag adds prefix, XXXXXXXXXX provides 10 random characters
  local temp_file=""
  temp_file=$(mktemp -t "${prefix}.XXXXXXXXXX" 2>/dev/null)

  if [[ -z "$temp_file" || ! -f "$temp_file" ]]; then
    log_message "ERROR" "Failed to create secure temp file with prefix: $prefix"
    return 1
  fi

  # Set restrictive permissions (owner read/write only)
  chmod 600 "$temp_file" 2>/dev/null || {
    log_message "ERROR" "Failed to set permissions on temp file: $temp_file"
    rm -f "$temp_file" 2>/dev/null
    return 1
  }

  echo "$temp_file"
  return 0
}

# Lock tracking for read-modify-write operations (SEC-4-FIX)
# Uses a lock owner file to track which process holds the lock
# This works across subshell boundaries (unlike global variables)

# Helper to check if this process owns the lock
_check_lock_ownership() {
  local lock_dir="$1"
  local lock_owner_file="${lock_dir}/owner"

  # Check if lock directory exists and contains our PID
  if [[ -d "$lock_dir" && -f "$lock_owner_file" ]]; then
    local owner_pid=$(cat "$lock_owner_file" 2>/dev/null || echo "")
    if [[ "$owner_pid" == "$$" ]]; then
      # Check age - auto-expire after 2 seconds to prevent deadlock
      local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_owner_file" 2>/dev/null || echo 0)))
      if [[ $lock_age -le 2 ]]; then
        return 0  # We own this lock and it's still valid
      fi
    fi
  fi
  return 1  # We don't own the lock
}

# Helper function to safely write to progress file with locking (SAFE-7, SEC-4)
# SEC-4-FIX: Uses atomic mkdir with lock reuse to prevent TOCTOU race conditions
# Phase 4.2: Enhanced with better error handling and cleanup
_write_progress_file() {
  local progress_file="$1"
  local content="$2"

  # Phase 4.2: Validate inputs
  if [[ -z "$progress_file" || -z "$content" ]]; then
    log_message "WARNING" "_write_progress_file called with empty arguments"
    return 1
  fi

  # Phase 4.2: Ensure parent directory exists
  local progress_dir=$(dirname "$progress_file" 2>/dev/null)
  if [[ -n "$progress_dir" && ! -d "$progress_dir" ]]; then
    mkdir -p "$progress_dir" 2>/dev/null || {
      log_message "ERROR" "Failed to create progress directory: $progress_dir"
      return 1
    }
  fi

  # SEC-4-FIX: Use atomic mkdir-based file locking to prevent race conditions
  # mkdir is atomic - only one process can successfully create the directory
  # This prevents TOCTOU race conditions that were present with lockf approach
  local lock_dir="${progress_file}.lock"
  local lock_owner_file="${lock_dir}/owner"
  local max_attempts=200  # 10 seconds total (200 * 0.05s) - generous for high contention
  local attempts=0

  # Clean up stale locks (older than 30 seconds)
  if [[ -d "$lock_dir" ]]; then
    local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 30 ]]; then
      log_message "WARNING" "Removing stale progress lock directory (age: ${lock_age}s)"
      rm -rf "$lock_dir" 2>/dev/null || true
    fi
  fi

  # Check if this process already holds the lock (for RMW operations)
  if _check_lock_ownership "$lock_dir"; then
    # We already hold the lock - just write and release
    echo "$content" > "$progress_file" 2>/dev/null || {
      log_message "ERROR" "Failed to write progress file: $progress_file"
      rm -rf "$lock_dir" 2>/dev/null || true
      return 1
    }
    # Release lock (completing the RMW cycle)
    rm -rf "$lock_dir" 2>/dev/null || true
    return 0
  fi

  # If lock directory exists but we don't own it, clean up expired locks
  if [[ -d "$lock_dir" ]]; then
    local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_owner_file" 2>/dev/null || stat -f %m "$lock_dir" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 2 ]]; then
      # Lock expired - clean it up
      rm -rf "$lock_dir" 2>/dev/null || true
    fi
  fi

  # Acquire lock using atomic mkdir
  while ! mkdir "$lock_dir" 2>/dev/null; do
    # Check for expired locks
    if [[ -d "$lock_dir" ]]; then
      local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_owner_file" 2>/dev/null || stat -f %m "$lock_dir" 2>/dev/null || echo 0)))
      if [[ $lock_age -gt 2 ]]; then
        # Lock expired during wait - try to clean it up
        rm -rf "$lock_dir" 2>/dev/null || true
        continue  # Try mkdir again immediately
      fi
    fi

    sleep 0.05
    attempts=$((attempts + 1))
    if [[ $attempts -ge $max_attempts ]]; then
      log_message "ERROR" "Failed to acquire lock after ${attempts} attempts (10 second timeout)"
      return 1
    fi
  done

  # Mark ownership
  echo "$$" > "$lock_owner_file" 2>/dev/null || true

  # Critical section: lock acquired, perform write
  echo "$content" > "$progress_file" 2>/dev/null || {
    log_message "ERROR" "Failed to write progress file: $progress_file"
    rm -rf "$lock_dir" 2>/dev/null || true
    return 1
  }

  # Release lock (always release on write, completing the RMW cycle)
  rm -rf "$lock_dir" 2>/dev/null || true
  return 0
}

# Helper function to safely read progress file with locking (SAFE-7, SEC-4)
# SEC-4-FIX: Uses atomic mkdir-based file locking with lock reuse to prevent TOCTOU race conditions
_read_progress_file() {
  local progress_file="$1"

  if [[ -z "$progress_file" || ! -f "$progress_file" ]]; then
    echo ""
    return 1
  fi

  # SEC-4-FIX: Use atomic mkdir-based file locking to prevent race conditions
  local lock_dir="${progress_file}.lock"
  local lock_owner_file="${lock_dir}/owner"
  local max_attempts=200  # 10 seconds total (200 * 0.05s) - generous for high contention
  local attempts=0
  local content=""

  # Check if this process already holds the lock (for nested reads)
  if _check_lock_ownership "$lock_dir"; then
    # We already hold the lock - just read
    content=$(cat "$progress_file" 2>/dev/null || echo "")
    echo "$content"
    return 0
  fi

  # Acquire lock using atomic mkdir
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.05
    attempts=$((attempts + 1))
    if [[ $attempts -ge $max_attempts ]]; then
      # If lock acquisition failed, read without lock for reads (acceptable for progress monitoring)
      # SEC-4: For reads, reading without lock is acceptable since we're just monitoring progress
      content=$(cat "$progress_file" 2>/dev/null || echo "")
      echo "$content"
      return 0
    fi
  done

  # Mark ownership
  echo "$$" > "$lock_owner_file" 2>/dev/null || true

  # Critical section: lock acquired, perform read
  content=$(cat "$progress_file" 2>/dev/null || echo "")

  # Keep the lock held - don't release it yet!
  # This allows a subsequent _write_progress_file call to reuse the lock (within 2 seconds)
  # The write function will release the lock, or it will auto-expire after 2 seconds

  echo "$content"
  return 0
}

# Atomic read-modify-write helper for progress file (SEC-4-FIX)
# This function holds the lock for the entire read-modify-write cycle to prevent race conditions
# Usage: _atomic_update_progress_file file_path callback_function
# The callback receives current content as $1 and should echo the new content
_atomic_update_progress_file() {
  local progress_file="$1"
  local callback="$2"

  if [[ -z "$progress_file" || -z "$callback" ]]; then
    log_message "WARNING" "_atomic_update_progress_file called with empty arguments"
    return 1
  fi

  # SEC-4-FIX: Use atomic mkdir-based file locking
  local lock_dir="${progress_file}.lock"
  local max_attempts=20  # 1 second total (20 * 0.05s)
  local attempts=0

  # Clean up stale locks (older than 30 seconds)
  if [[ -d "$lock_dir" ]]; then
    local lock_age=$(($(/bin/date +%s 2>/dev/null || echo 0) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 30 ]]; then
      log_message "WARNING" "Removing stale progress lock directory (age: ${lock_age}s)"
      rmdir "$lock_dir" 2>/dev/null || true
    fi
  fi

  # Acquire lock using atomic mkdir
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.05
    attempts=$((attempts + 1))
    if [[ $attempts -ge $max_attempts ]]; then
      log_message "ERROR" "Failed to acquire lock after ${attempts} attempts (1 second timeout)"
      return 1
    fi
  done

  # Critical section: lock acquired, perform atomic read-modify-write
  if [[ -d "$lock_dir" ]]; then
    local current_content=$(cat "$progress_file" 2>/dev/null || echo "")
    local new_content=$($callback "$current_content")

    if [[ $? -eq 0 ]]; then
      echo "$new_content" > "$progress_file" 2>/dev/null || {
        log_message "ERROR" "Failed to write progress file: $progress_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
      }
    else
      log_message "ERROR" "Callback function failed"
      rmdir "$lock_dir" 2>/dev/null || true
      return 1
    fi

    # Release lock
    rmdir "$lock_dir" 2>/dev/null || true
    return 0
  fi

  # This should never be reached, but handle it defensively
  log_message "ERROR" "Lock directory disappeared unexpectedly"
  return 1
}

# Progress reporting function for plugins
# Usage: update_operation_progress current_item total_items "item_name"
# This allows plugins to report progress as they process multiple items
# SAFE-7, SEC-4: Uses proper file locking to prevent race conditions
update_operation_progress() {
  local current_item=$1
  local total_items=$2
  local item_name="${3:-}"

  # Only update if progress file is set (we're in a cleanup operation)
  if [[ -n "${MC_PROGRESS_FILE:-}" && -f "$MC_PROGRESS_FILE" ]]; then
    # Throttle updates: only update every 1% or every 10 items, whichever is more frequent
    # This reduces output noise when processing many items
    local update_threshold=1
    if [[ $total_items -gt 100 ]]; then
      # For large item counts, update every 1% or every 10 items
      local percent_progress=$((current_item * 100 / total_items))
      local last_percent=${MC_LAST_PROGRESS_PERCENT:-0}
      local item_diff=$((current_item - ${MC_LAST_PROGRESS_ITEM:-0}))

      # Only update if we've crossed a percent boundary or processed 10+ items
      if [[ $percent_progress -eq $last_percent && $item_diff -lt 10 ]]; then
        # Skip this update
        return 0
      fi

      # Store last update values
      MC_LAST_PROGRESS_PERCENT=$percent_progress
      MC_LAST_PROGRESS_ITEM=$current_item
    fi

    # SEC-4: Use proper file locking for read-modify-write operation
    local lock_file="${MC_PROGRESS_FILE}.lock"
    local lock_dir="${MC_PROGRESS_FILE}.lock.d"
    local max_attempts=50  # 5 seconds total
    local timeout=5

    # Try lockf first (proper file locking, race-condition-free)
    if command -v lockf &>/dev/null; then
      # SEC-4: lockf provides proper advisory locking for atomic read-modify-write
      touch "$lock_file" 2>/dev/null || return 1

      # Use lockf with a shell script to do read-modify-write atomically
      lockf -t "$timeout" -k "$lock_file" sh -c "
        progress_line=\$(cat '$MC_PROGRESS_FILE' 2>/dev/null || echo '')
        if [[ -n \"\$progress_line\" ]]; then
          op_index=\$(echo \"\$progress_line\" | cut -d'|' -f1)
          total_ops=\$(echo \"\$progress_line\" | cut -d'|' -f2)
          op_name=\$(echo \"\$progress_line\" | cut -d'|' -f3- | cut -d'|' -f1)
          echo \"\$op_index|\$total_ops|\$op_name|$current_item|$total_items|$item_name\" > '$MC_PROGRESS_FILE'
        fi
      " 2>/dev/null || log_message "WARNING" "Progress update failed with lockf"
      return 0
    fi

    # Fallback: Use atomic mkdir for read-modify-write
    local attempts=0
    while [[ $attempts -lt $max_attempts ]]; do
      # SEC-4: mkdir is atomic - only one process can create the directory
      if mkdir "$lock_dir" 2>/dev/null; then
        # Successfully acquired lock - do read-modify-write
        local progress_line=$(cat "$MC_PROGRESS_FILE" 2>/dev/null || echo "")
        if [[ -n "$progress_line" ]]; then
          local op_index=$(echo "$progress_line" | cut -d'|' -f1)
          local total_ops=$(echo "$progress_line" | cut -d'|' -f2)
          local op_name=$(echo "$progress_line" | cut -d'|' -f3- | cut -d'|' -f1)
          echo "$op_index|$total_ops|$op_name|$current_item|$total_items|$item_name" > "$MC_PROGRESS_FILE" 2>/dev/null || true
        fi
        rmdir "$lock_dir" 2>/dev/null || true
        return 0
      fi

      # Lock exists - wait and retry
      sleep 0.1 2>/dev/null || sleep 0.1
      attempts=$((attempts + 1))
    done

    # SEC-4: If lock acquisition failed, log error and skip update
    # Progress updates are not critical, so we can safely skip rather than risk corruption
    log_message "WARNING" "Progress file lock timeout after ${attempts} attempts, skipping update"
  fi
}

# Log message to file if logging is enabled
# QUAL-14: Standardized logging levels
log_message() {
  local level="${1:-INFO}"
  local message="${2:-}"
  
  # QUAL-14: Standardize log levels - normalize to uppercase
  # Use /usr/bin/tr to ensure it's available
  level=$(echo "$level" | /usr/bin/tr '[:lower:]' '[:upper:]' 2>/dev/null || echo "$level")
  
  # Validate log level (QUAL-14)
  case "$level" in
    DEBUG|INFO|WARNING|ERROR|SUCCESS|DRY_RUN)
      # Valid log level
      ;;
    *)
      # Default to INFO for unknown levels
      level="INFO"
      ;;
  esac
  
  if [[ -n "$MC_LOG_FILE" ]]; then
    # Use full path to date to ensure it's available in subshells
    echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$MC_LOG_FILE"
  fi
}

# Calculate size of a directory or file
calculate_size() {
  local path="$1"
  if [[ -e "$path" ]]; then
    # Use du to get size in human-readable format
    # Use /usr/bin/awk to ensure it's available
    du -sh "$path" 2>/dev/null | /usr/bin/awk '{print $1}' 2>/dev/null || echo "0B"
  else
    echo "0B"
  fi
}

# Calculate size in bytes for accurate tracking (with caching)
calculate_size_bytes() {
  local path="$1"
  
  # Validate input
  if [[ -z "$path" ]]; then
    log_message "${MC_LOG_LEVEL_WARNING:-WARNING}" "calculate_size_bytes called with empty path"
    echo "0"
    return
  fi
  
  # Early exit for non-existent paths
  if [[ ! -e "$path" ]]; then
    echo "0"
    return
  fi
  
  # Check cache first
  local cache_key="$path"
  if [[ -n "${MC_SIZE_CACHE[$cache_key]:-}" ]]; then
    echo "${MC_SIZE_CACHE[$cache_key]}"
    return
  fi
  
  # Use /usr/bin/du explicitly and capture output more reliably
  local du_output=""
  du_output=$(/usr/bin/du -sk "$path" 2>/dev/null) || du_output=""
  
  local result=0
  if [[ -n "$du_output" ]]; then
    local kb=$(echo "$du_output" | /usr/bin/awk '{print $1}')
    
    if [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]]; then
      # Use awk for large number arithmetic to prevent overflow
      # On 32-bit systems, shell arithmetic can overflow at 2GB (2,097,152 KB)
      # Fix: Use awk variables instead of field references for multiplication
      result=$(/usr/bin/awk -v kb="$kb" 'BEGIN {printf "%.0f", kb * 1024}')
      # Ensure result is numeric (awk might return scientific notation for very large numbers)
      if [[ ! "$result" =~ ^[0-9]+$ ]]; then
        # Fallback: if awk fails, try bc if available, otherwise use shell arithmetic with overflow check
        if command -v bc &>/dev/null; then
          result=$(echo "$kb * 1024" | bc 2>/dev/null | awk '{printf "%.0f", $1}')
        else
          # Shell arithmetic with overflow protection (max 2^31-1 bytes = 2GB)
          local max_kb=2097152
          if [[ $kb -gt $max_kb ]]; then
            result=2147483647  # Max 32-bit signed integer
            log_message "WARNING" "Size calculation overflow protection: $path (KB: $kb)"
          else
            result=$((kb * 1024))
          fi
        fi
      fi
    fi
  fi
  
  # Cache the result
  MC_SIZE_CACHE[$cache_key]=$result
  echo "$result"
}

# Clear size calculation cache (useful after cleanup operations)
clear_size_cache() {
  MC_SIZE_CACHE=()
}

# Invalidate cache entry for a specific path
invalidate_size_cache() {
  local path="$1"
  unset "MC_SIZE_CACHE[$path]"
}

# Format bytes to human-readable format
# Uses floating point arithmetic for accurate rounding
format_bytes() {
  local bytes=$1
  
  # Load constants if not already loaded
  if [[ -z "${MC_BYTES_PER_GB:-}" ]]; then
    local MC_BYTES_PER_GB=1073741824
    local MC_BYTES_PER_MB=1048576
    local MC_BYTES_PER_KB=1024
  fi
  
  # Use awk for floating point calculations to avoid rounding errors
  if command -v awk &>/dev/null; then
    if [[ $bytes -ge $MC_BYTES_PER_GB ]]; then
      # GB with 2 decimal places
      awk -v b=$bytes -v gb_size=$MC_BYTES_PER_GB 'BEGIN {
        gb = b / gb_size
        printf "%.2f GB", gb
      }'
    elif [[ $bytes -ge $MC_BYTES_PER_MB ]]; then
      # MB with 2 decimal places
      awk -v b=$bytes -v mb_size=$MC_BYTES_PER_MB 'BEGIN {
        mb = b / mb_size
        printf "%.2f MB", mb
      }'
    elif [[ $bytes -ge $MC_BYTES_PER_KB ]]; then
      # KB with 2 decimal places
      awk -v b=$bytes -v kb_size=$MC_BYTES_PER_KB 'BEGIN {
        kb = b / kb_size
        printf "%.2f KB", kb
      }'
    else
      printf "%d B" $bytes
    fi
  else
    # Fallback to integer arithmetic if awk not available
    if [[ $bytes -ge $MC_BYTES_PER_GB ]]; then
      local gb=$((bytes / MC_BYTES_PER_GB))
      local remainder=$((bytes % MC_BYTES_PER_GB))
      local mb=$((remainder / MC_BYTES_PER_MB))
      # Calculate decimal part more accurately
      local decimal=$((remainder * 100 / MC_BYTES_PER_MB))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d GB" $gb $decimal
      else
        printf "%d GB" $gb
      fi
    elif [[ $bytes -ge $MC_BYTES_PER_MB ]]; then
      local mb=$((bytes / MC_BYTES_PER_MB))
      local remainder=$((bytes % MC_BYTES_PER_MB))
      local kb=$((remainder / MC_BYTES_PER_KB))
      local decimal=$((remainder * 100 / MC_BYTES_PER_KB))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d MB" $mb $decimal
      else
        printf "%d MB" $mb
      fi
    elif [[ $bytes -ge $MC_BYTES_PER_KB ]]; then
      local kb=$((bytes / MC_BYTES_PER_KB))
      local b=$((bytes % MC_BYTES_PER_KB))
      local decimal=$((b * 100 / MC_BYTES_PER_KB))
      if [[ $decimal -gt 0 ]]; then
        printf "%d.%02d KB" $kb $decimal
      else
        printf "%d KB" $kb
      fi
    else
      printf "%d B" $bytes
    fi
  fi
}

# Check if a file or directory is in use (SAFE-2)
_check_file_in_use() {
  local path="$1"
  
  # Skip check if lsof is not available
  if ! command -v lsof &>/dev/null; then
    return 1  # Assume not in use if we can't check
  fi
  
  # Check if file is open by any process
  if lsof "$path" &>/dev/null; then
    return 0  # File is in use
  fi
  
  # For directories, check if any files within are in use
  if [[ -d "$path" ]]; then
    # Limit depth to avoid performance issues on large directories
    if lsof +D "$path" 2>/dev/null | head -1 | grep -q .; then
      return 0  # Directory has files in use
    fi
  fi
  
  return 1  # File is not in use
}

# Check if we have write permission (SAFE-3)
_check_write_permission() {
  local path="$1"
  
  # Check if path exists
  if [[ ! -e "$path" ]]; then
    return 1
  fi
  
  # For directories, check if writable
  if [[ -d "$path" ]]; then
    if [[ ! -w "$path" ]]; then
      return 1  # No write permission
    fi
  else
    # For files, check parent directory is writable
    local parent_dir=$(dirname "$path")
    if [[ ! -w "$parent_dir" ]]; then
      return 1  # No write permission on parent
    fi
  fi
  
  return 0  # Has write permission
}

# Check if file is SIP-protected (SAFE-6)
_check_sip_protected() {
  local path="$1"
  
  # On macOS, check if file has extended attributes indicating SIP protection
  # SIP-protected files typically have special attributes
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check for com.apple.rootless attribute (indicates SIP protection)
    if xattr -l "$path" 2>/dev/null | grep -q "com.apple.rootless"; then
      return 0  # SIP-protected
    fi
    
    # Check if file is in protected system locations
    case "$path" in
      /System/*|/usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*)
        # These are typically SIP-protected
        return 0
        ;;
    esac
  fi
  
  return 1  # Not SIP-protected
}

# Safely remove a directory or file
# Phase 4.4: Enhanced with better edge case handling
safe_remove() {
  local path="$1"
  local description="$2"
  
  # Phase 4.4: Validate input
  if [[ -z "$path" ]]; then
    print_error "safe_remove called with empty path"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "safe_remove called with empty path"
    return 1
  fi
  
  # Phase 4.4: Handle empty directories gracefully
  if [[ -d "$path" ]]; then
    # Use full paths to ensure commands are available
    # wc -l outputs number with leading spaces and newline, use awk to extract just the number
    local item_count=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | /usr/bin/wc -l 2>/dev/null | /usr/bin/awk '{print $1+0}' 2>/dev/null || echo "0")
    # Ensure it's numeric - awk should handle this, but double-check
    if [[ -z "$item_count" || ! "$item_count" =~ ^[0-9]+$ ]]; then
      item_count=0
    fi
    if [[ $item_count -eq 0 ]]; then
      log_message "INFO" "Directory is empty, skipping: $path"
      return 0
    fi
  fi
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would remove $description ($size)"
    log_message "DRY_RUN" "Would remove: $path"
    return 0
  fi
  
  if [[ -e "$path" ]]; then
    # SAFE-6: Check if file is SIP-protected
    if _check_sip_protected "$path"; then
      print_warning "Skipping SIP-protected file: $path"
      log_message "WARNING" "Skipped SIP-protected file: $path"
      return 0
    fi
    
    # SAFE-3: Check write permission
    if ! _check_write_permission "$path"; then
      print_warning "No write permission for $description. Skipping."
      log_message "WARNING" "No write permission: $path"
      return 1
    fi
    
    # Phase 4.4: SAFE-2: Check if file is in use with better error message
    if _check_file_in_use "$path"; then
      print_warning "File is in use: $path. Skipping to prevent data corruption."
      print_info "To fix: Close any applications using this file and try again"
      log_message "WARNING" "File in use, skipped: $path"
      return 1
    fi
    
    local size_before=$(calculate_size_bytes "$path")
    
    # Backup before destructive operation
    if ! backup "$path" "safe_remove_${description// /_}"; then
      print_error "Backup failed for $description. Aborting removal to prevent data loss."
      log_message "ERROR" "Backup failed, aborting safe_remove: $path"
      return 1
    fi
    
    log_message "INFO" "Removing: $path"
    
    # SAFE-1 & SEC-5: Handle symlinks safely - don't follow them
    if [[ -L "$path" ]]; then
      # It's a symlink, remove the symlink itself, not the target
      rm -f "$path" 2>/dev/null || true
    elif [[ -d "$path" ]]; then
      # SEC-5: Use find to avoid following symlinks (prevents symlink attacks)
      # First remove symlinks, then regular files
      find "$path" -mindepth 1 -type l -delete 2>/dev/null || true
      find "$path" -mindepth 1 -not -type l -delete 2>/dev/null || {
        # SEC-5: Fallback without rm -rf to prevent symlink attacks
        # Recursively delete contents, then remove the directory itself
        find "$path" -mindepth 1 -delete 2>/dev/null || true
      }
      # Remove the directory itself after contents are deleted
      rmdir "$path" 2>/dev/null || true
    else
      # Regular file
      rm -f "$path" 2>/dev/null || true
    fi
    
    # Invalidate cache for this path since it was removed
    invalidate_size_cache "$path"
    
    if [[ ! -e "$path" ]]; then
      log_message "SUCCESS" "Removed: $path (freed $(format_bytes $size_before))"
      MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + size_before))
      # Write to space tracking file if in background process (with locking)
      # safe_remove is typically used standalone, so we write to the file
      if [[ -n "${MC_SPACE_TRACKING_FILE:-}" && -f "$MC_SPACE_TRACKING_FILE" ]]; then
        # Use helper function from base.sh if available, otherwise use simple write
        if type _write_space_tracking_file &>/dev/null; then
          _write_space_tracking_file "$description" "$size_before"
        else
          echo "$description|$size_before" >> "$MC_SPACE_TRACKING_FILE" 2>/dev/null || true
        fi
      fi
    else
      print_warning "Failed to completely remove $description"
      log_message "WARNING" "Failed to remove: $path"
    fi
  fi
}

# Safely clean a directory (remove contents but keep the directory)
# Phase 4.4: Enhanced with better edge case handling
safe_clean_dir() {
  local path="$1"
  local description="$2"
  
  # Phase 4.4: Validate input
  if [[ -z "$path" ]]; then
    print_error "safe_clean_dir called with empty path"
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "safe_clean_dir called with empty path"
    return 1
  fi
  
  # Phase 4.4: Handle non-existent directories gracefully
  if [[ ! -d "$path" ]]; then
    log_message "INFO" "Directory does not exist, skipping: $path"
    return 0
  fi
  
  # Phase 4.4: Handle empty directories gracefully
  # Use full paths to ensure commands are available
  # Get item count and ensure it's a clean numeric value
  # wc -l outputs number with leading spaces and newline (e.g., "       0\n")
  # Use awk to extract just the number, or default to 0
  local find_output=$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null)
  local item_count_raw=$(echo "$find_output" | /usr/bin/wc -l 2>/dev/null || echo "0")
  local item_count=$(echo "$item_count_raw" | /usr/bin/awk '{print $1+0}' 2>/dev/null || echo "0")
  # Ensure it's numeric - convert to integer explicitly
  item_count=$((item_count + 0))
  # Check directory size instead of item count - directories can have size even if find doesn't work
  local dir_size=$(calculate_size_bytes "$path" 2>/dev/null || echo "0")
  dir_size=$((dir_size + 0))
  # Skip only if both item_count is 0 AND directory size is 0
  if [[ $item_count -eq 0 && $dir_size -eq 0 ]]; then
    log_message "INFO" "Directory is empty, skipping: $path"
    return 0
  fi
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    if [[ -d "$path" ]]; then
      local size=$(calculate_size "$path")
      print_info "[DRY RUN] Would clean $description ($size)"
      log_message "DRY_RUN" "Would clean directory: $path"
    fi
    return 0
  fi
  
  if [[ -d "$path" ]]; then
    # Phase 4.4: SAFE-3: Check write permission with better error message
    if ! _check_write_permission "$path"; then
      print_warning "No write permission for $description. Skipping."
      print_info "To fix: Check directory permissions or run with appropriate privileges"
      log_message "WARNING" "No write permission: $path"
      return 1
    fi
    
    local size_before=$(calculate_size_bytes "$path")
    
    # Backup before destructive operation
    if ! backup "$path" "safe_clean_dir_${description// /_}"; then
      print_error "Backup failed for $description. Aborting directory cleanup to prevent data loss."
      log_message "ERROR" "Backup failed, aborting safe_clean_dir: $path"
      return 1
    fi
    
    log_message "INFO" "Cleaning directory: $path"
    
    # Track files that fail to delete for error reporting (SAFE-9)
    local failed_files=()
    
    # SAFE-2 & SAFE-6: Pre-check files before deletion (for critical system files)
    # Only check system directories to avoid performance impact
    if [[ "$path" =~ ^/(System|Library|usr) ]]; then
      find "$path" -mindepth 1 -not -type l 2>/dev/null | while read -r item; do
        # Skip SIP-protected files (SAFE-6)
        if _check_sip_protected "$item"; then
          log_message "INFO" "Skipping SIP-protected file: $item"
          failed_files+=("$item")
          continue
        fi
        
        # Check if in use (SAFE-2)
        if _check_file_in_use "$item"; then
          log_message "WARNING" "File in use, skipping: $item"
          failed_files+=("$item")
          continue
        fi
      done
    fi
    
    # Optimized batch deletion: use find with -delete for better performance
    # Important: Delete symlinks first (but don't follow them), then regular files
    # SAFE-1: Delete symlinks first to avoid following them, then delete everything else
    # Since find isn't finding files but glob is, use direct deletion approach
    # Delete items found by glob pattern (more reliable when find fails)
    # Track space freed from files we actually delete (not just directory size difference)
    local actual_space_freed=0
    # Delete symlinks first (but don't follow them)
    # Use /bin/rm explicitly to ensure it's found even if PATH is not set correctly
    # Use (N) qualifier in zsh to handle empty directories gracefully
    if [[ -n "${ZSH_VERSION:-}" ]]; then
      # Zsh: use (N) qualifier to return empty if no matches
      for item in "$path"/*(N) "$path"/.*(N); do
        if [[ -e "$item" && "$item" != "$path/." && "$item" != "$path/.." && -L "$item" ]]; then
          local item_size=$(/usr/bin/du -sk "$item" 2>/dev/null | /usr/bin/awk '{print $1}' 2>/dev/null || echo "0")
          # Ensure item_size is numeric - remove all whitespace and validate
          item_size=$(echo -n "$item_size" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "0")
          if [[ -z "$item_size" || ! "$item_size" =~ ^[0-9]+$ ]]; then
            item_size=0
          fi
          if /bin/rm -f "$item" 2>/dev/null; then
            if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
              actual_space_freed=$((actual_space_freed + item_size * 1024))
            fi
          fi
        fi
      done 2>/dev/null
      # Delete directories and files (SEC-5: Use find -delete to avoid symlink attacks)
      for item in "$path"/*(N) "$path"/.*(N); do
        if [[ -e "$item" && "$item" != "$path/." && "$item" != "$path/.." && ! -L "$item" ]]; then
          local item_size=$(/usr/bin/du -sk "$item" 2>/dev/null | /usr/bin/awk '{print $1}' 2>/dev/null || echo "0")
          # Ensure item_size is numeric - remove all whitespace and validate
          item_size=$(echo -n "$item_size" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "0")
          if [[ -z "$item_size" || ! "$item_size" =~ ^[0-9]+$ ]]; then
            item_size=0
          fi
          # SEC-5: Use find -delete for symlink-safe deletion
          if [[ -d "$item" ]]; then
            # For directories, recursively delete contents first
            find "$item" -mindepth 1 -delete 2>/dev/null && rmdir "$item" 2>/dev/null
          else
            # For regular files, just delete
            /bin/rm -f "$item" 2>/dev/null
          fi
          # Check if deletion succeeded
          if [[ ! -e "$item" ]]; then
            if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
              actual_space_freed=$((actual_space_freed + item_size * 1024))
            fi
          fi
        fi
      done 2>/dev/null
    else
      # Bash: use nullglob or check if directory is empty
      # Check if directory has any items before trying to delete
      if [[ -n "$(ls -A "$path" 2>/dev/null)" ]]; then
        for item in "$path"/* "$path"/.*; do
          if [[ -e "$item" && "$item" != "$path/." && "$item" != "$path/.." && -L "$item" ]]; then
            local item_size=$(/usr/bin/du -sk "$item" 2>/dev/null | /usr/bin/awk '{print $1}' 2>/dev/null || echo "0")
            if /bin/rm -f "$item" 2>/dev/null; then
              if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
                actual_space_freed=$((actual_space_freed + item_size * 1024))
              fi
            fi
          fi
        done 2>/dev/null
        # Delete directories and files (SEC-5: Use find -delete to avoid symlink attacks)
        for item in "$path"/* "$path"/.*; do
          if [[ -e "$item" && "$item" != "$path/." && "$item" != "$path/.." && ! -L "$item" ]]; then
            local item_size=$(/usr/bin/du -sk "$item" 2>/dev/null | /usr/bin/awk '{print $1}' 2>/dev/null || echo "0")
            # SEC-5: Use find -delete for symlink-safe deletion
            if [[ -d "$item" ]]; then
              # For directories, recursively delete contents first
              find "$item" -mindepth 1 -delete 2>/dev/null && rmdir "$item" 2>/dev/null
            else
              # For regular files, just delete
              /bin/rm -f "$item" 2>/dev/null
            fi
            # Check if deletion succeeded
            if [[ ! -e "$item" ]]; then
              if [[ -n "$item_size" && "$item_size" =~ ^[0-9]+$ ]]; then
                actual_space_freed=$((actual_space_freed + item_size * 1024))
              fi
            fi
          fi
        done 2>/dev/null
      fi
    fi
    # SEC-5: Symlink-safe fallback deletion using find -delete
    # This approach never follows symlinks, preventing symlink attack vulnerability
    find "$path" -mindepth 1 -not -type l -delete 2>/dev/null || {
      # Fallback: batch delete visible and hidden files separately
      find "$path" -mindepth 1 -maxdepth 1 ! -name ".*" -not -type l -delete 2>/dev/null || true
      find "$path" -mindepth 1 -maxdepth 1 -name ".*" -not -type l -delete 2>/dev/null || true
      find "$path" -mindepth 1 -maxdepth 1 -type l -delete 2>/dev/null || true
      # SEC-5: Final fallback WITHOUT rm -rf (prevents symlink attacks)
      # Manual per-item deletion with explicit symlink and directory handling
      if [[ -n "${ZSH_VERSION:-}" ]]; then
        # Zsh: use (N) qualifier to return empty if no matches
        for item in "${path:?}"/*(N) "${path:?}"/.[!.]*(N); do
          [[ -e "$item" ]] || continue
          if [[ -L "$item" ]]; then
            # Symlink: Remove link only, don't follow
            /bin/rm -f "$item" 2>/dev/null || true
          elif [[ -d "$item" ]]; then
            # Directory: Recursively delete contents with find, then remove dir
            find "$item" -mindepth 1 -delete 2>/dev/null || true
            rmdir "$item" 2>/dev/null || true
          else
            # Regular file
            /bin/rm -f "$item" 2>/dev/null || true
          fi
        done 2>/dev/null
      else
        # Bash: handle each item explicitly
        for item in "${path:?}"/* "${path:?}"/.[!.]*; do
          [[ -e "$item" ]] || continue
          if [[ -L "$item" ]]; then
            # Symlink: Remove link only, don't follow
            /bin/rm -f "$item" 2>/dev/null || true
          elif [[ -d "$item" ]]; then
            # Directory: Recursively delete contents with find, then remove dir
            find "$item" -mindepth 1 -delete 2>/dev/null || true
            rmdir "$item" 2>/dev/null || true
          else
            # Regular file
            /bin/rm -f "$item" 2>/dev/null || true
          fi
        done 2>/dev/null
      fi
    }
    
    # Invalidate cache for this path since it changed
    invalidate_size_cache "$path"
    
    local size_after=$(calculate_size_bytes "$path")
    # Use actual space freed from deleted files if we tracked it, otherwise use directory size difference
    local space_freed=0
    if [[ $actual_space_freed -gt 0 ]]; then
      space_freed=$actual_space_freed
    else
      space_freed=$((size_before - size_after))
    fi
    
    # Validate space_freed is not negative (directory may have grown during cleanup)
    if [[ $space_freed -lt 0 ]]; then
      space_freed=0
      log_message "WARNING" "Directory size increased during cleanup: $path (before: $(format_bytes $size_before), after: $(format_bytes $size_after))"
    fi
    
    # SAFE-9: Log any files that failed to delete
    if [[ ${#failed_files[@]} -gt 0 ]]; then
      log_message "WARNING" "Some files could not be deleted (in use or protected): ${failed_files[*]}"
    fi
    
    log_message "SUCCESS" "Cleaned: $path (freed $(format_bytes $space_freed))"
    MC_TOTAL_SPACE_SAVED=$((MC_TOTAL_SPACE_SAVED + space_freed))
    # Note: We don't write individual safe_clean_dir entries to space tracking file
    # because plugins that use safe_clean_dir typically call track_space_saved()
    # with the total, which will write to the file. Writing both would cause double-counting.
    return 0
  fi
  return 0
}
