#!/bin/bash

echo "🚨 WARNING: This will completely remove Zsh, Oh My Zsh, and all customizations."
read -p "Are you sure you want to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Uninstall canceled."
  exit 1
fi

echo "🧹 Starting Zsh Uninstall Process..."

# ===========================
#  Function: Uninstall with Live Spinner
# ===========================
uninstall_with_spinner() {
  local name="$1"          # Display name (e.g., "Zsh")
  local check_cmd="$2"     # Command to check if installed
  local uninstall_cmd="$3" # Command to uninstall

  if ! eval "$check_cmd"; then
    echo "⚠️  $name is not installed, skipping..."
    return
  fi

  echo -n "🗑 Removing $name"
  eval "$uninstall_cmd" >/dev/null 2>&1 &
  PID=$!

  i=0
  while kill -0 $PID 2>/dev/null; do
    dots=$(((i % 3) + 1)) # Cycle between 1, 2, 3 dots
    printf "\r🗑 Removing $name %s" "$(printf '.%.0s' $(seq 1 $dots))"
    sleep 0.5
    ((i++))
  done

  printf "\r🗑 Removing $name ... ✅ Done!\n"
}

# ===========================
#  Switch Back to Bash
# ===========================
echo "🔄 Switching shell back to Bash..."
chsh -s /bin/bash
export SHELL=/bin/bash

# ===========================
#  Uninstall Zsh Plugins & Themes First
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

echo "✅ Plugins and themes removed."

# ===========================
#  Uninstall Oh My Zsh
# ===========================
uninstall_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" "rm -rf ~/.oh-my-zsh"

echo "✅ Oh My Zsh removed."

# ===========================
#  Remove Configuration Files
# ===========================
echo "🗑 Removing Zsh configuration files..."
rm -f ~/.zshrc ~/.p10k.zsh ~/.zsh_history
rm -rf ~/.zsh_cache

echo "✅ Configuration files removed."

# ===========================
#  Uninstall Homebrew Packages
# ===========================
BREW_PACKAGES=(
  "zsh"
  "fzf"
  "autojump"
  "zoxide"
)

echo "🗑 Uninstalling Homebrew packages..."
for pkg in "${BREW_PACKAGES[@]}"; do
  uninstall_with_spinner "$pkg" "brew list --formula | grep -q '^$pkg$'" "brew remove --quiet $pkg"
done

# ===========================
#  Restart Shell
# ===========================
echo "🔄 Restarting shell..."
exec bash

echo "✅ Zsh has been completely removed. Your terminal has been reset to its default state!"
