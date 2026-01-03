# macOS Cleanup Utility

An interactive, safety-focused utility script to clean temporary files, caches, and logs on macOS systems.

![Version](https://img.shields.io/badge/version-4.0.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

The macOS Cleanup Utility (`mac-cleanup.sh`) is a comprehensive, interactive cleanup tool designed to help macOS users free up disk space by safely removing temporary files, application caches, logs, and other unnecessary data that accumulates over time.

### Key Features

- 🔍 **Interactive Selection** - Choose cleanup operations with real-time size preview
- 🔒 **Safety First** - Automatic backups, dry-run mode, and comprehensive error handling
- 📦 **Smart Backups** - JSON-based manifest system with automatic backup verification
- 🎨 **Beautiful UI** - Color-coded output with progress bars and fzf-based selection
- 🧰 **Comprehensive Coverage** - 22+ cleanup plugins across 5 categories
- 🤖 **Smart Detection** - Only offers to clean applications that are actually installed
- 📊 **Detailed Reporting** - Disk space calculation and savings summary by operation
- 🧪 **Dry-Run Mode** - Preview all operations without making changes
- 📝 **Comprehensive Logging** - Detailed operation logs with multiple log levels
- 🔐 **Secure Admin Operations** - Auto-detected admin user with sudo credential caching
- ↩️ **Undo Functionality** - Restore files from previous backups interactively
- 📈 **Progress Tracking** - Real-time progress bars with item-level detail
- ⏰ **Automated Scheduling** - Daily, weekly, or monthly cleanup via LaunchAgents
- 🔌 **Plugin Architecture** - Modular, extensible plugin system for easy customization
- ⚡ **Performance Optimized** - Parallel size calculations, size caching, and async operations

## System Requirements

- **macOS**: 10.15 (Catalina) or later
- **Shell**: Zsh (default on modern macOS)
- **Permissions**: Administrative account (auto-detected) for certain cleanup operations
- **Dependencies**: `fzf` (auto-installed if missing), `find`, `tar`, `gzip`
- **Disk Space**: Sufficient space for temporary backups (typically 10-20% of data to be cleaned)

## Installation

### Quick Install

1. Clone or download the repository:
   ```bash
   git clone https://github.com/yourusername/scripts.git
   cd scripts/mac-cleanup
   ```

2. Make the script executable:
   ```bash
   chmod +x mac-cleanup.sh
   ```

3. Run the script:
   ```bash
   ./mac-cleanup.sh
   ```

The script will automatically check for and install `fzf` if it's not already available.

### Directory Structure

The script uses a modular plugin-based architecture:

```
mac-cleanup/
├── mac-cleanup.sh          # Main entry point
├── lib/                    # Core libraries
│   ├── constants.sh        # Configuration constants and thresholds
│   ├── core.sh             # State management, plugin registry
│   ├── ui.sh               # UI functions and color output
│   ├── utils.sh            # Utility functions (size calculation, etc.)
│   ├── backup.sh           # Backup/restore wrapper (backward compatible)
│   ├── backup/             # New backup engine modules
│   │   ├── engine.sh       # Backup execution engine
│   │   ├── storage.sh      # Backup storage operations
│   │   ├── manifest.sh     # JSON manifest management
│   │   ├── restore.sh      # Restore operations
│   │   └── validation.sh   # Backup validation
│   ├── admin.sh            # Admin operations and sudo handling
│   ├── validation.sh       # Input validation
│   └── error_handler.sh    # Error handling and recovery
├── plugins/                # Cleanup operation plugins
│   ├── base.sh             # Plugin base interface and API
│   ├── browsers/           # Browser cache plugins
│   │   ├── chrome.sh       # Google Chrome
│   │   ├── firefox.sh      # Mozilla Firefox
│   │   ├── safari.sh       # Apple Safari
│   │   ├── edge.sh         # Microsoft Edge
│   │   └── common.sh       # Shared browser utilities
│   ├── package-managers/   # Package manager plugins
│   │   ├── homebrew.sh     # Homebrew cache
│   │   ├── npm.sh          # npm and yarn cache
│   │   ├── pip.sh          # Python pip cache
│   │   ├── gradle.sh       # Gradle cache
│   │   └── maven.sh        # Maven repository
│   ├── development/        # Development tool plugins
│   │   ├── dev_tools.sh    # IntelliJ IDEA, VS Code
│   │   ├── docker.sh       # Docker cache
│   │   ├── node_modules.sh # Node.js modules
│   │   └── xcode.sh        # Xcode derived data
│   ├── system/             # System cleanup plugins
│   │   ├── user_cache.sh   # User cache files
│   │   ├── system_cache.sh # System cache files
│   │   ├── logs.sh         # Application and system logs
│   │   ├── temp_files.sh   # Temporary files
│   │   └── containers.sh   # Application containers
│   └── maintenance/        # Maintenance plugins
│       ├── dns.sh          # DNS cache flush
│       ├── lockfiles.sh     # Preference lockfiles
│       └── trash.sh        # Empty Trash
└── features/               # Additional features
    ├── undo.sh             # Undo/restore functionality
    └── schedule.sh         # Automated scheduling
```

## Usage

### Basic Usage

1. Open Terminal.app
2. Run the script:
   ```bash
   ./mac-cleanup.sh
   ```

3. Follow the interactive prompts:
   - Select cleanup categories (System, Browsers, Development, etc.)
   - Select specific cleanup operations within each category
   - Each option shows the size of files that will be cleaned
   - Confirm your selection

4. Review the results:
   - Progress bars show real-time cleanup progress
   - Summary shows total space saved and breakdown by operation
   - Backup location and log file paths are displayed

### Command Line Options

```bash
./mac-cleanup.sh [OPTIONS]
```

**Options:**

- `--dry-run` - Preview all operations without making any changes. Shows what would be cleaned and estimated space savings.
- `--undo` - Restore files from a previous backup session. Lists available backups and allows interactive selection.
- `--schedule` - Setup automated scheduling for cleanup. Generates LaunchAgent plist files for daily, weekly, or monthly runs.
- `--quiet` - Run in quiet mode (for automated/scheduled runs). Skips interactive prompts where possible.
- `--help` or `-h` - Display help message and exit.

### Examples

**Preview what would be cleaned:**
```bash
./mac-cleanup.sh --dry-run
```

**Restore from a backup:**
```bash
./mac-cleanup.sh --undo
```

**Setup weekly automated cleanup:**
```bash
./mac-cleanup.sh --schedule
# Select "weekly" when prompted
```

**Run in quiet mode (for scripts):**
```bash
./mac-cleanup.sh --quiet
```

## Cleanup Operations

The script includes **22 cleanup plugins** organized into 5 categories:

### System Cleanup (5 plugins)

- **User Cache** - Cleans cache files in `~/Library/Caches`
  - Size: Calculated dynamically
  - Admin Required: No
  
- **System Cache** - Cleans system-wide cache in `/Library/Caches`
  - Size: Calculated dynamically
  - Admin Required: Yes
  
- **Application Logs** - Removes log files in `~/Library/Logs`
  - Size: Calculated dynamically
  - Admin Required: No
  
- **System Logs** - Cleans system log files in `/var/log` (`.log` and `.log.*` files only)
  - Size: Calculated dynamically
  - Admin Required: Yes
  
- **Temporary Files** - Cleans temporary files in `/tmp`, `$TMPDIR`, and application temp directories
  - Excludes: `.X*` files, `com.apple.*` files, script's own temp files
  - Size: Calculated dynamically
  - Admin Required: No

### Browser Caches (4 plugins)

All browser plugins clean cache, web data, and service workers for all profiles:

- **Safari Cache** - Cleans Safari browser cache and web data
  - Locations: `~/Library/Caches/com.apple.Safari`, `~/Library/Safari/LocalStorage`, etc.
  - Size: Calculated dynamically
  - Admin Required: No

- **Chrome Cache** - Cleans Google Chrome browser cache and web data (all profiles)
  - Locations: `~/Library/Caches/Google/Chrome`, `~/Library/Application Support/Google/Chrome/*/Cache`, etc.
  - Size: Calculated dynamically
  - Admin Required: No

- **Firefox Cache** - Cleans Firefox browser cache and web data (all profiles)
  - Locations: `~/Library/Caches/Firefox`, `~/Library/Application Support/Firefox/Profiles/*/cache2`, etc.
  - Size: Calculated dynamically
  - Admin Required: No

- **Microsoft Edge Cache** - Cleans Microsoft Edge browser cache and web data (all profiles)
  - Locations: `~/Library/Caches/com.microsoft.edgemac`, `~/Library/Application Support/Microsoft Edge/*/Cache`, etc.
  - Size: Calculated dynamically
  - Admin Required: No

### Package Manager Caches (5 plugins)

- **Homebrew Cache** - Cleans Homebrew package manager cache
  - Location: `$(brew --cache)` or `~/Library/Caches/Homebrew`
  - Size: Calculated dynamically
  - Admin Required: No

- **npm Cache** - Cleans npm and yarn package manager caches
  - Locations: `$(npm config get cache)` (typically `~/.npm`), yarn cache
  - Note: Manually removes `_cacache` directory after `npm cache clean --force`
  - Size: Calculated dynamically
  - Admin Required: No

- **pip Cache** - Cleans Python pip cache
  - Location: `$(pip cache dir)` or `~/Library/Caches/pip`
  - Size: Calculated dynamically
  - Admin Required: No

- **Gradle Cache** - Cleans Gradle build cache and wrapper caches
  - Locations: `~/.gradle/caches`, `~/.gradle/wrapper`
  - Size: Calculated dynamically
  - Admin Required: No

- **Maven Cache** - Cleans Maven local repository cache
  - Location: `~/.m2/repository`
  - Size: Calculated dynamically
  - Admin Required: No

### Development Tools (4 plugins)

- **Developer Tool Temp Files** - Cleans temporary files from IntelliJ IDEA and VS Code
  - JetBrains: `~/Library/Caches/JetBrains`, `~/Library/Application Support/JetBrains`, `~/Library/Logs/JetBrains`
  - VS Code: `~/Library/Application Support/Code/Cache`, `~/Library/Caches/com.microsoft.VSCode`, etc.
  - Size: Calculated dynamically
  - Admin Required: No

- **Xcode Data** - Cleans Xcode derived data, archives, and device support files
  - Locations: `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/Xcode/Archives`, etc.
  - ⚠️ **Warning**: May require rebuilding projects after cleanup
  - Size: Calculated dynamically
  - Admin Required: No

- **Node.js Modules** - Cleans Node.js module caches (optional `node_modules` cleanup with confirmation)
  - Locations: `~/.node_modules`, `~/.npm-global`
  - ⚠️ **Warning**: Cleaning `node_modules` requires re-running `npm install` or `yarn install`
  - Size: Calculated dynamically
  - Admin Required: No

- **Docker Cache** - Cleans unused Docker images, containers, volumes, and build cache
  - Uses: `docker system prune -a --volumes --force`
  - ⚠️ **Note**: Requires Docker Desktop to be running
  - Size: Calculated via `docker system df`
  - Admin Required: No

### Application-Specific (2 plugins)

- **Application Container Caches** - Cleans cache files in application containers
  - Location: `~/Library/Containers/*/Caches`
  - Size: Calculated dynamically
  - Admin Required: No

- **Saved Application States** - Cleans saved application states
  - Location: `~/Library/Saved Application State`
  - Size: Calculated dynamically
  - Admin Required: No

### System Maintenance (3 plugins)

- **Corrupted Preference Lockfiles** - Removes orphaned preference lockfiles
  - Locations: `~/Library/Preferences/*.lock`, `~/Library/Application Support/*.lock`
  - Size: Calculated dynamically
  - Admin Required: No

- **Empty Trash** - Empties the user's Trash
  - Location: `~/.Trash`
  - Size: Calculated dynamically
  - Admin Required: No

- **Flush DNS Cache** - Flushes the DNS cache
  - Uses: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
  - Size: N/A (no disk space freed)
  - Admin Required: Yes

## Safety Features

The script includes comprehensive safety measures to protect your system:

### Backup System

- **Automatic Backups** - Creates backups of all cleaned files before removal
- **JSON Manifest** - Modern JSON-based manifest system tracks all backed up files with metadata
- **Backward Compatibility** - Supports both new JSON manifests and legacy text manifests
- **Backup Verification** - Verifies that backups were created successfully before proceeding
- **Smart Skipping** - Skips empty directories (< 1MB) to improve performance
- **Compressed Storage** - Backups are stored as compressed tar.gz archives
- **Session Tracking** - Each cleanup session creates a timestamped backup directory

### Safety Measures

- **Dry-Run Mode** - Preview all operations without making any changes using `--dry-run` flag
- **Non-root Operation** - Refuses to run as root to prevent system damage
- **Interactive Confirmation** - Requires confirmation before performing potentially impactful operations
- **Selective Cleanup** - Allows you to choose which areas to clean
- **Smart Detection** - Only offers to clean applications that are actually installed
- **Detailed Warnings** - Provides clear warnings for operations with potential side effects (e.g., Xcode, node_modules)
- **Operation Logging** - Comprehensive logging of all operations with multiple log levels (DEBUG, INFO, WARNING, ERROR, SUCCESS)
- **Secure Admin Operations** - Uses sudo with credential caching and auto-detects admin user
- **Error Handling** - Comprehensive error handling with graceful recovery
- **Progress Tracking** - Real-time progress bars prevent operations from appearing hung
- **Timeout Protection** - Plugin operations have timeout protection (default 30 minutes)

### Reporting

- **Space Saved Summary** - Shows total disk space reclaimed and breakdown by operation
- **Detailed Logging** - All operations logged to `cleanup.log` in backup directory
- **Operation Breakdown** - Per-operation space savings tracking
- **Backup Manifest** - Complete list of all backed up files and their original paths

## Backup and Restoration

### Backup System Architecture

The script uses a modern backup system with the following features:

- **JSON Manifest Format** - Structured metadata about all backed up files
- **Compressed Archives** - Files are backed up as tar.gz archives
- **Session-Based Organization** - Each cleanup session creates a timestamped directory: `~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/`
- **Manifest Files** - `backup_manifest.json` contains file paths, sizes, timestamps, and checksums
- **Backward Compatibility** - Automatically migrates old text manifests to JSON format

### Automatic Restoration

Use the `--undo` flag to interactively restore from a previous backup:

```bash
./mac-cleanup.sh --undo
```

This will:
1. List all available backup sessions with dates and sizes
2. Let you select which backup to restore using fzf
3. Restore all files from that backup session to their original locations
4. Verify restoration success

### Manual Restoration

To manually restore from a backup:

1. Navigate to the backup directory:
   ```bash
   cd ~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/
   ```

2. View the manifest:
   ```bash
   cat backup_manifest.json
   ```

3. Extract specific backup archives:
   ```bash
   tar -xzf backup_name.tar.gz -C /destination/path/
   ```

### Backup Directory Contents

Each backup session directory contains:
- `backup_manifest.json` - JSON manifest with all backed up files and metadata
- `backup_manifest.txt` - Legacy text manifest (if migrated from old version)
- `cleanup.log` - Detailed log of all operations performed
- `*.tar.gz` - Compressed backup archives for each cleaned directory/file

## Automated Scheduling

The script supports automated scheduling using macOS LaunchAgents:

### Setup

1. Run the scheduling setup:
   ```bash
   ./mac-cleanup.sh --schedule
   ```

2. Select your preferred schedule:
   - **Daily** - Runs every 24 hours
   - **Weekly** - Runs every 7 days
   - **Monthly** - Runs every 30 days

3. The script generates a LaunchAgent plist file at:
   ```
   ~/Library/LaunchAgents/com.mac-cleanup.agent.plist
   ```

4. Activate the schedule:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.mac-cleanup.agent.plist
   ```

### Management

**Check if schedule is active:**
```bash
launchctl list | grep mac-cleanup
```

**Remove the schedule:**
```bash
launchctl unload ~/Library/LaunchAgents/com.mac-cleanup.agent.plist
rm ~/Library/LaunchAgents/com.mac-cleanup.agent.plist
```

**View scheduled run logs:**
```bash
cat ~/.mac-cleanup-backups/scheduled.log
cat ~/.mac-cleanup-backups/scheduled-error.log
```

Scheduled runs execute in quiet mode and log results to `~/.mac-cleanup-backups/scheduled.log`.

## Architecture

### Plugin System

The script uses a modular plugin-based architecture:

- **Plugin Discovery** - Automatically discovers and loads plugins from `plugins/` subdirectories
- **Plugin Registry** - Central registry tracks all plugins with metadata (name, category, function, admin requirements, version, dependencies)
- **Size Calculation** - Plugins can register custom size calculation functions for accurate previews
- **Category Organization** - Plugins are organized into categories (system, browsers, development, package-managers, maintenance)
- **Dependency Support** - Plugins can declare dependencies to ensure proper execution order
- **Version Tracking** - Plugin versions are tracked for compatibility and debugging

### Core Components

- **Core Library** (`lib/core.sh`) - State management, plugin registry, initialization
- **UI Library** (`lib/ui.sh`) - Color-coded output, progress bars, user interaction
- **Utils Library** (`lib/utils.sh`) - Size calculation, file operations, caching
- **Backup Engine** (`lib/backup/`) - Modern backup system with JSON manifests
- **Admin Library** (`lib/admin.sh`) - Sudo handling, admin user detection
- **Error Handler** (`lib/error_handler.sh`) - Error handling and recovery

### Performance Optimizations

- **Parallel Size Calculation** - Plugin sizes are calculated in parallel using background processes
- **Size Caching** - Size calculations are cached to avoid redundant disk I/O
- **Async Operations** - Long-running operations run asynchronously with progress tracking
- **Smart Skipping** - Empty directories and small files are skipped to improve performance
- **Lock File Management** - File locking prevents race conditions in concurrent operations

## Dependencies

### Required

- **fzf** - Interactive fuzzy finder for selection menus
  - Auto-installed if missing
  - Can be removed after use if installed by script

### System Tools

- **find** - File system search (standard macOS tool)
- **tar** - Archive creation/extraction (standard macOS tool)
- **gzip** - Compression (standard macOS tool)
- **zsh** - Shell interpreter (default on macOS)

### Optional

- **Docker** - Required only for Docker cache cleanup
- **Homebrew** - Required only for Homebrew cache cleanup
- **npm/yarn** - Required only for npm cache cleanup
- **pip** - Required only for pip cache cleanup
- **Gradle** - Required only for Gradle cache cleanup
- **Maven** - Required only for Maven cache cleanup

## Troubleshooting

### Common Issues

**Permission Denied Errors**
- Make sure the script is executable: `chmod +x mac-cleanup.sh`
- Check file permissions on the script directory

**Admin Privileges Required**
- Some operations require admin privileges (System Cache, System Logs, DNS Flush)
- The script will auto-detect your admin account or prompt you
- Enter your password when prompted for sudo operations

**Backup Failures**
- Ensure you have sufficient disk space for backups (typically 10-20% of data to be cleaned)
- Check disk space: `df -h ~`
- The script skips empty directories automatically to save space

**fzf Installation Failures**
- If automatic installation fails, try installing fzf manually:
  ```bash
  brew install fzf
  ```
- Or download from: https://github.com/junegunn/fzf

**Plugin Load Errors**
- Check that plugin files are executable: `chmod +x plugins/**/*.sh`
- Review the log file for specific plugin errors: `~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/cleanup.log`

**Docker Cleanup Issues**
- Ensure Docker Desktop is running before attempting Docker cache cleanup
- Check Docker status: `docker info`

**Xcode Cleanup Warnings**
- Cleaning Xcode data may require rebuilding projects
- Consider backing up important archives first
- Derived data will be regenerated on next build

**Node Modules Cleanup**
- Cleaning `node_modules` requires re-running `npm install` or `yarn install` in affected projects
- Only clean if you're sure you can reinstall dependencies

**Size Calculation Issues**
- If sizes appear incorrect, try clearing the size cache by running the script again
- Check that target directories exist and are accessible

**Check Logs**
- Review the `cleanup.log` file in the backup directory for detailed information about operations and any errors
- Log files are automatically compressed after cleanup completes

### Getting Help

1. Check the log file: `~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/cleanup.log`
2. Run with `--dry-run` to preview operations
3. Review the backup manifest to see what was backed up
4. Use `--undo` to restore if something went wrong

## Plugin Development

The script uses a plugin-based architecture, making it easy to add new cleanup operations.

### Plugin API

Plugins are registered using the `register_plugin` function:

```bash
register_plugin <name> <category> <clean_function> <requires_admin> [size_function] [version] [dependencies]
```

**Parameters:**
- `name` - Display name of the plugin (string)
- `category` - Category name (e.g., "browsers", "system", "package-managers")
- `clean_function` - Function name that performs the cleanup (must exist)
- `requires_admin` - "true" or "false" - whether plugin needs admin privileges
- `size_function` - (optional) Function name that calculates size to be cleaned
- `version` - (optional) Plugin version string (e.g., "1.0.0")
- `dependencies` - (optional) Space-separated list of plugin names that must run first

### Plugin Function Requirements

**Clean Function:**
- Must exist and be callable
- Should handle errors gracefully
- Should use `print_header` for operation start
- Should use `track_space_saved` to report space freed
- Should use `log_message` for logging

**Size Function (optional):**
- Should return size in bytes as a number
- Should handle missing directories gracefully (return 0)
- Should be fast (may be called multiple times)

### Example Plugin

```bash
#!/bin/zsh
# plugins/example/my_plugin.sh

# Size calculation function (optional but recommended)
_calculate_my_cache_size_bytes() {
  local cache_dir="$HOME/.myapp/cache"
  if [[ -d "$cache_dir" ]]; then
    calculate_size_bytes "$cache_dir"
  else
    echo "0"
  fi
}

# Cleanup function (required)
clean_my_cache() {
  print_header "Cleaning My Cache"
  
  local cache_dir="$HOME/.myapp/cache"
  if [[ ! -d "$cache_dir" ]]; then
    print_info "My Cache directory not found. Skipping."
    return 0
  fi
  
  local space_before=$(calculate_size_bytes "$cache_dir")
  
  # Perform cleanup
  if [[ "$MC_DRY_RUN" != "true" ]]; then
    # Backup first
    backup "$cache_dir" "My Cache"
    
    # Clean
    rm -rf "$cache_dir"/*
    
    # Calculate space saved
    local space_after=$(calculate_size_bytes "$cache_dir")
    local space_freed=$((space_before - space_after))
    
    # Track space saved
    track_space_saved "My Cache" $space_freed
    print_success "Cleaned My Cache: $(format_bytes $space_freed)"
  else
    print_info "DRY RUN: Would clean My Cache: $(format_bytes $space_before)"
  fi
}

# Register the plugin
register_plugin "My Cache" "example" "clean_my_cache" "false" "_calculate_my_cache_size_bytes" "1.0.0" ""
```

### Plugin Categories

Standard categories:
- `system` - System-level cleanup (may require admin)
- `browsers` - Browser cache cleanup
- `package-managers` - Package manager cache cleanup
- `development` - Development tool cleanup
- `maintenance` - General maintenance operations

Plugins can also define custom categories.

### Plugin Best Practices

1. **Always backup before cleaning** - Use the `backup` function
2. **Handle missing directories** - Check if directories exist before cleaning
3. **Report space saved** - Use `track_space_saved` to report space freed
4. **Log operations** - Use `log_message` for important operations
5. **Handle errors gracefully** - Don't exit on errors, log and continue
6. **Provide size calculation** - Register a size function for accurate previews
7. **Test with dry-run** - Always test plugins with `--dry-run` first
8. **Document warnings** - Use `print_warning` for operations with side effects

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

The modular architecture makes it easy to:
- **Add new cleanup operations** - Create a plugin in the appropriate category
- **Improve existing functionality** - Modify the relevant library or plugin
- **Fix bugs** - Targeted fixes in specific modules
- **Enhance documentation** - Improve README, add examples, document APIs

### Contribution Guidelines

1. Follow the existing code style and structure
2. Add appropriate error handling and logging
3. Test with `--dry-run` before submitting
4. Update documentation if adding new features
5. Ensure backward compatibility when possible

## License

This script is released under the MIT License. See the LICENSE file for details.

## Disclaimer

This script is provided as-is with no warranties. Always ensure you have recent backups of your important data before performing system cleanup operations. The authors are not responsible for any data loss or system damage that may occur from using this script.

## Acknowledgments

- Built with modern shell scripting best practices
- Uses [fzf](https://github.com/junegunn/fzf) for interactive selection
- Inspired by the need for safe, comprehensive macOS cleanup tools
