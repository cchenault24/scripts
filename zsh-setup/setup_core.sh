#!/usr/bin/env bash

#==============================================================================
# setup_core.sh - Core functionality for Zsh setup
#
# This script provides core functionality for the Zsh setup process:
# - System requirement checks
# - Logging mechanisms
# - Configuration backup
# - Oh My Zsh installation
# - Shell changing utilities
# - Installation verification
#==============================================================================

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

# Initialize the log file for the setup process
init_log_file() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "--- Zsh Setup Log ($(date)) ---" >"$LOG_FILE"
    echo "System: $(uname -a)" >>"$LOG_FILE"
    echo "User: $(whoami)" >>"$LOG_FILE"
    echo "Script version: 1.0.0" >>"$LOG_FILE"
    echo "----------------------------" >>"$LOG_FILE"
}

# Log an informational message
log_message() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    # Always write to log file
    echo "[$timestamp] $message" >>"$LOG_FILE"

    # Only print to console if verbose mode is enabled
    $VERBOSE && echo "$message"
}

# Log an error message
log_error() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    # Log to file with ERROR prefix
    echo "[$timestamp] ERROR: $message" >>"$LOG_FILE"

    # Always print errors to stderr
    echo "ERROR: $message" >&2
}

#------------------------------------------------------------------------------
# System Check Functions
#------------------------------------------------------------------------------

# Check if required software is installed and system is ready
check_system_requirements() {
    log_message "Checking system requirements..."
    local requirements_met=true

    # Check if Zsh is installed (required)
    if ! command -v zsh &>/dev/null; then
        log_error "Zsh is not installed. Please install Zsh first using your system package manager."
        _suggest_installation_command "zsh"
        requirements_met=false
    else
        log_message "✓ Zsh is installed: $(zsh --version | head -n1)"
    fi

    # Check if Git is installed (required)
    if ! command -v git &>/dev/null; then
        log_error "Git is not installed. Please install Git first."
        _suggest_installation_command "git"
        requirements_met=false
    else
        log_message "✓ Git is installed: $(git --version)"
    fi

    # Check for Homebrew (optional, macOS only)
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            log_message "✓ Homebrew is installed: $(brew --version | head -n1)"
        else
            log_message "ⓘ Homebrew not found. Some features may be limited."
        fi
    fi

    # Check for selection tools (optional)
    if command -v fzf &>/dev/null; then
        log_message "✓ Selection tool available: fzf $(fzf --version)"
    elif command -v gum &>/dev/null; then
        log_message "✓ Selection tool available: gum $(gum --version)"
    else
        log_message "ⓘ No selection tool (fzf/gum) found. Will use fallback selection method."
    fi

    # Exit if required tools are missing
    if ! $requirements_met; then
        log_error "System requirements check failed. Please install missing components."
        exit 1
    fi

    log_message "System requirements check completed successfully."
}

# Suggest installation commands for missing software
_suggest_installation_command() {
    local software="$1"

    echo "Installation suggestions:"

    # Detect OS and suggest appropriate installation method
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "  On macOS: brew install $software"
    elif [[ -f /etc/debian_version ]]; then
        echo "  On Debian/Ubuntu: sudo apt install $software"
    elif [[ -f /etc/fedora-release ]]; then
        echo "  On Fedora: sudo dnf install $software"
    elif [[ -f /etc/arch-release ]]; then
        echo "  On Arch Linux: sudo pacman -S $software"
    else
        echo "  Please check your distribution's package manager to install $software"
    fi
}

#------------------------------------------------------------------------------
# Backup Functions
#------------------------------------------------------------------------------

# Back up existing Zsh configuration files
backup_zshrc() {
    log_message "Backing up existing Zsh configuration..."

    local backup_dir="$HOME/.zsh_backup"
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local files_backed_up=0

    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"

    # Files to backup
    local config_files=(".zshrc" ".zshenv" ".zprofile" ".zlogin" ".zlogout")

    # Back up each file if it exists
    for file in "${config_files[@]}"; do
        local path="$HOME/$file"
        if [[ -f "$path" ]]; then
            cp "$path" "$backup_dir/$file.$timestamp"
            log_message "Backed up $file to $backup_dir/$file.$timestamp"
            ((files_backed_up++))
        fi
    done

    # Check for existing Oh My Zsh installation
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_message "⚠️ Existing Oh My Zsh installation found. Will not overwrite."
    fi

    # Provide backup summary
    if [[ $files_backed_up -eq 0 ]]; then
        log_message "No existing Zsh configuration files found. No backups created."
    else
        log_message "Backup completed. $files_backed_up files backed up to $backup_dir"
    fi
}

