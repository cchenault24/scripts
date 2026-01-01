#!/bin/bash
# Home Network Monitor Installer
# Production-quality installer for Gatus + ntfy monitoring stack
# Compatible with macOS default Bash 3.2

set -euo pipefail

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------

APP_NAME="netmon"
BASE_DIR="${HOME}/home-netmon"
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
DATA_DIR="${BASE_DIR}/data"
GATUS_DIR="${BASE_DIR}/gatus"
NTFY_DIR="${BASE_DIR}/ntfy"
LOG_FILE="${BASE_DIR}/install.log"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.${APP_NAME}.startup.plist"

LOG_PREFIX="[netmon]"
INSTALL_IN_PROGRESS=false
CLEANUP_NEEDED=false

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

init_logging() {
  mkdir -p "$BASE_DIR"
  if [ ! -f "$LOG_FILE" ]; then
    {
      echo "=== Home Network Monitor Install Log ==="
      echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "System: $(uname -a)"
      echo "User: $(whoami)"
      echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
      echo "========================================"
    } > "$LOG_FILE"
  fi
}

log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() {
  log_message "INFO" "$@"
}

log_warn() {
  log_message "WARN" "$@"
}

log_error() {
  log_message "ERROR" "$@"
}

log_user_input() {
  # Sanitize and log user inputs (remove sensitive data)
  local sanitized=$(echo "$1" | sed 's/[^a-zA-Z0-9._:-]//g')
  log_info "User input: $sanitized"
}

#------------------------------------------------------------------------------
# Output Functions
#------------------------------------------------------------------------------

say() {
  echo "${LOG_PREFIX} $*"
  log_info "$@"
}

warn() {
  echo "${LOG_PREFIX} WARNING: $*" >&2
  log_warn "$@"
}

err() {
  echo "${LOG_PREFIX} ERROR: $*" >&2
  log_error "$@"
}

info() {
  echo "${LOG_PREFIX} INFO: $*"
  log_info "$@"
}

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="$1"
  local def="${2:-Y}"
  local ans=""
  local other_opt
  
  if [ "$def" = "Y" ]; then
    other_opt="n"
  else
    other_opt="y"
  fi
  
  read -r -p "$prompt [${def}/${other_opt}]: " ans || true
  ans=$(lower "${ans:-$def}")
  case "$ans" in
    y|yes) return 0 ;;
    n|no)  return 1 ;;
    *)     [ "$def" = "Y" ] && return 0 || return 1 ;;
  esac
}

#------------------------------------------------------------------------------
# Error Handling & Cleanup
#------------------------------------------------------------------------------

cleanup_on_exit() {
  local exit_code=$?
  
  if [ $exit_code -ne 0 ] && [ "$INSTALL_IN_PROGRESS" = "true" ]; then
    log_error "Installation failed with exit code $exit_code"
    warn "Installation was interrupted. You may need to run uninstall to clean up."
  fi
  
  if [ "$CLEANUP_NEEDED" = "true" ]; then
    log_info "Performing cleanup..."
  fi
  
  exit $exit_code
}

cleanup_on_interrupt() {
  log_error "Script interrupted by user"
  echo ""
  warn "Installation interrupted. Run uninstall if you need to clean up."
  exit 130
}

trap cleanup_on_exit EXIT
trap cleanup_on_interrupt INT TERM

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

validate_ip() {
  local ip="$1"
  
  # Basic format check (bash 3.2 compatible - no regex)
  local octet1 octet2 octet3 octet4
  IFS='.' read -r octet1 octet2 octet3 octet4 <<< "$ip" || return 1
  
  # Check we have 4 octets
  if [ -z "$octet1" ] || [ -z "$octet2" ] || [ -z "$octet3" ] || [ -z "$octet4" ]; then
    return 1
  fi
  
  # Validate each octet is numeric and in range
  for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
    case "$octet" in
      *[!0-9]*) return 1 ;;
    esac
    if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
      return 1
    fi
  done
  
  return 0
}

validate_port() {
  local port="$1"
  
  # Check if numeric
  case "$port" in
    *[!0-9]*) return 1 ;;
  esac
  
  # Check range
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi
  
  # Check if port is in use (if lsof is available)
  if command_exists lsof; then
    if lsof -i ":$port" >/dev/null 2>&1; then
      return 1
    fi
  fi
  
  return 0
}

