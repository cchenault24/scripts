#!/usr/bin/env zsh

#==============================================================================
# uninstall_zsh.sh - Zsh Configuration Cleanup Utility
#
# This script removes Zsh customizations including Oh My Zsh, plugins, themes,
# and configuration files, with the option to remove Homebrew dependencies.
#==============================================================================

# Verify Zsh version
if [[ "${ZSH_VERSION}" < "4.0" ]]; then
    echo "This script requires Zsh version 4.0 or higher."
    echo "Current version: ${ZSH_VERSION}"
    exit 1
fi

# Set strict error handling
setopt ERR_EXIT

#------------------------------------------------------------------------------
# Configuration Variables
#------------------------------------------------------------------------------

# Script and log locations
SCRIPT_DIR="${0:a:h}" # Zsh way to get script directory
LOG_FILE="/tmp/zsh_uninstall_$(date +%Y%m%d_%H%M%S).log"

# Configuration paths
ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
CUSTOM_THEMES_DIR="$HOME/.oh-my-zsh/custom/themes"

# Arrays to track removals
typeset -a REMOVED_FILES
typeset -a REMOVED_DIRS
typeset -a REMOVED_PACKAGES

# Initialize log file
print "# Zsh Uninstall Log - $(date)" >"$LOG_FILE"
print "# System: $(uname -a)" >>"$LOG_FILE"
print "# User: $(whoami)" >>"$LOG_FILE"
print "-------------------------------------------" >>"$LOG_FILE"

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

# Log functions with consistent format
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    print "[$timestamp] $1" >>"$LOG_FILE"
    print "$1"
}

log_error() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    print "[$timestamp] ERROR: $1" >>"$LOG_FILE"
    print "ERROR: $1" >&2
}

log_debug() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    print "[$timestamp] DEBUG: $1" >>"$LOG_FILE"
}

#------------------------------------------------------------------------------
# Plugin Management Functions
#------------------------------------------------------------------------------

# Load plugins list from configuration or defaults
load_plugins_list() {
    local plugins_file="$SCRIPT_DIR/plugins.conf"
    typeset -a plugins

    if [[ -f "$plugins_file" ]]; then
        log_message "Loading plugin list from $plugins_file"

        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" == \#* ]] && continue

            # Extract plugin name and type
            local name="${line%%|*}"
            local remaining="${line#*|}"
            local type="${remaining%%|*}"

            plugins+=("$name|$type")
            log_debug "Added plugin from config: $name (type: $type)"
        done <"$plugins_file"
    else
        {
            log_message "Using default plugin list."

            # Default plugins list
            plugins=(
                "powerlevel10k|git"
                "zsh-autosuggestions|git"
                "zsh-syntax-highlighting|git"
                "zsh-completions|git"
                "zsh-history-substring-search|git"
                "zsh-defer|git"
                "autojump|brew"
                "fzf|brew"
                "zoxide|brew"
                "thefuck|brew"
                "bat|brew"
                "eza|brew"
                "exa|brew"
                "fd|brew"
                "ripgrep|brew"
                "gum|brew"
            )
        }
    fi

    echo "${plugins[@]}"
}

#------------------------------------------------------------------------------
# User Interaction Functions
#------------------------------------------------------------------------------

# Confirm uninstallation before proceeding
confirm_uninstall() {
    print "\n⚠️  WARNING: This will remove Oh My Zsh, plugins, themes, and all Zsh customizations."
    print "    Zsh itself will remain installed."
    print "\nThis will remove:"
    print "    - Oh My Zsh and all custom plugins/themes"
    print "    - Custom Zsh configurations (.zshrc, .p10k.zsh, etc.)"
    print "    - Brew packages can be optionally removed"
    print ""
    print -n "Are you sure you want to continue? (y/n): "

    read -r REPLY

    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        log_message "Uninstall canceled by user."
        exit 0
    fi

    log_message "User confirmed uninstall."
}

#------------------------------------------------------------------------------
# Shell & Config Management Functions
#------------------------------------------------------------------------------

# Backup current zshrc
backup_zshrc() {
    if [[ -f "$HOME/.zshrc" ]]; then
        local backup_file="$HOME/.zshrc.backup_$(date +%Y%m%d_%H%M%S)"
        log_message "Backing up .zshrc to $backup_file"

        cp "$HOME/.zshrc" "$backup_file"
        log_message "Backup created at: $backup_file"
        REMOVED_FILES+=("Original .zshrc backed up to $backup_file")
    else
        log_message "No .zshrc file found to backup."
    fi
}

