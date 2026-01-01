#!/usr/bin/env bash

#==============================================================================
# validate_config.sh - Configuration File Validation
#
# Validates plugins.conf and plugin_dependencies.conf files
#==============================================================================

# Load required utilities
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

# Validate plugins.conf file
validate_plugins_config() {
    local config_file="${1:-$SCRIPT_DIR/plugins.conf}"
    local errors=0
    local warnings=0
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Plugins configuration file not found: $config_file"
        return 1
    fi
    
    log_info "Validating plugins configuration: $config_file"
    
    local line_num=0
    local plugin_names=()
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Validate format: name|type|url|description
        if ! [[ "$line" =~ ^[^|]+\|[^|]+\|[^|]+\|.+$ ]]; then
            log_error "Line $line_num: Invalid format. Expected: name|type|url|description"
            ((errors++))
            continue
        fi
        
        IFS='|' read -r name type url description <<<"$line"
        
        # Trim whitespace
        name=$(echo "$name" | xargs)
        type=$(echo "$type" | xargs)
        url=$(echo "$url" | xargs)
        description=$(echo "$description" | xargs)
        
        # Validate plugin name
        if [[ -z "$name" ]]; then
            log_error "Line $line_num: Plugin name is empty"
            ((errors++))
        elif [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log_warn "Line $line_num: Plugin name '$name' contains unusual characters"
            ((warnings++))
        fi
        
        # Check for duplicate plugin names
        if printf '%s\n' "${plugin_names[@]}" | grep -q "^$name$"; then
            log_error "Line $line_num: Duplicate plugin name: $name"
            ((errors++))
        else
            plugin_names+=("$name")
        fi
        
        # Validate type
        case "$type" in
            git|brew|omz|npm)
                # Valid type
                ;;
            *)
                log_error "Line $line_num: Invalid plugin type '$type'. Must be: git, brew, omz, or npm"
                ((errors++))
                ;;
        esac
        
        # Validate URL for git type
        if [[ "$type" == "git" ]]; then
            if [[ -z "$url" ]]; then
                log_warn "Line $line_num: Git plugin '$name' has no URL (will use default)"
                ((warnings++))
            elif [[ ! "$url" =~ ^https?:// ]] && [[ ! "$url" =~ ^git@ ]]; then
                log_error "Line $line_num: Invalid URL format for git plugin '$name': $url"
                ((errors++))
            fi
        fi
        
        # Validate package name for brew type
        if [[ "$type" == "brew" ]]; then
            if [[ -z "$url" ]]; then
                log_error "Line $line_num: Brew plugin '$name' requires a package name"
                ((errors++))
            fi
        fi
        
        # Validate description
        if [[ -z "$description" ]]; then
            log_warn "Line $line_num: Plugin '$name' has no description"
            ((warnings++))
        fi
        
    done < "$config_file"
    
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        log_success "Plugins configuration is valid ($line_num lines checked)"
        return 0
    elif [[ $errors -eq 0 ]]; then
        log_warn "Plugins configuration has $warnings warning(s) but is usable"
        return 0
    else
        log_error "Plugins configuration has $errors error(s) and $warnings warning(s)"
        return 1
    fi
}

# Validate plugin_dependencies.conf file
validate_dependencies_config() {
    local deps_file="${1:-$SCRIPT_DIR/plugin_dependencies.conf}"
    local plugins_file="${2:-$SCRIPT_DIR/plugins.conf}"
    local errors=0
    local warnings=0
    
    if [[ ! -f "$deps_file" ]]; then
        log_warn "Dependencies configuration file not found: $deps_file (optional)"
        return 0
    fi
    
    log_info "Validating dependencies configuration: $deps_file"
    
    # Build list of valid plugin names from plugins.conf
    local valid_plugins=()
    if [[ -f "$plugins_file" ]]; then
        while IFS='|' read -r name _ _ _; do
            [[ -n "$name" && ! "$name" =~ ^[[:space:]]*# ]] && valid_plugins+=("$(echo "$name" | xargs)")
        done < "$plugins_file"
    fi
    
    local line_num=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Validate format: plugin=dependency1,dependency2,...
        if ! [[ "$line" =~ ^[^=]+=.+$ ]]; then
            log_error "Line $line_num: Invalid format. Expected: plugin=dependency1,dependency2,..."
            ((errors++))
            continue
        fi
        
        local plugin_name="${line%%=*}"
        local dependencies="${line#*=}"
        
        plugin_name=$(echo "$plugin_name" | xargs)
        dependencies=$(echo "$dependencies" | xargs)
        
        # Validate plugin name exists in plugins.conf
        if [[ ${#valid_plugins[@]} -gt 0 ]]; then
            if ! printf '%s\n' "${valid_plugins[@]}" | grep -q "^${plugin_name}$"; then
                log_warn "Line $line_num: Plugin '$plugin_name' not found in plugins.conf"
                ((warnings++))
            fi
        fi
        
        # Validate dependencies
        IFS=',' read -ra deps_array <<<"$dependencies"
        for dep in "${deps_array[@]}"; do
            dep=$(echo "$dep" | xargs)
            [[ -z "$dep" ]] && continue
            
            # Check if dependency is a valid plugin
            if [[ ${#valid_plugins[@]} -gt 0 ]]; then
                if ! printf '%s\n' "${valid_plugins[@]}" | grep -q "^${dep}$"; then
                    log_warn "Line $line_num: Dependency '$dep' for plugin '$plugin_name' not found in plugins.conf"
                    ((warnings++))
                fi
            fi
            
            # Check for self-dependency
            if [[ "$dep" == "$plugin_name" ]]; then
                log_error "Line $line_num: Plugin '$plugin_name' depends on itself (circular dependency)"
                ((errors++))
            fi
        done
        
    done < "$deps_file"
    
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        log_success "Dependencies configuration is valid"
        return 0
    elif [[ $errors -eq 0 ]]; then
        log_warn "Dependencies configuration has $warnings warning(s) but is usable"
        return 0
    else
        log_error "Dependencies configuration has $errors error(s) and $warnings warning(s)"
        return 1
    fi
}

# Validate all configuration files
validate_all_configs() {
    local script_dir="${1:-$SCRIPT_DIR}"
    local errors=0
    
    log_section "Validating Configuration Files"
    
    if ! validate_plugins_config "$script_dir/plugins.conf"; then
        ((errors++))
    fi
    
    if ! validate_dependencies_config "$script_dir/plugin_dependencies.conf" "$script_dir/plugins.conf"; then
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All configuration files are valid"
        return 0
    else
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_all_configs
    exit $?
fi
