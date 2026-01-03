#!/bin/zsh
#
# lib/backup.sh - Backup and restore functionality for mac-cleanup
#

# Backup a directory or file before cleaning
backup() {
  local path="$1"
  local backup_name="$2"
  
  # #region agent log
  local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
  echo "{\"id\":\"log_${log_timestamp}_backup_entry\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:7\",\"message\":\"backup() called\",\"data\":{\"path\":\"$path\",\"backup_name\":\"$backup_name\",\"MC_BACKUP_DIR\":\"$MC_BACKUP_DIR\",\"MC_DRY_RUN\":\"$MC_DRY_RUN\",\"path_exists\":\"$([[ -e \"$path\" ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"ENTRY\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>&1
  # #endregion
  
  if [[ "$MC_DRY_RUN" == "true" ]]; then
    local size=$(calculate_size "$path")
    print_info "[DRY RUN] Would backup $path ($size) to $backup_name"
    log_message "DRY_RUN" "Would backup: $path -> $backup_name"
    return 0
  fi
  
  # Ensure backup directory is set
  if [[ -z "$MC_BACKUP_DIR" ]]; then
    print_error "Backup directory not set. Cannot create backup."
    log_message "ERROR" "Backup directory not set (MC_BACKUP_DIR is empty)"
    return 1
  fi
  
  # #region agent log
  local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
  local path_check_e=$(test -e "$path" 2>/dev/null && echo "true" || echo "false")
  local path_check_d=$(test -d "$path" 2>/dev/null && echo "true" || echo "false")
  local path_check_f=$(test -f "$path" 2>/dev/null && echo "true" || echo "false")
  echo "{\"id\":\"log_${log_timestamp}_path_existence_check\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:30\",\"message\":\"Path existence check before if statement\",\"data\":{\"path\":\"$path\",\"path_check_e\":\"$path_check_e\",\"path_check_d\":\"$path_check_d\",\"path_check_f\":\"$path_check_f\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"PATH_CHECK\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>&1
  # #endregion
  
  if [[ -e "$path" ]]; then
    # Check if directory should be backed up
    if [[ -d "$path" ]]; then
      # Skip backup for very small directories (< 1MB) to save time
      # This check handles both truly empty directories (size = 0) and small ones
      local dir_size=$(calculate_size_bytes "$path" 2>/dev/null || echo "0")
      # Load constants if not already loaded
      if [[ -z "${MC_MIN_BACKUP_SIZE:-}" ]]; then
        local MC_MIN_BACKUP_SIZE=1048576  # Fallback if constants not loaded
      fi
      # #region agent log
      local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_size_check\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:32\",\"message\":\"Size check for directory\",\"data\":{\"path\":\"$path\",\"backup_name\":\"$backup_name\",\"dir_size\":\"$dir_size\",\"MC_MIN_BACKUP_SIZE\":\"$MC_MIN_BACKUP_SIZE\",\"will_skip\":\"$([[ -n \"$dir_size\" && \"$dir_size\" =~ ^[0-9]+$ && $dir_size -lt $MC_MIN_BACKUP_SIZE ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      if [[ -n "$dir_size" && "$dir_size" =~ ^[0-9]+$ && $dir_size -lt $MC_MIN_BACKUP_SIZE ]]; then
        # #region agent log
        local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_skip_small\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:42\",\"message\":\"Skipping small directory\",\"data\":{\"path\":\"$path\",\"backup_name\":\"$backup_name\",\"dir_size\":\"$dir_size\",\"MC_MIN_BACKUP_SIZE\":\"$MC_MIN_BACKUP_SIZE\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        print_info "Skipping backup of small directory (< 1MB): $path"
        log_message "INFO" "Skipped backup of small directory: $path ($(format_bytes $dir_size))"
        return 0
      fi
    fi
    
    # #region agent log
    local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
    echo "{\"id\":\"log_${log_timestamp}_after_size_check\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:43\",\"message\":\"After size check - proceeding with backup\",\"data\":{\"path\":\"$path\",\"backup_name\":\"$backup_name\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    
    print_info "Backing up $path..."
    log_message "INFO" "Creating backup: $path -> $backup_name"
    
    # Get timestamp for manifest (will be written after successful backup)
    # Use /usr/bin/date to ensure it's found even if PATH is not set correctly
    local timestamp=""
    if [[ -x "/usr/bin/date" ]]; then
      timestamp=$(/usr/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    else
      timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "NO-TIME")
    fi
    
    if [[ -d "$path" ]]; then
      # Check available disk space before backup
      local path_size=$(calculate_size_bytes "$path" 2>/dev/null || echo "0")
      
      # #region agent log
      local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_disk_space_start\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:73\",\"message\":\"Disk space calculation start\",\"data\":{\"MC_BACKUP_DIR\":\"$MC_BACKUP_DIR\",\"MC_BACKUP_DIR_set\":\"$([[ -n \"$MC_BACKUP_DIR\" ]] && echo true || echo false)\",\"MC_BACKUP_DIR_exists\":\"$([[ -d \"$MC_BACKUP_DIR\" ]] && echo true || echo false)\",\"HOME\":\"$HOME\",\"path_size\":\"$path_size\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>&1
      # #endregion
      
      # Use df to get available disk space
      # On macOS, df shows 512-byte blocks by default, so we need to multiply by 512
      # df output format: Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on
      # The "Available" column is in 512-byte blocks
      # Determine the best directory to check - use backup dir if it exists, otherwise parent or HOME
      local df_target_dir=""
      if [[ -d "$MC_BACKUP_DIR" ]]; then
        df_target_dir="$MC_BACKUP_DIR"
      elif [[ -d "$(/usr/bin/dirname "$MC_BACKUP_DIR" 2>/dev/null)" ]]; then
        df_target_dir="$(/usr/bin/dirname "$MC_BACKUP_DIR" 2>/dev/null)"
      else
        df_target_dir="$HOME/.mac-cleanup-backups"
        if [[ ! -d "$df_target_dir" ]]; then
          df_target_dir="$HOME"
        fi
      fi
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_df_target_selected\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:90\",\"message\":\"df target directory selected\",\"data\":{\"df_target_dir\":\"$df_target_dir\",\"df_target_exists\":\"$([[ -d \"$df_target_dir\" ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>&1
      # #endregion
      
      # Try to get disk space using df -k (1KB blocks, more standardized)
      # Use full path to df - try /bin/df first (macOS), then /usr/bin/df as fallback
      local backup_dir_available="0"
      local df_cmd=""
      if [[ -x "/bin/df" ]]; then
        df_cmd="/bin/df"
      elif [[ -x "/usr/bin/df" ]]; then
        df_cmd="/usr/bin/df"
      else
        df_cmd="df"  # Fallback to PATH lookup
      fi
      
      # Try df -k first (1KB blocks, more reliable)
      local df_k_output=$($df_cmd -k "$df_target_dir" 2>&1)
      local df_k_exit_code=$?
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_df_command_result\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:95\",\"message\":\"df -k command executed\",\"data\":{\"df_exit_code\":\"$df_k_exit_code\",\"df_output_length\":\"${#df_k_output}\",\"df_output_first_line\":\"$(echo \"$df_k_output\" | /usr/bin/head -1 2>/dev/null || echo \"\")\",\"df_output_second_line\":\"$(echo \"$df_k_output\" | /usr/bin/head -2 2>/dev/null | /usr/bin/tail -1 2>/dev/null || echo \"\")\",\"df_output_lines\":\"$(echo \"$df_k_output\" | /usr/bin/wc -l 2>/dev/null || echo 0)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      if [[ -n "$df_k_output" && $df_k_exit_code -eq 0 ]]; then
        # Parse the Available column (4th field) from df -k output
        # df -k output: Filesystem 1024-blocks Used Available Capacity ...
        backup_dir_available=$(echo "$df_k_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 1024; else print "0"}' 2>/dev/null)
        # Trim any whitespace
        backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
        
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        # Use arithmetic evaluation for numeric check
        local numeric_check=false
        if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
          numeric_check=true
        fi
        echo "{\"id\":\"log_${log_timestamp}_awk_parse_result\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:97\",\"message\":\"awk parsing result\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"backup_dir_available_length\":\"${#backup_dir_available}\",\"is_numeric\":\"$numeric_check\",\"df_line2_fields\":\"$(echo \"$df_k_output\" | /usr/bin/head -2 2>/dev/null | /usr/bin/tail -1 2>/dev/null | /usr/bin/awk '{print NF}' 2>/dev/null || echo 0)\",\"df_line2_field4\":\"$(echo \"$df_k_output\" | /usr/bin/head -2 2>/dev/null | /usr/bin/tail -1 2>/dev/null | /usr/bin/awk '{print \$4}' 2>/dev/null || echo '')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
      
      # Validate the result - if empty or not numeric, try fallback methods
      # Trim whitespace and check if numeric
      backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
      # Use arithmetic evaluation for more reliable numeric check
      local is_numeric=false
      if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
        is_numeric=true
      fi
      if [[ -z "$backup_dir_available" || "$is_numeric" == "false" ]]; then
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_trying_fallback\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:100\",\"message\":\"Trying fallback df (512-byte blocks)\",\"data\":{\"backup_dir_available_before\":\"$backup_dir_available\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"D\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        
        # Try df (512-byte blocks) as fallback
        local df_output=$($df_cmd "$df_target_dir" 2>&1)
        local df_exit_code=$?
        if [[ -n "$df_output" && $df_exit_code -eq 0 ]]; then
          backup_dir_available=$(echo "$df_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 512; else print "0"}' 2>/dev/null)
          # Trim any whitespace
          backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
          
          # #region agent log
          log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
          # Use arithmetic evaluation for numeric check
          local numeric_check_df=false
          if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
            numeric_check_df=true
          fi
          echo "{\"id\":\"log_${log_timestamp}_df_result\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:104\",\"message\":\"df result\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"is_numeric\":\"$numeric_check_df\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"D\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
          # #endregion
        fi
      fi
      
      # If still failing, try HOME directory as last resort
      if [[ -z "$backup_dir_available" || ! "$backup_dir_available" =~ ^[0-9]+$ ]]; then
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_trying_home\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:109\",\"message\":\"Trying HOME directory fallback\",\"data\":{\"backup_dir_available_before\":\"$backup_dir_available\",\"df_target_dir\":\"$df_target_dir\",\"HOME\":\"$HOME\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        
        if [[ "$df_target_dir" != "$HOME" ]]; then
          # Try df -k on HOME first
          local df_home_k_output=$($df_cmd -k "$HOME" 2>&1)
          local df_home_k_exit_code=$?
          if [[ -n "$df_home_k_output" && $df_home_k_exit_code -eq 0 ]]; then
            backup_dir_available=$(echo "$df_home_k_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 1024; else print "0"}' 2>/dev/null)
            # Trim any whitespace
            backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
            
            # #region agent log
            log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
            # Use arithmetic evaluation for numeric check
            local numeric_check_home_k=false
            if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
              numeric_check_home_k=true
            fi
            echo "{\"id\":\"log_${log_timestamp}_df_home_k_result\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:113\",\"message\":\"df -k HOME result\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"is_numeric\":\"$numeric_check_home_k\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
            # #endregion
          fi
          
          # If still failing, try regular df on HOME
          # Use arithmetic evaluation for numeric check
          local is_numeric_home_check=false
          if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
            is_numeric_home_check=true
          fi
          if [[ -z "$backup_dir_available" || "$is_numeric_home_check" == "false" ]]; then
            local df_home_output=$($df_cmd "$HOME" 2>&1)
            local df_home_exit_code=$?
            if [[ -n "$df_home_output" && $df_home_exit_code -eq 0 ]]; then
              backup_dir_available=$(echo "$df_home_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 512; else print "0"}' 2>/dev/null)
              # Trim any whitespace
              backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
              
              # #region agent log
              log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
              # Use arithmetic evaluation for numeric check
              local numeric_check_home_final=false
              if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
                numeric_check_home_final=true
              fi
              echo "{\"id\":\"log_${log_timestamp}_df_home_result\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:113\",\"message\":\"df HOME result\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"is_numeric\":\"$numeric_check_home_final\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"E\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
              # #endregion
            fi
          fi
        fi
      fi
      
      # Final validation - if still not valid, log warning and set to 0
      # Final validation - use arithmetic evaluation for numeric check
      local is_numeric_final_dir=false
      if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
        is_numeric_final_dir=true
      fi
      if [[ -z "$backup_dir_available" || "$is_numeric_final_dir" == "false" ]]; then
        backup_dir_available="0"
        log_message "WARNING" "Could not determine available disk space for backup directory (checked: $df_target_dir). Proceeding with assumption of 0 bytes available."
        
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_final_zero\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:120\",\"message\":\"Final backup_dir_available set to 0\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"df_target_dir\":\"$df_target_dir\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_disk_space_final\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:125\",\"message\":\"Disk space calculation final result\",\"data\":{\"backup_dir_available\":\"$backup_dir_available\",\"needed_space\":\"$((path_size + (path_size / 5)))\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"F\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Add 20% overhead for compression and metadata
      local needed_space=$((path_size + (path_size / 5)))
      
      # #region agent log
      local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_disk_space_check\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:65\",\"message\":\"Disk space check\",\"data\":{\"path_size\":\"$path_size\",\"backup_dir_available\":\"$backup_dir_available\",\"needed_space\":\"$needed_space\",\"df_output_lines\":\"$(echo \"$df_output\" | /usr/bin/wc -l 2>/dev/null || echo 0)\",\"df_output\":\"$(echo \"$df_output\" | /usr/bin/head -2 2>/dev/null | /usr/bin/tail -1 2>/dev/null || echo \"\")\",\"will_fail\":\"$([[ $backup_dir_available -lt $needed_space ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      if [[ $backup_dir_available -lt $needed_space ]]; then
        print_error "Insufficient disk space for backup. Available: $(format_bytes $backup_dir_available), Needed: $(format_bytes $needed_space)"
        log_message "ERROR" "Insufficient disk space for backup: $backup_name (available: $(format_bytes $backup_dir_available), needed: $(format_bytes $needed_space))"
        return 1
      fi
      
      # Use faster compression level (gzip -1) for better performance
      # Use a background process for large directories
      # #region agent log
      local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      local backup_file_path="$MC_BACKUP_DIR/${backup_name}.tar.gz"
      local backup_dir_writable=$(test -w "$MC_BACKUP_DIR" 2>/dev/null && echo "true" || echo "false")
      local backup_dir_exists=$(test -d "$MC_BACKUP_DIR" 2>/dev/null && echo "true" || echo "false")
      local parent_dir_writable=$(test -w "$(/usr/bin/dirname "$backup_file_path" 2>/dev/null)" 2>/dev/null && echo "true" || echo "false")
      echo "{\"id\":\"log_${log_timestamp}_before_tar\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:73\",\"message\":\"Before tar command\",\"data\":{\"path\":\"$path\",\"backup_file\":\"$backup_file_path\",\"parent_dir\":\"$(/usr/bin/dirname \"$path\")\",\"basename\":\"$(/usr/bin/basename \"$path\")\",\"backup_dir_exists\":\"$backup_dir_exists\",\"backup_dir_writable\":\"$backup_dir_writable\",\"parent_dir_writable\":\"$parent_dir_writable\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Ensure backup directory exists before starting tar
      if [[ ! -d "$MC_BACKUP_DIR" ]]; then
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_creating_backup_dir\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:280\",\"message\":\"Creating backup directory\",\"data\":{\"MC_BACKUP_DIR\":\"$MC_BACKUP_DIR\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        /bin/mkdir -p "$MC_BACKUP_DIR" 2>/dev/null || {
          print_error "Cannot create backup directory: $MC_BACKUP_DIR"
          log_message "ERROR" "Cannot create backup directory: $MC_BACKUP_DIR"
          return 1
        }
      fi
      
      # Verify backup directory exists and is writable
      if [[ ! -d "$MC_BACKUP_DIR" ]] || [[ ! -w "$MC_BACKUP_DIR" ]]; then
        print_error "Backup directory does not exist or is not writable: $MC_BACKUP_DIR"
        log_message "ERROR" "Backup directory not accessible: $MC_BACKUP_DIR"
        return 1
      fi
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_tar_command\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:280\",\"message\":\"Executing tar command\",\"data\":{\"tar_cmd\":\"/usr/bin/tar\",\"gzip_cmd\":\"/usr/bin/gzip\",\"backup_file\":\"$backup_file_path\",\"backup_dir_verified\":\"true\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Use explicit redirection - capture stderr to a temp file for debugging
      # The issue is that in background processes, exit codes from pipelines can be tricky
      # We'll capture stderr separately to see what's failing
      # Run tar and gzip in a way that preserves exit codes
      local stderr_file="$MC_BACKUP_DIR/${backup_name}.tar.gz.stderr"
      # Create the stderr file first to ensure it exists
      touch "$stderr_file" 2>/dev/null || true
      
      # Pre-calculate paths to avoid issues with quoting
      local parent_dir_path=$(/usr/bin/dirname "$path")
      local basename_path=$(/usr/bin/basename "$path")
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_before_pipeline\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:322\",\"message\":\"Before pipeline execution\",\"data\":{\"parent_dir_path\":\"$parent_dir_path\",\"basename_path\":\"$basename_path\",\"backup_file_path\":\"$backup_file_path\",\"stderr_file\":\"$stderr_file\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Execute tar | gzip pipeline directly in background subshell
      # Use explicit subshell with pipefail to capture correct exit code
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      local tar_cmd_exists=$(test -x /usr/bin/tar && echo "true" || echo "false")
      local gzip_cmd_exists=$(test -x /usr/bin/gzip && echo "true" || echo "false")
      local parent_dir_readable=$(test -r "$parent_dir_path" && echo "true" || echo "false")
      local basename_readable=$(test -r "$parent_dir_path/$basename_path" && echo "true" || echo "false")
      local backup_dir_writable=$(test -w "$MC_BACKUP_DIR" && echo "true" || echo "false")
      echo "{\"id\":\"log_${log_timestamp}_before_subshell\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:329\",\"message\":\"Before subshell execution\",\"data\":{\"tar_cmd_exists\":\"$tar_cmd_exists\",\"gzip_cmd_exists\":\"$gzip_cmd_exists\",\"parent_dir_path\":\"$parent_dir_path\",\"basename_path\":\"$basename_path\",\"parent_dir_readable\":\"$parent_dir_readable\",\"basename_readable\":\"$basename_readable\",\"backup_file_path\":\"$backup_file_path\",\"stderr_file\":\"$stderr_file\",\"backup_dir_writable\":\"$backup_dir_writable\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      (
        set -o pipefail
        /usr/bin/tar -c -C "$parent_dir_path" "$basename_path" 2>"$stderr_file" | \
        /usr/bin/gzip -1 > "$backup_file_path" 2>>"$stderr_file"
      ) &
      local pid=$!
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_tar_started\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:75\",\"message\":\"Tar process started\",\"data\":{\"pid\":\"$pid\",\"backup_file_immediate_exists\":\"$([[ -f \"$backup_file_path\" ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      show_spinner "Creating backup of $(/usr/bin/basename "$path")" $pid
      
      # Wait for the backup process to complete and check exit status
      # wait directly returns the exit code of the background process
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_before_wait\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:290\",\"message\":\"Before wait for tar process\",\"data\":{\"pid\":\"$pid\",\"backup_file\":\"$MC_BACKUP_DIR/${backup_name}.tar.gz\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      wait $pid 2>/dev/null
      local backup_exit_code=$?
      local wait_exit_code=$?
      
      # #region agent log
      log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      local backup_file_path_check="$MC_BACKUP_DIR/${backup_name}.tar.gz"
      local file_exists_after=$(test -f "$backup_file_path_check" 2>/dev/null && echo "true" || echo "false")
      local file_size_after=$(stat -f%z "$backup_file_path_check" 2>/dev/null || echo "0")
      local backup_dir_exists_after=$(test -d "$MC_BACKUP_DIR" 2>/dev/null && echo "true" || echo "false")
      local backup_dir_listing=$(ls -la "$MC_BACKUP_DIR" 2>/dev/null | /usr/bin/head -5 2>/dev/null || echo "")
      local stderr_content=$(/bin/cat "$stderr_file" 2>/dev/null | /usr/bin/head -20 2>/dev/null || echo "")
      local stderr_size=$(stat -f%z "$stderr_file" 2>/dev/null || echo "0")
      # Check if process is still running (shouldn't be after wait, but let's verify)
      local process_running=$(kill -0 $pid 2>/dev/null && echo "true" || echo "false")
      # Check if we can read the stderr file
      local stderr_readable=$(test -r "$stderr_file" && echo "true" || echo "false")
      echo "{\"id\":\"log_${log_timestamp}_after_wait\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:292\",\"message\":\"After wait for tar process\",\"data\":{\"backup_exit_code\":\"$backup_exit_code\",\"wait_exit_code\":\"$wait_exit_code\",\"process_running\":\"$process_running\",\"backup_file_exists\":\"$file_exists_after\",\"backup_file_size\":\"$file_size_after\",\"backup_dir_exists\":\"$backup_dir_exists_after\",\"backup_file_path\":\"$backup_file_path_check\",\"backup_dir_listing\":\"$backup_dir_listing\",\"stderr_size\":\"$stderr_size\",\"stderr_readable\":\"$stderr_readable\",\"stderr_content\":\"$stderr_content\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Clean up stderr file if backup succeeded
      if [[ $backup_exit_code -eq 0 && -f "$backup_file_path_check" && -s "$backup_file_path_check" ]]; then
        rm -f "$stderr_file" 2>/dev/null || true
      fi
      
      # Verify backup file exists before checking exit code
      # (exit code might be 0 even if file wasn't created due to redirection issues)
      if [[ ! -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" ]]; then
        # #region agent log
        log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_backup_file_missing\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:295\",\"message\":\"Backup file not found after tar\",\"data\":{\"backup_file\":\"$MC_BACKUP_DIR/${backup_name}.tar.gz\",\"backup_exit_code\":\"$backup_exit_code\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        print_error "Backup file was not created: ${backup_name}.tar.gz"
        log_message "ERROR" "Backup file not created for: $backup_name (exit code: $backup_exit_code)"
        return 1
      fi
      
      # Verify backup file has content (not empty)
      local backup_file_size=$(stat -f%z "$MC_BACKUP_DIR/${backup_name}.tar.gz" 2>/dev/null || echo "0")
      if [[ -z "$backup_file_size" || "$backup_file_size" == "0" ]]; then
        print_error "Backup file is empty: ${backup_name}.tar.gz"
        log_message "ERROR" "Backup file is empty for: $backup_name"
        rm -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" 2>/dev/null || true
        return 1
      fi
      
      # #region agent log
      local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
      echo "{\"id\":\"log_${log_timestamp}_backup_exit_code\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:83\",\"message\":\"Backup process exit code\",\"data\":{\"backup_exit_code\":\"$backup_exit_code\",\"backup_file_exists\":\"$([[ -f $MC_BACKUP_DIR/${backup_name}.tar.gz ]] && echo true || echo false)\",\"backup_file_size\":\"$(stat -f%z \"$MC_BACKUP_DIR/${backup_name}.tar.gz\" 2>/dev/null || echo 0)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Check if backup process failed
      if [[ $backup_exit_code -ne 0 ]]; then
        print_warning "Backup process failed with exit code $backup_exit_code"
        log_message "ERROR" "Backup process failed for: $backup_name (exit code: $backup_exit_code)"
        rm -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" 2>/dev/null || true
        return 1
      fi
      
      # Verify backup was created successfully and is valid
      if [[ -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" ]]; then
        # Verify backup integrity by testing if it can be listed
        local integrity_check=$(/usr/bin/tar -tzf "$MC_BACKUP_DIR/${backup_name}.tar.gz" &>/dev/null; echo $?)
        # #region agent log
        local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
        echo "{\"id\":\"log_${log_timestamp}_integrity_check\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:96\",\"message\":\"Backup integrity check\",\"data\":{\"integrity_check_result\":\"$integrity_check\",\"backup_file\":\"$MC_BACKUP_DIR/${backup_name}.tar.gz\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"C\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        if [[ $integrity_check -eq 0 ]]; then
          # Only write to manifest AFTER backup is successfully created and verified
          # #region agent log
          local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
          echo "{\"id\":\"log_${log_timestamp}_before_manifest_write\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:98\",\"message\":\"Before manifest write\",\"data\":{\"manifest_path\":\"$MC_BACKUP_DIR/backup_manifest.txt\",\"manifest_exists\":\"$([[ -f $MC_BACKUP_DIR/backup_manifest.txt ]] && echo true || echo false)\",\"manifest_writable\":\"$([[ -w $MC_BACKUP_DIR/backup_manifest.txt ]] && echo true || echo false)\",\"backup_dir_writable\":\"$([[ -w $MC_BACKUP_DIR ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
          # #endregion
          # Write to manifest and verify it was written successfully
          local manifest_entry="$path|$backup_name|$timestamp"
          if ! echo "$manifest_entry" >> "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null; then
            print_error "Failed to write to backup manifest: $MC_BACKUP_DIR/backup_manifest.txt"
            log_message "ERROR" "Manifest write failed for: $backup_name (path: $path)"
            # Don't remove backup file - it exists and is valid, just manifest write failed
            return 1
          fi
          
          # Verify manifest entry was actually written
          if ! grep -Fq "$manifest_entry" "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null; then
            print_error "Manifest entry verification failed: entry not found in manifest"
            log_message "ERROR" "Manifest entry verification failed for: $backup_name"
            return 1
          fi
          
          # #region agent log
          log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
          echo "{\"id\":\"log_${log_timestamp}_after_manifest_write\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:98\",\"message\":\"After manifest write\",\"data\":{\"manifest_size\":\"$(stat -f%z \"$MC_BACKUP_DIR/backup_manifest.txt\" 2>/dev/null || echo 0)\",\"manifest_line_count\":\"$(/usr/bin/wc -l < \"$MC_BACKUP_DIR/backup_manifest.txt\" 2>/dev/null || echo 0)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
          # #endregion
          print_success "Backup complete: $backup_name"
          log_message "SUCCESS" "Backup created and verified: $backup_name.tar.gz"
          return 0
        else
          print_warning "Backup file created but integrity check failed. Removing corrupted backup..."
          rm -f "$MC_BACKUP_DIR/${backup_name}.tar.gz" 2>/dev/null || true
          log_message "ERROR" "Backup integrity verification failed for: $backup_name"
          return 1
        fi
      else
        print_warning "Backup file was not created"
        log_message "WARNING" "Backup file not created for: $backup_name"
        return 1
      fi
    else
      # Check available disk space before backup (for files)
      local path_size=$(stat -f%z "$path" 2>/dev/null || echo "0")
      # Standardize on 512-byte blocks like directory backups
      # Use df to get available disk space (512-byte blocks on macOS)
      # Determine the best directory to check - use backup dir if it exists, otherwise parent or HOME
      local df_target_dir=""
      if [[ -d "$MC_BACKUP_DIR" ]]; then
        df_target_dir="$MC_BACKUP_DIR"
      elif [[ -d "$(/usr/bin/dirname "$MC_BACKUP_DIR" 2>/dev/null)" ]]; then
        df_target_dir="$(/usr/bin/dirname "$MC_BACKUP_DIR" 2>/dev/null)"
      else
        df_target_dir="$HOME/.mac-cleanup-backups"
        if [[ ! -d "$df_target_dir" ]]; then
          df_target_dir="$HOME"
        fi
      fi
      
      # Try to get disk space using df -k (1KB blocks, more standardized)
      # Use full path to df - try /bin/df first (macOS), then /usr/bin/df as fallback
      local backup_dir_available="0"
      local df_cmd=""
      if [[ -x "/bin/df" ]]; then
        df_cmd="/bin/df"
      elif [[ -x "/usr/bin/df" ]]; then
        df_cmd="/usr/bin/df"
      else
        df_cmd="df"  # Fallback to PATH lookup
      fi
      
      # Try df -k first (1KB blocks, more reliable)
      local df_k_output=$($df_cmd -k "$df_target_dir" 2>&1)
      local df_k_exit_code=$?
      if [[ -n "$df_k_output" && $df_k_exit_code -eq 0 ]]; then
        backup_dir_available=$(echo "$df_k_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 1024; else print "0"}' 2>/dev/null)
        # Trim any whitespace
        backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
      fi
      
      # Validate the result - if empty or not numeric, try fallback methods
      # Use arithmetic evaluation for more reliable numeric check
      local is_numeric_file=false
      if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
        is_numeric_file=true
      fi
      if [[ -z "$backup_dir_available" || "$is_numeric_file" == "false" ]]; then
        # Try df (512-byte blocks) as fallback
        local df_output=$($df_cmd "$df_target_dir" 2>&1)
        local df_exit_code=$?
        if [[ -n "$df_output" && $df_exit_code -eq 0 ]]; then
          backup_dir_available=$(echo "$df_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 512; else print "0"}' 2>/dev/null)
          # Trim any whitespace
          backup_dir_available=$(echo "$backup_dir_available" | /usr/bin/tr -d '[:space:]' 2>/dev/null || echo "$backup_dir_available")
        fi
      fi
      
      # If still failing, try HOME directory as last resort
      # Use arithmetic evaluation for numeric check
      local is_numeric_home_file=false
      if [[ -n "$backup_dir_available" ]] && (( backup_dir_available + 0 == backup_dir_available )) 2>/dev/null; then
        is_numeric_home_file=true
      fi
      if [[ -z "$backup_dir_available" || "$is_numeric_home_file" == "false" ]]; then
        if [[ "$df_target_dir" != "$HOME" ]]; then
          # Try df -k on HOME first
          local df_home_k_output=$($df_cmd -k "$HOME" 2>&1)
          local df_home_k_exit_code=$?
          if [[ -n "$df_home_k_output" && $df_home_k_exit_code -eq 0 ]]; then
            backup_dir_available=$(echo "$df_home_k_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 1024; else print "0"}' 2>/dev/null)
          fi
          
          # If still failing, try regular df on HOME
          if [[ -z "$backup_dir_available" || ! "$backup_dir_available" =~ ^[0-9]+$ ]]; then
            local df_home_output=$($df_cmd "$HOME" 2>&1)
            local df_home_exit_code=$?
            if [[ -n "$df_home_output" && $df_home_exit_code -eq 0 ]]; then
              backup_dir_available=$(echo "$df_home_output" | /usr/bin/awk 'NR==2 {if (NF >= 4 && $4 ~ /^[0-9]+$/) print $4 * 512; else print "0"}' 2>/dev/null)
            fi
          fi
        fi
      fi
      
      # Final validation - if still not valid, log warning and set to 0
      if [[ -z "$backup_dir_available" || ! "$backup_dir_available" =~ ^[0-9]+$ ]]; then
        backup_dir_available="0"
        log_message "WARNING" "Could not determine available disk space for backup directory (checked: $df_target_dir). Proceeding with assumption of 0 bytes available."
      fi
      
      if [[ $backup_dir_available -lt $path_size ]]; then
        print_error "Insufficient disk space for backup. Available: $(format_bytes $backup_dir_available), Needed: $(format_bytes $path_size)"
        log_message "ERROR" "Insufficient disk space for backup: $backup_name (available: $(format_bytes $backup_dir_available), needed: $(format_bytes $path_size))"
        return 1
      fi
      
      if cp "$path" "$MC_BACKUP_DIR/${backup_name}" 2>/dev/null; then
        # Verify backup file exists and has content
        if [[ -f "$MC_BACKUP_DIR/${backup_name}" && -s "$MC_BACKUP_DIR/${backup_name}" ]]; then
          # Verify backup file size matches original (for files)
          local backup_file_size=$(stat -f%z "$MC_BACKUP_DIR/${backup_name}" 2>/dev/null || echo "0")
          if [[ -z "$backup_file_size" || "$backup_file_size" == "0" || "$backup_file_size" != "$path_size" ]]; then
            print_error "Backup file size mismatch. Original: $(format_bytes $path_size), Backup: $(format_bytes $backup_file_size)"
            log_message "ERROR" "Backup file size verification failed for: $backup_name (original: $path_size, backup: $backup_file_size)"
            rm -f "$MC_BACKUP_DIR/${backup_name}" 2>/dev/null || true
            return 1
          fi
          
          # Only write to manifest AFTER backup is successfully created and verified
          # #region agent log
          local log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
          echo "{\"id\":\"log_${log_timestamp}_before_manifest_write_file\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:128\",\"message\":\"Before manifest write (file)\",\"data\":{\"manifest_path\":\"$MC_BACKUP_DIR/backup_manifest.txt\",\"manifest_exists\":\"$([[ -f $MC_BACKUP_DIR/backup_manifest.txt ]] && echo true || echo false)\",\"manifest_writable\":\"$([[ -w $MC_BACKUP_DIR/backup_manifest.txt ]] && echo true || echo false)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
          # #endregion
          # Write to manifest and verify it was written successfully
          local manifest_entry="$path|$backup_name|$timestamp"
          if ! echo "$manifest_entry" >> "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null; then
            print_error "Failed to write to backup manifest: $MC_BACKUP_DIR/backup_manifest.txt"
            log_message "ERROR" "Manifest write failed for: $backup_name (path: $path)"
            # Don't remove backup file - it exists and is valid, just manifest write failed
            return 1
          fi
          
          # Verify manifest entry was actually written
          if ! grep -Fq "$manifest_entry" "$MC_BACKUP_DIR/backup_manifest.txt" 2>/dev/null; then
            print_error "Manifest entry verification failed: entry not found in manifest"
            log_message "ERROR" "Manifest entry verification failed for: $backup_name"
            return 1
          fi
          
          # #region agent log
          log_timestamp=$(/usr/bin/date +%s 2>/dev/null || echo "0")
          echo "{\"id\":\"log_${log_timestamp}_after_manifest_write_file\",\"timestamp\":${log_timestamp}000,\"location\":\"backup.sh:128\",\"message\":\"After manifest write (file)\",\"data\":{\"manifest_size\":\"$(stat -f%z \"$MC_BACKUP_DIR/backup_manifest.txt\" 2>/dev/null || echo 0)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\"}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
          # #endregion
          print_success "Backup complete: $backup_name"
          log_message "SUCCESS" "Backup created and verified: $backup_name"
          return 0
        else
          print_warning "Backup file created but is empty or missing. Removing invalid backup..."
          rm -f "$MC_BACKUP_DIR/${backup_name}" 2>/dev/null || true
          log_message "ERROR" "Backup verification failed (empty or missing) for: $backup_name"
          return 1
        fi
      else
        print_warning "Backup failed"
        log_message "WARNING" "Backup failed for: $backup_name"
        return 1
      fi
    fi
  else
    # Path doesn't exist - this is an error
    print_error "Cannot backup: path does not exist: $path"
    log_message "ERROR" "Backup failed: path does not exist: $path (backup_name: $backup_name)"
    return 1
  fi
}

# List available backup sessions
mc_list_backups() {
  local backup_base="$HOME/.mac-cleanup-backups"
  
  if [[ ! -d "$backup_base" ]]; then
    print_warning "No backup directory found."
    return 1
  fi
  
  local backups=($(find "$backup_base" -mindepth 1 -maxdepth 1 -type d | sort -r))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    print_warning "No backup sessions found."
    return 1
  fi
  
  print_info "Available backup sessions:"
  local index=1
  for backup_dir in "${backups[@]}"; do
    local backup_name=$(/usr/bin/basename "$backup_dir")
    # Use /usr/bin/awk to ensure it's available
    local backup_date=$(echo "$backup_name" | sed 's/-/ /g' | /usr/bin/awk '{print $1"-"$2"-"$3" "$4":"$5":"$6}' 2>/dev/null || echo "$backup_name")
    local backup_size=$(calculate_size "$backup_dir" 2>/dev/null || echo "")
    print_message "$CYAN" "  $index. $backup_date${backup_size:+ ($backup_size)}"
    index=$((index + 1))
  done
  
  return 0
}

# Export for backward compatibility
list_backups() {
  mc_list_backups
}
