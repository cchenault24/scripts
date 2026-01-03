#!/bin/zsh
#
# plugins/package-managers/npm.sh - npm/yarn cache cleanup plugin
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

clean_npm_cache() {
  print_header "Cleaning npm Cache"
  
  if ! command -v npm &> /dev/null; then
    print_warning "npm is not installed."
    # Track 0 space saved since npm is not available
    track_space_saved "npm Cache" 0
    return 0
  fi
  
  local total_space_freed=0
  local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
  
  if [[ -d "$npm_cache_dir" ]]; then
    # Clear size cache to ensure accurate calculation for backup decision
    clear_size_cache
    local space_before=$(calculate_size_bytes "$npm_cache_dir")
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:18\",\"message\":\"Before npm cache clean\",\"data\":{\"npm_cache_dir\":\"$npm_cache_dir\",\"space_before\":\"$space_before\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    
    if [[ "$MC_DRY_RUN" == "true" ]]; then
      print_info "[DRY RUN] Would clean npm cache ($(format_bytes $space_before))"
      log_message "DRY_RUN" "Would clean npm cache"
    else
      if ! backup "$npm_cache_dir" "npm_cache"; then
        print_error "Backup failed for npm cache. Aborting cleanup to prevent data loss."
        log_message "ERROR" "Backup failed, aborting npm cache cleanup"
        return 1
      fi
      # #region agent log
      echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:29\",\"message\":\"Running npm cache clean\",\"data\":{\"npm_cache_dir\":\"$npm_cache_dir\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      npm cache clean --force 2>&1 | log_message "INFO" || {
        print_error "Failed to clean npm cache"
        return 1
      }
      
      # Manually remove cache files from _cacache directory to actually free disk space
      # npm cache clean --force may only clear the index, not delete files
      local npm_cacache_dir="$npm_cache_dir/_cacache"
      if [[ -d "$npm_cacache_dir" ]]; then
        log_message "INFO" "Removing npm cache files from $npm_cacache_dir"
        # SAFE-1: Use safe_remove to safely handle symlinks and permissions
        safe_remove "$npm_cacache_dir" "npm cache directory" || {
          print_warning "Failed to remove npm cache directory: $npm_cacache_dir"
          log_message "WARNING" "Failed to remove npm cache directory: $npm_cacache_dir"
        }
      fi
      
      # Clear size cache before recalculating to get accurate after size
      clear_size_cache
      # #region agent log
      echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:33\",\"message\":\"After npm cache clean, calculating space\",\"data\":{\"npm_cache_dir\":\"$npm_cache_dir\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      local space_after=$(calculate_size_bytes "$npm_cache_dir")
      # #region agent log
      echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:34\",\"message\":\"Space calculation complete\",\"data\":{\"space_before\":\"$space_before\",\"space_after\":\"$space_after\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      total_space_freed=$((space_before - space_after))
      # #region agent log
      echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:35\",\"message\":\"Calculated space freed\",\"data\":{\"total_space_freed\":\"$total_space_freed\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      # Validate space_freed is not negative (directory may have grown during cleanup)
      if [[ $total_space_freed -lt 0 ]]; then
        total_space_freed=0
        log_message "WARNING" "Directory size increased during cleanup: $npm_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
      fi
      
      # Warn if expected space wasn't freed (cleanup may not have worked as expected)
      # Only warn if we expected significant space (> 10MB) but freed very little (< 1% of expected)
      if [[ $space_before -gt 10485760 && $total_space_freed -lt $((space_before / 100)) ]]; then
        print_warning "npm cache cleanup may not have freed expected space. Expected: $(format_bytes $space_before), Freed: $(format_bytes $total_space_freed)"
        log_message "WARNING" "npm cache cleanup may not have freed expected space. Expected: $(format_bytes $space_before), Freed: $(format_bytes $total_space_freed)"
      fi
      # #region agent log
      echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:40\",\"message\":\"npm cache cleaned, will track total after yarn\",\"data\":{\"total_space_freed\":\"$total_space_freed\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
      # #endregion
      # Don't track space yet - wait until after yarn cleanup to track total (npm + yarn)
      print_success "npm cache cleaned."
      log_message "SUCCESS" "npm cache cleaned (freed $(format_bytes $total_space_freed))"
    fi
  else
    print_warning "npm cache directory not found."
  fi
  
  # Clean yarn cache if available
  if command -v yarn &> /dev/null; then
    local yarn_cache_dir=$(yarn cache dir 2>/dev/null || echo "$HOME/.yarn/cache")
    if [[ -d "$yarn_cache_dir" ]]; then
      # Clear size cache to ensure accurate calculation for backup decision
      clear_size_cache
      local space_before=$(calculate_size_bytes "$yarn_cache_dir")
      
      if [[ "$MC_DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would clean yarn cache ($(format_bytes $space_before))"
        log_message "DRY_RUN" "Would clean yarn cache"
      else
        if ! backup "$yarn_cache_dir" "yarn_cache"; then
          print_error "Backup failed for yarn cache. Aborting cleanup to prevent data loss."
          log_message "ERROR" "Backup failed for yarn cache, aborting"
          return 1
        fi
        
        # #region agent log
        echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:64\",\"message\":\"Running yarn cache clean\",\"data\":{\"yarn_cache_dir\":\"$yarn_cache_dir\",\"space_before\":\"$space_before\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        yarn cache clean 2>&1 | log_message "INFO" || {
          print_error "Failed to clean yarn cache"
          return 1
        }
        
        # Manually remove cache files to actually free disk space
        # yarn cache clean may only clear the index, not delete files
        if [[ -d "$yarn_cache_dir" ]]; then
          log_message "INFO" "Removing yarn cache files from $yarn_cache_dir"
          # SAFE-1: Use safe_clean_dir to safely handle symlinks and permissions
          # This is safer than find ... -exec rm -rf which can follow symlinks
          safe_clean_dir "$yarn_cache_dir" "yarn cache directory" || {
            print_warning "Failed to remove some yarn cache files from: $yarn_cache_dir"
            log_message "WARNING" "Failed to remove some yarn cache files from: $yarn_cache_dir"
          }
        fi
        
        # Clear size cache before recalculating to get accurate after size
        clear_size_cache
        local space_after=$(calculate_size_bytes "$yarn_cache_dir")
        # #region agent log
        echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:69\",\"message\":\"Yarn space calculation\",\"data\":{\"space_before\":\"$space_before\",\"space_after\":\"$space_after\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        local yarn_space_freed=$((space_before - space_after))
        # #region agent log
        echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"G\",\"location\":\"npm.sh:70\",\"message\":\"Yarn space freed\",\"data\":{\"yarn_space_freed\":\"$yarn_space_freed\"},\"timestamp\":$(/bin/date +%s 2>/dev/null || echo 0)}" >> /Users/chenaultfamily/Documents/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        # Validate space_freed is not negative (directory may have grown during cleanup)
        if [[ $yarn_space_freed -lt 0 ]]; then
          yarn_space_freed=0
          log_message "WARNING" "Directory size increased during cleanup: $yarn_cache_dir (before: $(format_bytes $space_before), after: $(format_bytes $space_after))"
        fi
        
        # Warn if expected space wasn't freed (cleanup may not have worked as expected)
        # Only warn if we expected significant space (> 10MB) but freed very little (< 1% of expected)
        if [[ $space_before -gt 10485760 && $yarn_space_freed -lt $((space_before / 100)) ]]; then
          print_warning "yarn cache cleanup may not have freed expected space. Expected: $(format_bytes $space_before), Freed: $(format_bytes $yarn_space_freed)"
          log_message "WARNING" "yarn cache cleanup may not have freed expected space. Expected: $(format_bytes $space_before), Freed: $(format_bytes $yarn_space_freed)"
        fi
        
        total_space_freed=$((total_space_freed + yarn_space_freed))
        print_success "yarn cache cleaned."
        log_message "SUCCESS" "yarn cache cleaned (freed $(format_bytes $yarn_space_freed))"
      fi
    fi
  fi
  
  # Track total space saved (npm + yarn) once at the end to avoid double-counting
  # Only track if we actually cleaned something (total_space_freed > 0 or we attempted cleanup)
  if [[ -n "${total_space_freed:-}" ]]; then
    track_space_saved "npm Cache" $total_space_freed
  else
    # If npm wasn't installed or cache dir didn't exist, track 0
    track_space_saved "npm Cache" 0
  fi
  
  return 0
}

# Size calculation function for sweep
_calculate_npm_cache_size_bytes() {
  local size_bytes=0
  if command -v npm &> /dev/null; then
    local npm_cache_dir=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
    if [[ -d "$npm_cache_dir" ]]; then
      size_bytes=$(calculate_size_bytes "$npm_cache_dir" 2>/dev/null || echo "0")
    fi
  fi
  if command -v yarn &> /dev/null; then
    local yarn_cache_dir=$(yarn cache dir 2>/dev/null || echo "$HOME/.yarn/cache")
    if [[ -d "$yarn_cache_dir" ]]; then
      local yarn_size=$(calculate_size_bytes "$yarn_cache_dir" 2>/dev/null || echo "0")
      [[ "$yarn_size" =~ ^[0-9]+$ ]] && size_bytes=$((size_bytes + yarn_size))
    fi
  fi
  echo "$size_bytes"
}

# Register plugin with size function
register_plugin "npm Cache" "package-managers" "clean_npm_cache" "false" "_calculate_npm_cache_size_bytes"
