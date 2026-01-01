#!/usr/bin/env bash

#==============================================================================
# update_plugins.sh - Plugin Update Management
#
# Provides functionality to check for and update installed plugins
#==============================================================================

# Load required utilities
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

if [ -f "$SCRIPT_DIR/error_handler.sh" ]; then
    source "$SCRIPT_DIR/error_handler.sh"
fi

if [ -f "$SCRIPT_DIR/state_manager.sh" ]; then
    source "$SCRIPT_DIR/state_manager.sh"
fi

if [ -f "$SCRIPT_DIR/install_functions.sh" ]; then
    source "$SCRIPT_DIR/install_functions.sh"
fi

#------------------------------------------------------------------------------
# Version Tracking
#------------------------------------------------------------------------------

# Get current plugin version (git commit hash)
get_plugin_version() {
    local plugin_name="$1"
    local plugin_path=""
    
    # Check theme location
    if [[ -d "$CUSTOM_THEMES_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_THEMES_DIR/$plugin_name"
    elif [[ -d "$CUSTOM_PLUGINS_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_PLUGINS_DIR/$plugin_name"
    else
        return 1
    fi
    
    if [[ -d "$plugin_path/.git" ]]; then
        (cd "$plugin_path" && git rev-parse HEAD 2>/dev/null)
    else
        echo "unknown"
    fi
}

# Get remote version (latest commit)
get_remote_version() {
    local plugin_name="$1"
    local plugin_url="$2"
    
    if [[ -z "$plugin_url" ]]; then
        # Try to get URL from git remote
        local plugin_path=""
        if [[ -d "$CUSTOM_THEMES_DIR/$plugin_name" ]]; then
            plugin_path="$CUSTOM_THEMES_DIR/$plugin_name"
        elif [[ -d "$CUSTOM_PLUGINS_DIR/$plugin_name" ]]; then
            plugin_path="$CUSTOM_PLUGINS_DIR/$plugin_name"
        fi
        
        if [[ -n "$plugin_path" && -d "$plugin_path/.git" ]]; then
            plugin_url=$(cd "$plugin_path" && git remote get-url origin 2>/dev/null)
        fi
    fi
    
    if [[ -z "$plugin_url" ]]; then
        return 1
    fi
    
    # Fetch latest commit from remote
    git ls-remote "$plugin_url" HEAD 2>/dev/null | awk '{print $1}'
}

# Check if plugin has updates available
check_plugin_update() {
    local plugin_name="$1"
    local plugin_type="${2:-git}"
    local plugin_url="${3:-}"
    
    if [[ "$plugin_type" != "git" ]]; then
        # For brew/npm packages, check via package manager
        if [[ "$plugin_type" == "brew" ]]; then
            if command -v brew &>/dev/null; then
                if brew outdated --formula | grep -q "^${plugin_name}$"; then
                    return 0
                fi
            fi
        fi
        return 1
    fi
    
    local current_version=$(get_plugin_version "$plugin_name")
    local remote_version=$(get_remote_version "$plugin_name" "$plugin_url")
    
    if [[ -z "$current_version" || "$current_version" == "unknown" ]]; then
        return 1
    fi
    
    if [[ -n "$remote_version" && "$current_version" != "$remote_version" ]]; then
        return 0  # Update available
    fi
    
    return 1  # No update
}

#------------------------------------------------------------------------------
# Update Functions
#------------------------------------------------------------------------------

# Update a single git-based plugin
update_git_plugin() {
    local plugin_name="$1"
    local plugin_path=""
    local backup_path=""
    
    # Determine plugin path
    if [[ -d "$CUSTOM_THEMES_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_THEMES_DIR/$plugin_name"
    elif [[ -d "$CUSTOM_PLUGINS_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_PLUGINS_DIR/$plugin_name"
    else
        log_error "Plugin $plugin_name not found"
        return 1
    fi
    
    if [[ ! -d "$plugin_path/.git" ]]; then
        log_error "$plugin_name is not a git repository"
        return 1
    fi
    
    local old_version=$(get_plugin_version "$plugin_name")
    
    log_info "Updating $plugin_name..."
    log_debug "Current version: $old_version"
    
    # Backup current state
    backup_path="${plugin_path}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -r "$plugin_path" "$backup_path" 2>/dev/null
    
    # Update plugin
    if (cd "$plugin_path" && git pull --rebase 2>&1); then
        local new_version=$(get_plugin_version "$plugin_name")
        log_success "Updated $plugin_name: $old_version → $new_version"
        
        # Remove backup on success
        rm -rf "$backup_path"
        return 0
    else
        log_error "Failed to update $plugin_name"
        log_info "Restoring from backup..."
        rm -rf "$plugin_path"
        mv "$backup_path" "$plugin_path"
        return 1
    fi
}

# Update a Homebrew package
update_brew_package() {
    local package_name="$1"
    
    if ! command -v brew &>/dev/null; then
        log_error "Homebrew not available"
        return 1
    fi
    
    log_info "Updating $package_name via Homebrew..."
    
    if brew upgrade "$package_name" 2>&1; then
        log_success "Updated $package_name"
        return 0
    else
        log_error "Failed to update $package_name"
        return 1
    fi
}

# Update a single plugin
update_plugin() {
    local plugin_name="$1"
    local plugin_type="${2:-git}"
    local plugin_url="${3:-}"
    
    case "$plugin_type" in
        git)
            update_git_plugin "$plugin_name"
            ;;
        brew)
            update_brew_package "$plugin_name"
            ;;
        *)
            log_warn "Update not supported for plugin type: $plugin_type"
            return 1
            ;;
    esac
}

#------------------------------------------------------------------------------
# Update Checking
#------------------------------------------------------------------------------

# Check all plugins for updates
check_all_plugin_updates() {
    local updates_available=()
    local plugin_count=0
    
    log_section "Checking for Plugin Updates"
    
    # Get installed plugins from state
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    if [[ ${#installed_plugins[@]} -eq 0 ]]; then
        log_info "No installed plugins found"
        return 0
    fi
    
    log_info "Checking ${#installed_plugins[@]} installed plugins..."
    
    # Load plugin config to get types
    local plugins_config="${SCRIPT_DIR}/plugins.conf"
    declare -A plugin_types
    declare -A plugin_urls
    
    if [[ -f "$plugins_config" ]]; then
        while IFS='|' read -r name type url _; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            plugin_types["$name"]="$type"
            plugin_urls["$name"]="$url"
        done < "$plugins_config"
    fi
    
    for plugin in "${installed_plugins[@]}"; do
        ((plugin_count++))
        local plugin_type="${plugin_types[$plugin]:-git}"
        local plugin_url="${plugin_urls[$plugin]:-}"
        
        log_info "[$plugin_count/${#installed_plugins[@]}] Checking $plugin..."
        
        if check_plugin_update "$plugin" "$plugin_type" "$plugin_url"; then
            updates_available+=("$plugin|$plugin_type|$plugin_url")
            log_info "  → Update available for $plugin"
        else
            log_debug "  → $plugin is up to date"
        fi
    done
    
    if [[ ${#updates_available[@]} -eq 0 ]]; then
        log_success "All plugins are up to date!"
        return 0
    else
        log_info "Found ${#updates_available[@]} plugin(s) with updates available"
        return 1
    fi
}

# Show update summary
show_update_summary() {
    local updates=("$@")
    
    if [[ ${#updates[@]} -eq 0 ]]; then
        log_info "No updates available"
        return 0
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              📦 Available Plugin Updates                  ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    
    local i=1
    for update in "${updates[@]}"; do
        IFS='|' read -r name type url <<<"$update"
        printf "║ %2d. %-52s ║\n" "$i" "$name ($type)"
        ((i++))
    done
    
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Interactive update process
update_all_plugins() {
    local updates=("$@")
    
    if [[ ${#updates[@]} -eq 0 ]]; then
        log_info "No updates to install"
        return 0
    fi
    
    show_update_summary "${updates[@]}"
    
    echo "The following plugins will be updated:"
    for update in "${updates[@]}"; do
        IFS='|' read -r name _ _ <<<"$update"
        echo "  - $name"
    done
    echo ""
    
    read -p "Proceed with updates? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        return 0
    fi
    
    local success_count=0
    local fail_count=0
    
    for update in "${updates[@]}"; do
        IFS='|' read -r name type url <<<"$update"
        
        if update_plugin "$name" "$type" "$url"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo ""
    log_section "Update Summary"
    log_info "Successfully updated: $success_count"
    if [[ $fail_count -gt 0 ]]; then
        log_warn "Failed to update: $fail_count"
    fi
    
    return $fail_count
}

# Main update function
main() {
    log_section "Plugin Update Manager"
    
    # Check for updates
    local updates_available=()
    check_all_plugin_updates
    
    # Collect updates
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    local plugins_config="${SCRIPT_DIR}/plugins.conf"
    declare -A plugin_types
    declare -A plugin_urls
    
    if [[ -f "$plugins_config" ]]; then
        while IFS='|' read -r name type url _; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            plugin_types["$name"]="$type"
            plugin_urls["$name"]="$url"
        done < "$plugins_config"
    fi
    
    for plugin in "${installed_plugins[@]}"; do
        local plugin_type="${plugin_types[$plugin]:-git}"
        local plugin_url="${plugin_urls[$plugin]:-}"
        
        if check_plugin_update "$plugin" "$plugin_type" "$plugin_url"; then
            updates_available+=("$plugin|$plugin_type|$plugin_url")
        fi
    done
    
    if [[ ${#updates_available[@]} -gt 0 ]]; then
        update_all_plugins "${updates_available[@]}"
    else
        log_success "All plugins are up to date!"
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
