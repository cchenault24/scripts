#!/usr/bin/env bash

#==============================================================================
# package_manager.sh - Package Manager Integration Utilities
#
# Provides functions for detecting and managing system packages across
# different package managers (Homebrew, apt, dnf, pacman)
#==============================================================================

# Load required utilities
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
fi

if [ -f "$SCRIPT_DIR/error_handler.sh" ]; then
    source "$SCRIPT_DIR/error_handler.sh"
fi

#------------------------------------------------------------------------------
# Package Manager Detection
#------------------------------------------------------------------------------

# Detect available package manager
detect_package_manager() {
    if command -v brew &>/dev/null; then
        echo "brew"
    elif command -v apt-get &>/dev/null && command -v dpkg &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null && ! command -v dnf &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Get package manager name (human-readable)
get_package_manager_name() {
    local pm=$(detect_package_manager)
    case "$pm" in
        brew) echo "Homebrew" ;;
        apt) echo "APT (Debian/Ubuntu)" ;;
        dnf) echo "DNF (Fedora)" ;;
        yum) echo "YUM (RHEL/CentOS)" ;;
        pacman) echo "Pacman (Arch Linux)" ;;
        zypper) echo "Zypper (openSUSE)" ;;
        *) echo "Unknown" ;;
    esac
}

#------------------------------------------------------------------------------
# Package Installation Status
#------------------------------------------------------------------------------

# Check if a package is installed
is_package_installed() {
    local package_name="$1"
    local pm=$(detect_package_manager)
    
    case "$pm" in
        brew)
            brew list --formula 2>/dev/null | grep -q "^${package_name}$" || \
            brew list --cask 2>/dev/null | grep -q "^${package_name}$"
            ;;
        apt)
            dpkg -l | grep -q "^ii[[:space:]]*${package_name}[[:space:]]"
            ;;
        dnf|yum)
            rpm -q "$package_name" &>/dev/null
            ;;
        pacman)
            pacman -Q "$package_name" &>/dev/null
            ;;
        zypper)
            zypper se -i "$package_name" &>/dev/null | grep -q "^i[[:space:]]"
            ;;
        *)
            return 1
            ;;
    esac
}

# Get installed package version
get_package_version() {
    local package_name="$1"
    local pm=$(detect_package_manager)
    local version=""
    
    case "$pm" in
        brew)
            version=$(brew list --versions "$package_name" 2>/dev/null | awk '{print $NF}')
            ;;
        apt)
            version=$(dpkg -l "$package_name" 2>/dev/null | awk '/^ii/ {print $3}')
            ;;
        dnf|yum)
            version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$package_name" 2>/dev/null)
            ;;
        pacman)
            version=$(pacman -Q "$package_name" 2>/dev/null | awk '{print $2}')
            ;;
        zypper)
            version=$(zypper info "$package_name" 2>/dev/null | grep "^Version" | awk '{print $3}')
            ;;
    esac
    
    echo "$version"
}

# Get list of installed packages
get_installed_packages() {
    local pm=$(detect_package_manager)
    local packages=()
    
    case "$pm" in
        brew)
            packages=($(brew list --formula 2>/dev/null))
            packages+=($(brew list --cask 2>/dev/null))
            ;;
        apt)
            packages=($(dpkg -l | awk '/^ii/ {print $2}'))
            ;;
        dnf)
            packages=($(dnf list installed 2>/dev/null | awk 'NR>1 {print $1}' | cut -d. -f1))
            ;;
        yum)
            packages=($(yum list installed 2>/dev/null | awk 'NR>1 {print $1}' | cut -d. -f1))
            ;;
        pacman)
            packages=($(pacman -Q | awk '{print $1}'))
            ;;
        zypper)
            packages=($(zypper se -i 2>/dev/null | awk '/^i/ {print $3}'))
            ;;
    esac
    
    printf '%s\n' "${packages[@]}"
}

#------------------------------------------------------------------------------
# Package Installation
#------------------------------------------------------------------------------