sanitize_input() {
  # Remove potentially dangerous characters
  echo "$1" | tr -d ';|&<>`$"\\'
}

#------------------------------------------------------------------------------
# State Detection Functions
#------------------------------------------------------------------------------

is_installed() {
  [ -d "$BASE_DIR" ] && [ -f "$COMPOSE_FILE" ] && [ -f "$ENV_FILE" ]
}

containers_running() {
  if [ ! -d "$BASE_DIR" ] || [ ! -f "$COMPOSE_FILE" ]; then
    return 1
  fi
  
  if ! command_exists docker; then
    return 1
  fi
  
  # Check if containers are running (bash 3.2 compatible)
  local ps_output
  ps_output=$(cd "$BASE_DIR" && docker compose ps --format json 2>/dev/null || echo "")
  
  if [ -z "$ps_output" ]; then
    return 1
  fi
  
  # Check for running state (simple grep, no jq required)
  echo "$ps_output" | grep -q '"State":"running"' || return 1
  return 0
}

launchagent_installed() {
  [ -f "$LAUNCH_AGENT" ]
}

#------------------------------------------------------------------------------
# Dependency Management
#------------------------------------------------------------------------------

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log_info "Xcode Command Line Tools already installed"
    return 0
  fi
  
  warn "Xcode Command Line Tools not found."
  say "Xcode Command Line Tools are required for Homebrew and other development tools."
  
  if ! confirm "Install Xcode Command Line Tools now?" "Y"; then
    err "Xcode Command Line Tools are required. Exiting."
    exit 1
  fi
  
  log_info "Installing Xcode Command Line Tools..."
  xcode-select --install || true
  say "Please complete the Xcode Command Line Tools installer, then re-run this script."
  exit 0
}

ensure_homebrew() {
  if command_exists brew; then
    log_info "Homebrew already installed"
    return 0
  fi
  
  warn "Homebrew not found."
  say "Homebrew is required to install Docker Desktop and other dependencies."
  
  if ! confirm "Install Homebrew now?" "Y"; then
    err "Homebrew is required. Exiting."
    exit 1
  fi
  
  ensure_xcode_clt
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  # Setup Homebrew in current shell
  if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  
  log_info "Homebrew installed successfully"
}

ensure_cli_tool() {
  local bin="$1"
  local formula="$2"
  
  if command_exists "$bin"; then
    log_info "$bin already installed"
    return 0
  fi
  
  ensure_homebrew
  say "$bin is not installed."
  
  if ! confirm "Install ${formula} via Homebrew?" "Y"; then
    err "$bin is required. Exiting."
    exit 1
  fi
  
  log_info "Installing $formula via Homebrew..."
  brew install "$formula"
  log_info "$formula installed successfully"
}

ensure_docker() {
  local docker_app="/Applications/Docker.app"
  local max_wait=120
  local waited=0

  if [ ! -d "$docker_app" ]; then
    warn "Docker Desktop not installed."
    ensure_homebrew
    say "Docker Desktop is required to run the monitoring containers."
    
    if ! confirm "Install Docker Desktop?" "Y"; then
      err "Docker Desktop is required. Exiting."
      exit 1
    fi
    
    log_info "Installing Docker Desktop via Homebrew..."
    brew install --cask docker
    log_info "Docker Desktop installed. Please start it manually and re-run this script."
    say "Docker Desktop has been installed. Please:"
    say "1. Open Docker Desktop from Applications"
    say "2. Wait for it to fully start"
    say "3. Re-run this script"
    exit 0
  fi

  if ! command_exists docker; then
    err "Docker CLI not found on PATH."
    err "This usually means Docker Desktop was just installed."
    err "Please open a new Terminal window and re-run this script."
    exit 1
  fi

  # Check if Docker Desktop is running
  if ! pgrep -f Docker >/dev/null 2>&1; then
    say "Starting Docker Desktop..."
    log_info "Starting Docker Desktop application"
    open -a Docker
    
    say "Waiting for Docker engine to start (this may take up to 2 minutes)..."
    log_info "Waiting for Docker engine to be ready"
    
    while [ $waited -lt $max_wait ]; do
      if docker info >/dev/null 2>&1; then
        log_info "Docker engine is ready"
        return 0
      fi
      sleep 2
      waited=$((waited + 2))
      if [ $((waited % 10)) -eq 0 ]; then
        echo -n "."
      fi
    done
    echo ""
    
    err "Docker engine did not start within $max_wait seconds."
    err "Please ensure Docker Desktop is running and try again."
    exit 1
  fi

  # Verify Docker is accessible
  if ! docker info >/dev/null 2>&1; then
    err "Docker engine is not accessible."
    err "Please ensure Docker Desktop is fully started and try again."
    exit 1
  fi
  
  log_info "Docker is ready"
}

