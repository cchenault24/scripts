#!/usr/bin/env bash

#==============================================================================
# backup.sh - Configuration Backup
#
# Handles backup and restore of configuration files
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/utils/filesystem.sh"
    # Load progress module if available
    if [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
        source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
    fi
fi

#------------------------------------------------------------------------------
# Backup Functions
#------------------------------------------------------------------------------

# Backup Zsh configuration files
zsh_setup::config::backup::backup_zshrc() {
    local backup_dir=$(zsh_setup::core::config::get backup_dir "$HOME/.zsh_backup")
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local files_backed_up=0
    
    local spinner_pid=""
    if declare -f zsh_setup::core::progress::spinner_start &>/dev/null; then
        spinner_pid=$(zsh_setup::core::progress::spinner_start "Backing up existing Zsh configuration")
    else
        zsh_setup::core::logger::info "Backing up existing Zsh configuration..."
    fi
    
    # Ensure backup directory exists
    zsh_setup::utils::filesystem::ensure_dir "$backup_dir"
    
    # Files to backup
    local config_files=(
        ".zshrc"
        ".zshenv"
        ".zprofile"
        ".zlogin"
        ".zlogout"
    )
    
    # Backup each file
    for file in "${config_files[@]}"; do
        local path="$HOME/$file"
        if [[ -f "$path" ]]; then
            cp "$path" "$backup_dir/$file.$timestamp" 2>/dev/null && {
                ((files_backed_up++))
            }
        fi
    done
    
    # Check for existing Oh My Zsh
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    if [[ -d "$ohmyzsh_dir" ]]; then
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "" 0
        fi
        zsh_setup::core::logger::warn "Existing Oh My Zsh installation found. Will not overwrite."
    fi
    
    if [[ -n "$spinner_pid" ]]; then
        if [[ $files_backed_up -eq 0 ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "No existing Zsh configuration files found. No backups created." "" 0
        else
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✅ Backup completed. $files_backed_up files backed up to $backup_dir" "" 0
        fi
    else
        if [[ $files_backed_up -eq 0 ]]; then
            zsh_setup::core::logger::info "No existing Zsh configuration files found. No backups created."
        else
            zsh_setup::core::logger::success "Backup completed. $files_backed_up files backed up to $backup_dir"
        fi
    fi
}

# Restore from backup
zsh_setup::config::backup::restore() {
    local backup_file="$1"
    local target_file="${2:-$HOME/.zshrc}"
    
    if [[ ! -f "$backup_file" ]]; then
        zsh_setup::core::logger::error "Backup file not found: $backup_file"
        return 1
    fi
    
    zsh_setup::core::logger::info "Restoring from backup: $backup_file"
    
    if cp "$backup_file" "$target_file"; then
        zsh_setup::core::logger::success "Restored $target_file from backup"
        return 0
    else
        zsh_setup::core::logger::error "Failed to restore from backup"
        return 1
    fi
}

# List available backups
zsh_setup::config::backup::list() {
    local backup_dir=$(zsh_setup::core::config::get backup_dir "$HOME/.zsh_backup")
    
    if [[ ! -d "$backup_dir" ]]; then
        zsh_setup::core::logger::info "No backup directory found"
        return 0
    fi
    
    echo "Available backups in $backup_dir:"
    ls -lt "$backup_dir" 2>/dev/null | head -10
}

