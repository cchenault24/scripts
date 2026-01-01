#!/usr/bin/env bash

#==============================================================================
# monitor.sh - Zsh Setup Monitoring and Diagnostics
#
# Provides comprehensive monitoring, profiling, and health checks
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
# Startup Time Profiling
#------------------------------------------------------------------------------

# Profile zsh startup time
profile_startup_time() {
    log_section "Zsh Startup Time Profiling"
    
    local temp_zshrc=$(mktemp)
    local profile_output=$(mktemp)
    
    # Create a test zshrc that includes profiling
    cat > "$temp_zshrc" <<'PROFILE_EOF'
# Enable profiling
zmodload zsh/zprof

# Source actual zshrc
if [[ -f ~/.zshrc ]]; then
    source ~/.zshrc
fi

# Output profile
zprof > /tmp/zsh_profile_output.txt
PROFILE_EOF
    
    log_info "Measuring zsh startup time..."
    
    # Measure startup time
    local start_time=$(date +%s.%N)
    zsh -c "source $temp_zshrc" 2>/dev/null
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || \
                     awk "BEGIN {print $end_time - $start_time}")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Startup Time: ${duration}s"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Show detailed profile if available
    if [[ -f /tmp/zsh_profile_output.txt ]]; then
        log_info "Detailed function timing:"
        head -20 /tmp/zsh_profile_output.txt
        rm -f /tmp/zsh_profile_output.txt
    fi
    
    rm -f "$temp_zshrc"
    
    # Categorize performance
    local duration_int=$(echo "$duration" | cut -d. -f1)
    if [[ $duration_int -lt 1 ]]; then
        log_success "Excellent startup time (< 1s)"
    elif [[ $duration_int -lt 2 ]]; then
        log_info "Good startup time (< 2s)"
    elif [[ $duration_int -lt 5 ]]; then
        log_warn "Moderate startup time (< 5s) - consider optimization"
    else
        log_error "Slow startup time (>= 5s) - optimization recommended"
    fi
}

#------------------------------------------------------------------------------
# Plugin Performance Monitoring
#------------------------------------------------------------------------------

