#!/usr/bin/env bash

#==============================================================================
# manager.sh - Plugin Manager
#
# Orchestrates plugin installation, updates, and removal
#==============================================================================

# Load dependencies
# Note: This module can be loaded via bootstrap or sourced directly
# When loaded via bootstrap, dependencies are already available
# When sourced directly, we load them here
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    # Use bootstrap if available, otherwise source directly
    if declare -f zsh_setup::core::bootstrap::load_module &>/dev/null; then
        zsh_setup::core::bootstrap::load_module "core::config" || source "$ZSH_SETUP_ROOT/lib/core/config.sh"
        zsh_setup::core::bootstrap::load_module "core::logger" || source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
        zsh_setup::core::bootstrap::load_module "plugins::registry" || source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
        zsh_setup::core::bootstrap::load_module "plugins::resolver" || source "$ZSH_SETUP_ROOT/lib/plugins/resolver.sh"
        zsh_setup::core::bootstrap::load_module "plugins::installer" || source "$ZSH_SETUP_ROOT/lib/plugins/installer.sh"
        zsh_setup::core::bootstrap::load_module "system::package_manager" || source "$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
    else
        source "$ZSH_SETUP_ROOT/lib/core/config.sh"
        source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
        source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh"
        source "$ZSH_SETUP_ROOT/lib/plugins/resolver.sh"
        source "$ZSH_SETUP_ROOT/lib/plugins/installer.sh"
        source "$ZSH_SETUP_ROOT/lib/system/package_manager.sh"
    fi
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
        local total=${#parallel_plugins[@]}
        
        # Load progress module
        if [[ -n "${ZSH_SETUP_ROOT:-}" ]] && [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
            source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
        fi
        
        # Initialize progress bar
        if declare -f zsh_setup::core::progress::bar_init &>/dev/null; then
            zsh_setup::core::progress::bar_init "$total" "Installing plugins"
        else
            zsh_setup::core::logger::info "Installing ${#parallel_plugins[@]} plugins in parallel (max $max_parallel concurrent)..."
        fi
        
        # Create worker script (reusable)
        local worker_script=$(mktemp -t zsh_setup_worker.XXXXXX.sh)
        # #region agent log
        echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\",\"location\":\"manager.sh:95\",\"message\":\"Creating worker script\",\"data\":{\"worker_script\":\"$worker_script\",\"plugin_count\":${#parallel_plugins[@]}},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
        # #endregion
        cat > "$worker_script" <<'WORKER_EOF'
#!/usr/bin/env bash
set +e  # Don't exit on error, we'll handle it
ZSH_SETUP_ROOT="$1"
PLUGIN_NAME="$2"
LOG_FILE="${3:-/tmp/zsh_setup_${PLUGIN_NAME}_$$.log}"

# #region agent log
echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"A\",\"location\":\"worker_script:start\",\"message\":\"Worker script started\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\",\"bash_version\":\"$(bash --version | head -1)\",\"script_type\":\"standalone\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
# #endregion

# Export for subprocesses
export ZSH_SETUP_ROOT

# Source bootstrap and initialize
if ! source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh" 2>>"$LOG_FILE"; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\",\"location\":\"worker_script:bootstrap_load\",\"message\":\"Bootstrap load failed\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Failed to load bootstrap.sh" >> "$LOG_FILE"
    exit 1
fi

if ! zsh_setup::core::bootstrap::init 2>>"$LOG_FILE"; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\",\"location\":\"worker_script:bootstrap_init\",\"message\":\"Bootstrap init failed\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Failed to initialize bootstrap" >> "$LOG_FILE"
    exit 1
fi

# Load required modules
if ! source "$ZSH_SETUP_ROOT/lib/plugins/registry.sh" 2>>"$LOG_FILE"; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\",\"location\":\"worker_script:registry_load\",\"message\":\"Registry load failed\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Failed to load registry.sh" >> "$LOG_FILE"
    exit 1
fi

if ! source "$ZSH_SETUP_ROOT/lib/plugins/installer.sh" 2>>"$LOG_FILE"; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\",\"location\":\"worker_script:installer_load\",\"message\":\"Installer load failed\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Failed to load installer.sh" >> "$LOG_FILE"
    exit 1
fi

# Load plugin registry
if ! zsh_setup::plugins::registry::load 2>>"$LOG_FILE"; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"B\",\"location\":\"worker_script:registry_load_func\",\"message\":\"Registry load function failed\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Failed to load plugin registry" >> "$LOG_FILE"
    exit 1
fi

# Get plugin info
# #region agent log
echo "{\"sessionId\":\"debug-session\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"worker_script:before_vars\",\"message\":\"Before variable declarations\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\",\"line\":135},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
# #endregion
plugin_type=$(zsh_setup::plugins::registry::get "$PLUGIN_NAME" "type" 2>>"$LOG_FILE")
# #region agent log
echo "{\"sessionId\":\"debug-session\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"worker_script:after_first_var\",\"message\":\"After first variable\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\",\"plugin_type\":\"$plugin_type\",\"line\":136},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
# #endregion
plugin_url=$(zsh_setup::plugins::registry::get "$PLUGIN_NAME" "url" 2>>"$LOG_FILE")

if [[ -z "$plugin_type" ]]; then
    # #region agent log
    echo "{\"sessionId\":\"debug-session\",\"runId\":\"post-fix\",\"hypothesisId\":\"C\",\"location\":\"worker_script:empty_plugin_type\",\"message\":\"Plugin type is empty\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\"},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
    # #endregion
    echo "ERROR: Could not determine plugin type for $PLUGIN_NAME" >> "$LOG_FILE"
    exit 1
fi

# Install plugin
# #region agent log
echo "{\"sessionId\":\"debug-session\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"worker_script:before_exit_code\",\"message\":\"Before exit_code variable\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\",\"line\":144},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
# #endregion
exit_code=0
if [[ "$PLUGIN_NAME" == "powerlevel10k" ]]; then
    if ! zsh_setup::plugins::installer::install_git "$PLUGIN_NAME" "$plugin_url" "theme" >>"$LOG_FILE" 2>&1; then
        exit_code=1
    fi
else
    if ! zsh_setup::plugins::installer::install "$PLUGIN_NAME" "$plugin_type" "$plugin_url" >>"$LOG_FILE" 2>&1; then
        exit_code=1
    fi
fi

# #region agent log
echo "{\"sessionId\":\"debug-session\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"worker_script:before_exit\",\"message\":\"Before exit\",\"data\":{\"plugin_name\":\"$PLUGIN_NAME\",\"exit_code\":$exit_code},\"timestamp\":$(date +%s000)}" >> /Users/chenaultfamily/Documents/coding/scripts/.cursor/debug.log 2>/dev/null || true
# #endregion
exit $exit_code
WORKER_EOF
        chmod +x "$worker_script"
        
        # Track progress and errors
        local completed=0
        local failed=0
        local failed_plugins=()
        local total=${#parallel_plugins[@]}
        local pids=()
        local plugins_by_pid=""  # Format: "pid:plugin:log|pid:plugin:log|..."
        
        # Install plugins in parallel using background processes
        for plugin in "${parallel_plugins[@]}"; do
            local log_file="/tmp/zsh_setup_${plugin}_$$.log"
            
            # Run worker in background
            "$worker_script" "$ZSH_SETUP_ROOT" "$plugin" "$log_file" &
            local pid=$!
            pids+=("$pid")
            if [[ -z "$plugins_by_pid" ]]; then
                plugins_by_pid="${pid}:${plugin}:${log_file}"
            else
                plugins_by_pid="${plugins_by_pid}|${pid}:${plugin}:${log_file}"
            fi
            
            # Limit concurrent jobs - wait for one to finish if we're at max
            while [[ ${#pids[@]} -ge $max_parallel ]]; do
                # Check which processes have finished
                local finished_pid=""
                local finished_idx=-1
                local idx=0
                for pid in "${pids[@]}"; do
                    if ! kill -0 "$pid" 2>/dev/null; then
                        finished_pid="$pid"
                        finished_idx=$idx
                        break
                    fi
                    ((idx++))
                done
                
                if [[ -n "$finished_pid" ]]; then
                    # Wait for the finished process and get exit code
                    wait "$finished_pid"
                    local exit_code=$?
                    
                    # Extract plugin and log from plugins_by_pid
                    local plugin=""
                    local log_file=""
                    local remaining_info=""
                    local found=0
                    for entry in $(echo "$plugins_by_pid" | tr '|' ' '); do
                        IFS=':' read -r entry_pid entry_plugin entry_log <<< "$entry"
                        if [[ "$entry_pid" == "$finished_pid" ]]; then
                            plugin="$entry_plugin"
                            log_file="$entry_log"
                            found=1
                        else
                            if [[ -z "$remaining_info" ]]; then
                                remaining_info="$entry"
                            else
                                remaining_info="${remaining_info}|${entry}"
                            fi
                        fi
                    done
                    plugins_by_pid="$remaining_info"
                    
                    if [[ $exit_code -eq 0 ]]; then
                        ((completed++))
                        if declare -f zsh_setup::core::progress::bar_increment &>/dev/null; then
                            zsh_setup::core::progress::bar_increment 1 "✓ $plugin installed"
                        else
                            zsh_setup::core::logger::info "[$completed/$total] ✓ $plugin installed"
                        fi
                        rm -f "$log_file"
                    else
                        ((failed++))
                        failed_plugins+=("$plugin")
                        if declare -f zsh_setup::core::progress::status_line &>/dev/null; then
                            zsh_setup::core::progress::status_line "✗ $plugin failed (check $log_file)"
                        else
                            zsh_setup::core::logger::error "[$completed/$total] ✗ $plugin failed (check $log_file)"
                        fi
                    fi
                    
                    # Remove from pids array
                    local new_pids=()
                    for p in "${pids[@]}"; do
                        [[ "$p" != "$finished_pid" ]] && new_pids+=("$p")
                    done
                    pids=("${new_pids[@]}")
                    break
                else
                    # No process finished yet, wait a bit
                    sleep 0.2
                fi
            done
        done
        
        # Wait for all remaining processes
        for pid in "${pids[@]}"; do
            wait "$pid"
            local exit_code=$?
            
            # Extract plugin and log from plugins_by_pid
            local plugin=""
            local log_file=""
            for entry in $(echo "$plugins_by_pid" | tr '|' ' '); do
                IFS=':' read -r entry_pid entry_plugin entry_log <<< "$entry"
                if [[ "$entry_pid" == "$pid" ]]; then
                    plugin="$entry_plugin"
                    log_file="$entry_log"
                    break
                fi
            done
            
            if [[ $exit_code -eq 0 ]]; then
                ((completed++))
                if declare -f zsh_setup::core::progress::bar_increment &>/dev/null; then
                    zsh_setup::core::progress::bar_increment 1 "✓ $plugin installed"
                else
                    zsh_setup::core::logger::info "[$completed/$total] ✓ $plugin installed"
                fi
                rm -f "$log_file"
            else
                ((failed++))
                failed_plugins+=("$plugin")
                if declare -f zsh_setup::core::progress::status_line &>/dev/null; then
                    zsh_setup::core::progress::status_line "✗ $plugin failed (check $log_file)"
                else
                    zsh_setup::core::logger::error "[$completed/$total] ✗ $plugin failed (check $log_file)"
                fi
            fi
        done
        
        # Cleanup and report
        rm -f "$worker_script"
        
        # Complete progress bar if it was initialized
        if declare -f zsh_setup::core::progress::bar_complete &>/dev/null && [[ -n "${ZSH_SETUP_PROGRESS_TOTAL:-}" ]]; then
            if [[ $failed -eq 0 ]]; then
                zsh_setup::core::progress::bar_complete "All plugins installed"
            fi
        fi
        
        if [[ $failed -gt 0 ]]; then
            zsh_setup::core::logger::warn "Installation complete: $completed succeeded, $failed failed"
            zsh_setup::core::logger::info "Failed plugins: ${failed_plugins[*]}"
            return 1
        else
            zsh_setup::core::logger::success "All $completed plugins installed successfully"
        fi
    fi
    
    # Install Homebrew plugins sequentially
    if [[ ${#brew_plugins[@]} -gt 0 ]]; then
        local brew_total=${#brew_plugins[@]}
        local brew_completed=0
        
        # Load progress module if not already loaded
        if [[ -n "${ZSH_SETUP_ROOT:-}" ]] && [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
            source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
        fi
        
        # Initialize progress bar for brew packages
        if declare -f zsh_setup::core::progress::bar_init &>/dev/null; then
            zsh_setup::core::progress::bar_init "$brew_total" "Installing Homebrew packages"
        else
            zsh_setup::core::logger::info "Installing ${#brew_plugins[@]} Homebrew packages sequentially..."
        fi
        
        for plugin in "${brew_plugins[@]}"; do
            local plugin_url=$(zsh_setup::plugins::registry::get "$plugin" "url")
            if zsh_setup::plugins::installer::install_brew "$plugin" "$plugin_url"; then
                ((brew_completed++))
                if declare -f zsh_setup::core::progress::bar_increment &>/dev/null; then
                    zsh_setup::core::progress::bar_increment 1 "✓ $plugin installed"
                fi
            fi
        done
        
        # Complete progress bar
        if declare -f zsh_setup::core::progress::bar_complete &>/dev/null && [[ -n "${ZSH_SETUP_PROGRESS_TOTAL:-}" ]]; then
            zsh_setup::core::progress::bar_complete "Homebrew packages installed"
        fi
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

