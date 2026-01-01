#!/usr/bin/env bash

#==============================================================================
# filesystem.sh - Filesystem Utilities
#
# Provides file and directory operation functions
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# Filesystem Operations
#------------------------------------------------------------------------------

# Ensure directory exists
zsh_setup::utils::filesystem::ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null || {
            zsh_setup::core::logger::error "Failed to create directory: $dir"
            return 1
        }
    fi
    return 0
}

# Check if file exists and is readable
zsh_setup::utils::filesystem::file_readable() {
    local file="$1"
    [[ -f "$file" && -r "$file" ]]
}

# Check if directory exists and is writable
zsh_setup::utils::filesystem::dir_writable() {
    local dir="$1"
    [[ -d "$dir" && -w "$dir" ]]
}

# Safe file copy with backup
zsh_setup::utils::filesystem::safe_copy() {
    local source="$1"
    local dest="$2"
    local backup_suffix="${3:-.backup}"
    
    if [[ ! -f "$source" ]]; then
        zsh_setup::core::logger::error "Source file not found: $source"
        return 1
    fi
    
    # Backup existing file
    if [[ -f "$dest" ]]; then
        cp "$dest" "${dest}${backup_suffix}" 2>/dev/null || {
            zsh_setup::core::logger::warn "Could not backup existing file: $dest"
        }
    fi
    
    # Copy file
    cp "$source" "$dest" 2>/dev/null || {
        zsh_setup::core::logger::error "Failed to copy $source to $dest"
        return 1
    }
    
    return 0
}
