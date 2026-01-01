#!/usr/bin/env bash

#==============================================================================
# install_plugins.sh - ZSH Plugin Installation Manager
#
# This script handles the installation of ZSH plugins, including:
# - Loading plugin configurations
# - Dependency resolution
# - Installation with proper tracking
# - Rollback on failure
#==============================================================================

# Ensure SCRIPT_DIR is set
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Load the installation utility functions
if [ -f "$SCRIPT_DIR/install_functions.sh" ]; then
  source "$SCRIPT_DIR/install_functions.sh"
else
  echo "Error: Required script install_functions.sh not found."
  exit 1
fi

# Load error handler and state manager
if [ -f "$SCRIPT_DIR/error_handler.sh" ]; then
  source "$SCRIPT_DIR/error_handler.sh"
fi

if [ -f "$SCRIPT_DIR/state_manager.sh" ]; then
  source "$SCRIPT_DIR/state_manager.sh"
  # Initialize state if needed
  if [ ! -f "$STATE_FILE" ]; then
    init_state "$SCRIPT_DIR"
  fi
fi

#------------------------------------------------------------------------------
# Configuration Variables
#------------------------------------------------------------------------------

# File paths
PLUGINS_CONFIG_FILE="$SCRIPT_DIR/plugins.conf"          # Plugin definitions
PLUGIN_DEPS_FILE="$SCRIPT_DIR/plugin_dependencies.conf" # Plugin dependency mappings
INSTALLATION_LOG="${INSTALLATION_LOG:-/tmp/zsh_plugin_installation.log}"

# Ensure log directory exists
mkdir -p "$(dirname "$INSTALLATION_LOG")" 2>/dev/null

# Installation settings
MAX_PARALLEL_INSTALLS=3  # Maximum number of concurrent installations
ROLLBACK_ON_FAILURE=true # Whether to roll back failed installations

# Arrays for tracking plugins and dependencies
PLUGINS_TO_INSTALL=()       # List of plugins to install
PLUGIN_DEPENDENCY_KEYS=()   # Plugin names that have dependencies
PLUGIN_DEPENDENCY_VALUES=() # Corresponding dependency lists
INSTALLED_PLUGINS=()        # Successfully installed plugins
FAILED_PLUGINS=()           # Failed plugin installations
INSTALLATION_ORDER=()       # Order of installation attempts (for rollback)
SELECTION=""                # Selected plugins from menu

# Initialize the log file
echo "# ZSH Plugin Installation Log - $(date)" >"$INSTALLATION_LOG"
echo "# System: $(uname -a)" >>"$INSTALLATION_LOG"
echo "# User: $(whoami)" >>"$INSTALLATION_LOG"
echo "-------------------------------------------" >>"$INSTALLATION_LOG"

#------------------------------------------------------------------------------
# Helper: Detect Existing Plugins
#------------------------------------------------------------------------------

plugin_already_installed() {
  local plugin="$1"
  [[ -d "$HOME/.oh-my-zsh/custom/plugins/$plugin" ]] || [[ -d "$HOME/.oh-my-zsh/custom/themes/$plugin" ]]
}

brew_plugin_installed() {
  local plugin="$1"
  brew list --formula | grep -q "^$plugin$"
}

#------------------------------------------------------------------------------
# Configuration Loading Functions
#------------------------------------------------------------------------------