#------------------------------------------------------------------------------
# Installation Functions
#------------------------------------------------------------------------------

# Install Oh My Zsh
install_oh_my_zsh() {
    log_message "Installing Oh My Zsh..."

    # Check if already installed
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_message "Oh My Zsh is already installed. Skipping installation."
        return 0
    fi

    # Create a temporary installation script
    local install_script="/tmp/install_ohmyzsh.sh"

    # Download the install script
    log_message "Downloading Oh My Zsh installer..."
    if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$install_script"; then
        log_error "Failed to download Oh My Zsh installer. Check your internet connection."
        return 1
    fi

    # Modify the install script to prevent it from changing the shell
    log_message "Preparing installer script..."
    sed -i.bak 's/exec zsh -l/exit 0/g' "$install_script"

    # Run the installer
    log_message "Running Oh My Zsh installer..."
    if ! sh "$install_script" --unattended; then
        log_error "Oh My Zsh installation failed. Check logs for details."
        return 1
    fi

    # Verify installation
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_error "Oh My Zsh directory not found after installation. Something went wrong."
        return 1
    fi

    log_message "✅ Oh My Zsh installed successfully."
    return 0
}

# Change the user's default shell to Zsh
change_default_shell() {
    log_message "Changing default shell to Zsh..."

    # Use the system Zsh path if available, otherwise use which
    local zsh_path="${SYSTEM_ZSH_PATH:-$(which zsh)}"
    log_message "Using Zsh path: $zsh_path"

    # Check if Zsh is already the default shell
    if [[ "$SHELL" == "$zsh_path" ]]; then
        log_message "Zsh is already the default shell. No changes needed."
        return 0
    fi

    # Handle /etc/shells verification
    if ! grep -q "^$zsh_path$" /etc/shells; then
        # Try to find any zsh in /etc/shells
        local system_zsh=$(grep -m1 "zsh" /etc/shells || echo "")

        if [ -n "$system_zsh" ] && [ -x "$system_zsh" ]; then
            log_message "Using system Zsh: $system_zsh"
            zsh_path="$system_zsh"
        else
            # Need to add Zsh to /etc/shells
            log_message "Adding $zsh_path to /etc/shells..."

            if ! echo "$zsh_path" | sudo -n tee -a /etc/shells >/dev/null 2>&1; then
                log_message "Requesting sudo to update /etc/shells..."
                if ! echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
                    log_error "Failed to add Zsh to /etc/shells."
                    _attempt_direct_shell_change "$zsh_path"
                    return $?
                fi
            fi
        fi
    fi

    # Change the shell
    log_message "Changing shell to $zsh_path..."
    if chsh -s "$zsh_path"; then
        log_message "✅ Default shell changed to Zsh successfully."
        export SHELL="$zsh_path"
        return 0
    else
        log_error "Failed to change the default shell to Zsh."
        _display_manual_shell_change_instructions "$zsh_path"

        # Ask if user wants to continue
        read -p "Would you like to continue with setup anyway? (y/n) " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_message "Continuing setup despite shell change failure."
            return 0
        else
            log_message "Setup aborted by user after shell change failure."
            exit 1
        fi
    fi
}

# Helper function to attempt direct shell change without /etc/shells
_attempt_direct_shell_change() {
    local zsh_path="$1"

    log_message "Attempting direct shell change to $zsh_path..."

    if chsh -s "$zsh_path" 2>/dev/null; then
        log_message "✅ Successfully changed shell directly."
        export SHELL="$zsh_path"
        return 0
    fi

    # Look for alternatives in /etc/shells
    log_message "Looking for alternative Zsh in /etc/shells..."
    local alt_zsh=$(grep -m1 "zsh" /etc/shells || echo "")

    if [ -n "$alt_zsh" ] && [ -x "$alt_zsh" ]; then
        log_message "Found alternative: $alt_zsh"
        if chsh -s "$alt_zsh"; then
            log_message "✅ Changed shell to alternative Zsh: $alt_zsh"
            export SHELL="$alt_zsh"
            return 0
        fi
    fi

    log_error "Could not change shell automatically."
    return 1
}