#------------------------------------------------------------------------------
# Network Detection Functions
#------------------------------------------------------------------------------

detect_gateway() {
  route -n get default 2>/dev/null | awk '/gateway:/{print $2}' || true
}

ping_ok() {
  ping -c 1 -W 1000 "$1" >/dev/null 2>&1
}

detect_adguard_dns_port() {
  if ! command_exists docker; then
    return 1
  fi
  
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | awk -F'|' '
    tolower($1) ~ /adguard/ {
      if (match($2, /([0-9]{2,5})->53\/(tcp|udp)/, m)) {
        print m[1]; exit
      }
    }
  ' || true
}

#------------------------------------------------------------------------------
# Configuration Management
#------------------------------------------------------------------------------

load_env_if_exists() {
  if [ -f "$ENV_FILE" ]; then
    log_info "Loading existing .env file"
    # Source .env file safely (bash 3.2 compatible)
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      case "$key" in
        \#*|"") continue ;;
      esac
      # Remove quotes if present
      value=$(echo "$value" | sed "s/^['\"]//; s/['\"]$//")
      export "$key=$value"
    done < "$ENV_FILE"
  fi
}

get_env_value() {
  local key="$1"
  if [ -f "$ENV_FILE" ]; then
    grep "^${key}=" "$ENV_FILE" | cut -d= -f2- | sed "s/^['\"]//; s/['\"]$//"
  fi
}

upsert_env() {
  local key="$1"
  local value="$2"
  local comment="$3"
  
  mkdir -p "$BASE_DIR"
  touch "$ENV_FILE"
  
  # Add comment if provided and key doesn't exist
  if [ -n "$comment" ] && ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "# $comment" >> "$ENV_FILE"
  fi
  
  if grep -q "^${key}=" "$ENV_FILE"; then
    # Update existing value (preserve comment if any)
    local temp_file=$(mktemp)
    awk -v key="$key" -v val="$value" '
      /^#.*/ { print; next }
      /^[[:space:]]*#/ { print; next }
      $0 ~ "^" key "=" { print key "=" val; next }
      { print }
    ' "$ENV_FILE" > "$temp_file"
    mv "$temp_file" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  
  log_info "Updated .env: ${key}=${value}"
}

prompt_if_missing() {
  local key="$1"
  local prompt_text="$2"
  local default="$3"
  local validator="${4:-}"
  local comment="$5"
  
  local existing_value
  existing_value=$(get_env_value "$key")
  
  if [ -n "$existing_value" ]; then
    say "Using existing ${key}: ${existing_value}"
    eval "export ${key}=\"${existing_value}\""
    log_info "Using existing value for $key: $existing_value"
    return 0
  fi
  
  # Prompt for new value
  local value=""
  local valid=false
  
  while [ "$valid" = false ]; do
    echo ""
    echo "$prompt_text"
    read -r -p "[default: ${default}]: " value || true
    value="${value:-$default}"
    value=$(sanitize_input "$value")
    
    if [ -n "$validator" ]; then
      if $validator "$value"; then
        valid=true
      else
        warn "Invalid value. Please try again."
        continue
      fi
    else
      valid=true
    fi
  done
  
  log_user_input "$key=$value"
  upsert_env "$key" "$value" "$comment"
  eval "export ${key}=\"${value}\""
}

prompt_ip() {
  local label="$1"
  local hint="$2"
  local def="$3"
  local ip=""

  while true; do
    echo ""
    echo "$label"
    echo "($hint)"
    read -r -p "[default: ${def}]: " ip || true
    ip="${ip:-$def}"
    ip=$(sanitize_input "$ip")

    if ! validate_ip "$ip"; then
      warn "Invalid IP address format. Please enter a valid IP (e.g., 192.168.1.1)"
      continue
    fi

    if ping_ok "$ip"; then
      echo "$ip"
      return 0
    fi

    warn "Ping to $ip failed."
    if confirm "Accept this IP anyway?" "n"; then
      echo "$ip"
      return 0
    fi
  done
}

