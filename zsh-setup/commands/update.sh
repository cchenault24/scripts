#!/usr/bin/env bash

#==============================================================================
# update.sh - Update Command
#
# Updates installed plugins
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger \
    core::errors \
    core::state \
    plugins::registry \
    plugins::installer || exit 1

zsh_setup::commands::update::execute() {
    local check_only="${1:-false}"
    zsh_setup::core::logger::section "Updating Plugins"
    
    # Get installed plugins
    local plugins_to_update=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && plugins_to_update+=("$plugin")
    done < <(zsh_setup::state::store::get_installed_plugins 2>/dev/null)
    
    if [[ ${#plugins_to_update[@]} -eq 0 ]]; then
        zsh_setup::core::logger::info "No plugins installed. Nothing to update."
        return 0
    fi
    
    zsh_setup::core::logger::info "Found ${#plugins_to_update[@]} installed plugins"
    
    # Load registry
    zsh_setup::plugins::registry::load
    
    # Check for updates first
    if [[ "$check_only" == "check" || "$check_only" == "--check" ]]; then
        zsh_setup::commands::update::_check_updates "${plugins_to_update[@]}"
        return $?
    fi
    
    # Update each plugin
    local updated=0
    local failed=0
    local up_to_date=0
    
    for plugin in "${plugins_to_update[@]}"; do
        local plugin_type=$(zsh_setup::state::store::get_plugin_version "$plugin" 2>/dev/null | cut -d'|' -f2 || echo "")
        
        if [[ -z "$plugin_type" ]]; then
            # Try to determine from registry
            plugin_type=$(zsh_setup::plugins::registry::get "$plugin" "type")
        fi
        
        # Check if update is available
        if zsh_setup::commands::update::_check_plugin_update "$plugin" "$plugin_type"; then
            zsh_setup::core::logger::info "Updating $plugin ($plugin_type)..."
            
            case "$plugin_type" in
                git)
                    zsh_setup::commands::update::_update_git "$plugin"
                    [[ $? -eq 0 ]] && ((updated++)) || ((failed++))
                    ;;
                brew)
                    zsh_setup::commands::update::_update_brew "$plugin"
                    [[ $? -eq 0 ]] && ((updated++)) || ((failed++))
                    ;;
                *)
                    zsh_setup::core::logger::warn "Unknown plugin type for $plugin. Skipping."
                    ;;
            esac
        else
            ((up_to_date++))
            zsh_setup::core::logger::info "✓ $plugin is up to date"
        fi
    done
    
    zsh_setup::core::logger::success "Update complete: $updated updated, $up_to_date up to date, $failed failed"
}

# Check if a plugin has updates available
zsh_setup::commands::update::_check_plugin_update() {
    local plugin="$1"
    local plugin_type="$2"
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local plugin_path="$ohmyzsh_dir/custom/plugins/$plugin"
    local theme_path="$ohmyzsh_dir/custom/themes/$plugin"
    
    case "$plugin_type" in
        git)
            if [[ -d "$plugin_path/.git" ]]; then
                (cd "$plugin_path" && git fetch -q 2>/dev/null && git diff HEAD origin/HEAD --quiet 2>/dev/null) && return 1 || return 0
            elif [[ -d "$theme_path/.git" ]]; then
                (cd "$theme_path" && git fetch -q 2>/dev/null && git diff HEAD origin/HEAD --quiet 2>/dev/null) && return 1 || return 0
            fi
            ;;
        brew)
            # Check if brew upgrade is available
            brew outdated "$plugin" &>/dev/null && return 0 || return 1
            ;;
    esac
    
    return 1
}

# Check for updates and show what's available
zsh_setup::commands::update::_check_updates() {
    local plugins=("$@")
    local updates_available=0
    
    zsh_setup::core::logger::info "Checking for available updates..."
    echo ""
    
    for plugin in "${plugins[@]}"; do
        local plugin_type=$(zsh_setup::plugins::registry::get "$plugin" "type")
        local current_version=$(zsh_setup::state::store::get_plugin_version "$plugin" 2>/dev/null || echo "unknown")
        
        if zsh_setup::commands::update::_check_plugin_update "$plugin" "$plugin_type"; then
            ((updates_available++))
            zsh_setup::core::logger::info "  → $plugin (current: $current_version) - UPDATE AVAILABLE"
        else
            zsh_setup::core::logger::info "  → $plugin (current: $current_version) - up to date"
        fi
    done
    
    echo ""
    if [[ $updates_available -gt 0 ]]; then
        zsh_setup::core::logger::info "Found $updates_available plugin(s) with updates available"
        zsh_setup::core::logger::info "Run 'zsh-setup update' to install updates"
        return 0
    else
        zsh_setup::core::logger::success "All plugins are up to date"
        return 1
    fi
}

zsh_setup::commands::update::_update_git() {
    local plugin="$1"
    local ohmyzsh_dir=$(zsh_setup::core::config::get oh_my_zsh_dir)
    local plugin_path="$ohmyzsh_dir/custom/plugins/$plugin"
    local theme_path="$ohmyzsh_dir/custom/themes/$plugin"
    
    if [[ -d "$plugin_path/.git" ]]; then
        (cd "$plugin_path" && git pull --rebase) && {
            local version=$(cd "$plugin_path" && git rev-parse HEAD 2>/dev/null)
            zsh_setup::state::store::update_plugin_version "$plugin" "$version"
            zsh_setup::core::logger::success "Updated $plugin"
            return 0
        }
    elif [[ -d "$theme_path/.git" ]]; then
        (cd "$theme_path" && git pull --rebase) && {
            local version=$(cd "$theme_path" && git rev-parse HEAD 2>/dev/null)
            zsh_setup::state::store::update_plugin_version "$plugin" "$version"
            zsh_setup::core::logger::success "Updated $plugin"
            return 0
        }
    else
        zsh_setup::core::logger::warn "Plugin $plugin not found or not a git repository"
        return 1
    fi
}

zsh_setup::commands::update::_update_brew() {
    local plugin="$1"
    zsh_setup::core::logger::info "Updating Homebrew package: $plugin"
    brew upgrade "$plugin" && {
        local version=$(brew list --versions "$plugin" 2>/dev/null | awk '{print $NF}')
        zsh_setup::state::store::update_plugin_version "$plugin" "$version"
        zsh_setup::core::logger::success "Updated $plugin"
        return 0
    }
    return 1
}
