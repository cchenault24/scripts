# Home Network Monitor Setup

A production-quality, automated setup script for deploying a self-hosted home network monitoring solution using Gatus and ntfy.sh with Docker Compose on macOS.

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Bash](https://img.shields.io/badge/bash-3.2+-blue)

## Overview

This installer script transforms a Mac mini (or any macOS system) into a reliable, self-hosted network monitoring appliance. The script is designed for technically competent users who value correctness, safety, reversibility, and clean UX.

### What It Does

The script automates the installation and configuration of:

- **Gatus**: A health monitoring dashboard for your network services and endpoints
- **ntfy**: A simple HTTP-based pub-sub notification service for alerts

### Design Philosophy

- **Production Quality**: Safe to run on your primary Mac mini
- **Idempotent**: Can be safely re-run indefinitely without issues
- **Reversible**: Complete, clean uninstall that leaves no traces
- **Zero Hand-Holding**: Clear prompts, but respects your time
- **Safe by Default**: Never silently installs software without explicit consent

## Features

- 🔍 **Automatic Detection**: Router IP, AdGuard DNS ports, existing installations
- 🐳 **Docker Compose Orchestration**: Reliable container management
- 🚀 **Auto-Start on Boot**: Optional LaunchAgent for unattended operation
- 🔧 **Interactive Configuration**: Smart prompts with sensible defaults
- 🧹 **Complete Uninstall**: Removes everything cleanly, optionally removes Docker Desktop
- 📦 **Dependency Management**: Automatically handles Xcode CLI Tools, Homebrew, Docker, and CLI tools
- 📝 **Comprehensive Logging**: All operations logged with timestamps for troubleshooting
- ✅ **Input Validation**: Port conflicts, IP format validation, sanitization
- 🔄 **Update-Safe**: Preserves your configuration when re-running
- 🛡️ **Error Recovery**: Graceful handling of failures and interruptions

## System Requirements

- **macOS**: 10.15 (Catalina) or later
- **Bash**: Default system Bash (3.2+) - no additional shell required
- **Permissions**: Administrative access for installing dependencies
- **Network**: Internet connection for downloading Docker images and dependencies
- **Disk Space**: ~500MB for Docker images and data

## Quick Start

1. **Download or clone the script:**
   ```bash
   cd /path/to/scripts/home-netmon
   ```

2. **Make it executable:**
   ```bash
   chmod +x setup-home-netmon.sh
   ```

3. **Run the installer:**
   ```bash
   ./setup-home-netmon.sh
   ```

4. **Follow the prompts:**
   - Choose option `1` to install
   - The script will detect and prompt for any missing dependencies
   - Enter your router IP (or accept the auto-detected value)
   - Configure ports (defaults: Gatus 3001, ntfy 8088)
   - Optionally install LaunchAgent for auto-start

5. **Access your services:**
   - Gatus Dashboard: `http://localhost:3001`
   - ntfy Dashboard: `http://localhost:8088`

## Installation Details

### What Gets Installed

#### Dependencies (with your consent)

The script will check for and optionally install:

1. **Xcode Command Line Tools** (required for Homebrew)
   - Prompts before installing
   - May require GUI interaction to complete

2. **Homebrew** (package manager)
   - Installed to `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)
   - Never uninstalled by this script

3. **Docker Desktop** (container runtime)
   - Installed via Homebrew Cask
   - Optional removal during uninstall

4. **CLI Tools**: `curl`, `jq`
   - Installed via Homebrew if missing

#### Application Files

The script creates the following structure:

```
~/home-netmon/
├── .env                    # Environment configuration (preserved on updates)
├── docker-compose.yml      # Docker Compose configuration (regenerated on updates)
├── install.log             # Installation and operation logs
├── gatus/                  # Gatus configuration directory
├── ntfy/                   # ntfy data directory
└── data/                   # General data directory
```

#### LaunchAgent (Optional)

If you choose to install it:

- **Location**: `~/Library/LaunchAgents/com.netmon.startup.plist`
- **Purpose**: Automatically starts containers on login
- **Logs**: `~/home-netmon/launchagent.log` and `launchagent-error.log`

### Configuration

#### Environment Variables (`.env` file)

The script creates and manages a `.env` file with the following variables:

| Variable | Description | Default | Auto-Detected |
|----------|-------------|---------|---------------|
| `ROUTER_IP` | Router IP address for monitoring | `192.168.1.1` | ✅ Yes |
| `GATUS_PORT` | Port for Gatus web interface | `3001` | ❌ No |
| `NTFY_PORT` | Port for ntfy web interface | `8088` | ❌ No |
| `ADGUARD_DNS_PORT` | AdGuard DNS port | - | ✅ Yes (if AdGuard running) |

**Important**: On updates, existing values are preserved. The script only prompts for missing keys.

#### Port Configuration

- **Gatus**: Default port `3001` (configurable)
- **ntfy**: Default port `8088` (configurable)
- Ports are validated for:
  - Valid range (1-65535)
  - Conflicts with existing services
  - Format correctness

## Usage

### Accessing Services

After installation:

- **Gatus Dashboard**: Open `http://localhost:3001` in your browser
- **ntfy Dashboard**: Open `http://localhost:8088` in your browser

### Managing Services Manually

```bash
cd ~/home-netmon

# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f

# View logs for specific service
docker compose logs -f gatus
docker compose logs -f ntfy

# Restart services
docker compose restart

# Check status
docker compose ps
```

### Updating Configuration

Simply re-run the installer:

```bash
./setup-home-netmon.sh
# Choose option 1 (Install or update)
```

The script will:
- Detect existing installation
- Preserve your current `.env` values
- Only prompt for missing or new configuration keys
- Update `docker-compose.yml` if needed
- Restart containers with new configuration

### Viewing Logs

**Installation Logs:**
```bash
tail -f ~/home-netmon/install.log
```

**LaunchAgent Logs:**
```bash
tail -f ~/home-netmon/launchagent.log
tail -f ~/home-netmon/launchagent-error.log
```

**Docker Container Logs:**
```bash
cd ~/home-netmon
docker compose logs -f
```

## Uninstallation

To completely remove the network monitor:

1. **Run the script:**
   ```bash
   ./setup-home-netmon.sh
   ```

2. **Choose option 2 (Uninstall)**

3. **Confirm the uninstall**

The uninstall process will:
- ✅ Stop and remove Docker containers and volumes
- ✅ Remove the LaunchAgent (if installed)
- ✅ Delete the `~/home-netmon/` directory and all data
- ✅ Optionally remove Docker Desktop (your choice)
- ✅ **Never** remove Homebrew or other system tools
- ✅ Verify complete removal

**Important**: Uninstallation is **destructive** and **irreversible**. All monitoring data and configuration will be permanently deleted.

## Troubleshooting

### Docker Desktop Not Starting

**Symptoms**: Script hangs waiting for Docker engine, or "Docker CLI not on PATH" error.

**Solutions**:
1. Open Docker Desktop manually from Applications
2. Wait for it to fully start (whale icon in menu bar)
3. Re-run the script
4. If Docker was just installed, open a new Terminal window first

### Port Conflicts

**Symptoms**: "Port already in use" errors or validation failures.

**Solutions**:
1. Choose different ports during installation
2. Identify what's using the port:
   ```bash
   lsof -i :3001  # Replace with your port
   ```
3. Stop the conflicting service or choose a different port

### LaunchAgent Not Working

**Symptoms**: Services don't start automatically on login.

**Solutions**:
1. **Check if LaunchAgent is loaded:**
   ```bash
   launchctl list | grep netmon
   ```

2. **Manually load it:**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.netmon.startup.plist
   ```

3. **Check LaunchAgent logs:**
   ```bash
   tail -f ~/home-netmon/launchagent.log
   tail -f ~/home-netmon/launchagent-error.log
   ```

4. **Check system logs:**
   ```bash
   log show --predicate 'process == "com.netmon.startup"' --last 5m
   ```

5. **Reinstall LaunchAgent:**
   - Run the installer again and choose to update
   - Select "Yes" when prompted about LaunchAgent

### Containers Not Starting

**Symptoms**: Containers exit immediately or show errors.

**Solutions**:
1. **Check container logs:**
   ```bash
   cd ~/home-netmon
   docker compose logs
   ```

2. **Check Docker status:**
   ```bash
   docker info
   ```

3. **Verify configuration:**
   ```bash
   cat ~/home-netmon/.env
   cat ~/home-netmon/docker-compose.yml
   ```

4. **Check disk space:**
   ```bash
   df -h
   ```

### Installation Fails Partway Through

**Symptoms**: Script exits with error, partial installation exists.

**Solutions**:
1. **Check the log file:**
   ```bash
   tail -50 ~/home-netmon/install.log
   ```

2. **Run uninstall to clean up:**
   ```bash
   ./setup-home-netmon.sh
   # Choose option 2
   ```

3. **Re-run installation:**
   ```bash
   ./setup-home-netmon.sh
   # Choose option 1
   ```

The script is idempotent and safe to re-run.

### Services Not Accessible

**Symptoms**: Can't access Gatus or ntfy in browser.

**Solutions**:
1. **Verify containers are running:**
   ```bash
   cd ~/home-netmon
   docker compose ps
   ```

2. **Check if ports are correct:**
   ```bash
   cat ~/home-netmon/.env
   ```

3. **Test connectivity:**
   ```bash
   curl http://localhost:3001  # Gatus
   curl http://localhost:8088  # ntfy
   ```

4. **Check firewall settings** (macOS may block ports)

5. **Wait a bit**: Containers may need 30-60 seconds to fully start

### Router IP Detection Fails

**Symptoms**: Auto-detected router IP is incorrect or missing.

**Solutions**:
1. **Find your router IP manually:**
   - System Settings > Network > Wi-Fi > Details > TCP/IP > Router
   - Or run: `route -n get default | grep gateway`

2. **Enter it manually** when prompted (the script allows this)

3. **Ping test fails but IP is correct**: Choose "Accept anyway" when prompted

## Advanced Usage

### Custom Configuration

You can manually edit `~/.home-netmon/.env` after installation. The script will preserve your changes on updates, but be careful with:
- Port numbers (must be valid and available)
- IP addresses (must be valid format)
- Special characters (will be sanitized)

### Backup Before Uninstall

If you want to backup your configuration before uninstalling:

```bash
# Backup configuration
cp -r ~/home-netmon ~/home-netmon-backup

# Backup just the config
mkdir -p ~/netmon-backup
cp ~/home-netmon/.env ~/netmon-backup/
cp ~/home-netmon/docker-compose.yml ~/netmon-backup/
cp -r ~/home-netmon/gatus ~/netmon-backup/ 2>/dev/null || true
```

### Running on a Headless Mac

For Mac minis running headless (no display):

1. SSH into the Mac
2. Run the installer as normal
3. The script works entirely via command line
4. LaunchAgent will start services on boot even without login

### Monitoring Multiple Networks

The current setup monitors your local network. To monitor multiple networks or external services, configure Gatus with additional endpoints via its web interface at `http://localhost:3001`.

## Dependencies

The script automatically manages these dependencies (with your consent):

| Dependency | Purpose | Installation Method |
|------------|---------|---------------------|
| Xcode Command Line Tools | Required for Homebrew | `xcode-select --install` |
| Homebrew | Package manager | Official installer script |
| Docker Desktop | Container runtime | Homebrew Cask |
| curl | HTTP client | Homebrew (usually pre-installed) |
| jq | JSON processor | Homebrew |

**Note**: Homebrew is never uninstalled by this script, even during full uninstall.

## Logging

All operations are logged to `~/home-netmon/install.log` with:
- Timestamps for every operation
- User inputs (sanitized)
- System information
- Error details
- Operation outcomes

Log file format:
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message
```

Example:
```
[2024-01-15 14:23:45] [INFO] Starting installation
[2024-01-15 14:23:46] [INFO] Xcode Command Line Tools already installed
[2024-01-15 14:23:47] [INFO] Homebrew already installed
```

## Security Considerations

- The script runs with your user permissions (no sudo required for most operations)
- Docker Desktop installation may require administrator password
- LaunchAgent runs as your user, not root
- All user inputs are sanitized before use
- No sensitive data is logged (passwords, tokens, etc.)
- Containers run with default Docker security settings

## Limitations

- **macOS Only**: Designed specifically for macOS
- **Docker Desktop Required**: Does not support Docker Engine without Desktop
- **Single Installation**: One installation per user (uses `~/home-netmon`)
- **Network Monitoring Focus**: Primarily for local network monitoring, not deep observability

## Contributing

This is a production-quality script. Contributions should maintain:
- Bash 3.2 compatibility
- Idempotency
- Clear error messages
- Comprehensive logging
- User safety

## License

This script is provided as-is with no warranties. Use at your own risk.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review `~/home-netmon/install.log` for error details
3. Verify your system meets the requirements
4. Check that Docker Desktop is running and accessible

---

**Last Updated**: Script version includes comprehensive error handling, logging, validation, and production-quality UX improvements.