#------------------------------------------------------------------------------
# Docker Management
#------------------------------------------------------------------------------

generate_compose_file() {
  log_info "Generating docker-compose.yml"
  cat > "$COMPOSE_FILE" <<'YAML'
# Home Network Monitor - Docker Compose Configuration
# Generated by setup-home-netmon.sh
# Do not edit manually - changes will be overwritten on update

services:
  gatus:
    image: twinproduction/gatus:latest
    container_name: home-netmon-gatus
    restart: unless-stopped
    ports:
      - "${GATUS_PORT}:8080"
    volumes:
      - "./gatus:/config"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: home-netmon-ntfy
    restart: unless-stopped
    ports:
      - "${NTFY_PORT}:80"
    volumes:
      - "./ntfy:/var/lib/ntfy"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
YAML
  log_info "docker-compose.yml generated"
}

start_containers() {
  if containers_running; then
    say "Containers are already running. Updating configuration..."
    log_info "Containers already running, performing update"
    cd "$BASE_DIR"
    docker compose --env-file "$ENV_FILE" up -d
  else
    say "Starting Docker containers..."
    log_info "Starting Docker containers"
    cd "$BASE_DIR"
    docker compose --env-file "$ENV_FILE" up -d
    
    # Wait a moment for containers to start
    sleep 3
  fi
  
  log_info "Docker containers started"
}

#------------------------------------------------------------------------------
# Verification Functions
#------------------------------------------------------------------------------

verify_installation() {
  say ""
  say "Verifying installation..."
  log_info "Starting installation verification"
  
  local errors=0
  
  # Check containers are running
  if ! containers_running; then
    err "Containers are not running"
    log_error "Container verification failed"
    errors=$((errors + 1))
  else
    info "✓ Containers are running"
    log_info "Container verification passed"
  fi
  
  # Check Gatus port
  local gatus_port
  gatus_port=$(get_env_value "GATUS_PORT")
  if [ -n "$gatus_port" ]; then
    if command_exists curl; then
      if curl -sf "http://localhost:${gatus_port}" >/dev/null 2>&1; then
        info "✓ Gatus is accessible on port ${gatus_port}"
        log_info "Gatus accessibility check passed"
      else
        warn "Gatus may not be fully ready on port ${gatus_port} (this is normal if it just started)"
        log_warn "Gatus accessibility check: service may still be starting"
      fi
    fi
  fi
  
  # Check ntfy port
  local ntfy_port
  ntfy_port=$(get_env_value "NTFY_PORT")
  if [ -n "$ntfy_port" ]; then
    if command_exists curl; then
      if curl -sf "http://localhost:${ntfy_port}" >/dev/null 2>&1; then
        info "✓ ntfy is accessible on port ${ntfy_port}"
        log_info "ntfy accessibility check passed"
      else
        warn "ntfy may not be fully ready on port ${ntfy_port} (this is normal if it just started)"
        log_warn "ntfy accessibility check: service may still be starting"
      fi
    fi
  fi
  
  if [ $errors -eq 0 ]; then
    say "Installation verification completed successfully"
    log_info "Installation verification completed successfully"
    return 0
  else
    warn "Installation verification found some issues"
    log_warn "Installation verification found issues"
    return 1
  fi
}

#------------------------------------------------------------------------------
# LaunchAgent Management
#------------------------------------------------------------------------------

install_launchagent() {
  if launchagent_installed; then
    say "LaunchAgent already installed. Updating..."
    log_info "LaunchAgent already exists, updating"
    launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  fi
  
  log_info "Creating LaunchAgent plist"
  cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.${APP_NAME}.startup</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>cd ${BASE_DIR} && docker compose --env-file ${ENV_FILE} up -d</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${BASE_DIR}/launchagent.log</string>
  <key>StandardErrorPath</key>
  <string>${BASE_DIR}/launchagent-error.log</string>
</dict>
</plist>
PLIST
  
  launchctl load "$LAUNCH_AGENT" 2>/dev/null || {
    warn "Failed to load LaunchAgent. You may need to log out and back in."
    log_warn "LaunchAgent load failed"
  }
  
  log_info "LaunchAgent installed successfully"
  say "LaunchAgent installed. Services will start automatically on login."
}

