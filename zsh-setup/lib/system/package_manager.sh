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
    # Load progress module if available
    if [[ -f "$ZSH_SETUP_ROOT/lib/core/progress.sh" ]]; then
        source "$ZSH_SETUP_ROOT/lib/core/progress.sh" 2>/dev/null || true
    fi
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
        if declare -f zsh_setup::core::progress::status_line &>/dev/null; then
            zsh_setup::core::progress::status_line "✅ $package_name is already installed ($(zsh_setup::system::package_manager::get_name))"
        else
            zsh_setup::core::logger::info "✅ $package_name is already installed ($(zsh_setup::system::package_manager::get_name))"
        fi
        return 0
    fi
    
    # Use spinner for installation
    local spinner_pid=""
    if declare -f zsh_setup::core::progress::spinner_start &>/dev/null; then
        spinner_pid=$(zsh_setup::core::progress::spinner_start "Installing $package_name via $(zsh_setup::system::package_manager::get_name)")
    else
        zsh_setup::core::logger::info "📦 $description via $(zsh_setup::system::package_manager::get_name)..."
    fi
    
    local install_success=false
    case "$pm" in
        brew)
            # Homebrew typically doesn't need sudo on macOS (especially with /opt/homebrew)
            # But check if we can write to the brew prefix
            local brew_prefix=$(brew --prefix 2>/dev/null || echo "/usr/local")
            if [[ -w "$brew_prefix" ]] || [[ -w "$(dirname "$brew_prefix")" ]]; then
                if zsh_setup::core::errors::execute_with_retry "$description" brew install "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                # Need sudo for Homebrew
                zsh_setup::core::bootstrap::load_module "system::validation"
                if zsh_setup::system::validation::has_privileges; then
                    if zsh_setup::core::errors::execute_with_retry "$description" brew install "$package_name" >/dev/null 2>&1; then
                        install_success=true
                    fi
                else
                    install_success=false
                fi
            fi
            ;;
        apt)
            zsh_setup::core::bootstrap::load_module "system::validation"
            if zsh_setup::system::validation::has_privileges; then
                if zsh_setup::core::errors::execute_with_retry "$description" sudo apt-get install -y "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                install_success=false
            fi
            ;;
        dnf)
            zsh_setup::core::bootstrap::load_module "system::validation"
            if zsh_setup::system::validation::has_privileges; then
                if zsh_setup::core::errors::execute_with_retry "$description" sudo dnf install -y "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                install_success=false
            fi
            ;;
        yum)
            zsh_setup::core::bootstrap::load_module "system::validation"
            if zsh_setup::system::validation::has_privileges; then
                if zsh_setup::core::errors::execute_with_retry "$description" sudo yum install -y "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                install_success=false
            fi
            ;;
        pacman)
            zsh_setup::core::bootstrap::load_module "system::validation"
            if zsh_setup::system::validation::has_privileges; then
                if zsh_setup::core::errors::execute_with_retry "$description" sudo pacman -S --noconfirm "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                install_success=false
            fi
            ;;
        zypper)
            zsh_setup::core::bootstrap::load_module "system::validation"
            if zsh_setup::system::validation::has_privileges; then
                if zsh_setup::core::errors::execute_with_retry "$description" sudo zypper install -y "$package_name" >/dev/null 2>&1; then
                    install_success=true
                fi
            else
                install_success=false
            fi
            ;;
        *)
            install_success=false
            ;;
    esac
    
    # Stop spinner and show result
    if [[ -n "$spinner_pid" ]] && declare -f zsh_setup::core::progress::spinner_stop &>/dev/null; then
        if [[ "$install_success" == "true" ]]; then
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "✅ Successfully installed $package_name via $(zsh_setup::system::package_manager::get_name)" "" 0
        else
            local error_msg=""
            case "$pm" in
                brew)
                    error_msg="Cannot install $package_name: Homebrew requires write access"
                    ;;
                apt|dnf|yum|pacman|zypper)
                    error_msg="Cannot install $package_name: $(zsh_setup::system::package_manager::get_name) requires sudo privileges"
                    ;;
                *)
                    error_msg="No supported package manager found. Cannot install $package_name"
                    ;;
            esac
            zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "$error_msg" 1
        fi
    elif [[ "$install_success" != "true" ]]; then
        case "$pm" in
            brew)
                zsh_setup::core::logger::warn "Cannot install $package_name: Homebrew requires write access and no sudo privileges available"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later."
                ;;
            apt)
                zsh_setup::core::logger::warn "Cannot install $package_name: APT requires sudo privileges"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later with: sudo apt-get install $package_name"
                ;;
            dnf)
                zsh_setup::core::logger::warn "Cannot install $package_name: DNF requires sudo privileges"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later with: sudo dnf install $package_name"
                ;;
            yum)
                zsh_setup::core::logger::warn "Cannot install $package_name: YUM requires sudo privileges"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later with: sudo yum install $package_name"
                ;;
            pacman)
                zsh_setup::core::logger::warn "Cannot install $package_name: Pacman requires sudo privileges"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later with: sudo pacman -S $package_name"
                ;;
            zypper)
                zsh_setup::core::logger::warn "Cannot install $package_name: Zypper requires sudo privileges"
                zsh_setup::core::logger::info "Skipping $package_name installation. You can install it manually later with: sudo zypper install $package_name"
                ;;
            *)
                zsh_setup::core::logger::error "No supported package manager found. Cannot install $package_name"
                ;;
        esac
        return 1
    fi
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
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