# Display instructions for manually changing the shell
_display_manual_shell_change_instructions() {
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

#------------------------------------------------------------------------------
# Verification Functions
#------------------------------------------------------------------------------

# Verify that the installation was successful
verify_installation() {
    log_message "Verifying installation..."

    local issues=0

    # Check if Oh My Zsh is installed (if it was supposed to be)
    if $INSTALL_OHMYZSH; then
        if [[ -d "$HOME/.oh-my-zsh" ]]; then
            log_message "✓ Oh My Zsh is correctly installed."
        else
            log_error "Oh My Zsh directory not found at $HOME/.oh-my-zsh"
            ((issues++))
        fi
    fi

    # Check if .zshrc exists and is properly configured
    if [[ -f "$HOME/.zshrc" ]]; then
        log_message "✓ .zshrc configuration file exists."

        # Basic check for Oh My Zsh configuration
        if grep -q "oh-my-zsh" "$HOME/.zshrc" || grep -q "plugins=" "$HOME/.zshrc"; then
            log_message "✓ .zshrc appears to be properly configured."
        else
            log_message "⚠️ .zshrc might not be properly configured for Oh My Zsh."
            ((issues++))
        fi
    else
        log_error ".zshrc configuration file not found."
        ((issues++))
    fi

    # Check if shell is set to Zsh
    local current_shell=""
    if command -v dscl &>/dev/null; then
        # macOS method
        current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | sed 's/UserShell: //')
    else
        # Fallback method
        current_shell="$SHELL"
    fi

    # Check if current shell is any variant of zsh
    if [[ "$current_shell" == *"zsh"* ]]; then
        log_message "✓ Default shell is set to Zsh ($current_shell)."
    else
        if $CHANGE_SHELL; then
            log_message "⚠️ Default shell does not appear to be Zsh. Current shell: $current_shell"
            log_message "   You will need to log out and log back in for the change to take effect."
            ((issues++))
        else
            log_message "ⓘ Default shell is not Zsh (as requested)."
        fi
    fi

    # Check plugins if they were installed
    if $INSTALL_PLUGINS && type verify_plugins &>/dev/null; then
        verify_plugins
    fi

    # Display overall status
    if [[ $issues -eq 0 ]]; then
        log_message "✅ Installation verification passed. All components appear to be correctly installed."
    else
        log_message "⚠️ Installation verification completed with $issues issues."
        log_message "You can still use Zsh, but some components might not work as expected."
    fi
}

#------------------------------------------------------------------------------
# Summary Functions
#------------------------------------------------------------------------------

# Display a summary of the installation
display_summary() {
    # Get installed plugin count
    local plugin_count=0
    [[ -n "${INSTALLED_PLUGINS[*]}" ]] && plugin_count=${#INSTALLED_PLUGINS[@]}

    # Create a visually appealing summary
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║           Zsh Setup Summary            ║"
    echo "╠════════════════════════════════════════╣"
    echo "║ Oh My Zsh      : $(if $INSTALL_OHMYZSH && [[ -d "$HOME/.oh-my-zsh" ]]; then echo "✅ Installed    "; else echo "⚠️ Skipped      "; fi) ║"
    echo "║ Default Shell  : $(if $CHANGE_SHELL && [[ "$SHELL" == *"zsh"* ]]; then echo "✅ Zsh          "; else echo "⚠️ Not changed  "; fi) ║"
    echo "║ Backup Created : $(if $BACKUP_ZSHRC; then echo "✅ Yes          "; else echo "⚠️ Skipped      "; fi) ║"
    echo "║ Plugins        : ✅ $plugin_count installed  $(printf '%*s' $((16 - ${#plugin_count})) '')║"
    echo "╠════════════════════════════════════════╣"
    echo "║ Log file: $LOG_FILE"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Enhanced shell status section
    if $CHANGE_SHELL; then
        # Get current shell config
        local current_shell=""
        if command -v dscl &>/dev/null; then
            # macOS method
            current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | sed 's/UserShell: //')
        else
            # Fallback to environment variable
            current_shell="$SHELL"
        fi

        # Find installed zsh path
        local zsh_path=""
        for path in "/bin/zsh" "/usr/bin/zsh" "/usr/local/bin/zsh" "$(which zsh 2>/dev/null)"; do
            [[ -x "$path" ]] && {
                zsh_path="$path"
                break
            }
        done

        zsh_path="${zsh_path:-$(which zsh 2>/dev/null || echo "/bin/zsh")}"

        if [[ "$current_shell" == *"zsh"* ]]; then
            echo "✓ Your default shell appears to be Zsh: $current_shell"
        else
            echo "⚠️ Your default shell is currently: $current_shell"
            echo "   Desired shell is: $zsh_path"
            echo ""
            echo "You may need to log out and log back in for shell changes to take effect."
            echo "If your shell hasn't changed after relogging, run this manually:"
            echo "   chsh -s $zsh_path"
        fi
    fi
    echo ""

    # Start Zsh if installed
    if command -v zsh &>/dev/null; then
        echo "Starting Zsh..."
        exec zsh
    fi
}