#------------------------------------------------------------------------------
# Installation Function
#------------------------------------------------------------------------------

install_netmon() {
  INSTALL_IN_PROGRESS=true
  log_info "=== Starting installation ==="
  
  say ""
  say "=========================================="
  say "Home Network Monitor - Installation"
  say "=========================================="
  say ""
  
  # Check if already installed
  if is_installed; then
    say "Existing installation detected. This will update your configuration."
    log_info "Update mode: existing installation detected"
    
    if ! confirm "Continue with update?" "Y"; then
      say "Update cancelled."
      exit 0
    fi
    
    # Load existing environment
    load_env_if_exists
  else
    say "Starting fresh installation..."
    log_info "Fresh installation mode"
  fi
  
  # Ensure dependencies
  say ""
  say "Checking dependencies..."
  ensure_cli_tool curl curl
  ensure_cli_tool jq jq
  ensure_docker
  
  # Create directories
  say ""
  say "Setting up directories..."
  mkdir -p "$DATA_DIR" "$GATUS_DIR" "$NTFY_DIR"
  log_info "Directories created"
  
  # Network configuration
  say ""
  say "Network Configuration"
  say "--------------------"
  
  local auto_router
  auto_router=$(detect_gateway)
  auto_router="${auto_router:-192.168.1.1}"
  
  local router_ip
  router_ip=$(prompt_ip \
    "Router IP" \
    "System Settings > Network > Wi-Fi > Details > TCP/IP > Router" \
    "$auto_router")
  
  upsert_env "ROUTER_IP" "$router_ip" "Router IP address for monitoring"
  
  # Port configuration with validation
  say ""
  say "Port Configuration"
  say "------------------"
  
  prompt_if_missing "GATUS_PORT" \
    "Gatus web interface port" \
    "3001" \
    "validate_port" \
    "Port for Gatus monitoring dashboard"
  
  prompt_if_missing "NTFY_PORT" \
    "ntfy web interface port" \
    "8088" \
    "validate_port" \
    "Port for ntfy notification service"
  
  # AdGuard detection
  local adguard_port
  adguard_port=$(detect_adguard_dns_port)
  
  if [ -n "$adguard_port" ]; then
    say ""
    say "Detected AdGuard DNS running on port: $adguard_port"
    log_info "AdGuard DNS detected on port $adguard_port"
    upsert_env "ADGUARD_DNS_PORT" "$adguard_port" "AdGuard DNS port (auto-detected)"
  fi
  
  # Generate docker-compose.yml
  say ""
  say "Generating Docker configuration..."
  generate_compose_file
  
  # Start containers
  say ""
  start_containers
  
  # LaunchAgent
  say ""
  if ! launchagent_installed; then
    if confirm "Install LaunchAgent for automatic startup on login?" "Y"; then
      install_launchagent
    else
      say "Skipping LaunchAgent installation."
      log_info "User declined LaunchAgent installation"
    fi
  else
    if confirm "LaunchAgent is already installed. Update it?" "Y"; then
      install_launchagent
    else
      say "Keeping existing LaunchAgent."
      log_info "User declined LaunchAgent update"
    fi
  fi
  
  # Verification
  say ""
  verify_installation
  
  # Success message
  say ""
  say "=========================================="
  say "Installation Complete!"
  say "=========================================="
  say ""
  say "Services are now running:"
  say "  • Gatus:  http://localhost:${GATUS_PORT}"
  say "  • ntfy:   http://localhost:${NTFY_PORT}"
  say ""
  say "Configuration directory: ${BASE_DIR}"
  say "Log file: ${LOG_FILE}"
  say ""
  say "To manage services manually:"
  say "  cd ${BASE_DIR}"
  say "  docker compose up -d    # Start"
  say "  docker compose down      # Stop"
  say "  docker compose logs -f   # View logs"
  say ""
  
  log_info "=== Installation completed successfully ==="
  INSTALL_IN_PROGRESS=false
}

#------------------------------------------------------------------------------
# Uninstall Function
#------------------------------------------------------------------------------

