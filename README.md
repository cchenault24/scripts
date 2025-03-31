# macOS Productivity Tools

A collection of high-quality shell scripts designed to improve and streamline your macOS experience. This repository includes:

- 🧼 **macOS Cleanup Utility**: An interactive script to clean temporary files, caches, logs, and more—safely and effectively.
- ⚙️ **Zsh Setup Scripts**: A set of scripts to automate the installation and configuration of Zsh, Oh My Zsh, and popular plugins.

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

📄 [Read the full Zsh Setup Scripts README](./zsh-setup-scripts/README.md)

---

## ⚙️ System Requirements

| Tool                    | macOS | Linux | Zsh | Git | Homebrew |
|-------------------------|:-----:|:-----:|:---:|:---:|:--------:|
| macOS Cleanup Utility   | ✅    | ❌    | ✅  | ❌  | ✅       |
| Zsh Setup Scripts       | ✅    | ✅    | ✅  | ✅  | Optional |

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
cd mac-productivity-tools/zsh-setup-scripts
chmod +x *.sh
./setup_zsh.sh
```