# Reset shell to bash
reset_shell() {
    local current_shell=$(grep "^$USER:" /etc/passwd | cut -d: -f7)

    if [[ "$current_shell" == *"zsh"* ]]; then
        log_message "Resetting default shell to bash..."

        # Try to find bash in common locations
        for bash_path in "/bin/bash" "/usr/bin/bash"; do
            if [[ -x "$bash_path" ]]; then
                chsh -s "$bash_path"
                log_message "Default shell changed to $bash_path."
                return 0
            fi
        done

        log_error "Could not find bash. Please manually change your shell using: chsh -s /bin/bash"
    else
        log_message "Default shell is not Zsh. No need to change."
    fi
}

#------------------------------------------------------------------------------
# Removal Functions
#------------------------------------------------------------------------------

# Remove Oh My Zsh
remove_oh_my_zsh() {
    log_message "Removing Oh My Zsh and custom plugins..."

    if [[ -d "$ZSH_DIR" ]]; then
        log_message "Removing Oh My Zsh directory: $ZSH_DIR"
        rm -rf "$ZSH_DIR"
        REMOVED_DIRS+=("$ZSH_DIR")
    else
        log_message "Oh My Zsh directory not found. Nothing to remove."
    fi
}

# Remove custom plugins and themes
remove_custom_plugins() {
    local -a plugins=("$@")

    log_message "Removing custom plugins and themes..."

    # Possible plugin locations
    local alt_locations=(
        "$HOME/.zsh_plugins"
        "$HOME/.zsh"
        "$HOME/.zsh/plugins"
    )

    for plugin_entry in "${plugins[@]}"; do
        local plugin_name="${plugin_entry%%|*}"
        local plugin_type="${plugin_entry##*|}"

        # Only handle git-installed plugins here
        if [[ "$plugin_type" == "git" ]]; then
            # Check theme vs plugin
            if [[ "$plugin_name" == "powerlevel10k" ]]; then
                [[ -d "$CUSTOM_THEMES_DIR/$plugin_name" ]] && {
                    log_message "Removing theme: $plugin_name"
                    rm -rf "$CUSTOM_THEMES_DIR/$plugin_name"
                    REMOVED_DIRS+=("$CUSTOM_THEMES_DIR/$plugin_name")
                }
            else
                [[ -d "$CUSTOM_PLUGINS_DIR/$plugin_name" ]] && {
                    log_message "Removing plugin: $plugin_name"
                    rm -rf "$CUSTOM_PLUGINS_DIR/$plugin_name"
                    REMOVED_DIRS+=("$CUSTOM_PLUGINS_DIR/$plugin_name")
                }
            fi

            # Check alternative locations
            for dir in "${alt_locations[@]}"; do
                [[ -d "$dir/$plugin_name" ]] && {
                    log_message "Removing plugin from $dir: $plugin_name"
                    rm -rf "$dir/$plugin_name"
                    REMOVED_DIRS+=("$dir/$plugin_name")
                }
            done
        fi
    done

    # Clean up empty plugin directories
    for dir in "${alt_locations[@]}"; do
        if [[ -d "$dir" && -z "$(ls -A "$dir")" ]]; then
            log_message "Removing empty directory: $dir"
            rm -rf "$dir"
            REMOVED_DIRS+=("$dir")
        fi
    done
}

