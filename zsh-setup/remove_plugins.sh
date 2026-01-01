#!/usr/bin/env bash

#==============================================================================
# remove_plugins.sh - Plugin Removal Management
#
# Provides functionality to remove installed plugins safely
#==============================================================================

# Load required utilities
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

if [ -f "$SCRIPT_DIR/state_manager.sh" ]; then
    source "$SCRIPT_DIR/state_manager.sh"
fi

if [ -f "$SCRIPT_DIR/package_manager.sh" ]; then
    source "$SCRIPT_DIR/package_manager.sh"
fi

#------------------------------------------------------------------------------
# Dependency Checking
#------------------------------------------------------------------------------

# Check if other plugins depend on this plugin
check_plugin_dependents() {
    local plugin_name="$1"
    local dependents=()
    
    # Load dependency config
    local deps_file="${SCRIPT_DIR}/plugin_dependencies.conf"
    if [[ ! -f "$deps_file" ]]; then
        return 0
    fi
    
    while IFS='=' read -r dependent deps; do
        [[ -z "$dependent" || "$dependent" =~ ^# ]] && continue
        
        # Check if this plugin is in the dependencies
        if echo "$deps" | grep -q "$plugin_name"; then
            dependents+=("$dependent")
        fi
    done < "$deps_file"
    
    if [[ ${#dependents[@]} -gt 0 ]]; then
        printf '%s\n' "${dependents[@]}"
        return 1
    fi
    
    return 0
}

#------------------------------------------------------------------------------
# Removal Functions
#------------------------------------------------------------------------------

# Remove plugin from .zshrc configuration
cleanup_plugin_config() {
    local plugin_name="$1"
    local zshrc="$ZSHRC_PATH"
    
    if [[ ! -f "$zshrc" ]]; then
        return 0
    fi
    
    log_info "Removing $plugin_name from .zshrc configuration..."
    
    # Create backup
    local backup="${zshrc}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$zshrc" "$backup"
    
    # Remove plugin from plugins array
    # This is a simple approach - for production, use a proper parser
    sed -i.bak "s/\b${plugin_name}\b//g" "$zshrc" 2>/dev/null || \
    sed -i '' "s/\b${plugin_name}\b//g" "$zshrc" 2>/dev/null
    
    # Clean up extra spaces and commas
    sed -i.bak 's/plugins=(\([^)]*\)  */plugins=(\1 /g' "$zshrc" 2>/dev/null || \
    sed -i '' 's/plugins=(\([^)]*\)  */plugins=(\1 /g' "$zshrc" 2>/dev/null
    
    sed -i.bak 's/plugins=(\([^)]*\),, */plugins=(\1 /g' "$zshrc" 2>/dev/null || \
    sed -i '' 's/plugins=(\([^)]*\),, */plugins=(\1 /g' "$zshrc" 2>/dev/null
    
    rm -f "${zshrc}.bak"
    
    log_success "Removed $plugin_name from .zshrc"
}

# Remove git-based plugin
remove_git_plugin() {
    local plugin_name="$1"
    local plugin_path=""
    
    # Check theme location
    if [[ -d "$CUSTOM_THEMES_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_THEMES_DIR/$plugin_name"
    elif [[ -d "$CUSTOM_PLUGINS_DIR/$plugin_name" ]]; then
        plugin_path="$CUSTOM_PLUGINS_DIR/$plugin_name"
    else
        log_warn "Plugin $plugin_name not found in expected locations"
        return 0
    fi
    
    log_info "Removing plugin directory: $plugin_path"
    rm -rf "$plugin_path"
    
    if [[ ! -d "$plugin_path" ]]; then
        log_success "Removed $plugin_name"
        return 0
    else
        log_error "Failed to remove $plugin_name"
        return 1
    fi
}

# Remove Homebrew package
remove_brew_package() {
    local package_name="$1"
    local confirm="${2:-false}"
    
    if ! command -v brew &>/dev/null; then
        log_warn "Homebrew not available"
        return 0
    fi
    
    if ! is_package_installed "$package_name"; then
        log_info "$package_name is not installed via Homebrew"
        return 0
    fi
    
    if [[ "$confirm" != "true" ]]; then
        read -p "Remove Homebrew package $package_name? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Homebrew package removal"
            return 0
        fi
    fi
    
    log_info "Removing $package_name via Homebrew..."
    
    if brew uninstall --ignore-dependencies "$package_name" 2>&1; then
        log_success "Removed $package_name"
        return 0
    else
        log_error "Failed to remove $package_name"
        return 1
    fi
}

# Remove a plugin
remove_plugin() {
    local plugin_name="$1"
    local plugin_type="${2:-git}"
    local force="${3:-false}"
    
    log_section "Removing Plugin: $plugin_name"
    
    # Check for dependents
    local dependents=()
    while IFS= read -r dependent; do
        [[ -n "$dependent" ]] && dependents+=("$dependent")
    done < <(check_plugin_dependents "$plugin_name" 2>/dev/null)
    
    if [[ ${#dependents[@]} -gt 0 && "$force" != "true" ]]; then
        log_warn "The following plugins depend on $plugin_name:"
        for dep in "${dependents[@]}"; do
            echo "  - $dep"
        done
        echo ""
        read -p "Remove $plugin_name anyway? This may break dependent plugins. (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removal cancelled"
            return 0
        fi
    fi
    
    # Remove plugin files
    case "$plugin_type" in
        git)
            remove_git_plugin "$plugin_name"
            ;;
        brew)
            remove_brew_package "$plugin_name" "$force"
            ;;
        omz)
            log_info "Oh My Zsh built-in plugins cannot be removed"
            log_info "They will be ignored if not listed in plugins array"
            ;;
        *)
            log_warn "Unknown plugin type: $plugin_type"
            ;;
    esac
    
    # Clean up configuration
    cleanup_plugin_config "$plugin_name"
    
    # Update state file
    if command -v add_failed_plugin &>/dev/null; then
        # Remove from installed plugins in state
        # This would require a remove function in state_manager
        log_debug "State file update needed for $plugin_name"
    fi
    
    log_success "Plugin $plugin_name removal completed"
}

# Main removal function
main() {
    local plugin_name="$1"
    local force="${2:-false}"
    
    if [[ -z "$plugin_name" ]]; then
        log_error "Plugin name required"
        echo "Usage: $0 <plugin_name> [--force]"
        exit 1
    fi
    
    if [[ "$plugin_name" == "--force" ]]; then
        force="true"
        plugin_name="$2"
    fi
    
    # Determine plugin type
    local plugins_config="${SCRIPT_DIR}/plugins.conf"
    local plugin_type="git"
    
    if [[ -f "$plugins_config" ]]; then
        while IFS='|' read -r name type _ _; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            if [[ "$name" == "$plugin_name" ]]; then
                plugin_type="$type"
                break
            fi
        done < "$plugins_config"
    fi
    
    remove_plugin "$plugin_name" "$plugin_type" "$force"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
