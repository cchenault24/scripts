#!/usr/bin/env bash

#==============================================================================
# shell.sh - Shell Management
#
# Provides functions for managing default shell
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/core/errors.sh"
    # Load progress module if available
    if [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
        source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
    fi
fi

#------------------------------------------------------------------------------
# Shell Management
#------------------------------------------------------------------------------

# Change the user's default shell to Zsh
zsh_setup::system::shell::change_default() {
    local spinner_pid=""
    if declare -f zsh_setup::core::progress::spinner_start &>/dev/null; then
        spinner_pid=$(zsh_setup::core::progress::spinner_start "Changing default shell to Zsh")
    else
        zsh_setup::core::logger::info "Changing default shell to Zsh..."
    fi
    
    local zsh_path=""
    for path in "/bin/zsh" "/usr/bin/zsh" "/usr/local/bin/zsh" "$(which zsh 2>/dev/null)"; do
        [[ -x "$path" ]] && {
            zsh_path="$path"
            break
        }
    done
    
    zsh_path="${zsh_path:-$(which zsh 2>/dev/null)}"
    
    # Check if Zsh is already the default shell
    if [[ "$SHELL" == "$zsh_path" ]]; then
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "Zsh is already the default shell. No changes needed." "" 0
        else
            zsh_setup::core::logger::info "Zsh is already the default shell. No changes needed."
        fi
        return 0
    fi
    
    # Check for privileges before attempting shell change
    zsh_setup::core::bootstrap::load_module "system::validation"
    if ! zsh_setup::system::validation::has_privileges; then
        zsh_setup::core::logger::warn "No sudo/admin privileges detected. Skipping shell change."
        zsh_setup::core::logger::info "You can manually change your shell later with: chsh -s $zsh_path"
        zsh_setup::system::shell::_show_manual_instructions "$zsh_path"
        return 0
    fi
    
    # Handle /etc/shells verification
    if ! grep -q "^$zsh_path$" /etc/shells 2>/dev/null; then
        local system_zsh=$(grep -m1 "zsh" /etc/shells 2>/dev/null || echo "")
        
        if [[ -n "$system_zsh" && -x "$system_zsh" ]]; then
            zsh_setup::core::logger::info "Using system Zsh: $system_zsh"
            zsh_path="$system_zsh"
        else
            zsh_setup::core::logger::info "Adding $zsh_path to /etc/shells..."
            
            if ! echo "$zsh_path" | sudo -n tee -a /etc/shells >/dev/null 2>&1; then
                zsh_setup::core::logger::info "Requesting sudo to update /etc/shells..."
                if ! echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
                    zsh_setup::core::logger::error "Failed to add Zsh to /etc/shells."
                    zsh_setup::system::shell::_attempt_direct_change "$zsh_path"
                    return $?
                fi
            fi
        fi
    fi
    
    # Change the shell
    if [[ -n "$spinner_pid" ]]; then
        zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "" 0
        spinner_pid=$(zsh_setup::core::progress::spinner_start "Changing shell to $zsh_path")
    else
        zsh_setup::core::logger::info "Changing shell to $zsh_path..."
    fi
    
    if chsh -s "$zsh_path" >/dev/null 2>&1; then
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✅ Default shell changed to Zsh successfully." "" 0
        else
            zsh_setup::core::logger::success "Default shell changed to Zsh successfully."
        fi
        export SHELL="$zsh_path"
        return 0
    else
        if [[ -n "$spinner_pid" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "❌ Failed to change the default shell to Zsh." 1
        else
            zsh_setup::core::logger::error "Failed to change the default shell to Zsh."
        fi
        zsh_setup::system::shell::_show_manual_instructions "$zsh_path"
        return 1
    fi
}

# Attempt direct shell change
zsh_setup::system::shell::_attempt_direct_change() {
    local zsh_path="$1"
    zsh_setup::core::logger::info "Attempting direct shell change to $zsh_path..."
    
    if chsh -s "$zsh_path" 2>/dev/null; then
        zsh_setup::core::logger::success "Successfully changed shell directly."
        export SHELL="$zsh_path"
        return 0
    fi
    
    local alt_zsh=$(grep -m1 "zsh" /etc/shells 2>/dev/null || echo "")
    if [[ -n "$alt_zsh" && -x "$alt_zsh" ]]; then
        zsh_setup::core::logger::info "Found alternative: $alt_zsh"
        if chsh -s "$alt_zsh"; then
            zsh_setup::core::logger::success "Changed shell to alternative Zsh: $alt_zsh"
            export SHELL="$alt_zsh"
            return 0
        fi
    fi
    
    zsh_setup::core::logger::error "Could not change shell automatically."
    return 1
}

# Show manual instructions
zsh_setup::system::shell::_show_manual_instructions() {
    local zsh_path="$1"
    echo ""
    echo "To complete Zsh setup later, you'll need to:"
    echo "1. Have an administrator add your Zsh path to /etc/shells:"
    echo "   sudo sh -c 'echo $zsh_path >> /etc/shells'"
    echo ""
    echo "2. Then change your default shell:"
    echo "   chsh -s $zsh_path"
    echo ""
    echo "For now, you can use Zsh by typing 'zsh' in your terminal."
    echo ""
}

