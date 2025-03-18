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
#  Uninstall Zsh Plugins & Themes
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
#  Uninstall Oh My Zsh
# ===========================
uninstall_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" "rm -rf ~/.oh-my-zsh"

# ===========================
#  Remove Configuration Files
# ===========================
echo "🗑 Removing Zsh configuration files..."
# Remove Zsh-related files (but not directories)
rm -f ~/.zshrc ~/.zshenv ~/.zsh_history ~/.zsh_sessions ~/.p10k* ~/.config_p10k_once ~/.zprofile ~/.zlogin ~/.zcompdump* ~/.shell.pre-oh-my-zsh ~/.brew_last_update
# Remove Zsh-related directories separately
rm -rf ~/.zsh_cache ~/.zsh

# ===========================
#  Uninstall Homebrew Packages
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

echo "✅ Zsh and all related configurations have been removed. Your terminal has been reset to its default state!"

# ===========================
#  Restore or create new .zshrc
# ===========================
# Restore the backup if it exists, otherwise create an empty .zshrc
BACKUP_FILE=$(ls -t $HOME/.zshrc.bak_* 2>/dev/null | head -n 1)

if [ -f "$BACKUP_FILE" ]; then
  echo "🔄 Restoring previous .zshrc from backup..."
  mv "$BACKUP_FILE" "$HOME/.zshrc"
  rm -f "$BACKUP_FILE"
else
  echo "📝 No backup found. Creating a minimal .zshrc to prevent new user prompt."
  echo "# Empty .zshrc to bypass new user installation prompt" >"$HOME/.zshrc"
fi

# ===========================
#  Restart Shell
# ===========================
echo "🔄 Restarting shell..."
exec zsh
