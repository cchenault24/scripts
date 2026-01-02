#!/usr/bin/env bash

#==============================================================================
# generate_zshrc.sh - Zsh Configuration Generator
#
# This script generates a comprehensive .zshrc file based on installed plugins
# and best practice defaults for Zsh/Oh-My-Zsh
#==============================================================================

#------------------------------------------------------------------------------
# Constants and Defaults
#------------------------------------------------------------------------------

# Path for the generated .zshrc file
ZSHRC_PATH="$HOME/.zshrc"

# Default Oh My Zsh theme if powerlevel10k isn't installed
DEFAULT_THEME="robbyrussell"

# Standard plugins to include regardless of selection
STANDARD_PLUGINS=("git")

# Load state manager if available
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [ -f "$SCRIPT_DIR/state_manager.sh" ]; then
    source "$SCRIPT_DIR/state_manager.sh"
    # Sync INSTALLED_PLUGINS from state file
    if [ -f "$STATE_FILE" ]; then
        INSTALLED_PLUGINS=()
        while IFS= read -r plugin; do
            [[ -n "$plugin" ]] && INSTALLED_PLUGINS+=("$plugin")
        done < <(get_installed_plugins 2>/dev/null)
    fi
fi

# Initialize INSTALLED_PLUGINS array if not defined (backward compatibility)
INSTALLED_PLUGINS=${INSTALLED_PLUGINS:-()}

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

# Simple logging function that handles both direct and external logger
log() {
    if command -v log_message &>/dev/null; then
        log_message "$1"
    else
        echo "$1"
    fi
}

# Check if an element exists in array
contains_element() {
    local element="$1"
    shift
    for e in "$@"; do
        [[ "$e" == "$element" ]] && return 0
    done
    return 1
}

# Get plugin-specific configuration
get_plugin_config() {
    local plugin_name="$1"

    case "$plugin_name" in
    "nvm")
        echo '# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
        ;;
    "fzf")
        echo '# FZF configuration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git 2>/dev/null || find . -type f -not -path \"*/\.git/*\" -not -path \"*/node_modules/*\""
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"'
        ;;
    "autojump")
        echo '# Autojump configuration
[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh
[ -f /opt/homebrew/etc/profile.d/autojump.sh ] && . /opt/homebrew/etc/profile.d/autojump.sh'
        ;;
    "zoxide")
        echo '# Zoxide configuration (smart cd command)
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi'
        ;;
    *)
        echo ""
        ;;
    esac
}

# Determine the best editor to use
determine_editor() {
    if [[ -n "$SSH_CONNECTION" ]]; then
        # Remote session - prefer vim
        if command -v vim >/dev/null; then
            EDITOR='vim'
        else
            EDITOR='nano'
        fi
    else
        # Local session - try code, then vim, then nano
        if command -v code >/dev/null; then
            EDITOR='code'
        elif command -v vim >/dev/null; then
            EDITOR='vim'
        else
            EDITOR='nano'
        fi
    fi
    export EDITOR
}

