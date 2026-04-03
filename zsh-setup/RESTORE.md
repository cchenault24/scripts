# Restoration Guide

This guide explains how to undo or restore your Zsh configuration after running zsh-setup.

## Quick Restore Options

### Option 1: Full Uninstall (Recommended)

The easiest way to completely undo everything:

```bash
./zsh-setup uninstall
```

This will:
- ✅ Remove Oh My Zsh and all plugins
- ✅ Delete generated `.zshrc`
- ✅ Restore your original `.zshrc` from backup (if available)
- ✅ Optionally change your shell back to Bash
- ✅ Optionally remove Homebrew packages

### Option 2: Manual Restore from Backup

If you want to restore just your `.zshrc` without full uninstall:

```bash
# 1. List available backups
ls -la ~/.zsh_backup/

# 2. Find the backup you want (timestamped)
# Example: .zshrc.20260403_084836

# 3. Restore it
cp ~/.zsh_backup/.zshrc.20260403_084836 ~/.zshrc

# 4. Reload your shell
source ~/.zshrc
# or restart your terminal
```

### Option 3: Keep Plugins, Restore Custom Configs

If you want to keep Oh My Zsh and plugins but restore your custom configurations:

```bash
# Restore your backed up .zshrc
cp ~/.zsh_backup/.zshrc.20260403_084836 ~/.zshrc

# Or just restore your custom configs
cp ~/.zsh_backup/.zshrc.local.backup.20260403_084836 ~/.zshrc.local

# Reload
source ~/.zshrc
```

## What Gets Backed Up?

Every time you run `./zsh-setup install`, these files are automatically backed up:

| File | Backup Location | Description |
|------|----------------|-------------|
| `.zshrc` | `~/.zsh_backup/.zshrc.YYYYMMDD_HHMMSS` | Main Zsh configuration |
| `.zshenv` | `~/.zsh_backup/.zshenv.YYYYMMDD_HHMMSS` | Environment variables |
| `.zprofile` | `~/.zsh_backup/.zprofile.YYYYMMDD_HHMMSS` | Login shell config |
| `.zlogin` | `~/.zsh_backup/.zlogin.YYYYMMDD_HHMMSS` | Login commands |
| `.zlogout` | `~/.zsh_backup/.zlogout.YYYYMMDD_HHMMSS` | Logout commands |
| `.zshrc.local` | `~/.zshrc.local.backup.YYYYMMDD_HHMMSS` | Custom configs |

## Restoration Scenarios

### Scenario 1: "I just installed and want to go back"

```bash
# Full uninstall
./zsh-setup uninstall

# When prompted:
# - Choose "yes" to restore from backup
# - Choose "yes" to change shell back to Bash (optional)
# - Choose "no" to keep Homebrew packages (they're useful)
```

### Scenario 2: "I lost my custom aliases and functions"

```bash
# Check if they're in .zshrc.local
cat ~/.zshrc.local

# If not, restore from backup
ls ~/.zsh_backup/.zshrc*
cp ~/.zsh_backup/.zshrc.20260403_084836 ~/.zshrc

# Then extract custom configs again
./migrate-custom-configs.sh
```

### Scenario 3: "Oh My Zsh broke something"

```bash
# Restore just the .zshrc
cp ~/.zsh_backup/.zshrc.20260403_084836 ~/.zshrc

# Reload
exec zsh
```

### Scenario 4: "I want to start completely fresh"

```bash
# Full uninstall
./zsh-setup uninstall

# Remove all backups
rm -rf ~/.zsh_backup

# Remove state files
rm -rf ~/.local/state/zsh-setup

# Remove custom configs (if you want)
rm ~/.zshrc.local

# Change back to Bash
chsh -s /bin/bash

# Logout and back in
```

### Scenario 5: "A plugin is causing issues"

```bash
# Remove the specific plugin
./zsh-setup remove <plugin-name>

# Or manually remove from .zshrc
nano ~/.zshrc
# Delete the plugin from the plugins=() array

# Reload
source ~/.zshrc
```

## Step-by-Step Manual Restoration

### 1. Check What Backups You Have

```bash
ls -lah ~/.zsh_backup/
```

Example output:
```
.zshrc.20260403_084836
.zshenv.20260403_084836
.zlogin.20260403_084836
```

### 2. Identify the Right Backup

Backups are timestamped: `YYYYMMDD_HHMMSS`
- `20260403` = April 3rd, 2026
- `084836` = 8:48:36 AM

Choose the backup from **before** you ran zsh-setup.

### 3. Preview the Backup

```bash
# See what's in the backup
cat ~/.zsh_backup/.zshrc.20260403_084836
```

### 4. Restore It

```bash
# Backup your current .zshrc first (just in case)
cp ~/.zshrc ~/.zshrc.current

# Restore the backup
cp ~/.zsh_backup/.zshrc.20260403_084836 ~/.zshrc

# Make it executable
chmod 644 ~/.zshrc
```

### 5. Test It

