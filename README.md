# macOS Productivity Tools

A collection of high-quality shell scripts designed to improve and streamline your macOS experience. This repository includes:

- 🧼 **macOS Cleanup Utility**: An interactive script to clean temporary files, caches, logs, and more—safely and effectively.
- ⚙️ **Zsh Setup Scripts**: A set of scripts to automate the installation and configuration of Zsh, Oh My Zsh, and popular plugins.
- 📡 **Home Network Monitor**: A production-quality installer that transforms a Mac mini into a self-hosted network monitoring appliance using Gatus and ntfy.

---

## 🔧 Included Tools

### 1. macOS Cleanup Utility

An interactive, safety-focused utility script to clean temporary files, caches, logs, and other clutter from your Mac.

**Features:**

- Interactive, user-friendly CLI with safety confirmations
- Cleans user/system caches, logs, temp files, and app-specific data
- Smart app detection (e.g., Chrome, Safari, VSCode)
- Built-in backups and restoration options
- Color-coded output and disk savings summary

📄 [Read the full macOS Cleanup Utility README](./mac-cleanup/README.md)

### 2. Zsh Setup Scripts

Automates the setup of a powerful Zsh environment with Oh My Zsh, plugins, and smart defaults.

**Features:**

- One-command setup for Zsh and Oh My Zsh
- Plugin selector for autocomplete, syntax highlighting, navigation, and more
- Auto-generated `.zshrc` file
- Clean uninstallation with backup options

📄 [Read the full Zsh Setup Scripts README](./zsh-setup/README.md)

### 3. Home Network Monitor

A production-quality installer script that sets up a self-hosted network monitoring solution on macOS using Docker Compose.

**Features:**

- Automatic dependency management (Xcode CLI Tools, Homebrew, Docker Desktop)
- Network auto-detection (router IP, AdGuard DNS ports)
- Docker Compose orchestration for Gatus and ntfy monitoring services
- Optional LaunchAgent for automatic startup on boot
- Idempotent installation (safe to re-run)
- Complete uninstall with clean rollback
- Comprehensive logging and error handling
- Input validation and sanitization

📄 [Read the full Home Network Monitor README](./home-netmon/README.md)

---

## ⚙️ System Requirements

| Tool                    | macOS | Linux | Zsh | Git | Homebrew | Docker |
|-------------------------|:-----:|:-----:|:---:|:---:|:--------:|:------:|
| macOS Cleanup Utility   | ✅    | ❌    | ✅  | ❌  | ✅       | ❌     |
| Zsh Setup Scripts       | ✅    | ✅    | ✅  | ✅  | Optional | ❌     |
| Home Network Monitor    | ✅    | ❌    | ❌  | ❌  | Optional | ✅     |

---

## 📥 Installation Overview

### macOS Cleanup Utility

```bash
curl -o ~/mac-cleanup.zsh https://raw.githubusercontent.com/yourusername/mac-productivity-tools/main/mac-cleanup/mac-cleanup.zsh
chmod +x ~/mac-cleanup.zsh
~/mac-cleanup.zsh
```

### Zsh Setup Scripts
```bash
git clone https://github.com/yourusername/mac-productivity-tools.git
cd mac-productivity-tools/zsh-setup
chmod +x *.sh
./setup_zsh.sh
```

### Home Network Monitor
```bash
cd /path/to/scripts/home-netmon
chmod +x setup-home-netmon.sh
./setup-home-netmon.sh
```

Follow the interactive prompts to install Gatus and ntfy monitoring services. The script will handle all dependencies automatically.