# Load plugin configurations from external files
load_plugin_configs() {
  # Load plugin definitions
  if [ -f "$PLUGINS_CONFIG_FILE" ]; then
    echo "📁 Loading plugin configurations from $PLUGINS_CONFIG_FILE"
    PLUGINS_TO_INSTALL=()

    # Read plugin definitions line by line
    while IFS= read -r line; do
      # Skip empty lines and comments
      [[ "$line" =~ ^#|^$ ]] && continue

      # Parse the pipe-delimited format
      IFS='|' read -r name type url description <<<"$line"
      PLUGINS_TO_INSTALL+=("$description - $name|$name|$type")
    done <"$PLUGINS_CONFIG_FILE"
  else
    echo "📋 Using default plugin configurations"
    # Default plugins if config file doesn't exist
    PLUGINS_TO_INSTALL=(
      "autojump - Navigate directories quickly using stored jumps|autojump|brew"
      "fzf - Fuzzy file finder for quick searching|fzf|brew"
      "powerlevel10k - Highly customizable & fast Zsh theme|powerlevel10k|git"
      "zoxide - Smarter alternative to 'cd' for fast navigation|zoxide|brew"
      "zsh-autosuggestions - Suggests previous commands as you type|zsh-autosuggestions|git"
      "zsh-completions - Expands Zsh autocompletions for many tools|zsh-completions|git"
      "zsh-defer - Speeds up Zsh startup by lazy-loading plugins|zsh-defer|git"
      "zsh-history-substring-search - Search history with partial matches|zsh-history-substring-search|git"
      "zsh-syntax-highlighting - Adds syntax highlighting to commands|zsh-syntax-highlighting|git"
    )
  fi

  # Load plugin dependencies
  PLUGIN_DEPENDENCY_KEYS=()
  PLUGIN_DEPENDENCY_VALUES=()

  if [ -f "$PLUGIN_DEPS_FILE" ]; then
    echo "📁 Loading plugin dependencies from $PLUGIN_DEPS_FILE"

    while IFS= read -r line; do
      # Skip empty lines and comments
      [[ "$line" =~ ^#|^$ ]] && continue

      # Parse dependency mapping (plugin=dep1,dep2,...)
      local plugin_name="${line%%=*}"
      local dependencies="${line#*=}"

      PLUGIN_DEPENDENCY_KEYS+=("$plugin_name")
      PLUGIN_DEPENDENCY_VALUES+=("$dependencies")
    done <"$PLUGIN_DEPS_FILE"
  else
    echo "⚠️ No plugin dependencies file found, continuing without dependencies."
  fi
}

#------------------------------------------------------------------------------
# Dependency Resolution Functions
#------------------------------------------------------------------------------

# Track resolved dependencies to prevent circular dependencies
declare -A RESOLVED_DEPS=()

# Resolve dependencies for a plugin (with circular dependency detection)
resolve_dependencies() {
  local plugin="$1"
  local depth="${2:-0}"
  local max_depth=10  # Prevent infinite recursion
  
  # Prevent infinite recursion
  if [ "$depth" -gt "$max_depth" ]; then
    echo "⚠️ Maximum dependency depth reached for $plugin. Possible circular dependency." >&2
    return 1
  fi
  
  # Check for circular dependencies
  if [[ -n "${RESOLVED_DEPS[$plugin]}" ]]; then
    echo "⚠️ Circular dependency detected involving $plugin. Skipping." >&2
    return 0  # Return success to continue processing
  fi
  
  # Mark as being resolved
  RESOLVED_DEPS[$plugin]=1
  
  local deps=$(get_plugin_dependencies "$plugin")

  # No dependencies to resolve
  [ -z "$deps" ] && return 0

  # Split dependencies by comma or space
  local deps_array=()
  if [[ "$deps" == *","* ]]; then
    IFS=',' read -ra deps_array <<<"$deps"
  else
    read -ra deps_array <<<"$deps"
  fi

  for dep in "${deps_array[@]}"; do
    # Trim whitespace
    dep=$(echo "$dep" | xargs)
    [ -z "$dep" ] && continue

    # Check if dependency is already in the selection
    local dep_in_selection=false
    for entry in "${PLUGINS_TO_INSTALL[@]}"; do
      local entry_name=$(echo "$entry" | cut -d'|' -f2)
      local entry_desc=$(echo "$entry" | cut -d'|' -f1)
      
      if [ "$entry_name" = "$dep" ]; then
        # Check if this plugin description is already in SELECTION
        if echo "$SELECTION" | grep -q "^${entry_desc}$"; then
          dep_in_selection=true
          break
        fi
      fi
    done

    if ! $dep_in_selection; then
      # Find the full description for this dependency
      local dep_desc=""
      local dep_found=false
      
      for entry in "${PLUGINS_TO_INSTALL[@]}"; do
        local entry_name=$(echo "$entry" | cut -d'|' -f2)
        if [ "$entry_name" = "$dep" ]; then
          dep_desc=$(echo "$entry" | cut -d'|' -f1)
          dep_found=true
          break
        fi
      done

      if $dep_found; then
        # Add dependency with description
        echo "📝 Plugin '$plugin' requires: $dep_desc, adding automatically"
        SELECTION+=$'\n'"$dep_desc"
        
        # Recursively resolve dependencies of this dependency
        resolve_dependencies "$dep" $((depth + 1))
      else
        echo "⚠️ Dependency '$dep' for plugin '$plugin' not found in available plugins. Skipping." >&2
      fi
    fi
  done

  return 0
}

#------------------------------------------------------------------------------
# Installation Tracking Functions
#------------------------------------------------------------------------------

# Record the status of a plugin installation
record_installation() {
  local plugin="$1"
  local install_status="$2"
  local method="$3"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Record in the appropriate array
  if [ "$install_status" -eq 0 ]; then
    INSTALLED_PLUGINS+=("$plugin")
    echo "$timestamp - ✅ Installed: $plugin ($method)" >>"$INSTALLATION_LOG"
  else
    FAILED_PLUGINS+=("$plugin")
    echo "$timestamp - ❌ Failed: $plugin ($method)" >>"$INSTALLATION_LOG"
  fi

  # Track installation order for potential rollback
  INSTALLATION_ORDER+=("$plugin:$install_status:$method")
}

#------------------------------------------------------------------------------
# Plugin Installation Functions
#------------------------------------------------------------------------------

# Worker function for parallel plugin installation
install_plugin_worker() {
  local entry="$1"
  [ -z "$entry" ] && return 1
  
  IFS='|' read -r description name type <<<"$entry"
  
  # Skip if already installed
  if plugin_already_installed "$name"; then
    echo "✅ Skipping already installed plugin: $name" >&2
    record_installation "$name" 0 "already-installed"
    return 0
  fi

  case "$type" in
    "git")
      local plugin_url=""
      if [ "$name" = "powerlevel10k" ]; then
        install_git_plugin "$name" "https://github.com/romkatv/$name" "theme"
      elif [ "$name" = "zsh-defer" ]; then
        install_git_plugin "$name" "https://github.com/romkatv/$name" "plugin"
      elif [ "$name" = "nvm" ]; then
        install_git_plugin "$name" "https://github.com/nvm-sh/$name" "plugin"
      else
        install_git_plugin "$name" "https://github.com/zsh-users/$name" "plugin"
      fi
      ;;
    "omz")
      install_omz_plugin "$name"
      ;;
    "npm")
      install_npm_plugin "$name" "$name" "global"
      ;;
    *)
      echo "⚠️ Unknown method: $type for $name" >&2
      record_installation "$name" 1 "$type"
      return 1
      ;;
  esac
}