set_java_home_mac() {
    local FZF_WAS_INSTALLED=false
    local FZF_AVAILABLE=false

    if command -v fzf >/dev/null; then
        FZF_AVAILABLE=true
    else
        log "Installing fzf silently..."
        if brew install fzf >/dev/null 2>&1; then
            FZF_AVAILABLE=true
            FZF_WAS_INSTALLED=true
        else
            log "⚠️  Failed to install fzf. Falling back to standard prompt."
        fi
    fi

    # Get raw java versions
    local raw_versions
    IFS=$'\n' read -rd '' -a raw_versions < <(/usr/libexec/java_home -V 2>&1 | grep -E '^ *[0-9]' && printf '\0')

    if [[ ${#raw_versions[@]} -eq 0 ]]; then
        echo "No Java versions found via /usr/libexec/java_home."
        return
    fi

    # Format the raw output into clean, consistent lines
    local choices=()
    for line in "${raw_versions[@]}"; do
        # Sample line format:
        #   17.0.14 (x86_64) "Amazon.com Inc." - "Amazon Corretto 17" /Library/Java/...
        local version vendor path
        version=$(echo "$line" | awk '{print $1}')
        vendor=$(echo "$line" | grep -oE '"[^"]+"' | head -n1 | tr -d '"')
        path=$(echo "$line" | grep -oE '/.*')

        # Shorten path for display (optional)
        short_path=$(echo "$path" | sed "s|$HOME|~|")

        choices+=("Java $version | $vendor | $short_path")
    done

    local selected=""
    if [[ "$FZF_AVAILABLE" == true ]]; then
        selected=$(printf "%s\n" "${choices[@]}" | fzf --header="Select a Java version to use:")
    else
        echo "Multiple Java versions found:"
        for i in "${!choices[@]}"; do
            echo "[$((i+1))] ${choices[$i]}"
        done
        read -p "Select the Java version to use [1-${#choices[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#choices[@]} ]]; then
            selected="${choices[$((choice-1))]}"
        else
            echo "Invalid choice. Skipping JAVA_HOME setup."
            return
        fi
    fi

    if [[ -n "$selected" ]]; then
        local version_number
        version_number=$(echo "$selected" | awk '{print $2}') # from "Java 17.0.14 | ..."
        JAVA_HOME=$(/usr/libexec/java_home -v "$version_number")
        export JAVA_HOME
        log "JAVA_HOME set to $JAVA_HOME"
    fi

    if [[ "$FZF_WAS_INSTALLED" == true ]]; then
        trap 'log "Removing fzf..."; brew uninstall --force fzf >/dev/null 2>&1' EXIT
    fi
}

#------------------------------------------------------------------------------
# PATH Builder
#------------------------------------------------------------------------------

build_final_path() {
    local paths=()

    # User binaries
    paths+=("$HOME/bin")

    # Homebrew (Apple Silicon vs Intel)
    if [[ -d "/opt/homebrew/bin" ]]; then
        paths+=("/opt/homebrew/bin" "/opt/homebrew/sbin")
        export HOMEBREW_PREFIX="/opt/homebrew"
    elif [[ -d "/usr/local/Homebrew" ]]; then
        paths+=("/usr/local/bin" "/usr/local/sbin")
        export HOMEBREW_PREFIX="/usr/local"
    fi

    # Python user installs (detect dynamically)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Check for Python user install directories (macOS)
        for python_dir in "$HOME/Library/Python"/*/bin; do
            [[ -d "$python_dir" ]] && paths+=("$python_dir")
        done
    fi

    # JAVA_HOME (only add once)
    if [[ -n "$JAVA_HOME" && -d "$JAVA_HOME/bin" ]]; then
        paths+=("$JAVA_HOME/bin")
    fi

    # System paths
    paths+=(
        "/System/Cryptexes/App/usr/bin"
        "/usr/local/bin"
        "/usr/local/sbin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
        "/Library/Apple/usr/bin"
    )

    # Append existing $PATH
    paths+=($PATH)

    # Deduplicate
    local deduped=()
    local deduped_str=""
    for path in "${paths[@]}"; do
        if [[ -n "$path" && -d "$path" && ":$deduped_str:" != *":$path:"* ]]; then
            deduped+=("$path")
            deduped_str="$deduped_str:$path"
        fi
    done

    FINAL_PATH=$(IFS=:; echo "${deduped[*]}")
}



# Build all environment configurations
build_environment() {
    # Build the PATH first
    build_final_path
    
    # Determine the editor
    determine_editor

    # Set JAVA_HOME for macOS
    if [[ "$OSTYPE" == "darwin"* && -z "$JAVA_HOME" ]]; then
        set_java_home_mac
    fi
}

#------------------------------------------------------------------------------
# Configuration File Generators
#------------------------------------------------------------------------------

# Generate the main .zshrc configuration file
generate_zsh_config() {
    log "Generating Zsh configuration..."

    # Create a temporary file for building the .zshrc
    local temp_zshrc=$(mktemp)

    # Build all environment configurations first
    build_environment

    # Build the configuration file piece by piece
    generate_header "$temp_zshrc"
    generate_theme_config "$temp_zshrc"
    generate_oh_my_zsh_settings "$temp_zshrc"
    add_plugins_to_zshrc "$temp_zshrc"
    add_env_vars_to_zshrc "$temp_zshrc"
    add_aliases_to_zshrc "$temp_zshrc"
    generate_footer "$temp_zshrc"

    # Move the temporary file to the final location
    mv "$temp_zshrc" "$ZSHRC_PATH"

    log "Zsh configuration generated successfully at $ZSHRC_PATH"
}

# Generate the header section of .zshrc
generate_header() {
    local zshrc_file="$1"

    cat >"$zshrc_file" <<'EOF'
#==============================================================================
# .zshrc - Zsh Configuration
# Generated by Zsh Setup Script
#==============================================================================

# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

EOF
}

# Generate the theme section of .zshrc
generate_theme_config() {
    local zshrc_file="$1"

    # Add theme configuration section header
    cat >>"$zshrc_file" <<'EOF'
#------------------------------------------------------------------------------
# Theme Configuration
#------------------------------------------------------------------------------

EOF

    # Check if powerlevel10k is installed
    if contains_element "powerlevel10k" "${INSTALLED_PLUGINS[@]}"; then
        cat >>"$zshrc_file" <<'EOF'
# Use Powerlevel10k theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Load Powerlevel10k configuration if it exists
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# If powerlevel10k theme is not found, try direct path as fallback
if [[ ! -f $ZSH/themes/powerlevel10k/powerlevel10k.zsh-theme && ! -f $ZSH/custom/themes/powerlevel10k/powerlevel10k.zsh-theme ]]; then
    # Create a symlink from plugins to themes if needed
    if [[ -d $ZSH/custom/plugins/powerlevel10k ]]; then
        mkdir -p "$ZSH/custom/themes"
        # Create a symlink if needed
        [[ ! -d $ZSH/custom/themes/powerlevel10k ]] && ln -sf "$ZSH/custom/plugins/powerlevel10k" "$ZSH/custom/themes/"
        echo "Created symlink for powerlevel10k theme"
    else
        # Fall back to default theme
        ZSH_THEME="robbyrussell"
        echo "Warning: powerlevel10k theme not found, using default theme"
    fi
fi
EOF
    else
        cat >>"$zshrc_file" <<EOF
# Use the default Oh My Zsh theme
ZSH_THEME="$DEFAULT_THEME"
EOF
    fi

    # Add a blank line for readability
    echo "" >>"$zshrc_file"
}

# Generate the Oh My Zsh settings section
generate_oh_my_zsh_settings() {
    local zshrc_file="$1"

    cat >>"$zshrc_file" <<'EOF'
#------------------------------------------------------------------------------
# Oh My Zsh Settings
#------------------------------------------------------------------------------

# Case sensitivity and correction
# CASE_SENSITIVE="true"       # Uncomment for case-sensitive completion
HYPHEN_INSENSITIVE="true"   # Treat hyphens and underscores as equivalent

# Update behavior
# DISABLE_AUTO_UPDATE="true" # Uncomment to disable auto-updates
DISABLE_UPDATE_PROMPT="true" # Update without asking
# export UPDATE_ZSH_DAYS=13  # How often to check for updates (in days)

# Display settings
# DISABLE_MAGIC_FUNCTIONS="true" # Fix paste issues if needed
# DISABLE_LS_COLORS="true"       # Uncomment to disable ls colors
# DISABLE_AUTO_TITLE="true"      # Uncomment to disable auto-setting terminal title
# ENABLE_CORRECTION="true"       # Uncomment to enable command auto-correction
COMPLETION_WAITING_DOTS="true"   # Display dots while waiting for completion

# Performance settings
# DISABLE_UNTRACKED_FILES_DIRTY="true" # Faster status checks for large repos

# History settings
HIST_STAMPS="yyyy-mm-dd" # Format for history timestamp display

# Custom folder location
# ZSH_CUSTOM=/path/to/new-custom-folder # Override custom folder location

EOF
}

# Add plugin configuration to .zshrc
add_plugins_to_zshrc() {
    local zshrc_file="$1"

    cat >>"$zshrc_file" <<'EOF'
#------------------------------------------------------------------------------
# Plugins Configuration
#------------------------------------------------------------------------------

EOF

    # Build plugins array
    local plugins=("${STANDARD_PLUGINS[@]}")

    # Add installed plugins (skipping themes)
    for plugin in "${INSTALLED_PLUGINS[@]}"; do
        # Skip powerlevel10k as it's handled separately in themes
        [[ "$plugin" == "powerlevel10k" ]] && continue

        # Only add if it exists (either built-in or custom plugin)
        if [[ -d "$HOME/.oh-my-zsh/plugins/$plugin" || -d "$HOME/.oh-my-zsh/custom/plugins/$plugin" ]]; then
            plugins+=("$plugin")
        fi
    done

    # Write the plugins array to the config file
    echo "plugins=(${plugins[*]})" >>"$zshrc_file"
    echo "" >>"$zshrc_file"

    # Add plugin-specific configurations
    add_plugin_specific_configs "$zshrc_file"
}

# Add specific configurations for certain plugins
add_plugin_specific_configs() {
    local zshrc_file="$1"

    # Add configurations for installed plugins
    for plugin in "${INSTALLED_PLUGINS[@]}"; do
        local config=$(get_plugin_config "$plugin")
        if [[ -n "$config" ]]; then
            cat >>"$zshrc_file" <<EOF
${config}

EOF
        fi
    done

    # Syntax highlighting should be loaded last if installed
    if contains_element "zsh-syntax-highlighting" "${INSTALLED_PLUGINS[@]}"; then
        cat >>"$zshrc_file" <<'EOF'
# Syntax highlighting (must be loaded at the end)
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

EOF
    fi
}

# Add environment variables to .zshrc
add_env_vars_to_zshrc() {
    local zshrc_file="$1"

    # Section header
    cat >>"$zshrc_file" <<'EOF'
#------------------------------------------------------------------------------
# Environment Variables
#------------------------------------------------------------------------------
EOF

    # Write the final PATH and editor to .zshrc
    cat >>"$zshrc_file" <<EOF

# PATH configuration
export PATH="$FINAL_PATH"

# Editor configuration
export EDITOR="${EDITOR:-vim}"

# History configuration
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history

# Language and locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF

    # Add JAVA_HOME if available
    if [[ -n "$JAVA_HOME" ]]; then
        echo "export JAVA_HOME=\"$JAVA_HOME\"" >>"$zshrc_file"
    fi

    echo "" >>"$zshrc_file"
}


# Add aliases to .zshrc
add_aliases_to_zshrc() {
    local zshrc_file="$1"

    cat >>"$zshrc_file" <<'EOF'
#------------------------------------------------------------------------------
# Aliases
#------------------------------------------------------------------------------

# List directory contents
alias ls='ls -G'            # Colorized output
alias ll='ls -la'           # Long format, all files
alias la='ls -A'            # All files except . and ..
alias l='ls -CF'            # Columns, classify

# File operations
alias cp='cp -i'            # Confirm before overwriting
alias mv='mv -i'            # Confirm before overwriting
alias mkdir='mkdir -p'      # Create parent directories as needed
alias rmrf='rm -rf'         # Remove directories recursively

EOF
}

# Generate the footer section of .zshrc
generate_footer() {
    local zshrc_file="$1"

    cat >>"$zshrc_file" <<'EOF'

#------------------------------------------------------------------------------
# Load Oh My Zsh
#------------------------------------------------------------------------------

source $ZSH/oh-my-zsh.sh

#------------------------------------------------------------------------------
# User Customizations
#------------------------------------------------------------------------------

# Load additional local configuration if it exists
# Create ~/.zshrc.local to add your own customizations without modifying this file
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Load any custom scripts in ~/.zsh directory if it exists
if [[ -d $HOME/.zsh ]]; then
  for file in $HOME/.zsh/*.zsh; do
    [[ -f "$file" ]] && source "$file"
  done
  unset file
fi

# Generated by Zsh Setup Script - Happy Zsh-ing!
EOF
}

#------------------------------------------------------------------------------
# Direct Script Execution
#------------------------------------------------------------------------------

# If this script is being executed directly (not sourced),
# run the main function automatically
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    generate_zsh_config
fi