# Remove Homebrew packages
remove_brew_packages() {
    local -a plugins=("$@")
    typeset -a brew_packages

    # Extract brew packages from plugins list
    for plugin_entry in "${plugins[@]}"; do
        local plugin_name="${plugin_entry%%|*}"
        local plugin_type="${plugin_entry##*|}"

        [[ "$plugin_type" == "brew" ]] && brew_packages+=("$plugin_name")
    done

    # Check if Homebrew is installed
    if ! command -v brew &>/dev/null; then
        log_message "Homebrew not installed. Skipping package removal."
        return 0
    fi

    # Filter to only include installed packages
    typeset -a installed_packages
    for pkg in "${brew_packages[@]}"; do
        if brew list --formula | grep -q "^$pkg$"; then
            installed_packages+=("$pkg")
        elif [[ "$pkg" == "exa" ]] && brew list --formula | grep -q "^eza$"; then
            # Special case for exa → eza
            installed_packages+=("eza")
        fi
    done

    # Exit if no packages to remove
    if [[ ${#installed_packages[@]} -eq 0 ]]; then
        log_message "No Homebrew packages to remove."
        return 0
    fi

    # Ask user about removal
    print "\nThe following Homebrew packages were installed as dependencies:"
    for pkg in "${installed_packages[@]}"; do
        print "  - $pkg"
    done

    print -n "Would you like to remove these packages? (y/n): "
    read -r REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        log_message "Removing Homebrew packages..."

        for pkg in "${installed_packages[@]}"; do
            print "Removing package: $pkg"
            if brew uninstall --ignore-dependencies "$pkg" &>/dev/null; then
                log_message "Successfully removed: $pkg"
                REMOVED_PACKAGES+=("$pkg")
            else
                log_error "Failed to remove package: $pkg"
            fi
        done
    else
        log_message "User chose not to remove Homebrew packages."
    fi
}

# Remove Zsh configuration files
remove_config_files() {
    log_message "Removing Zsh configuration files..."

    # List of files to remove
    local files_to_remove=(
        "$HOME/.zshrc"
        "$HOME/.zshrc.pre-oh-my-zsh"
        "$HOME/.zshenv"
        "$HOME/.zprofile"
        "$HOME/.zlogin"
        "$HOME/.zlogout"
        "$HOME/.zcompdump"
        "$HOME/.zsh_history"
        "$HOME/.p10k.zsh"
        "$HOME/.fzf.zsh"
        "$HOME/.zsh_plugins.txt"
    )

    # Remove each file if it exists
    for file in "${files_to_remove[@]}"; do
        [[ -f "$file" ]] && {
            log_message "Removing file: $file"
            rm -f "$file"
            REMOVED_FILES+=("$file")
        }
    done

    # Remove .zcompdump* files
    for file in "$HOME"/.zcompdump*; do
        [[ -f "$file" ]] && {
            log_message "Removing file: $file"
            rm -f "$file"
            REMOVED_FILES+=("$file")
        }
    done
}

# Create a minimal .bashrc
create_minimal_bashrc() {
    local bashrc="$HOME/.bashrc"

    # Only create if it doesn't exist
    if [[ ! -f "$bashrc" ]]; then
        log_message "Creating a minimal .bashrc file"

        cat >"$bashrc" <<'EOF'
# Default .bashrc created after Zsh uninstallation

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# User specific aliases and functions
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Enable bash completion
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi
EOF

        log_message ".bashrc file created."
    else
        log_message ".bashrc already exists. Not modifying."
    fi
}

#------------------------------------------------------------------------------
# Summary Functions
#------------------------------------------------------------------------------

# Show uninstallation summary
show_summary() {
    print "\n🧹 Zsh Uninstallation Summary:"
    print "✅ Oh My Zsh removed"
    print "✅ Custom plugins and themes removed"
    print "✅ Zsh configuration files removed"

    [[ -f "$HOME/.bashrc" ]] && print "✅ Bash configuration is ready" ||
        print "⚠️  No .bashrc file found. You may need to create one."

    # Show removed items
    if [[ ${#REMOVED_DIRS[@]} -gt 0 ]]; then
        print "\nRemoved directories:"
        for dir in "${REMOVED_DIRS[@]}"; do
            print "  - $dir"
        done
    fi

    if [[ ${#REMOVED_PACKAGES[@]} -gt 0 ]]; then
        print "\nRemoved packages:"
        for pkg in "${REMOVED_PACKAGES[@]}"; do
            print "  - $pkg"
        done
    fi

    print "\nTo complete the transition back to Bash:"
    print "1. Close all terminal windows"
    print "2. Open a new terminal (which should now use Bash)"
    print "\nLog file: $LOG_FILE\n"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

# Main function
main() {
    log_message "Starting Zsh uninstallation process"

    # Unified workflow
    confirm_uninstall
    backup_zshrc
    reset_shell

    # Load plugin list
    typeset -a plugins_list
    plugins_list=($(load_plugins_list))

    # Remove components
    remove_oh_my_zsh
    remove_custom_plugins "${plugins_list[@]}"
    remove_config_files
    remove_brew_packages "${plugins_list[@]}"
    create_minimal_bashrc

    # Show summary
    show_summary

    log_message "Zsh uninstallation completed successfully"
    print "✅ Uninstallation completed successfully!"
}

# Run the main function
main
exit 0
