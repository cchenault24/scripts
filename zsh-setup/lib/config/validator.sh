#!/usr/bin/env bash

#==============================================================================
# validator.sh - Configuration Validation
#
# Validates plugin configuration files
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
fi

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

# Validate plugins configuration
zsh_setup::config::validator::validate_plugins() {
    local config_file="${1:-$ZSH_SETUP_ROOT/plugins.conf}"
    local errors=0
    local warnings=0
    
    if [[ ! -f "$config_file" ]]; then
        zsh_setup::core::logger::error "Plugins configuration file not found: $config_file"
        return 1
    fi
    
    zsh_setup::core::logger::info "Validating plugins configuration: $config_file"
    
    local line_num=0
    local plugin_names=()
    
    while IFS= read -r line; do
        ((line_num++))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if ! [[ "$line" =~ ^[^|]+\|[^|]+\|[^|]+\|.+$ ]]; then
            zsh_setup::core::logger::error "Line $line_num: Invalid format. Expected: name|type|url|description"
            ((errors++))
            continue
        fi
        
        IFS='|' read -r name type url description <<<"$line"
        name=$(echo "$name" | xargs)
        type=$(echo "$type" | xargs)
        
        # Check for duplicates
        if printf '%s\n' "${plugin_names[@]}" | grep -q "^${name}$"; then
            zsh_setup::core::logger::error "Line $line_num: Duplicate plugin name: $name"
            ((errors++))
        else
            plugin_names+=("$name")
        fi
        
        # Validate type
        case "$type" in
            git|brew|omz|npm) ;;
            *)
                zsh_setup::core::logger::error "Line $line_num: Invalid plugin type '$type'. Must be: git, brew, omz, or npm"
                ((errors++))
                ;;
        esac
    done < "$config_file"
    
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        zsh_setup::core::logger::success "Plugins configuration is valid"
        return 0
    elif [[ $errors -eq 0 ]]; then
        zsh_setup::core::logger::warn "Plugins configuration has $warnings warning(s) but is usable"
        return 0
    else
        zsh_setup::core::logger::error "Plugins configuration has $errors error(s)"
        return 1
    fi
}

# Validate dependencies configuration
zsh_setup::config::validator::validate_dependencies() {
    local deps_file="${1:-$ZSH_SETUP_ROOT/plugin_dependencies.conf}"
    local plugins_file="${2:-$ZSH_SETUP_ROOT/plugins.conf}"
    local errors=0
    local warnings=0
    
    if [[ ! -f "$deps_file" ]]; then
        zsh_setup::core::logger::info "Dependencies configuration file not found (optional)"
        return 0
    fi
    
    zsh_setup::core::logger::info "Validating dependencies configuration: $deps_file"
    
    # Build list of valid plugins
    local valid_plugins=()
    if [[ -f "$plugins_file" ]]; then
        while IFS='|' read -r name _ _ _; do
            [[ -n "$name" && ! "$name" =~ ^[[:space:]]*# ]] && valid_plugins+=("$(echo "$name" | xargs)")
        done < "$plugins_file"
    fi
    
    local line_num=0
    while IFS= read -r line; do
        ((line_num++))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if ! [[ "$line" =~ ^[^=]+=.+$ ]]; then
            zsh_setup::core::logger::error "Line $line_num: Invalid format. Expected: plugin=dependency1,dependency2,..."
            ((errors++))
            continue
        fi
        
        local plugin_name="${line%%=*}"
        plugin_name=$(echo "$plugin_name" | xargs)
        
        # Check if plugin exists
        if [[ ${#valid_plugins[@]} -gt 0 ]]; then
            if ! printf '%s\n' "${valid_plugins[@]}" | grep -q "^${plugin_name}$"; then
                zsh_setup::core::logger::warn "Line $line_num: Plugin '$plugin_name' not found in plugins.conf"
                ((warnings++))
            fi
        fi
    done < "$deps_file"
    
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        zsh_setup::core::logger::success "Dependencies configuration is valid"
        return 0
    elif [[ $errors -eq 0 ]]; then
        zsh_setup::core::logger::warn "Dependencies configuration has $warnings warning(s) but is usable"
        return 0
    else
        zsh_setup::core::logger::error "Dependencies configuration has $errors error(s)"
        return 1
    fi
}

# Validate all configuration files
zsh_setup::config::validator::validate_all() {
    local root="${1:-$ZSH_SETUP_ROOT}"
    local errors=0
    
    zsh_setup::core::logger::section "Validating Configuration Files"
    
    if ! zsh_setup::config::validator::validate_plugins "$root/plugins.conf"; then
        ((errors++))
    fi
    
    if ! zsh_setup::config::validator::validate_dependencies "$root/plugin_dependencies.conf" "$root/plugins.conf"; then
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        zsh_setup::core::logger::success "All configuration files are valid"
        return 0
    else
        zsh_setup::core::logger::error "Configuration validation failed with $errors error(s)"
        return 1
    fi
}