```bash
# Start a new shell to test
zsh

# Or reload current shell
source ~/.zshrc

# If it works, you're done!
# If not, restore the current version:
cp ~/.zshrc.current ~/.zshrc
```

## Using the Built-in Restore Function

The backup module has a restore function (for advanced users):

```bash
# Source the zsh-setup environment
export ZSH_SETUP_ROOT="/path/to/zsh-setup"
source "$ZSH_SETUP_ROOT/lib/core/bootstrap.sh"
zsh_setup::core::bootstrap::load_module config::backup

# List backups
zsh_setup::config::backup::list

# Restore specific backup
zsh_setup::config::backup::restore ~/.zsh_backup/.zshrc.20260403_084836
```

## Common Issues During Restoration

### Issue: "My shell is still Zsh after restoring"

```bash
# Change default shell back to Bash
chsh -s /bin/bash

# Logout and back in (required)
```

### Issue: "I can't find my backups"

```bash
# Check the default location
ls -la ~/.zsh_backup/

# Check for alternative location
ls -la /tmp/.zsh_backup/

# If really lost, check your original .zshrc location
ls -la ~/ | grep zshrc
```

### Issue: "The backup is empty or corrupted"

```bash
# Check file size
ls -lh ~/.zsh_backup/.zshrc.20260403_084836

# If 0 bytes, it's empty - use an earlier backup
ls -la ~/.zsh_backup/ | sort

# Or start with a basic .zshrc
cat > ~/.zshrc <<'EOF'
# Basic Zsh configuration
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
EOF
```

### Issue: "Restoration broke my terminal"

```bash
# Start Bash directly (bypass .zshrc)
/bin/bash

# Remove problematic .zshrc
mv ~/.zshrc ~/.zshrc.broken

# Create minimal .zshrc
echo 'export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"' > ~/.zshrc

# Try again with a different backup
```

## Prevention: Before Installing

To make restoration easier in the future:

### 1. Manually Backup Before Installing

```bash
# Create your own backup
cp ~/.zshrc ~/.zshrc.my_backup_$(date +%Y%m%d)

# Or backup entire directory
tar -czf ~/zsh_configs_backup_$(date +%Y%m%d).tar.gz \
    ~/.zshrc ~/.zshenv ~/.zprofile ~/.zlogin ~/.zlogout ~/.zshrc.local 2>/dev/null
```

### 2. Use Version Control

```bash
# Initialize git in your home directory (dotfiles repo)
cd ~
git init
git add .zshrc .zshenv .zprofile
git commit -m "Backup before zsh-setup"
```

### 3. Test in Dry-Run Mode

```bash
# Preview what will happen
./zsh-setup install --dry-run
```

### 4. Keep Custom Configs Separate

```bash
# Move all custom configs to .zshrc.local BEFORE installing
nano ~/.zshrc.local
# Add your custom aliases, functions, etc.

# Then install
./zsh-setup install
```

## Emergency Recovery

If everything is broken and you can't access your shell:

### On macOS:

1. **Boot in Safe Mode**: Hold Shift during boot
2. **Open Terminal** (Applications > Utilities > Terminal)
3. Run recovery commands:
   ```bash
   # Change shell to Bash
   chsh -s /bin/bash

   # Move problematic .zshrc
   mv ~/.zshrc ~/.zshrc.broken

   # Reboot normally
   sudo reboot
   ```

### Via SSH (if applicable):

```bash
# SSH with explicit shell
ssh -t user@host /bin/bash

# Then fix the issue
mv ~/.zshrc ~/.zshrc.broken
```

### Via Recovery Mode:

1. Boot into Recovery Mode (Cmd+R on Mac)
2. Open Terminal from Utilities menu
3. Navigate to your user directory:
   ```bash
   cd /Volumes/Macintosh\ HD/Users/yourusername
   mv .zshrc .zshrc.broken
   ```

## Verification After Restoration

After restoring, verify everything works:

```bash
# Check shell
echo $SHELL

# Check .zshrc loads without errors
zsh -n ~/.zshrc

# Check for syntax errors
source ~/.zshrc 2>&1 | grep -i error

# Test basic commands
ls
cd ~
pwd
```

## Support

If restoration fails:

1. **Check the logs**: Look for error messages
2. **Review backups**: `ls -la ~/.zsh_backup/`
3. **Try different backup**: Use an earlier timestamp
4. **Start fresh**: Remove everything and reinstall manually
5. **Ask for help**: Open an issue with details

## Summary

| What You Want | Command |
|---------------|---------|
| **Full undo** | `./zsh-setup uninstall` |
| **Restore .zshrc only** | `cp ~/.zsh_backup/.zshrc.TIMESTAMP ~/.zshrc` |
| **List backups** | `ls -la ~/.zsh_backup/` |
| **Keep plugins, restore config** | `cp ~/.zsh_backup/.zshrc.TIMESTAMP ~/.zshrc` |
| **Remove everything** | `./zsh-setup uninstall` + remove backups |
| **Test before commit** | `./zsh-setup install --dry-run` |

Remember: **Backups are created automatically** every time you run install, so you can always go back!
