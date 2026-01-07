#!/usr/bin/env bash

#==============================================================================
# monitor.sh - Monitor Command
#
# Runs monitoring and diagnostics
#==============================================================================

# Load required modules
zsh_setup::core::bootstrap::load_modules \
    core::config \
    core::logger || exit 1

zsh_setup::commands::monitor::execute() {
    local monitor_type="${1:-all}"
    
    case "$monitor_type" in
        startup|startup-time)
            zsh_setup::commands::monitor::_profile_startup
            ;;
        plugins|plugin-times)
            zsh_setup::commands::monitor::_profile_plugins
            ;;
        dashboard|report)
            zsh_setup::commands::monitor::_show_dashboard
            ;;
        all|*)
            zsh_setup::commands::monitor::_show_dashboard
            ;;
    esac
}

zsh_setup::commands::monitor::_profile_startup() {
    zsh_setup::core::logger::info "Profiling Zsh startup time..."
    
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ ! -f "$zshrc_path" ]]; then
        zsh_setup::core::bootstrap::load_module "core::errors"
        zsh_setup::core::errors::handle 1 "Monitor startup time" \
            ".zshrc file not found at $zshrc_path. Run 'zsh-setup install' first."
        return 1
    fi
    
    # Measure startup time
    local start_time=$(date +%s.%N)
    zsh -i -c exit 2>/dev/null
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    
    zsh_setup::core::logger::info "Zsh startup time: ${duration}s"
}

# Profile plugin load times
zsh_setup::commands::monitor::_profile_plugins() {
    zsh_setup::core::logger::section "Plugin Performance Analysis"
    
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ ! -f "$zshrc_path" ]]; then
        zsh_setup::core::bootstrap::load_module "core::errors"
        zsh_setup::core::errors::handle 1 "Monitor plugin times" \
            ".zshrc file not found. Run 'zsh-setup install' first."
        return 1
    fi
    
    zsh_setup::core::logger::info "Profiling plugin load times..."
    echo ""
    
    # Extract plugins from .zshrc
    local plugins=()
    if grep -q "plugins=(" "$zshrc_path"; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*[^#]*\"([^\"]+)\" ]] && plugins+=("${BASH_REMATCH[1]}")
        done < <(grep "plugins=(" "$zshrc_path" | head -1)
    fi
    
    if [[ ${#plugins[@]} -eq 0 ]]; then
        zsh_setup::core::logger::warn "No plugins found in .zshrc"
        return 1
    fi
    
    zsh_setup::core::logger::info "Found ${#plugins[@]} plugins to profile"
    echo ""
    
    # Profile each plugin (simplified - would need zsh profiling for accurate times)
    for plugin in "${plugins[@]}"; do
        zsh_setup::core::logger::info "  → $plugin"
    done
    
    echo ""
    zsh_setup::core::logger::info "Note: Accurate plugin timing requires zsh profiling. Use 'zsh -x' for detailed analysis."
}

# Show performance dashboard
zsh_setup::commands::monitor::_show_dashboard() {
    zsh_setup::core::logger::section "Zsh Setup Performance Dashboard"
    echo ""
    
    # Overall startup time
    zsh_setup::commands::monitor::_profile_startup
    echo ""
    
    # Plugin information
    zsh_setup::core::bootstrap::load_module "core::state"
    local installed_count=0
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && ((installed_count++))
    done < <(zsh_setup::state::store::get_installed_plugins 2>/dev/null)
    
    zsh_setup::core::logger::info "Installed plugins: $installed_count"
    
    # System information
    echo ""
    zsh_setup::core::logger::section "System Information"
    zsh_setup::core::logger::info "Zsh version: $(zsh --version 2>/dev/null | head -n1 || echo "unknown")"
    zsh_setup::core::logger::info "Oh My Zsh: $([ -d "$(zsh_setup::core::config::get oh_my_zsh_dir)" ] && echo "installed" || echo "not installed")"
    
    # Configuration status
    echo ""
    zsh_setup::core::logger::section "Configuration Status"
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ -f "$zshrc_path" ]]; then
        local zshrc_size=$(wc -l < "$zshrc_path" 2>/dev/null || echo "0")
        zsh_setup::core::logger::info ".zshrc: $zshrc_size lines"
    else
        zsh_setup::core::logger::warn ".zshrc: not found"
    fi
    
    echo ""
    zsh_setup::core::logger::info "For detailed plugin timing, run: zsh-setup monitor plugins"
    zsh_setup::core::logger::info "For startup profiling, run: zsh-setup monitor startup"
}
