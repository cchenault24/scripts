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
    
    # Update each plugin
    local updated=0
    local failed=0
    
    for plugin in "${plugins_to_update[@]}"; do
        local plugin_type=$(zsh_setup::state::store::get_plugin_version "$plugin" 2>/dev/null | cut -d'|' -f2 || echo "")
        
        if [[ -z "$plugin_type" ]]; then
            # Try to determine from registry
            plugin_type=$(zsh_setup::plugins::registry::get "$plugin" "type")
        fi
        
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
    done
    
    zsh_setup::core::logger::success "Update complete: $updated updated, $failed failed"
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
