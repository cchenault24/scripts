#!/bin/bash
# Home Network Monitor - Dependency Management
# Dependency installation (Xcode, Homebrew, Docker)
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# Dependency Management
#------------------------------------------------------------------------------

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    if command -v log_info >/dev/null 2>&1; then
      log_info "Xcode Command Line Tools already installed"
    fi
    return 0
  fi
  
  if command -v warn >/dev/null 2>&1; then
    warn "Xcode Command Line Tools not found."
  fi
  if command -v say >/dev/null 2>&1; then
    say "Xcode Command Line Tools are required for Homebrew and other development tools."
  fi
  
  if ! confirm "Install Xcode Command Line Tools now?" "Y"; then
    if command -v err >/dev/null 2>&1; then
      err "Xcode Command Line Tools are required. Exiting."
    fi
    exit 1
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Installing Xcode Command Line Tools..."
  fi
  xcode-select --install || true
  if command -v say >/dev/null 2>&1; then
    say "Please complete the Xcode Command Line Tools installer, then re-run this script."
  fi
  exit 0
}

ensure_homebrew() {
  if command_exists brew; then
    if command -v log_info >/dev/null 2>&1; then
      log_info "Homebrew already installed"
    fi
    return 0
  fi
  
  if command -v warn >/dev/null 2>&1; then
    warn "Homebrew not found."
  fi
  if command -v say >/dev/null 2>&1; then
    say "Homebrew is required to install Docker Desktop and other dependencies."
  fi
  
  if ! confirm "Install Homebrew now?" "Y"; then
    if command -v err >/dev/null 2>&1; then
      err "Homebrew is required. Exiting."
    fi
    exit 1
  fi
  
  ensure_xcode_clt
  if command -v log_info >/dev/null 2>&1; then
    log_info "Installing Homebrew..."
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  # Setup Homebrew in current shell
  if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Homebrew installed successfully"
  fi
}

ensure_cli_tool() {
  local bin="$1"
  local formula="$2"
  
  if command_exists "$bin"; then
    if command -v log_info >/dev/null 2>&1; then
      log_info "$bin already installed"
    fi
    return 0
  fi
  
  ensure_homebrew
  if command -v say >/dev/null 2>&1; then
    say "$bin is not installed."
  fi
  
  if ! confirm "Install ${formula} via Homebrew?" "Y"; then
    if command -v err >/dev/null 2>&1; then
      err "$bin is required. Exiting."
    fi
    exit 1
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Installing $formula via Homebrew..."
  fi
  brew install "$formula"
  if command -v log_info >/dev/null 2>&1; then
    log_info "$formula installed successfully"
  fi
}

ensure_docker() {
  local docker_app="/Applications/Docker.app"
  local max_wait=120
  local waited=0

  if [ ! -d "$docker_app" ]; then
    if command -v warn >/dev/null 2>&1; then
      warn "Docker Desktop not installed."
    fi
    ensure_homebrew
    if command -v say >/dev/null 2>&1; then
      say "Docker Desktop is required to run the monitoring containers."
    fi
    
    if ! confirm "Install Docker Desktop?" "Y"; then
      if command -v err >/dev/null 2>&1; then
        err "Docker Desktop is required. Exiting."
      fi
      exit 1
    fi
    
    if command -v log_info >/dev/null 2>&1; then
      log_info "Installing Docker Desktop via Homebrew..."
    fi
    brew install --cask docker
    if command -v log_info >/dev/null 2>&1; then
      log_info "Docker Desktop installed. Please start it manually and re-run this script."
    fi
    if command -v say >/dev/null 2>&1; then
      say "Docker Desktop has been installed. Please:"
      say "1. Open Docker Desktop from Applications"
      say "2. Wait for it to fully start"
      say "3. Re-run this script"
    fi
    exit 0
  fi

  if ! command_exists docker; then
    if command -v err >/dev/null 2>&1; then
      err "Docker CLI not found on PATH."
      err "This usually means Docker Desktop was just installed."
      err "Please open a new Terminal window and re-run this script."
    fi
    exit 1
  fi

  # Check if Docker Desktop is running
  if ! pgrep -f Docker >/dev/null 2>&1; then
    if command -v say >/dev/null 2>&1; then
      say "Starting Docker Desktop..."
    fi
    if command -v log_info >/dev/null 2>&1; then
      log_info "Starting Docker Desktop application"
    fi
    open -a Docker
    
    if command -v say >/dev/null 2>&1; then
      say "Waiting for Docker engine to start (this may take up to 2 minutes)..."
    fi
    if command -v log_info >/dev/null 2>&1; then
      log_info "Waiting for Docker engine to be ready"
    fi
    
    while [ $waited -lt $max_wait ]; do
      if docker info >/dev/null 2>&1; then
        if command -v log_info >/dev/null 2>&1; then
          log_info "Docker engine is ready"
        fi
        return 0
      fi
      sleep 2
      waited=$((waited + 2))
      if [ $((waited % 10)) -eq 0 ]; then
        echo -n "."
      fi
    done
    echo ""
    
    if command -v err >/dev/null 2>&1; then
      err "Docker engine did not start within $max_wait seconds."
      err "Please ensure Docker Desktop is running and try again."
    fi
    exit 1
  fi

  # Verify Docker is accessible
  if ! docker info >/dev/null 2>&1; then
    if command -v err >/dev/null 2>&1; then
      err "Docker engine is not accessible."
      err "Please ensure Docker Desktop is fully started and try again."
    fi
    exit 1
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Docker is ready"
  fi
}
