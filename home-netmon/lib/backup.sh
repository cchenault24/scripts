#!/bin/bash
# Home Network Monitor - Backup/Restore Functions
# Backup and restore functionality
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Backup Functions
#------------------------------------------------------------------------------

backup_config() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  local backup_dir="${BASE_DIR}/backups"
  local timestamp=$(date '+%Y%m%d_%H%M%S')
  local backup_name="backup_${timestamp}"
  local backup_path="${backup_dir}/${backup_name}"
  
  mkdir -p "$backup_dir" "$backup_path"
  
  # Backup key files
  [ -f "${BASE_DIR}/.env" ] && cp "${BASE_DIR}/.env" "$backup_path/" 2>/dev/null || true
  [ -f "${BASE_DIR}/docker-compose.yml" ] && cp "${BASE_DIR}/docker-compose.yml" "$backup_path/" 2>/dev/null || true
  [ -d "${BASE_DIR}/gatus" ] && cp -r "${BASE_DIR}/gatus" "$backup_path/" 2>/dev/null || true
  [ -d "${BASE_DIR}/ntfy" ] && cp -r "${BASE_DIR}/ntfy" "$backup_path/" 2>/dev/null || true
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Backup created: $backup_path"
  fi
  
  echo "$backup_path"
}

list_backups() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  local backup_dir="${BASE_DIR}/backups"
  
  if [ ! -d "$backup_dir" ]; then
    return 1
  fi
  
  ls -1t "$backup_dir" 2>/dev/null || true
}

restore_from_backup() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  local backup_name="$1"
  local backup_dir="${BASE_DIR}/backups"
  local backup_path="${backup_dir}/${backup_name}"
  
  if [ ! -d "$backup_path" ]; then
    if command -v err >/dev/null 2>&1; then
      err "Backup not found: $backup_name"
    fi
    return 1
  fi
  
  # Restore files
  [ -f "${backup_path}/.env" ] && cp "${backup_path}/.env" "${BASE_DIR}/" 2>/dev/null || true
  [ -f "${backup_path}/docker-compose.yml" ] && cp "${backup_path}/docker-compose.yml" "${BASE_DIR}/" 2>/dev/null || true
  [ -d "${backup_path}/gatus" ] && cp -r "${backup_path}/gatus" "${BASE_DIR}/" 2>/dev/null || true
  [ -d "${backup_path}/ntfy" ] && cp -r "${backup_path}/ntfy" "${BASE_DIR}/" 2>/dev/null || true
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Restored from backup: $backup_name"
  fi
  
  return 0
}

cleanup_old_backups() {
  : "${BASE_DIR:=${HOME}/home-netmon}"
  local backup_dir="${BASE_DIR}/backups"
  local max_backups=10
  
  if [ ! -d "$backup_dir" ]; then
    return 0
  fi
  
  # Remove backups beyond max_backups, keeping most recent
  local backups
  backups=$(ls -1t "$backup_dir" 2>/dev/null | tail -n +$((max_backups + 1)))
  
  if [ -n "$backups" ]; then
    echo "$backups" | while read -r backup; do
      rm -rf "${backup_dir}/${backup}"
      if command -v log_info >/dev/null 2>&1; then
        log_info "Removed old backup: $backup"
      fi
    done
  fi
}
