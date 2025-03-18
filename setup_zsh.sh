#!/bin/bash

echo "🚀 Starting Zsh setup..."

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

  if [[ "$type" == "theme" ]]; then
    local install_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/$name"
  else
    local install_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"
  fi

  mkdir -p "$(dirname "$install_dir")"

  if [ ! -d "$install_dir" ]; then
    install_silently_with_spinner "$name" "[ -d \"$install_dir\" ]" "git clone --depth=1 \"$repo\" \"$install_dir\""
  else
    echo "✅ $name is already installed. Skipping..."
  fi
}

# ===========================
#  Function: Install Brew-Based Packages
# ===========================
install_brew_package() {
  local name="$1"
  local post_install="$2"

  if ! command -v "$name" &>/dev/null; then
    install_silently_with_spinner "$name" "command -v \"$name\" &>/dev/null" "brew install \"$name\""

    if [ -n "$post_install" ]; then
      eval "$post_install" >/dev/null 2>&1
    fi
  else
    echo "✅ $name is already installed. Skipping..."
  fi
}

# ===========================
#  Handle Ctrl+C Gracefully
# ===========================
trap 'echo -e "\n⚠️  Installation aborted. Exiting gracefully..."; exit 1' SIGINT

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
if [ ! -f "$BREW_LAST_UPDATE_FILE" ] || [ $(find "$BREW_LAST_UPDATE_FILE" -mtime +1) ]; then
  echo "🔄 Updating Homebrew..."
  brew update >/dev/null 2>&1
  touch "$BREW_LAST_UPDATE_FILE"
fi

# ===========================
#  Install Zsh & Oh My Zsh Using Silent Spinner
# ===========================
install_silently_with_spinner "Zsh" "brew list --formula | grep -q '^zsh$'" "brew install zsh"
install_silently_with_spinner "Oh My Zsh" "[ -d \"$HOME/.oh-my-zsh\" ]" "RUNZSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""

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
        install_git_plugin "$plugin_name" "https://github.com/zsh-users/$plugin_name" "$plugin_type"
      fi
    elif [[ "$install_method" == "brew" ]]; then
      if [[ "$plugin_name" == "fzf" ]]; then
        install_brew_package "$plugin_name" "\"\$(brew --prefix)/opt/fzf/install\" --key-bindings --completion --no-update-rc"
      else
        install_brew_package "$plugin_name"
      fi
    fi
  fi
done

# ===========================
#  Prompt User to Add VS Code CLI
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

# ===========================
#  Generate .zshrc File with Configurations
# ===========================
echo "📝 Generating ~/.zshrc..."

{
  # Ensure Powerlevel10k Instant Prompt is disabled first if installed
  if [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]]; then
    echo "typeset -g POWERLEVEL9K_INSTANT_PROMPT=off"
  fi

  cat <<'EOF'
#==============================================
#              Zsh Configuration
# ==============================================

# -------------- PATH CONFIGURATION --------------
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
EOF

  if [ "$ADD_VSCODE_CLI" = true ]; then
    cat <<'EOF'

# Add VS Code CLI to PATH
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
EOF
  fi

  cat <<'EOF'

# -------------- OH MY ZSH CONFIGURATION --------------
export ZSH="$HOME/.oh-my-zsh"
EOF

  if echo "$SELECTION" | grep -q "powerlevel10k"; then
    cat <<'EOF'

# Set Powerlevel10k theme
ZSH_THEME="powerlevel10k/powerlevel10k"
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
  fi

  cat <<'EOF'

# Disable Oh My Zsh auto-update (optional)
zstyle ':omz:update' mode disabled

# -------------- SPEED OPTIMIZATIONS --------------
autoload -Uz compinit && compinit -d ~/.zsh_cache
EOF

  if echo "$SELECTION" | grep -q "zsh-defer"; then
    cat <<'EOF'

# Lazy-load plugins using zsh-defer (only if installed)
source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-defer/zsh-defer.plugin.zsh
EOF
  fi

  cat <<'EOF'

# -------------- PLUGINS --------------
EOF

  IFS=$'\n'
  echo "plugins=("
  for entry in "${PLUGINS_TO_INSTALL[@]}"; do
    plugin_name=$(echo "$entry" | cut -d'|' -f2)
    plugin_description=$(echo "$entry" | cut -d'|' -f1)

    if echo "$SELECTION" | grep -q "$plugin_description"; then
      echo "  \"$plugin_name\""
    fi
  done
  echo ")"
  unset IFS

  cat <<'EOF'

source $ZSH/oh-my-zsh.sh
EOF

  if echo "$SELECTION" | grep -q "autojump"; then
    cat <<'EOF'

# Initialize autojump
[ -f "$(brew --prefix)/etc/profile.d/autojump.sh" ] && . "$(brew --prefix)/etc/profile.d/autojump.sh"
EOF
  fi

  if echo "$SELECTION" | grep -q "zoxide"; then
    cat <<'EOF'

# Initialize zoxide
eval "$(zoxide init zsh)"
EOF
  fi

  cat <<'EOF'

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
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY

# -------------- NODE & NVM CONFIGURATION --------------
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \ . "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \ . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# -------------- HOMEBREW CONFIGURATION --------------
if command -v brew &>/dev/null; then
  eval "$(brew shellenv)"
fi
EOF
} >~/.zshrc

echo "✅ .zshrc file created successfully."

# ===========================
#  Set Zsh as Default Shell
# ===========================
echo "🔄 Setting Zsh as the default shell..."
ZSH_PATH=$(brew --prefix)/bin/zsh
chsh -s "$ZSH_PATH"

# ===========================
#  Reload Zsh Configuration
# ===========================
echo "🔄 Zsh installation is complete!"

if gum confirm "Do you want to restart your shell now to apply changes?"; then
  echo "🔄 Restarting shell..."
  if echo "$SELECTION" | grep -q "powerlevel10k"; then
    echo "You may see "plugin 'powerlevel10k' not found", ignore this"
  fi
  exec zsh
else
  echo "⚠️ You need to restart your shell for the changes to take effect."
  echo "➡️ Run this command manually: exec zsh"
fi

# ===========================
#  Prompt User to Configure Powerlevel10k If Installed
# ===========================
if echo "$SELECTION" | grep -q "powerlevel10k"; then
  echo "⚡ Powerlevel10k installed! Restart your terminal and run: p10k configure"
fi

echo "✅ Zsh is now your default shell. Restart your terminal for changes to take effect!"
exit 0
