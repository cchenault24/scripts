#!/bin/zsh
#
# lib/backup/manifest.sh - JSON manifest management for backup system
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Initialize a new manifest file
# Arguments: manifest_path, session_id
mc_manifest_init() {
  local manifest_path="$1"
  local session_id="$2"
  
  if [[ -z "$manifest_path" || -z "$session_id" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_manifest_init: missing arguments"
    return 1
  fi
  
  # Create parent directory if needed
  local manifest_dir=$(dirname "$manifest_path" 2>/dev/null)
  if [[ -n "$manifest_dir" && ! -d "$manifest_dir" ]]; then
    mkdir -p "$manifest_dir" 2>/dev/null || return 1
  fi
  
  # Get current timestamp in ISO 8601 format
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  
  # Write initial manifest structure
  cat > "$manifest_path" <<EOF
{
  "version": "2.0",
  "session_id": "$session_id",
  "created_at": "$timestamp",
  "backups": []
}
EOF
  
  if [[ $? -ne 0 ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to create manifest: $manifest_path"
    return 1
  fi
  
  return 0
}

# Add a backup entry to the manifest (atomic operation)
# Arguments: manifest_path, original_path, backup_name, backup_file, type, size_bytes, checksum
mc_manifest_add() {
  local manifest_path="$1"
  local original_path="$2"
  local backup_name="$3"
  local backup_file="$4"
  local backup_type="$5"
  local size_bytes="$6"
  local checksum="${7:-}"
  
  if [[ -z "$manifest_path" || -z "$original_path" || -z "$backup_name" || -z "$backup_file" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_manifest_add: missing required arguments"
    return 1
  fi
  
  # Validate manifest exists
  if [[ ! -f "$manifest_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest does not exist: $manifest_path"
    return 1
  fi
  
  # Get current timestamp
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  
  # Escape JSON special characters in paths
  local escaped_original_path=$(echo "$original_path" | sed 's/\\/\\\\/g; s/"/\\"/g')
  local escaped_backup_name=$(echo "$backup_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
  local escaped_backup_file=$(echo "$backup_file" | sed 's/\\/\\\\/g; s/"/\\"/g')
  
  # Create backup entry JSON
  local entry_json=""
  if [[ -n "$checksum" ]]; then
    entry_json="    {
      \"id\": \"${backup_name}_$(date +%s 2>/dev/null || echo '0')\",
      \"original_path\": \"$escaped_original_path\",
      \"backup_name\": \"$escaped_backup_name\",
      \"backup_file\": \"$escaped_backup_file\",
      \"type\": \"${backup_type:-unknown}\",
      \"size_bytes\": ${size_bytes:-0},
      \"checksum\": \"$checksum\",
      \"created_at\": \"$timestamp\",
      \"status\": \"completed\"
    }"
  else
    entry_json="    {
      \"id\": \"${backup_name}_$(date +%s 2>/dev/null || echo '0')\",
      \"original_path\": \"$escaped_original_path\",
      \"backup_name\": \"$escaped_backup_name\",
      \"backup_file\": \"$escaped_backup_file\",
      \"type\": \"${backup_type:-unknown}\",
      \"size_bytes\": ${size_bytes:-0},
      \"created_at\": \"$timestamp\",
      \"status\": \"completed\"
    }"
  fi
  
  # Atomic update: write to temp file, then move
  local temp_manifest="${manifest_path}.tmp"
  
  # Read existing manifest and add entry
  # Write entry_json to temp file to avoid quoting issues with awk
  local entry_file="${temp_manifest}.entry"
  echo "$entry_json" > "$entry_file" 2>/dev/null || {
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to create entry temp file"
    return 1
  }
  
  # Use awk to insert entry before closing bracket of backups array
  # Use here-document to avoid shell quoting issues
  # Use /usr/bin/awk to ensure it's available
  if ! /usr/bin/awk -v entry_file="$entry_file" <<'AWK_SCRIPT'
    BEGIN { 
      found=0
      inserted=0
      in_backups=0
      # Read entry from file
      entry=""
      while ((getline line < entry_file) > 0) {
        if (entry == "") {
          entry = line
        } else {
          entry = entry "\n" line
        }
      }
      close(entry_file)
    }
    /"backups":\s*\[/ { 
      found=1
      in_backups=1
      print
      next
    }
    found && in_backups && /^\s*\]/ && !inserted {
      # Check if this is the first entry (empty array) or need comma
      if (prev_line ~ /\[\s*$/) {
        # Empty array - no comma needed
        print entry
      } else if (prev_line !~ /,$/) {
        # Previous entry doesn't have comma - add it
        print ","
        print entry
      } else {
        # Previous entry has comma
        print entry
      }
      inserted=1
      in_backups=0
      print
      next
    }
    found && in_backups && /^\s*\{/ {
      # We're in backups array, keep track
      in_backups=1
    }
    { 
      prev_line=$0
      print
    }
AWK_SCRIPT
  "$manifest_path" > "$temp_manifest" 2>/dev/null; then
    # Clean up entry file
    rm -f "$entry_file" 2>/dev/null
    # Fallback: simple method - remove last 2 lines, add entry, re-add closing
    {
      # Remove closing bracket lines
      head -n -2 "$manifest_path" 2>/dev/null
      # Check if we need a comma (if backups array is not empty)
      if grep -q '"backups":\s*\[\s*[^]]' "$manifest_path" 2>/dev/null; then
        echo ","
      fi
      echo "$entry_json"
      echo "  ]"
      echo "}"
    } > "$temp_manifest" 2>/dev/null || {
      log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to create temp manifest"
      rm -f "$temp_manifest" "$entry_file" 2>/dev/null
      return 1
    }
  fi
  
  # Clean up entry file
  rm -f "$entry_file" 2>/dev/null
  
  # Verify temp file is valid JSON (basic check)
  if [[ ! -s "$temp_manifest" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Temp manifest is empty"
    rm -f "$temp_manifest" 2>/dev/null
    return 1
  fi
  
  # Atomically move temp file to final location
  if ! mv "$temp_manifest" "$manifest_path" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Failed to update manifest atomically"
    rm -f "$temp_manifest" 2>/dev/null
    return 1
  fi
  
  return 0
}

# Get all backup entries from manifest
# Arguments: manifest_path
# Outputs: JSON array of backup entries (one per line for easy parsing)
mc_manifest_get_all() {
  local manifest_path="$1"
  
  if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
    return 1
  fi
  
  # Extract backups array using awk
  # Use /usr/bin/awk to ensure it's available
  /usr/bin/awk '
    BEGIN { in_backups=0; brace_count=0; entry="" }
    /"backups":\s*\[/ { in_backups=1; next }
    in_backups {
      entry = entry $0 "\n"
      # Count braces to find complete entries
      gsub(/{/, "{", entry); brace_count += gsub(/{/, "", $0)
      gsub(/}/, "}", entry); brace_count -= gsub(/}/, "", $0)
      
      if (brace_count == 0 && entry ~ /{/) {
        # Complete entry found
        print entry
        entry = ""
      }
      if (/\]/) { exit }
    }
  ' "$manifest_path" 2>/dev/null
  
  return 0
}

# Get a specific backup entry by backup_name
# Arguments: manifest_path, backup_name
mc_manifest_get() {
  local manifest_path="$1"
  local backup_name="$2"
  
  if [[ -z "$manifest_path" || -z "$backup_name" ]]; then
    return 1
  fi
  
  # Search for backup_name in manifest
  grep -A 10 "\"backup_name\": \"$backup_name\"" "$manifest_path" 2>/dev/null | \
    head -n 10 | \
    grep -E "(original_path|backup_file|type|size_bytes)" 2>/dev/null
  
  return 0
}

# Validate manifest integrity
# Arguments: manifest_path
# Returns 0 if valid, 1 if invalid
mc_manifest_validate() {
  local manifest_path="$1"
  
  if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest does not exist: $manifest_path"
    return 1
  fi
  
  # Basic JSON structure validation
  # Check for required top-level keys
  if ! grep -q '"version"' "$manifest_path" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest missing version field"
    return 1
  fi
  
  if ! grep -q '"session_id"' "$manifest_path" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest missing session_id field"
    return 1
  fi
  
  if ! grep -q '"backups"' "$manifest_path" 2>/dev/null; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest missing backups array"
    return 1
  fi
  
  # Check for balanced braces (basic check)
  local open_braces=$(grep -o '{' "$manifest_path" 2>/dev/null | wc -l | tr -d ' ')
  local close_braces=$(grep -o '}' "$manifest_path" 2>/dev/null | wc -l | tr -d ' ')
  
  if [[ "$open_braces" != "$close_braces" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "Manifest has unbalanced braces"
    return 1
  fi
  
  return 0
}

# Convert old pipe-delimited manifest to JSON format
# Arguments: old_manifest_path, new_manifest_path, session_id
mc_manifest_migrate_old() {
  local old_manifest="$1"
  local new_manifest="$2"
  local session_id="$3"
  
  if [[ -z "$old_manifest" || ! -f "$old_manifest" ]]; then
    return 0  # No old manifest to migrate
  fi
  
  if [[ -z "$new_manifest" || -z "$session_id" ]]; then
    log_message "${MC_LOG_LEVEL_ERROR:-ERROR}" "mc_manifest_migrate_old: missing arguments"
    return 1
  fi
  
  # Initialize new manifest
  if ! mc_manifest_init "$new_manifest" "$session_id"; then
    return 1
  fi
  
  # Read old manifest and convert entries
  local converted=0
  while IFS='|' read -r original_path backup_name backup_date; do
    # Skip empty or malformed lines
    if [[ -z "$original_path" || -z "$backup_name" ]]; then
      continue
    fi
    
    # Trim whitespace
    original_path=$(echo "$original_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    backup_name=$(echo "$backup_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Determine backup file and type
    local backup_file="${backup_name}.tar.gz"
    local backup_type="directory"
    if [[ ! -f "$(dirname "$new_manifest")/${backup_file}" ]]; then
      backup_file="$backup_name"
      backup_type="file"
    fi
    
    # Get file size if backup exists
    local size_bytes=0
    local backup_path="$(dirname "$new_manifest")/$backup_file"
    if [[ -f "$backup_path" ]]; then
      size_bytes=$(stat -f%z "$backup_path" 2>/dev/null || echo "0")
    fi
    
    # Add to new manifest
    if mc_manifest_add "$new_manifest" "$original_path" "$backup_name" "$backup_file" "$backup_type" "$size_bytes"; then
      converted=$((converted + 1))
    fi
  done < "$old_manifest"
  
  if [[ $converted -gt 0 ]]; then
    log_message "${MC_LOG_LEVEL_INFO:-INFO}" "Migrated $converted entries from old manifest format"
  fi
  
  return 0
}
