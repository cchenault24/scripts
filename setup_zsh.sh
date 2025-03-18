#!/bin/zsh

echo "🚀 Starting Zsh setup..."

trap "echo -e '\n❌ Installation aborted. Exiting...'; exit 1" SIGINT

# Backup existing .zshrc
if [ -f "$HOME/.zshrc" ]; then
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILE="$HOME/.zshrc.bak_$TIMESTAMP"
  echo "📝 Backing up existing .zshrc to $BACKUP_FILE..."
  cp "$HOME/.zshrc" "$BACKUP_FILE"
fi

# Ensure Homebrew is installed
if ! command -v brew &>/dev/null; then
  echo "🚨 Homebrew is not installed. Install it first: https://brew.sh/"
  exit 1
fi

# Detect Homebrew installation path
if [[ -d "/opt/homebrew/bin" ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -d "/usr/local/bin" ]]; then
  HOMEBREW_PREFIX="/usr/local"
else
  echo "❌ Homebrew not found! Install it first."
  exit 1
fi

# Set Homebrew paths
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
export FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:$FPATH"

install_silently_with_spinner() {
  local name="$1"
  local check_cmd="$2"
  local install_cmd="$3"
  local log_file="/tmp/install_${name// /_}.log"

  if eval "$check_cmd"; then
    echo "✅ $name is already installed."
    return
  fi

  echo -n "📥 Installing $name"
  eval "$install_cmd" >"$log_file" 2>&1 &
  PID=$!

  i=0
  while kill -0 $PID 2>/dev/null; do
    dots=$(((i % 3) + 1))
    printf "\r📥 Installing $name %s" "$(printf '.%.0s' $(seq 1 $dots))"
    sleep 0.5
    ((i++))
  done

  if eval "$check_cmd"; then
    printf "\r📥 Installing $name ... ✅ Done!\n"
  else
    printf "\r📥 Installing $name ... ❌ Failed! Check logs: $log_file\n"
  fi
}

# ===========================
#  Function: Install Git-Based Plugins or Themes
# ===========================
install_git_plugin() {
  local name="$1"
  local repo="$2"
  local type="$3"

  local install_dir
  if [[ "$type" == "theme" ]]; then
    install_dir="$HOME/.oh-my-zsh/custom/themes/$name"
  else
    install_dir="$HOME/.oh-my-zsh/custom/plugins/$name"
  fi

  mkdir -p "$(dirname "$install_dir")"

  if [ ! -d "$install_dir" ]; then
    install_silently_with_spinner "$name" "[ -d \"$install_dir\" ]" "git clone --depth=1 \"$repo\" \"$install_dir\" || { echo '❌ Failed to install $name!'; exit 1; }"
  else
    echo "✅ $name is already installed. Skipping..."
  fi
}

# ===========================
#  Function: Install Brew-Based Packages
# ===========================
install_brew_package() {
  local name="$1"
  local post_install="${2:-}"

  if ! command -v "$name" &>/dev/null; then
    install_silently_with_spinner "$name" "command -v $name &>/dev/null" "brew install $name"

    if [ -n "$post_install" ]; then
      eval "$post_install" >/dev/null 2>&1
    fi
  else
    echo "✅ $name is already installed. Skipping..."
  fi
}

# ===========================
#  Ensure Gum is Installed (Silent)
# ===========================
if ! command -v gum &>/dev/null; then
  brew install gum >/dev/null 2>&1
fi

# ===========================
#  Ensure Brew is Updated (Silent)
# ===========================
BREW_LAST_UPDATE_FILE="$HOME/.brew_last_update"
if [ ! -f "$BREW_LAST_UPDATE_FILE" ] || find "$BREW_LAST_UPDATE_FILE" -mtime +1 &>/dev/null; then
  echo "🔄 Updating Homebrew..."
  brew update >/dev/null 2>&1
  touch "$BREW_LAST_UPDATE_FILE"
fi

# Install Zsh & Oh My Zsh
install_silently_with_spinner "Zsh" "brew list --formula | grep -q '^zsh$'" "brew install zsh"
install_silently_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" \
  "RUNZSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended > /dev/null 2>&1 || { echo '❌ Oh My Zsh installation failed!'; exit 1; }"