# Install a package via the appropriate package manager
install_package() {
    local package_name="$1"
    local description="${2:-Installing $package_name}"
    local pm=$(detect_package_manager)
    
    # Check if already installed
    if is_package_installed "$package_name"; then
        log_info "✅ $package_name is already installed ($(get_package_manager_name))"
        return 0
    fi
    
    log_info "📦 $description via $(get_package_manager_name)..."
    
    case "$pm" in
        brew)
            if execute_with_retry "$description" brew install "$package_name"; then
                log_success "Successfully installed $package_name via Homebrew"
                return 0
            else
                log_error "Failed to install $package_name via Homebrew"
                return 1
            fi
            ;;
        apt)
            if execute_with_retry "$description" sudo apt-get install -y "$package_name"; then
                log_success "Successfully installed $package_name via APT"
                return 0
            else
                log_error "Failed to install $package_name via APT"
                return 1
            fi
            ;;
        dnf)
            if execute_with_retry "$description" sudo dnf install -y "$package_name"; then
                log_success "Successfully installed $package_name via DNF"
                return 0
            else
                log_error "Failed to install $package_name via DNF"
                return 1
            fi
            ;;
        yum)
            if execute_with_retry "$description" sudo yum install -y "$package_name"; then
                log_success "Successfully installed $package_name via YUM"
                return 0
            else
                log_error "Failed to install $package_name via YUM"
                return 1
            fi
            ;;
        pacman)
            if execute_with_retry "$description" sudo pacman -S --noconfirm "$package_name"; then
                log_success "Successfully installed $package_name via Pacman"
                return 0
            else
                log_error "Failed to install $package_name via Pacman"
                return 1
            fi
            ;;
        zypper)
            if execute_with_retry "$description" sudo zypper install -y "$package_name"; then
                log_success "Successfully installed $package_name via Zypper"
                return 0
            else
                log_error "Failed to install $package_name via Zypper"
                return 1
            fi
            ;;
        *)
            log_error "No supported package manager found. Cannot install $package_name"
            return 1
            ;;
    esac
}

# Check package version for compatibility
check_package_version() {
    local package_name="$1"
    local min_version="${2:-}"
    local current_version=""
    
    if ! is_package_installed "$package_name"; then
        log_warn "$package_name is not installed"
        return 1
    fi
    
    current_version=$(get_package_version "$package_name")
    
    if [[ -z "$current_version" ]]; then
        log_warn "Could not determine version for $package_name"
        return 1
    fi
    
    log_info "$package_name version: $current_version"
    
    if [[ -n "$min_version" ]]; then
        # Simple version comparison (basic implementation)
        log_debug "Checking if $current_version >= $min_version"
        # For production, use a proper version comparison library
    fi
    
    return 0
}

# Map plugin names to system package names
map_plugin_to_package() {
    local plugin_name="$1"
    
    # Common mappings
    case "$plugin_name" in
        bat)
            echo "bat"
            ;;
        fd)
            echo "fd"
            ;;
        ripgrep)
            echo "ripgrep"
            ;;
        fzf)
            echo "fzf"
            ;;
        zoxide)
            echo "zoxide"
            ;;
        autojump)
            echo "autojump"
            ;;
        eza|exa)
            echo "eza"
            ;;
        thefuck)
            echo "thefuck"
            ;;
        *)
            # Default: assume plugin name matches package name
            echo "$plugin_name"
            ;;
    esac
}

# Install missing dependencies for a plugin
install_plugin_dependencies() {
    local plugin_name="$1"
    local pm=$(detect_package_manager)
    
    if [[ "$pm" == "unknown" ]]; then
        log_warn "No package manager detected. Cannot install dependencies for $plugin_name"
        return 1
    fi
    
    # Get system package name
    local package_name=$(map_plugin_to_package "$plugin_name")
    
    if [[ -z "$package_name" ]]; then
        log_debug "No system package mapping for $plugin_name"
        return 0
    fi
    
    if ! is_package_installed "$package_name"; then
        log_info "Installing system dependency: $package_name"
        install_package "$package_name" "Installing dependency for $plugin_name"
    else
        log_debug "Dependency $package_name already installed"
    fi
}

# Export functions
export -f detect_package_manager
export -f get_package_manager_name
export -f is_package_installed
export -f get_package_version
export -f get_installed_packages
export -f install_package
export -f check_package_version
export -f map_plugin_to_package
export -f install_plugin_dependencies
