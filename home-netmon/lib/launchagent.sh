#!/bin/bash
# Home Network Monitor - LaunchAgent Management
# LaunchAgent management (install, uninstall)
# Compatible with macOS default Bash 3.2

# Prevent direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "This is a library file and should be sourced, not executed."
  exit 1
fi

#------------------------------------------------------------------------------
# LaunchAgent Management
#------------------------------------------------------------------------------

install_launchagent() {
  : "${LAUNCH_AGENT:=${HOME}/Library/LaunchAgents/com.netmon.startup.plist}"
  : "${BASE_DIR:=${HOME}/home-netmon}"
  : "${ENV_FILE:=${BASE_DIR}/.env}"
  : "${APP_NAME:=netmon}"
  
  if launchagent_installed; then
    if command -v say >/dev/null 2>&1; then
      say "LaunchAgent already installed. Updating..."
    fi
    if command -v log_info >/dev/null 2>&1; then
      log_info "LaunchAgent already exists, updating"
    fi
    launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  fi
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "Creating LaunchAgent plist"
  fi
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
    if command -v warn >/dev/null 2>&1; then
      warn "Failed to load LaunchAgent. You may need to log out and back in."
    fi
    if command -v log_warn >/dev/null 2>&1; then
      log_warn "LaunchAgent load failed"
    fi
  }
  
  if command -v log_info >/dev/null 2>&1; then
    log_info "LaunchAgent installed successfully"
  fi
  if command -v say >/dev/null 2>&1; then
    say "LaunchAgent installed. Services will start automatically on login."
  fi
}

uninstall_launchagent() {
  : "${LAUNCH_AGENT:=${HOME}/Library/LaunchAgents/com.netmon.startup.plist}"
  
  if [ -f "$LAUNCH_AGENT" ]; then
    launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
    rm -f "$LAUNCH_AGENT"
    if command -v log_info >/dev/null 2>&1; then
      log_info "LaunchAgent removed"
    fi
    return 0
  fi
  return 1
}