# ===========================
#  Define Plugins That Require Manual Installation
# ===========================
PLUGINS_TO_INSTALL=(
  "autojump - Navigate directories quickly using stored jumps|autojump|brew"
  "fzf - Fuzzy file finder for quick searching|fzf|brew"
  "powerlevel10k - Highly customizable & fast Zsh theme|powerlevel10k|git"
  "zoxide - Smarter alternative to 'cd' for fast navigation|zoxide|brew"
  "zsh-autosuggestions - Suggests previous commands as you type|zsh-autosuggestions|git"
  "zsh-completions - Expands Zsh autocompletions for many tools|zsh-completions|git"
  "zsh-defer - Speeds up Zsh startup by lazy-loading plugins|zsh-defer|git"
  "zsh-history-substring-search - Search history with partial matches|zsh-history-substring-search|git"
  "zsh-syntax-highlighting - Adds syntax highlighting to commands|zsh-syntax-highlighting|git"
)
# ===========================
#  Display Selection Menu
# ===========================
echo "📦 Select additional plugins to install (use space to toggle, enter to confirm):"
height=$((${#PLUGINS_TO_INSTALL[@]} + 2))
SELECTION=$(printf "%s\n" "${PLUGINS_TO_INSTALL[@]}" | cut -d'|' -f1 | gum choose --no-limit --height="$height")

# ===========================
#  Install Selected Plugins and Themes
# ===========================
echo "Installing selections... (this may take a while)"

for entry in "${PLUGINS_TO_INSTALL[@]}"; do
  plugin_description=$(echo "$entry" | cut -d'|' -f1)
  plugin_name=$(echo "$entry" | cut -d'|' -f2)
  install_method=$(echo "$entry" | cut -d'|' -f3)

  if echo "$SELECTION" | grep -q "$plugin_description"; then
    if [[ "$install_method" == "git" ]]; then
      if [[ "$plugin_name" == "powerlevel10k" ]]; then
        install_git_plugin "$plugin_name" "https://github.com/romkatv/$plugin_name" "theme"
      elif [[ "$plugin_name" == "zsh-defer" ]]; then
        install_git_plugin "$plugin_name" "https://github.com/romkatv/$plugin_name" "plugin"
      else
        install_git_plugin "$plugin_name" "https://github.com/zsh-users/$plugin_name" "plugin"
      fi
    elif [[ "$install_method" == "brew" ]]; then
      if [[ "$plugin_name" == "fzf" ]]; then
        install_brew_package "fzf"

        if command -v fzf &>/dev/null; then
          $(brew --prefix)/opt/fzf/install --all --key-bindings --completion --no-update-rc >/dev/null 2>&1 || {
            echo "❌ fzf post-install script failed!"
            exit 1
          }
        fi
      else
        install_brew_package "$plugin_name"
      fi
    fi
  fi
done

# ===========================
#  VS Code CLI Integration
# ===========================
if gum confirm "Would you like to add the VS Code 'code' command to your PATH? 

Example:
  - Open a file:  code myfile.txt
  - Open a folder: code .
  - Compare files: code --diff file1.js file2.js
  - Open VS Code in a new window: code --new-window

Selecting 'Yes' will allow you to use the 'code' command from anywhere in the terminal."; then
  ADD_VSCODE_CLI=true
else
  ADD_VSCODE_CLI=false
fi

# Create ~/.zshrc if it doesn't exist
if [ ! -f "$HOME/.zshrc" ]; then
  echo "Creating ~/.zshrc..."
  touch "$HOME/.zshrc"
fi

# ===========================
#  Generate .zshrc in Home Directory (~)
# ===========================
echo "📝 Generating ~/.zshrc..."

{
  cat <<EOF
# ==============================================
#              Zsh Configuration
# ==============================================

# Homebrew Path Configuration
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:\$PATH"
export FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:\$FPATH"

# -------------- OH MY ZSH CONFIGURATION --------------
export ZSH="$HOME/.oh-my-zsh"
EOF

  # Add Powerlevel10k configuration if selected
  if echo "$SELECTION" | grep -q "powerlevel10k"; then
    cat <<EOF

# -------------- POWERLEVEL10K THEME --------------
# Enable Powerlevel10k instant prompt (should stay at top of .zshrc)
if [[ -r "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh" ]]; then
  source "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh"
fi

# Set Powerlevel10k as the theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# To customize prompt, run 'p10k configure' or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
  else
    echo 'ZSH_THEME="robbyrussell"'
  fi

  cat <<EOF

# Disable Oh My Zsh auto-update (optional)
zstyle ':omz:update' mode disabled

# -------------- PLUGINS --------------
EOF

  echo -n "plugins=("
  # Always include git
  echo -n "git "

  # Add selected plugins
  for entry in "${PLUGINS_TO_INSTALL[@]}"; do
    plugin_description=$(echo "$entry" | cut -d'|' -f1)
    plugin_name=$(echo "$entry" | cut -d'|' -f2)
    install_method=$(echo "$entry" | cut -d'|' -f3)

    if echo "$SELECTION" | grep -q "$plugin_description"; then
      # Skip powerlevel10k as it's a theme, not a plugin
      if [[ "$plugin_name" != "powerlevel10k" ]]; then
        # For git plugins, we need to check if they're sourced as plugins
        if [[ "$install_method" == "git" ]]; then
          echo -n "$plugin_name "
        # For brew packages, only certain ones need explicit plugin inclusion
        elif [[ "$plugin_name" == "autojump" || "$plugin_name" == "fzf" ]]; then
          echo -n "$plugin_name "
        fi
      fi
    fi
  done
  echo ")"

  cat <<EOF

# Source Oh My Zsh
source \$ZSH/oh-my-zsh.sh

EOF

  if [ "$ADD_VSCODE_CLI" = true ]; then
    cat <<EOF
# Add VS Code CLI to PATH
export PATH="\$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

EOF
  fi

  if echo "$SELECTION" | grep -q "zoxide"; then
    cat <<EOF
# Initialize Zoxide (if installed)
if command -v zoxide &>/dev/null; then
    eval "\$(zoxide init zsh)"
fi

EOF
  fi

  if echo "$SELECTION" | grep -q "autojump"; then
    cat <<EOF
# Initialize Autojump (if installed)
[ -f "\$(brew --prefix)/etc/profile.d/autojump.sh" ] && . "\$(brew --prefix)/etc/profile.d/autojump.sh"

EOF
  fi

  if echo "$SELECTION" | grep -q "zsh-history-substring-search"; then
    cat <<EOF
# Enable history substring search keybindings
if [ -f \$HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi

EOF
  fi

  cat <<EOF
# ==============================================
#   Aliases
# ==============================================

# Navigation
alias ...="cd ../.."
alias ....="cd ../../.."
alias ls="eza --icons --long --group --git"
alias cat="bat"
alias reload="source ~/.zshrc"

# Git Aliases
alias g="git"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gco="git checkout"
alias gs="git status"
alias gl="git log --oneline --graph --decorate --all"

# Yarn & NPM
alias y="yarn"
alias ya="yarn add"
alias yad="yarn add -D"
alias ys="yarn start"
alias yd="yarn dev"
alias ni="npm install"
alias nr="npm run"

# Docker Shortcuts
alias dps="docker ps"
alias dstop="docker stop $(docker ps -q)"
alias drm="docker rm $(docker ps -a -q)"
alias dimg="docker rmi $(docker images -q)"
alias dcup="docker-compose up -d"
alias dcdown="docker-compose down"

# -------------- FZF & SEARCH SETTINGS --------------
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="fd --type d . $HOME"
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"

  # Enable history substring search
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down

# -------------- HISTORY SETTINGS --------------
HISTFILE="\$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY

# -------------- NODE & NVM CONFIGURATION --------------
export NVM_DIR="\$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && . "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# -------------- HOMEBREW CONFIGURATION --------------
if command -v brew &>/dev/null; then
    eval "\$(brew shellenv)"
fi

EOF
} >~/.zshrc

echo "✅ .zshrc file created successfully."

# Reload Zsh Configuration
echo "🔄 Zsh installation is complete!"
if gum confirm "Do you want to restart your shell now to apply changes?"; then
  echo "🔄 Restarting shell..."
  exec zsh || echo "⚠️ Restart your shell manually: Run 'exec zsh' or open a new terminal."
else
  echo "⚠️ You need to restart your shell for the changes to take effect."
  echo "➡️ Run this command manually: exec zsh"
fi

# ===========================
#  Powerlevel10k Instructions
# ===========================
if [ "$INSTALL_P10K" = true ]; then
  echo "⚡ Powerlevel10k installed!"
  echo "📝 After restarting your terminal, you can run 'p10k configure' to set up your prompt."
  echo "💡 If 'p10k configure' doesn't work, try running: source ~/.zshrc && p10k configure"
fi

echo "✅ Zsh setup complete! Restart your terminal for changes to take effect."
exit 0
