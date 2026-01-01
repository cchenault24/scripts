#!/usr/bin/env bash

#==============================================================================
# self_heal.sh - Self-Healing Capabilities
#
# Automatically detects and fixes common issues with Zsh setup
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

if [ -f "$SCRIPT_DIR/package_manager.sh" ]; then
    source "$SCRIPT_DIR/package_manager.sh"
fi

if [ -f "$SCRIPT_DIR/install_functions.sh" ]; then
    source "$SCRIPT_DIR/install_functions.sh"
fi

# Issue tracking
declare -a DETECTED_ISSUES=()
declare -a FIXED_ISSUES=()
declare -a FAILED_FIXES=()

#------------------------------------------------------------------------------
# Issue Detection
#------------------------------------------------------------------------------

# Detect all issues
detect_issues() {
    log_section "Detecting Issues"
    
    DETECTED_ISSUES=()
    
    # Check for broken plugins
    detect_broken_plugins
    
    # Check for config errors
    detect_config_errors
    
    # Check for missing dependencies
    detect_missing_dependencies
    
    # Check for permission issues
    detect_permission_issues
    
    if [[ ${#DETECTED_ISSUES[@]} -eq 0 ]]; then
        log_success "No issues detected"
        return 0
    else
        log_warn "Detected ${#DETECTED_ISSUES[@]} issue(s)"
        return 1
    fi
}

# Detect broken/missing plugins
detect_broken_plugins() {
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    for plugin in "${installed_plugins[@]}"; do
        local plugin_found=false
        
        # Check plugin locations
        if [[ -d "$CUSTOM_PLUGINS_DIR/$plugin" ]]; then
            plugin_found=true
        elif [[ -d "$CUSTOM_THEMES_DIR/$plugin" ]]; then
            plugin_found=true
        elif [[ -d "$OH_MY_ZSH_DIR/plugins/$plugin" ]]; then
            plugin_found=true
        fi
        
        if ! $plugin_found; then
            DETECTED_ISSUES+=("broken_plugin:$plugin")
            log_warn "Broken plugin detected: $plugin"
        fi
    done
}

# Detect config errors
detect_config_errors() {
    local zshrc="$ZSHRC_PATH"
    
    if [[ ! -f "$zshrc" ]]; then
        DETECTED_ISSUES+=("missing_zshrc")
        log_warn ".zshrc file not found"
        return
    fi
    
    # Check syntax
    if ! zsh -n "$zshrc" 2>/dev/null; then
        DETECTED_ISSUES+=("syntax_error:$zshrc")
        log_warn "Syntax errors in .zshrc"
    fi
    
    # Check for Oh My Zsh path
    if ! grep -q "ZSH=" "$zshrc"; then
        DETECTED_ISSUES+=("missing_zsh_path")
        log_warn "ZSH path not set in .zshrc"
    fi
}

# Detect missing dependencies
detect_missing_dependencies() {
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    local deps_file="${SCRIPT_DIR}/plugin_dependencies.conf"
    if [[ ! -f "$deps_file" ]]; then
        return 0
    fi
    
    while IFS='=' read -r plugin_name deps; do
        [[ -z "$plugin_name" || "$plugin_name" =~ ^# ]] && continue
        
        if ! printf '%s\n' "${installed_plugins[@]}" | grep -q "^${plugin_name}$"; then
            continue
        fi
        
        IFS=',' read -ra dep_array <<<"$deps"
        for dep in "${dep_array[@]}"; do
            dep=$(echo "$dep" | xargs)
            [[ -z "$dep" ]] && continue
            
            # Check system package
            if command -v map_plugin_to_package &>/dev/null; then
                local package=$(map_plugin_to_package "$dep")
                if ! is_package_installed "$package"; then
                    DETECTED_ISSUES+=("missing_dep:$plugin_name:$dep")
                    log_warn "Missing dependency for $plugin_name: $dep"
                fi
            fi
        done
    done < "$deps_file"
}

# Detect permission issues
detect_permission_issues() {
    # Check .zshrc permissions
    if [[ -f "$ZSHRC_PATH" ]]; then
        if [[ ! -r "$ZSHRC_PATH" ]]; then
            DETECTED_ISSUES+=("permission:$ZSHRC_PATH:not_readable")
            log_warn ".zshrc is not readable"
        fi
    fi
    
    # Check Oh My Zsh directory
    if [[ -d "$OH_MY_ZSH_DIR" ]]; then
        if [[ ! -r "$OH_MY_ZSH_DIR" ]]; then
            DETECTED_ISSUES+=("permission:$OH_MY_ZSH_DIR:not_readable")
            log_warn "Oh My Zsh directory is not readable"
        fi
    fi
    
    # Check plugin directories
    if [[ -d "$CUSTOM_PLUGINS_DIR" ]]; then
        for plugin_dir in "$CUSTOM_PLUGINS_DIR"/*; do
            if [[ -d "$plugin_dir" && ! -r "$plugin_dir" ]]; then
                local plugin_name=$(basename "$plugin_dir")
                DETECTED_ISSUES+=("permission:$plugin_dir:not_readable")
                log_warn "Plugin directory not readable: $plugin_name"
            fi
        done
    fi
}

#------------------------------------------------------------------------------
# Fix Functions
#------------------------------------------------------------------------------

# Fix broken plugins
fix_broken_plugins() {
    local fixed=0
    local failed=0
    
    for issue in "${DETECTED_ISSUES[@]}"; do
        if [[ "$issue" =~ ^broken_plugin: ]]; then
            local plugin_name="${issue#broken_plugin:}"
            log_info "Attempting to reinstall broken plugin: $plugin_name"
            
            # Determine plugin type and URL
            local plugins_config="${SCRIPT_DIR}/plugins.conf"
            local plugin_type="git"
            local plugin_url=""
            
            if [[ -f "$plugins_config" ]]; then
                while IFS='|' read -r name type url _; do
                    [[ -z "$name" || "$name" =~ ^# ]] && continue
                    if [[ "$name" == "$plugin_name" ]]; then
                        plugin_type="$type"
                        plugin_url="$url"
                        break
                    fi
                done < "$plugins_config"
            fi
            
            # Reinstall plugin
            case "$plugin_type" in
                git)
                    if [[ "$plugin_name" == "powerlevel10k" ]]; then
                        if install_git_plugin "$plugin_name" "https://github.com/romkatv/$plugin_name" "theme"; then
                            FIXED_ISSUES+=("broken_plugin:$plugin_name")
                            ((fixed++))
                        else
                            FAILED_FIXES+=("broken_plugin:$plugin_name")
                            ((failed++))
                        fi
                    else
                        if install_git_plugin "$plugin_name" "$plugin_url" "plugin"; then
                            FIXED_ISSUES+=("broken_plugin:$plugin_name")
                            ((fixed++))
                        else
                            FAILED_FIXES+=("broken_plugin:$plugin_name")
                            ((failed++))
                        fi
                    fi
                    ;;
                *)
                    log_warn "Cannot auto-fix plugin type: $plugin_type"
                    FAILED_FIXES+=("broken_plugin:$plugin_name")
                    ((failed++))
                    ;;
            esac
        fi
    done
    
    if [[ $fixed -gt 0 ]]; then
        log_success "Fixed $fixed broken plugin(s)"
    fi
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed to fix $failed plugin(s)"
    fi
}

# Fix config errors
fix_config_errors() {
    local zshrc="$ZSHRC_PATH"
    local fixed=0
    
    for issue in "${DETECTED_ISSUES[@]}"; do
        if [[ "$issue" == "missing_zshrc" ]]; then
            log_info "Creating missing .zshrc file..."
            if [[ -f "$SCRIPT_DIR/generate_zshrc.sh" ]]; then
                source "$SCRIPT_DIR/generate_zshrc.sh"
                if generate_zsh_config; then
                    FIXED_ISSUES+=("missing_zshrc")
                    ((fixed++))
                else
                    FAILED_FIXES+=("missing_zshrc")
                fi
            fi
        elif [[ "$issue" == "missing_zsh_path" ]]; then
            log_info "Adding ZSH path to .zshrc..."
            if ! grep -q "ZSH=" "$zshrc"; then
                sed -i.bak "1i export ZSH=\"\$HOME/.oh-my-zsh\"" "$zshrc" 2>/dev/null || \
                sed -i '' "1i export ZSH=\"\$HOME/.oh-my-zsh\"" "$zshrc" 2>/dev/null
                rm -f "${zshrc}.bak"
                FIXED_ISSUES+=("missing_zsh_path")
                ((fixed++))
            fi
        elif [[ "$issue" =~ ^syntax_error: ]]; then
            log_warn "Syntax errors detected - attempting to restore from backup..."
            local backup_dir="$BACKUP_DIR"
            if [[ -d "$backup_dir" ]]; then
                local latest_backup=$(ls -t "$backup_dir"/.zshrc.* 2>/dev/null | head -1)
                if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
                    read -p "Restore .zshrc from backup? (y/n): " -r
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        cp "$latest_backup" "$zshrc"
                        FIXED_ISSUES+=("syntax_error")
                        ((fixed++))
                    fi
                fi
            fi
        fi
    done
    
    if [[ $fixed -gt 0 ]]; then
        log_success "Fixed $fixed config error(s)"
    fi
}

# Install missing dependencies
install_missing_deps() {
    local fixed=0
    local failed=0
    
    for issue in "${DETECTED_ISSUES[@]}"; do
        if [[ "$issue" =~ ^missing_dep: ]]; then
            local parts="${issue#missing_dep:}"
            IFS=':' read -r plugin_name dep_name <<<"$parts"
            
            log_info "Installing missing dependency for $plugin_name: $dep_name"
            
            # Try to install as system package
            if command -v map_plugin_to_package &>/dev/null; then
                local package=$(map_plugin_to_package "$dep_name")
                if install_package "$package" "Installing dependency $dep_name"; then
                    FIXED_ISSUES+=("missing_dep:$plugin_name:$dep_name")
                    ((fixed++))
                else
                    FAILED_FIXES+=("missing_dep:$plugin_name:$dep_name")
                    ((failed++))
                fi
            else
                log_warn "Cannot determine package name for $dep_name"
                FAILED_FIXES+=("missing_dep:$plugin_name:$dep_name")
                ((failed++))
            fi
        fi
    done
    
    if [[ $fixed -gt 0 ]]; then
        log_success "Installed $fixed missing dependency/dependencies"
    fi
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed to install $failed dependency/dependencies"
    fi
}

# Fix permission issues
fix_permissions() {
    local fixed=0
    
    for issue in "${DETECTED_ISSUES[@]}"; do
        if [[ "$issue" =~ ^permission: ]]; then
            local parts="${issue#permission:}"
            IFS=':' read -r path problem <<<"$parts"
            
            log_info "Fixing permissions for: $path"
            
            if [[ "$problem" == "not_readable" ]]; then
                if [[ -f "$path" ]]; then
                    chmod 644 "$path" 2>/dev/null && ((fixed++))
                elif [[ -d "$path" ]]; then
                    chmod 755 "$path" 2>/dev/null && ((fixed++))
                fi
                
                if [[ $? -eq 0 ]]; then
                    FIXED_ISSUES+=("permission:$path")
                else
                    log_warn "Failed to fix permissions for $path (may require sudo)"
                    FAILED_FIXES+=("permission:$path")
                fi
            fi
        fi
    done
    
    if [[ $fixed -gt 0 ]]; then
        log_success "Fixed $fixed permission issue(s)"
    fi
}

#------------------------------------------------------------------------------
# Main Self-Healing Function
#------------------------------------------------------------------------------

# Run self-healing
self_heal() {
    local auto_fix="${1:-false}"
    
    log_section "Self-Healing Zsh Setup"
    
    # Detect issues
    detect_issues
    
    if [[ ${#DETECTED_ISSUES[@]} -eq 0 ]]; then
        log_success "No issues to fix"
        return 0
    fi
    
    echo ""
    log_info "Found ${#DETECTED_ISSUES[@]} issue(s) to fix:"
    for issue in "${DETECTED_ISSUES[@]}"; do
        echo "  - $issue"
    done
    echo ""
    
    if [[ "$auto_fix" != "true" ]]; then
        read -p "Proceed with automatic fixes? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Self-healing cancelled"
            return 0
        fi
    fi
    
    # Fix issues
    fix_broken_plugins
    fix_config_errors
    install_missing_deps
    fix_permissions
    
    # Summary
    echo ""
    log_section "Self-Healing Summary"
    log_info "Issues detected: ${#DETECTED_ISSUES[@]}"
    log_success "Issues fixed: ${#FIXED_ISSUES[@]}"
    if [[ ${#FAILED_FIXES[@]} -gt 0 ]]; then
        log_warn "Issues failed to fix: ${#FAILED_FIXES[@]}"
        for failed in "${FAILED_FIXES[@]}"; do
            echo "  - $failed"
        done
    fi
    
    return $((${#FAILED_FIXES[@]} > 0))
}

# Main function
main() {
    local auto_fix="${1:-false}"
    self_heal "$auto_fix"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
