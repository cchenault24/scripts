#!/usr/bin/env bash

#==============================================================================
# package_manager.sh - Package Manager Abstraction
#
# Provides namespaced package manager functions
#==============================================================================

# Load dependencies
if [[ -n "${ZSH_SETUP_ROOT:-}" ]]; then
    source "$ZSH_SETUP_ROOT/lib/core/config.sh"
    source "$ZSH_SETUP_ROOT/lib/core/logger.sh"
    source "$ZSH_SETUP_ROOT/lib/core/errors.sh"
fi

#------------------------------------------------------------------------------
# Package Manager Detection
#------------------------------------------------------------------------------

# Detect available package manager
zsh_setup::system::package_manager::detect() {
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
zsh_setup::system::package_manager::get_name() {
    local pm=$(zsh_setup::system::package_manager::detect)
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
# Package Operations
#------------------------------------------------------------------------------

# Check if a package is installed
zsh_setup::system::package_manager::is_installed() {
    local package_name="$1"
    local pm=$(zsh_setup::system::package_manager::detect)
    
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
zsh_setup::system::package_manager::get_version() {
    local package_name="$1"
    local pm=$(zsh_setup::system::package_manager::detect)
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

# Install a package
zsh_setup::system::package_manager::install() {
    local package_name="$1"
    local description="${2:-Installing $package_name}"
    local pm=$(zsh_setup::system::package_manager::detect)
    
    # Check if already installed
    if zsh_setup::system::package_manager::is_installed "$package_name"; then
        zsh_setup::core::logger::info "✅ $package_name is already installed ($(zsh_setup::system::package_manager::get_name))"
        return 0
    fi
    
    zsh_setup::core::logger::info "📦 $description via $(zsh_setup::system::package_manager::get_name)..."
    
    case "$pm" in
        brew)
            zsh_setup::core::errors::execute_with_retry "$description" brew install "$package_name"
            ;;
        apt)
            zsh_setup::core::errors::execute_with_retry "$description" sudo apt-get install -y "$package_name"
            ;;
        dnf)
            zsh_setup::core::errors::execute_with_retry "$description" sudo dnf install -y "$package_name"
            ;;
        yum)
            zsh_setup::core::errors::execute_with_retry "$description" sudo yum install -y "$package_name"
            ;;
        pacman)
            zsh_setup::core::errors::execute_with_retry "$description" sudo pacman -S --noconfirm "$package_name"
            ;;
        zypper)
            zsh_setup::core::errors::execute_with_retry "$description" sudo zypper install -y "$package_name"
            ;;
        *)
            zsh_setup::core::logger::error "No supported package manager found. Cannot install $package_name"
            return 1
            ;;
    esac
}

# Map plugin names to system package names
zsh_setup::system::package_manager::map_plugin_to_package() {
    local plugin_name="$1"
    
    case "$plugin_name" in
        bat) echo "bat" ;;
        fd) echo "fd" ;;
        ripgrep) echo "ripgrep" ;;
        fzf) echo "fzf" ;;
        zoxide) echo "zoxide" ;;
        autojump) echo "autojump" ;;
        eza|exa) echo "eza" ;;
        thefuck) echo "thefuck" ;;
        *) echo "$plugin_name" ;;
    esac
}

# Install plugin dependencies
zsh_setup::system::package_manager::install_dependency() {
    local plugin_name="$1"
    local pm=$(zsh_setup::system::package_manager::detect)
    
    if [[ "$pm" == "unknown" ]]; then
        zsh_setup::core::logger::warn "No package manager detected. Cannot install dependencies for $plugin_name"
        return 1
    fi
    
    local package_name=$(zsh_setup::system::package_manager::map_plugin_to_package "$plugin_name")
    
    if [[ -z "$package_name" ]]; then
        zsh_setup::core::logger::debug "No system package mapping for $plugin_name"
        return 0
    fi
    
    if ! zsh_setup::system::package_manager::is_installed "$package_name"; then
        zsh_setup::core::logger::info "Installing system dependency: $package_name"
        zsh_setup::system::package_manager::install "$package_name" "Installing dependency for $plugin_name"
    else
        zsh_setup::core::logger::debug "Dependency $package_name already installed"
    fi
}

# Backward compatibility
detect_package_manager() {
    zsh_setup::system::package_manager::detect
}

get_package_manager_name() {
    zsh_setup::system::package_manager::get_name
}

is_package_installed() {
    zsh_setup::system::package_manager::is_installed "$@"
}

get_package_version() {
    zsh_setup::system::package_manager::get_version "$@"
}

install_package() {
    zsh_setup::system::package_manager::install "$@"
}

map_plugin_to_package() {
    zsh_setup::system::package_manager::map_plugin_to_package "$@"
}

install_plugin_dependencies() {
    zsh_setup::system::package_manager::install_dependency "$@"
}
