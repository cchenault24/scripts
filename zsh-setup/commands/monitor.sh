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
        *)
            zsh_setup::commands::monitor::_profile_startup
            ;;
    esac
}

zsh_setup::commands::monitor::_profile_startup() {
    zsh_setup::core::logger::info "Profiling Zsh startup time..."
    
    local zshrc_path=$(zsh_setup::core::config::get zshrc_path)
    if [[ ! -f "$zshrc_path" ]]; then
        zsh_setup::core::logger::error ".zshrc not found"
        return 1
    fi
    
    # Measure startup time
    local start_time=$(date +%s.%N)
    zsh -i -c exit 2>/dev/null
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    
    zsh_setup::core::logger::info "Zsh startup time: ${duration}s"
}
