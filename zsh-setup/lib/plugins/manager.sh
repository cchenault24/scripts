#!/usr/bin/env bash

#==============================================================================
# manager.sh - Plugin Manager
#
# Orchestrates plugin installation, updates, and removal
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
    source "$ZSH_SETUP_ROOT/lib/plugins/resolver.sh"
    source "$ZSH_SETUP_ROOT/lib/plugins/installer.sh"
    source "$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
fi

#------------------------------------------------------------------------------
# Plugin Installation
#------------------------------------------------------------------------------

# Install plugins interactively
zsh_setup::plugins::manager::install_interactive() {
    # Load plugin registry
    zsh_setup::plugins::registry::load
    
    # Show selection menu
    local selected=$(zsh_setup::plugins::manager::_show_selection_menu)
    
    if [[ -z "$selected" ]]; then
        zsh_setup::core::logger::info "No plugins selected"
        return 0
    fi
    
    # Parse selections and resolve dependencies
    local plugins_to_install=()
    while IFS= read -r selection; do
        [[ -z "$selection" ]] && continue
        # Extract plugin name from selection (format: "description - name")
        local plugin_name=$(echo "$selection" | sed 's/.* - //')
        plugins_to_install+=("$plugin_name")
    done <<< "$selected"
    
    # Resolve dependencies
    local all_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && all_plugins+=("$plugin")
    done < <(zsh_setup::plugins::resolver::resolve_all "${plugins_to_install[@]}")
    
    # Install plugins
    zsh_setup::plugins::manager::install_list "${all_plugins[@]}"
}

# Install a list of plugins
zsh_setup::plugins::manager::install_list() {
    local plugins=("$@")
    local total=${#plugins[@]}
    
    zsh_setup::core::logger::info "Installing $total plugins..."
    
    # Separate by installation method
    local brew_plugins=()
    local parallel_plugins=()
    
    for plugin in "${plugins[@]}"; do
        local plugin_type=$(zsh_setup::plugins::registry::get "$plugin" "type")
        
        if [[ "$plugin_type" == "brew" ]]; then
            brew_plugins+=("$plugin")
        else
            parallel_plugins+=("$plugin")
        fi
    done
    
    # Install parallel plugins
    if [[ ${#parallel_plugins[@]} -gt 0 ]]; then
        local max_parallel=$(zsh_setup::core::config::get max_parallel_installs "3")
        zsh_setup::core::logger::info "Installing ${#parallel_plugins[@]} plugins in parallel (max $max_parallel concurrent)..."
        
        # Create worker script
        local worker_script=$(mktemp)
        cat > "$worker_script" <<'WORKER_EOF'
#!/usr/bin/env bash
ZSH_SETUP_ROOT="$1"
PLUGIN_NAME="$2"

source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"
zsh_setup::core::bootstrap::init

source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
source "$ZSH_SETUP_ROOT/lib/plugins/installer.sh"

zsh_setup::plugins::registry::load

local plugin_type=$(zsh_setup::plugins::registry::get "$PLUGIN_NAME" "type")
local plugin_url=$(zsh_setup::plugins::registry::get "$PLUGIN_NAME" "url")

if [[ "$PLUGIN_NAME" == "powerlevel10k" ]]; then
    zsh_setup::plugins::installer::install_git "$PLUGIN_NAME" "$plugin_url" "theme"
else
    zsh_setup::plugins::installer::install "$PLUGIN_NAME" "$plugin_type" "$plugin_url"
fi
WORKER_EOF
        chmod +x "$worker_script"
        
        # Use xargs -P or GNU parallel
        if command -v parallel &>/dev/null; then
            printf '%s\n' "${parallel_plugins[@]}" | \
                parallel -j "$max_parallel" --tag "$worker_script" "$ZSH_SETUP_ROOT" {}
        else
            printf '%s\n' "${parallel_plugins[@]}" | \
                xargs -P "$max_parallel" -I {} "$worker_script" "$ZSH_SETUP_ROOT" "{}"
        fi
        
        rm -f "$worker_script"
    fi
    
    # Install Homebrew plugins sequentially
    if [[ ${#brew_plugins[@]} -gt 0 ]]; then
        zsh_setup::core::logger::info "Installing ${#brew_plugins[@]} Homebrew packages sequentially..."
        for plugin in "${brew_plugins[@]}"; do
            local plugin_url=$(zsh_setup::plugins::registry::get "$plugin" "url")
            zsh_setup::plugins::installer::install_brew "$plugin" "$plugin_url"
        done
    fi
}

# Show plugin selection menu
zsh_setup::plugins::manager::_show_selection_menu() {
    local plugins=()
    local root="${ZSH_SETUP_ROOT:-}"
    local plugins_file="${root}/plugins.conf"
    
    # Load plugins from config
    if [[ -f "$plugins_file" ]]; then
        while IFS='|' read -r name type url description; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            plugins+=("$description - $name|$name|$type")
        done < "$plugins_file"
    fi
    
    # Use fzf if available, otherwise fallback
    if command -v fzf &>/dev/null; then
        local height=$((${#plugins[@]} + 2))
        height=$((height > 20 ? 20 : height))
        printf '%s\n' "${plugins[@]}" | cut -d'|' -f1 | fzf --multi --height="$height"
    else
        # Basic menu
        echo "Select plugins to install (comma-separated numbers, or 'all'):"
        local i=1
        for entry in "${plugins[@]}"; do
            local desc=$(echo "$entry" | cut -d'|' -f1)
            echo "$i) $desc"
            ((i++))
        done
        
        read -r choice
        if [[ "$choice" == "all" ]]; then
            printf '%s\n' "${plugins[@]}" | cut -d'|' -f1
        else
            local selected=""
            IFS=',' read -ra nums <<<"$choice"
            for num in "${nums[@]}"; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#plugins[@]} ]]; then
                    local entry="${plugins[$((num - 1))]}"
                    selected+="$(echo "$entry" | cut -d'|' -f1)"$'\n'
                fi
            done
            echo "$selected"
        fi
    fi
}

# Backward compatibility
install_plugins() {
    zsh_setup::plugins::manager::install_list "$@"
}