uninstall_netmon() {
  log_info "=== Starting uninstallation ==="
  
  say ""
  say "=========================================="
  say "Home Network Monitor - Uninstallation"
  say "=========================================="
  say ""
  
  if ! is_installed; then
    say "No installation found. Nothing to uninstall."
    log_info "Uninstall: no installation found"
    exit 0
  fi
  
  warn "This will completely remove the home network monitor installation."
  say ""
  say "This will remove:"
  say "  • Docker containers and volumes"
  say "  • Configuration files and data"
  say "  • LaunchAgent (if installed)"
  say "  • All data in ${BASE_DIR}"
  say ""
  
  if ! confirm "Are you sure you want to continue?" "n"; then
    say "Uninstall cancelled."
    exit 0
  fi
  
  # Stop and remove containers
  if [ -d "$BASE_DIR" ] && command_exists docker; then
    say ""
    say "Stopping and removing Docker containers..."
    log_info "Stopping Docker containers"
    
    if [ -f "$COMPOSE_FILE" ]; then
      (cd "$BASE_DIR" && docker compose down -v) || {
        warn "Some containers may not have been removed. Continuing..."
        log_warn "Some containers may not have been removed"
      }
      say "✓ Containers stopped and removed"
    fi
  fi
  
  # Remove LaunchAgent
  if [ -f "$LAUNCH_AGENT" ]; then
    say ""
    say "Removing LaunchAgent..."
    log_info "Removing LaunchAgent"
    launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
    rm -f "$LAUNCH_AGENT"
    say "✓ LaunchAgent removed"
  fi
  
  # Remove data directory
  if [ -d "$BASE_DIR" ]; then
    say ""
    say "Removing installation directory..."
    log_info "Removing installation directory: $BASE_DIR"
    rm -rf "$BASE_DIR"
    say "✓ Installation directory removed"
  fi
  
  # Optional Docker Desktop removal
  if [ -d "/Applications/Docker.app" ]; then
    say ""
    if confirm "Remove Docker Desktop as well?" "n"; then
      log_info "User requested Docker Desktop removal"
      if command_exists brew; then
        brew uninstall --cask docker 2>/dev/null || {
          warn "Failed to remove Docker Desktop via Homebrew. You may need to remove it manually."
          log_warn "Docker Desktop removal failed"
        }
        say "✓ Docker Desktop removed"
      else
        warn "Homebrew not found. Please remove Docker Desktop manually."
      fi
    fi
  fi
  
  # Verification
  say ""
  say "Verifying uninstallation..."
  local issues=0
  
  if [ -d "$BASE_DIR" ]; then
    warn "Installation directory still exists: ${BASE_DIR}"
    issues=$((issues + 1))
  fi
  
  if [ -f "$LAUNCH_AGENT" ]; then
    warn "LaunchAgent still exists: ${LAUNCH_AGENT}"
    issues=$((issues + 1))
  fi
  
  if command_exists docker && [ -d "$BASE_DIR" ]; then
    local running_containers
    running_containers=$(docker ps --filter "name=home-netmon" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$running_containers" ]; then
      warn "Some containers may still be running"
      issues=$((issues + 1))
    fi
  fi
  
  if [ $issues -eq 0 ]; then
    say ""
    say "=========================================="
    say "Uninstallation Complete"
    say "=========================================="
    say ""
    say "All components have been removed successfully."
    say "Homebrew and other system tools were not modified."
    say ""
    log_info "=== Uninstallation completed successfully ==="
  else
    warn "Uninstallation completed with some warnings."
    warn "Please review the messages above."
    log_warn "Uninstallation completed with warnings"
  fi
  
  exit 0
}

#------------------------------------------------------------------------------
# Main Entry Point
#------------------------------------------------------------------------------

main() {
  # Initialize logging first
  init_logging
  log_info "Script started"
  
  # Display menu
  echo ""
  echo "=========================================="
  echo "Home Network Monitor"
  echo "=========================================="
  echo ""
  echo "1) Install or update"
  echo "2) Uninstall"
  echo ""
  
  local choice
  read -r -p "Choose [1/2]: " choice || true
  log_user_input "menu_choice=$choice"
  
  case "$choice" in
    2)
      uninstall_netmon
      ;;
    1|"")
      install_netmon
      ;;
    *)
      err "Invalid choice. Please run the script again and select 1 or 2."
      exit 1
      ;;
  esac
}

# Run main function
main
