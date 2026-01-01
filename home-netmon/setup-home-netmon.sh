#!/bin/bash
# Home Network Monitor Installer
# Production-quality installer for Gatus + ntfy monitoring stack
# Compatible with macOS default Bash 3.2

set -euo pipefail

#------------------------------------------------------------------------------
# Get script directory and setup paths
#------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

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
# Load Modules (in dependency order)
#------------------------------------------------------------------------------

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/network.sh"      # Load before validation.sh (prompt_ip uses ping_ok)
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/dependencies.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/launchagent.sh"
source "${LIB_DIR}/backup.sh"
source "${LIB_DIR}/gatus.sh"

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
  
  # Generate initial Gatus config
  say ""
  say "Generating Gatus configuration..."
  generate_gatus_config
  
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
  say "Verifying installation..."
  log_info "Starting installation verification"
  
  local errors=0
  if ! verify_containers; then
    errors=$((errors + 1))
  fi
  
  if [ $errors -eq 0 ]; then
    say "Installation verification completed successfully"
    log_info "Installation verification completed successfully"
  else
    warn "Installation verification found some issues"
    log_warn "Installation verification found issues"
  fi
  
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
  if launchagent_installed; then
    say ""
    say "Removing LaunchAgent..."
    log_info "Removing LaunchAgent"
    uninstall_launchagent
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
  
  if launchagent_installed; then
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
