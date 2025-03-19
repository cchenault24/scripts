#!/bin/zsh

echo "🚨 WARNING: This will completely remove Zsh, Oh My Zsh, plugins, themes, and all customizations."
echo -n "Are you sure you want to continue? (y/n): "
read CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Uninstall canceled."
  exit 1
fi

echo "🧹 Starting Zsh Uninstall Process..."

# ===========================
#  Function: Uninstall with Live Spinner
# ===========================
uninstall_with_spinner() {
  local name="$1"
  local check_cmd="$2"
  local uninstall_cmd="$3"

  if ! eval "$check_cmd"; then
    echo "⚠️  $name is not installed, skipping..."
    return
  fi

  echo -n "🗑 Removing $name"
  eval "$uninstall_cmd" >/dev/null 2>&1 &
  PID=$!

  i=0
  while kill -0 $PID 2>/dev/null; do
    dots=$(((i % 3) + 1))
    printf "\r🗑 Removing $name %s" "$(printf '.%.0s' $(seq 1 $dots))"
    sleep 0.5
    ((i++))
  done

  printf "\r🗑 Removing $name ... ✅ Done!\n"
}

# ===========================
#  Reset Default Shell to Bash
# ===========================
echo "🔄 Resetting default shell to Bash..."
if chsh -s /bin/bash 2>/dev/null; then
  echo "✅ Default shell changed to Bash."
else
  echo "❌ Failed to change shell. You might need to manually run:"
  echo "   chsh -s /bin/bash"
fi

# ===========================
#  Remove Homebrew Packages Installed by Setup
# ===========================
BREW_PACKAGES=(
  "fzf"
  "autojump"
  "zoxide"
  "gum"
)

echo "🗑 Uninstalling Homebrew packages..."
for pkg in "${BREW_PACKAGES[@]}"; do
  uninstall_with_spinner "$pkg" "brew list --formula | grep -q '^$pkg$'" "brew remove --quiet $pkg"
done

# ===========================
#  Remove Git-Based Plugins & Themes
# ===========================
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
PLUGINS=(
  "powerlevel10k|themes"
  "zsh-autosuggestions|plugins"
  "zsh-completions|plugins"
  "zsh-defer|plugins"
  "zsh-history-substring-search|plugins"
  "zsh-syntax-highlighting|plugins"
)

echo "🗑 Removing Zsh plugins and themes..."
for entry in "${PLUGINS[@]}"; do
  name="${entry%%|*}"
  type="${entry##*|}"
  uninstall_with_spinner "$name" "[ -d \"$ZSH_CUSTOM/$type/$name\" ]" "rm -rf $ZSH_CUSTOM/$type/$name"
done

# ===========================
#  Remove Oh My Zsh
# ===========================
uninstall_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" "rm -rf ~/.oh-my-zsh"

# ===========================
#  Remove Zsh Itself
# ===========================
uninstall_with_spinner "Zsh" "command -v zsh &>/dev/null" "brew remove --quiet zsh"

# ===========================
#  Remove Configuration Files
# ===========================
echo "🗑 Removing Zsh configuration files..."
rm -f ~/.brew_last_update ~/.fzf.bash ~/.fzf.zsh ~/.zcompdump* ~/.zsh_history ~/.zshrc ~/.zshrc.bak_* ~/.zshrc.pre-oh-my-zsh* 
rm -rf ~/.zsh_cache ~/.zsh ~/.nvm ~/.oh-my-zsh ~/.zoxide

# ===========================
#  Restore or Create Default .bashrc
# ===========================
BACKUP_FILE=$(ls -t $HOME/.zshrc.bak_* 2>/dev/null | head -n 1)
if [ -f "$BACKUP_FILE" ]; then
  echo "🔄 Restoring previous .zshrc from backup..."
  mv "$BACKUP_FILE" "$HOME/.zshrc"
  rm -f "$BACKUP_FILE"
else
  echo "📝 No backup found. Creating a minimal .bashrc to restore default behavior."
  echo "# Default .bashrc" >"$HOME/.bashrc"
fi

# ===========================
#  Cleanup VS Code CLI Path if Modified
# ===========================
if grep -q "/Visual Studio Code.app/Contents/Resources/app/bin" ~/.zshrc; then
  echo "🗑 Removing VS Code CLI path modification..."
  sed -i '' '/Visual Studio Code.app\/Contents\/Resources\/app\/bin/d' ~/.zshrc
fi

# ===========================
#  Restart Shell (Back to Bash)
# ===========================
echo "🔄 Restarting shell..."
exec bash