# Monitor plugin load times
monitor_plugin_performance() {
    log_section "Plugin Performance Monitoring"
    
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    if [[ ${#installed_plugins[@]} -eq 0 ]]; then
        log_info "No plugins installed"
        return 0
    fi
    
    log_info "Monitoring ${#installed_plugins[@]} plugins..."
    echo ""
    
    declare -A plugin_times
    local total_time=0
    
    for plugin in "${installed_plugins[@]}"; do
        local plugin_file=""
        
        # Find plugin file
        if [[ -f "$CUSTOM_PLUGINS_DIR/$plugin/$plugin.plugin.zsh" ]]; then
            plugin_file="$CUSTOM_PLUGINS_DIR/$plugin/$plugin.plugin.zsh"
        elif [[ -f "$CUSTOM_PLUGINS_DIR/$plugin/$plugin.zsh" ]]; then
            plugin_file="$CUSTOM_PLUGINS_DIR/$plugin/$plugin.zsh"
        elif [[ -f "$CUSTOM_THEMES_DIR/$plugin/$plugin.zsh-theme" ]]; then
            plugin_file="$CUSTOM_THEMES_DIR/$plugin/$plugin.zsh-theme"
        fi
        
        if [[ -z "$plugin_file" || ! -f "$plugin_file" ]]; then
            log_debug "Plugin file not found for $plugin"
            continue
        fi
        
        # Measure load time
        local start=$(date +%s.%N)
        zsh -c "source $plugin_file" 2>/dev/null
        local end=$(date +%s.%N)
        local load_time=$(echo "$end - $start" | bc 2>/dev/null || \
                          awk "BEGIN {print $end - $start}")
        
        plugin_times["$plugin"]="$load_time"
        total_time=$(echo "$total_time + $load_time" | bc 2>/dev/null || \
                     awk "BEGIN {print $total_time + $load_time}")
    done
    
    # Sort by load time
    echo "Plugin Load Times:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %10s\n" "Plugin" "Load Time"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for plugin in "${!plugin_times[@]}"; do
        local time="${plugin_times[$plugin]}"
        printf "%-30s %10.3fs\n" "$plugin" "$time"
    done | sort -k2 -rn
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %10.3fs\n" "Total" "$total_time"
    echo ""
    
    # Identify slow plugins
    local slow_plugins=()
    for plugin in "${!plugin_times[@]}"; do
        local time="${plugin_times[$plugin]}"
        local time_int=$(echo "$time" | cut -d. -f1)
        if [[ $time_int -ge 1 ]]; then
            slow_plugins+=("$plugin: ${time}s")
        fi
    done
    
    if [[ ${#slow_plugins[@]} -gt 0 ]]; then
        log_warn "Slow-loading plugins detected:"
        for plugin_info in "${slow_plugins[@]}"; do
            echo "  - $plugin_info"
        done
    fi
}

#------------------------------------------------------------------------------
# Conflict Detection
#------------------------------------------------------------------------------

# Detect plugin conflicts
detect_conflicts() {
    log_section "Plugin Conflict Detection"
    
    # Known conflict patterns
    declare -A conflict_groups=(
        ["cd_enhancers"]="autojump zoxide z"
        ["syntax_highlighters"]="zsh-syntax-highlighting"
        ["completion_systems"]="zsh-completions"
        ["history_searchers"]="zsh-history-substring-search history-substring-search"
    )
    
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    local conflicts_found=0
    
    for group in "${!conflict_groups[@]}"; do
        local group_plugins="${conflict_groups[$group]}"
        local found_plugins=()
        
        for plugin in "${installed_plugins[@]}"; do
            if echo "$group_plugins" | grep -q "\b$plugin\b"; then
                found_plugins+=("$plugin")
            fi
        done
        
        if [[ ${#found_plugins[@]} -gt 1 ]]; then
            log_warn "Potential conflict in $group:"
            for plugin in "${found_plugins[@]}"; do
                echo "  - $plugin"
            done
            ((conflicts_found++))
        fi
    done
    
    if [[ $conflicts_found -eq 0 ]]; then
        log_success "No plugin conflicts detected"
    else
        log_warn "Found $conflicts_found potential conflict(s)"
    fi
}

#------------------------------------------------------------------------------
# Config Linting
#------------------------------------------------------------------------------

# Lint .zshrc configuration
lint_zshrc() {
    log_section ".zshrc Configuration Linting"
    
    local zshrc="$ZSHRC_PATH"
    local issues=0
    
    if [[ ! -f "$zshrc" ]]; then
        log_error ".zshrc file not found"
        return 1
    fi
    
    log_info "Validating .zshrc syntax..."
    
    # Check syntax
    if ! zsh -n "$zshrc" 2>/dev/null; then
        log_error "Syntax errors found in .zshrc"
        zsh -n "$zshrc" 2>&1 | head -10
        ((issues++))
    else
        log_success "Syntax is valid"
    fi
    
    echo ""
    log_info "Checking for common issues..."
    
    # Check for deprecated options
    if grep -q "DISABLE_AUTO_UPDATE" "$zshrc"; then
        log_warn "Found DISABLE_AUTO_UPDATE (consider using UPDATE_ZSH_DAYS instead)"
        ((issues++))
    fi
    
    # Check for plugin references that don't exist
    local installed_plugins=()
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    if grep -q "plugins=(" "$zshrc"; then
        local plugins_line=$(grep "plugins=(" "$zshrc" | head -1)
        local plugins_in_config=$(echo "$plugins_line" | grep -o '[a-zA-Z0-9_-]\+' | grep -v "plugins")
        
        for plugin in $plugins_in_config; do
            if ! printf '%s\n' "${installed_plugins[@]}" | grep -q "^${plugin}$"; then
                if [[ ! -d "$OH_MY_ZSH_DIR/plugins/$plugin" ]]; then
                    log_warn "Plugin '$plugin' referenced in .zshrc but not installed"
                    ((issues++))
                fi
            fi
        done
    fi
    
    # Check for best practices
    if ! grep -q "ZSH_THEME" "$zshrc"; then
        log_warn "No theme specified in .zshrc"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "No issues found in .zshrc"
    else
        log_warn "Found $issues issue(s) in .zshrc"
    fi
}

#------------------------------------------------------------------------------
# Dependency Health Checks
#------------------------------------------------------------------------------

# Check dependency health
check_dependencies() {
    log_section "Dependency Health Check"
    
    local issues=0
    local installed_plugins=()
    
    while IFS= read -r plugin; do
        [[ -n "$plugin" ]] && installed_plugins+=("$plugin")
    done < <(get_installed_plugins 2>/dev/null)
    
    # Load dependency config
    local deps_file="${SCRIPT_DIR}/plugin_dependencies.conf"
    if [[ ! -f "$deps_file" ]]; then
        log_info "No dependency configuration found"
        return 0
    fi
    
    log_info "Checking dependencies for ${#installed_plugins[@]} plugins..."
    
    # Check each plugin's dependencies
    while IFS='=' read -r plugin_name deps; do
        [[ -z "$plugin_name" || "$plugin_name" =~ ^# ]] && continue
        
        # Check if plugin is installed
        if ! printf '%s\n' "${installed_plugins[@]}" | grep -q "^${plugin_name}$"; then
            continue
        fi
        
        # Check each dependency
        IFS=',' read -ra dep_array <<<"$deps"
        for dep in "${dep_array[@]}"; do
            dep=$(echo "$dep" | xargs)
            [[ -z "$dep" ]] && continue
            
            # Check if dependency is a system package
            if command -v map_plugin_to_package &>/dev/null; then
                local package=$(map_plugin_to_package "$dep")
                if ! is_package_installed "$package"; then
                    log_warn "Missing dependency for $plugin_name: $dep ($package)"
                    ((issues++))
                fi
            fi
            
            # Check if dependency is another plugin
            if ! printf '%s\n' "${installed_plugins[@]}" | grep -q "^${dep}$"; then
                if [[ ! -d "$OH_MY_ZSH_DIR/plugins/$dep" ]]; then
                    log_warn "Missing plugin dependency for $plugin_name: $dep"
                    ((issues++))
                fi
            fi
        done
    done < "$deps_file"
    
    # Check plugin file structure
    for plugin in "${installed_plugins[@]}"; do
        local plugin_dir=""
        if [[ -d "$CUSTOM_PLUGINS_DIR/$plugin" ]]; then
            plugin_dir="$CUSTOM_PLUGINS_DIR/$plugin"
        elif [[ -d "$CUSTOM_THEMES_DIR/$plugin" ]]; then
            plugin_dir="$CUSTOM_THEMES_DIR/$plugin"
        fi
        
        if [[ -n "$plugin_dir" ]]; then
            # Check for main plugin file
            if [[ ! -f "$plugin_dir/$plugin.plugin.zsh" ]] && \
               [[ ! -f "$plugin_dir/$plugin.zsh" ]] && \
               [[ ! -f "$plugin_dir/$plugin.zsh-theme" ]]; then
                log_warn "Plugin $plugin may be missing main file"
                ((issues++))
            fi
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_success "All dependencies are healthy"
    else
        log_warn "Found $issues dependency issue(s)"
    fi
}

#------------------------------------------------------------------------------
# Main Monitoring Function
#------------------------------------------------------------------------------

# Run all monitoring checks
run_all_checks() {
    log_section "Comprehensive Zsh Setup Monitoring"
    
    profile_startup_time
    echo ""
    
    monitor_plugin_performance
    echo ""
    
    detect_conflicts
    echo ""
    
    lint_zshrc
    echo ""
    
    check_dependencies
    echo ""
    
    log_section "Monitoring Complete"
}

# Main function
main() {
    local check_type="${1:-all}"
    
    case "$check_type" in
        startup|startup-time)
            profile_startup_time
            ;;
        performance|plugin-performance)
            monitor_plugin_performance
            ;;
        conflicts)
            detect_conflicts
            ;;
        lint|config)
            lint_zshrc
            ;;
        dependencies|deps)
            check_dependencies
            ;;
        all|*)
            run_all_checks
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