# Install plugins with parallel execution
install_plugins() {
  local plugins_to_process=("$@")
  local total=${#plugins_to_process[@]}

  echo "🔄 Installing $total plugins..."

  # Separate plugins by installation method
  local brew_plugins=()
  local parallel_plugins=()  # git, npm, omz plugins that can run in parallel

  for entry in "${plugins_to_process[@]}"; do
    local install_method=$(echo "$entry" | cut -d'|' -f3)
    if [ "$install_method" = "brew" ]; then
      brew_plugins+=("$entry")
    else
      parallel_plugins+=("$entry")
    fi
  done

  # Install parallel plugins using xargs -P or GNU parallel
  if [ ${#parallel_plugins[@]} -gt 0 ]; then
    echo "📦 Installing ${#parallel_plugins[@]} plugins in parallel (max $MAX_PARALLEL_INSTALLS concurrent)..."
    
    # Create a temporary script for parallel execution
    local worker_script=$(mktemp)
    cat > "$worker_script" <<'WORKER_EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$1"
ENTRY="$2"

# Source required scripts
source "$SCRIPT_DIR/install_functions.sh"
source "$SCRIPT_DIR/error_handler.sh" 2>/dev/null || true
source "$SCRIPT_DIR/state_manager.sh" 2>/dev/null || true

# Source install_plugins.sh functions
source "$SCRIPT_DIR/install_plugins.sh"

# Execute worker function
install_plugin_worker "$ENTRY"
WORKER_EOF
    chmod +x "$worker_script"
    
    # Check for GNU parallel first
    if command -v parallel &>/dev/null; then
      # Use GNU parallel
      printf '%s\n' "${parallel_plugins[@]}" | \
        parallel -j "$MAX_PARALLEL_INSTALLS" --tag "$worker_script" "$SCRIPT_DIR" {}
    else
      # Use xargs -P as fallback
      printf '%s\n' "${parallel_plugins[@]}" | \
        xargs -P "$MAX_PARALLEL_INSTALLS" -I {} "$worker_script" "$SCRIPT_DIR" "{}"
    fi
    
    # Cleanup
    rm -f "$worker_script"
  fi

  # Install Homebrew plugins sequentially (brew doesn't handle parallel well)
  if [ ${#brew_plugins[@]} -gt 0 ]; then
    echo "🍺 Installing ${#brew_plugins[@]} Homebrew packages sequentially..."
    for entry in "${brew_plugins[@]}"; do
      local name=$(echo "$entry" | cut -d'|' -f2)

      if brew_plugin_installed "$name"; then
        echo "✅ Skipping already installed Homebrew plugin: $name"
        record_installation "$name" 0 "already-installed"
        continue
      fi

      install_brew_plugin "$name" "$name"
    done
  fi
  
  # Sync arrays from state after all installations
  if command -v sync_arrays_from_state &>/dev/null; then
    sync_arrays_from_state
  fi
}

#------------------------------------------------------------------------------
# Rollback Functions
#------------------------------------------------------------------------------

# Roll back failed installations to maintain system integrity
rollback_failed_installations() {
  # Skip if no failures
  [ ${#FAILED_PLUGINS[@]} -eq 0 ] && return 0

  echo "🔄 Rolling back failed installations..."

  # Create list of plugins to roll back
  local plugins_to_rollback=("${FAILED_PLUGINS[@]}")

  # Add dependencies that need rollback
  for plugin in "${FAILED_PLUGINS[@]}"; do
    for i in "${!PLUGIN_DEPENDENCY_KEYS[@]}"; do
      if [ "${PLUGIN_DEPENDENCY_KEYS[$i]}" = "$plugin" ]; then
        # If a plugin failed, we need to roll back its dependencies
        local deps="${PLUGIN_DEPENDENCY_VALUES[$i]}"
        IFS=',' read -ra deps_array <<<"$deps"

        for dep in "${deps_array[@]}"; do
          # Check if dependency was installed
          for installed in "${INSTALLED_PLUGINS[@]}"; do
            if [ "$installed" = "$dep" ]; then
              # Add to rollback list if not already present
              if ! printf '%s\n' "${plugins_to_rollback[@]}" | grep -qx "$dep"; then
                plugins_to_rollback+=("$dep")
              fi
              break
            fi
          done
        done
      fi
    done
  done

  # Process rollbacks in reverse installation order
  for ((i = ${#INSTALLATION_ORDER[@]} - 1; i >= 0; i--)); do
    local entry="${INSTALLATION_ORDER[$i]}"
    local plugin=$(echo "$entry" | cut -d':' -f1)
    local method=$(echo "$entry" | cut -d':' -f3)

    # Skip if not in rollback list
    if ! printf '%s\n' "${plugins_to_rollback[@]}" | grep -qx "$plugin"; then
      continue
    fi

    echo "♻️ Rolling back $plugin..."

    # Handle rollback based on installation method
    if [ "$method" = "git" ]; then
      local install_dir

      # Determine plugin location
      if [ "$plugin" = "powerlevel10k" ]; then
        install_dir="$HOME/.oh-my-zsh/custom/themes/$plugin"
        # Also check for plugin directory version that might have a symlink
        if [ -d "$HOME/.oh-my-zsh/custom/plugins/$plugin" ]; then
          echo "🗑️ Removing plugin version: $HOME/.oh-my-zsh/custom/plugins/$plugin"
          rm -rf "$HOME/.oh-my-zsh/custom/plugins/$plugin"
        fi
      else
        install_dir="$HOME/.oh-my-zsh/custom/plugins/$plugin"
      fi

      # Remove the directory if it exists
      if [ -d "$install_dir" ]; then
        echo "🗑️ Removing $install_dir"
        rm -rf "$install_dir"
        echo "$(date +"%Y-%m-%d %H:%M:%S") - ♻️ Rolled back: $plugin" >>"$INSTALLATION_LOG"
      fi
    elif [ "$method" = "brew" ]; then
      # Skip Homebrew uninstallation in rollback phase
      echo "⚠️ Not uninstalling brew package $plugin to avoid affecting other software"
      echo "$(date +"%Y-%m-%d %H:%M:%S") - ⚠️ Skipped rollback for brew package: $plugin" >>"$INSTALLATION_LOG"
    fi
  done

  echo "♻️ Rollback complete"
}

#------------------------------------------------------------------------------
# Base Component Installation
#------------------------------------------------------------------------------

# Install required base components (Zsh and Oh My Zsh)
install_base_components() {
  echo "📦 Installing base components..."

  # Check for system Zsh
  local system_zsh=""
  for zsh_path in /bin/zsh /usr/bin/zsh "$(which zsh)"; do
    [ -x "$zsh_path" ] && {
      system_zsh="$zsh_path"
      break
    }
  done

  if [ -n "$system_zsh" ]; then
    echo "✅ System Zsh is already installed: $system_zsh ($(\"$system_zsh\" --version | head -n1))"
    export SYSTEM_ZSH_PATH="$system_zsh"
    record_installation "zsh" 0 "system"
  else
    echo "❌ Zsh is not installed on the system. Please install Zsh first."
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ❌ Critical failure: Zsh not found" >>"$INSTALLATION_LOG"
    exit 1
  fi

  # Install Oh My Zsh if needed
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✅ Oh My Zsh is already installed."
    record_installation "oh-my-zsh" 0 "existing"
  else
    install_silently_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" \
      "RUNZSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended"
    local omz_status=$?
    record_installation "oh-my-zsh" "$omz_status" "curl"

    # Exit if Oh My Zsh installation failed and rollback is enabled
    if [ "$omz_status" -ne 0 ] && [ "$ROLLBACK_ON_FAILURE" = true ]; then
      echo "❌ Oh My Zsh installation failed, cannot continue."
      echo "$(date +"%Y-%m-%d %H:%M:%S") - ❌ Critical failure: Oh My Zsh installation failed" >>"$INSTALLATION_LOG"
      exit 1
    fi
  fi
}

#------------------------------------------------------------------------------
# Plugin Selection Functions
#------------------------------------------------------------------------------

# Show an interactive menu for selecting plugins to install
show_plugin_selection_menu() {
  # Check if gum is installed for nice UI
  if ! command -v gum &>/dev/null; then
    echo "📦 Installing gum for interactive selection..."
    install_silently_with_spinner "gum" "command -v gum &>/dev/null" "brew install gum"

    # Fall back to basic selection if gum installation fails
    if ! command -v gum &>/dev/null; then
      echo "⚠️ Could not install gum. Using basic selection instead."
      _show_basic_selection_menu
      return
    fi
  fi

  # Use gum for selection UI
  echo "📦 Select plugins to install (use space to toggle, enter to confirm):"
  local height=$((${#PLUGINS_TO_INSTALL[@]} + 2))
  height=$((height > 20 ? 20 : height)) # Cap height at 20

  SELECTION=$(printf "%s\n" "${PLUGINS_TO_INSTALL[@]}" | cut -d'|' -f1 | gum choose --no-limit --height="$height")

  # Log selection
  echo "$(date +"%Y-%m-%d %H:%M:%S") - 🔍 User selected the following plugins:" >>"$INSTALLATION_LOG"
  echo "$SELECTION" | while read -r line; do
    [ -n "$line" ] && echo "  - $line" >>"$INSTALLATION_LOG"
  done
}

# Show a basic text-based selection menu (fallback)
_show_basic_selection_menu() {
  echo "Select plugins to install (comma-separated list of numbers, or 'all'):"
  local i=1

  # Display available plugins
  for entry in "${PLUGINS_TO_INSTALL[@]}"; do
    local plugin_description=$(echo "$entry" | cut -d'|' -f1)
    echo "$i) $plugin_description"
    ((i++))
  done

  read -r choice

  # Parse selection
  if [ "$choice" = "all" ]; then
    SELECTION=$(printf "%s\n" "${PLUGINS_TO_INSTALL[@]}" | cut -d'|' -f1)
  else
    SELECTION=""
    IFS=',' read -ra selected_nums <<<"$choice"

    for num in "${selected_nums[@]}"; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#PLUGINS_TO_INSTALL[@]}" ]; then
        local entry="${PLUGINS_TO_INSTALL[$((num - 1))]}"
        local plugin_description=$(echo "$entry" | cut -d'|' -f1)
        SELECTION+="$plugin_description"$'\n'
      fi
    done
  fi

  # Clean up empty lines
  SELECTION=$(echo "$SELECTION" | grep -v "^$")

  # Log selection
  echo "$(date +"%Y-%m-%d %H:%M:%S") - 🔍 User selected plugins (basic menu):" >>"$INSTALLATION_LOG"
  echo "$SELECTION" | while read -r line; do
    [ -n "$line" ] && echo "  - $line" >>"$INSTALLATION_LOG"
  done
}

#------------------------------------------------------------------------------
# Summary Functions
#------------------------------------------------------------------------------

# Display a summary of the installation results
show_installation_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║              📋 Plugin Installation Summary                ║"
  echo "╠════════════════════════════════════════════════════════════╣"

  # Show successfully installed plugins
  echo "║ ✅ Successfully installed plugins: ${#INSTALLED_PLUGINS[@]}"
  if [ "${#INSTALLED_PLUGINS[@]}" -gt 0 ]; then
    for plugin in "${INSTALLED_PLUGINS[@]}"; do
      printf "║   • %-54s ║\n" "$plugin"
    done
  else
    echo "║   (none)                                                  ║"
  fi

  # Show failed installations if any
  if [ "${#FAILED_PLUGINS[@]}" -gt 0 ]; then
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║ ❌ Failed plugin installations: ${#FAILED_PLUGINS[@]}"
    for plugin in "${FAILED_PLUGINS[@]}"; do
      printf "║   • %-54s ║\n" "$plugin"
    done
    echo "║                                                            ║"
    echo "║ 📝 Check log for details: $INSTALLATION_LOG"
  fi

  echo "╚════════════════════════════════════════════════════════════╝"

  # Make arrays available to parent scripts
  export INSTALLED_PLUGINS
  export FAILED_PLUGINS
}

#------------------------------------------------------------------------------
# Main Execution Function
#------------------------------------------------------------------------------

# Main function that orchestrates the plugin installation process
main() {
  # Set up error handling
  if command -v setup_error_trap &>/dev/null; then
    setup_error_trap "Plugin installation"
  else
    trap 'echo "Error on line $LINENO"; exit 1' ERR
  fi
  
  # Skip if dry-run mode
  if command -v is_dry_run &>/dev/null && is_dry_run; then
    echo "🔍 Dry-run mode: Plugin installation would be performed here"
    return 0
  fi

  # Step 1: Load plugin configurations
  load_plugin_configs

  # Step 2: Install base components (Zsh and Oh My Zsh)
  install_base_components

  # Step 3: Show plugin selection menu
  show_plugin_selection_menu

  # Step 4: Verify selection is not empty
  if [ -z "$SELECTION" ]; then
    echo "⚠️ No plugins were selected. Exiting plugin installation."
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ⚠️ No plugins selected" >>"$INSTALLATION_LOG"
    return 0
  fi

  # Step 5: Prepare list of selected plugins
  local selected_plugins=()

  # Process direct selections first
  for entry in "${PLUGINS_TO_INSTALL[@]}"; do
    local plugin_description=$(echo "$entry" | cut -d'|' -f1)
    local plugin_name=$(echo "$entry" | cut -d'|' -f2)

    if echo "$SELECTION" | grep -q "^${plugin_description}$"; then
      selected_plugins+=("$entry")
      # Resolve dependencies
      resolve_dependencies "$plugin_name"
    fi
  done

  # Handle added dependencies
  SELECTION=$(echo "$SELECTION" | sort | uniq)
  for entry in "${PLUGINS_TO_INSTALL[@]}"; do
    local plugin_description=$(echo "$entry" | cut -d'|' -f1)

    if echo "$SELECTION" | grep -q "^${plugin_description}$" &&
      ! printf "%s\n" "${selected_plugins[@]}" | grep -q "^${entry}$"; then
      selected_plugins+=("$entry")
    fi
  done

  # Step 6: Install selected plugins
  if [ ${#selected_plugins[@]} -gt 0 ]; then
    echo "📦 Installing ${#selected_plugins[@]} plugins..."
    install_plugins "${selected_plugins[@]}"

    # Step 7: Handle rollback if needed
    if [ "${#FAILED_PLUGINS[@]}" -gt 0 ] && [ "$ROLLBACK_ON_FAILURE" = true ]; then
      echo "⚠️ Some plugin installations failed. Rolling back..."
      rollback_failed_installations
    fi
  else
    echo "⚠️ No matching plugins found for your selection."
  fi

  # Step 8: Show installation summary
  show_installation_summary

  # Log the final list of installed plugins
  echo "$(date +"%Y-%m-%d %H:%M:%S") - Final list of installed plugins:" >>"$INSTALLATION_LOG"
  for plugin in "${INSTALLED_PLUGINS[@]}"; do
    # Extract the plugin name if it contains a description
    plugin_name="$plugin"
    if [[ "$plugin" == *" - "* ]]; then
      plugin_name=$(echo "$plugin" | cut -d'-' -f1 | xargs)
    fi

    # Check if it's a recognized plugin or a raw name
    if [[ "$plugin" == *"|"* ]]; then
      # Handle structured plugin entries
      entry_name=$(echo "$plugin" | cut -d'|' -f2)
      echo "  - $entry_name" >>"$INSTALLATION_LOG"
    else
      # Handle simple plugin names
      echo "  - $plugin_name" >>"$INSTALLATION_LOG"
    fi
  done

  # Export lists for use in other scripts
  export INSTALLED_PLUGINS
  export FAILED_PLUGINS

  # Check for powerlevel10k and create symlink if needed
  if printf '%s\n' "${INSTALLED_PLUGINS[@]}" | grep -q "powerlevel10k"; then
    if [ -d "$HOME/.oh-my-zsh/custom/plugins/powerlevel10k" ] &&
      [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
      echo "Creating symlink for powerlevel10k theme..."
      mkdir -p "$HOME/.oh-my-zsh/custom/themes"
      ln -sf "$HOME/.oh-my-zsh/custom/plugins/powerlevel10k" "$HOME/.oh-my-zsh/custom/themes/"
      echo "$(date +"%Y-%m-%d %H:%M:%S") - Created symlink for powerlevel10k theme" >>"$INSTALLATION_LOG"
    fi
  fi

  # Return status based on failures
  return $((${#FAILED_PLUGINS[@]} > 0))
}

#------------------------------------------------------------------------------
# Script Entry Point
#------------------------------------------------------------------------------

# Only run the main function if this script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
  exit $?
fi
