#!/bin/bash

echo "🚀 Starting Zsh setup..."

install_silently_with_spinner() {
  local name="$1"
  local check_cmd="$2"
  local install_cmd="$3"
  local log_file="/tmp/install_${name// /_}.log" # Log file for each package

  if eval "$check_cmd"; then
    echo "✅ $name is already installed."
    return
  fi

  echo -n "📥 Installing $name"
  eval "$install_cmd" >"$log_file" 2>&1 & # Capture output in a log file
  PID=$!

  i=0
  while kill -0 $PID 2>/dev/null; do
    dots=$(((i % 3) + 1))
    printf "\r📥 Installing $name %s" "$(printf '.%.0s' $(seq 1 $dots))"
    sleep 0.5
    ((i++))
  done

  # Check if installation succeeded
  if eval "$check_cmd"; then
    printf "\r📥 Installing $name ... ✅ Done!\n"
  else
    printf "\r📥 Installing $name ... ❌ Failed! Check logs: $log_file\n"
  fi
}

# ===========================
#  Function: Install Git-Based Plugins
# ===========================
install_git_plugin() {
  local name="$1"
  local repo="$2"
  local install_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"

  # Ensure the plugins directory exists
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
  local post_install="$2" # Optional post-install command

  if ! command -v "$name" &>/dev/null; then
    install_silently_with_spinner "$name" "command -v \"$name\" &>/dev/null" "brew install \"$name\""

    # Run post-install command if provided
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
# Check when Homebrew was last updated
BREW_LAST_UPDATE_FILE="$HOME/.brew_last_update"
if [ ! -f "$BREW_LAST_UPDATE_FILE" ] || [ $(find "$BREW_LAST_UPDATE_FILE" -mtime +1) ]; then
  echo "🔄 Updating Homebrew..."
  brew update >/dev/null 2>&1
  touch "$BREW_LAST_UPDATE_FILE" # Update timestamp
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
  "autojump|brew|Navigate directories quickly using stored jumps"
  "fzf|brew|Fuzzy file finder for quick searching"
  "powerlevel10k|git|Highly customizable & fast Zsh theme"
  "zoxide|brew|Smarter alternative to 'cd' for fast navigation"
  "zsh-autosuggestions|git|Suggests previous commands as you type"
  "zsh-completions|git|Expands Zsh autocompletions for many tools"
  "zsh-defer|git|Speeds up Zsh startup by lazy-loading plugins"
  "zsh-history-substring-search|git|Search history with partial matches"
  "zsh-syntax-highlighting|git|Adds syntax highlighting to commands"
)

# ===========================
#  Display Selection Menu (No Pagination)
# ===========================
echo "📦 Select additional plugins to install (use space to toggle, enter to confirm):"
height=$((${#PLUGINS_TO_INSTALL[@]} + 2))
SELECTION=$(printf "%s\n" "${PLUGINS_TO_INSTALL[@]}" | gum choose --no-limit --height="$height" | cut -d'|' -f1)

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
#  Uninstall Gum After Selection (Only If Installed)
# ===========================
if brew list --formula | grep -q "^gum\$"; then
  brew uninstall --quiet gum >/dev/null 2>&1
fi

# ===========================
#  Install Git-Based Plugins (Only If Selected)
# ===========================
if echo "$SELECTION" | grep -q "zsh-completions"; then
  install_git_plugin "zsh-completions" "https://github.com/zsh-users/zsh-completions"
fi

if echo "$SELECTION" | grep -q "zsh-autosuggestions"; then
  install_git_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
fi

if echo "$SELECTION" | grep -q "zsh-syntax-highlighting"; then
  install_git_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"
fi

if echo "$SELECTION" | grep -q "zsh-history-substring-search"; then
  install_git_plugin "zsh-history-substring-search" "https://github.com/zsh-users/zsh-history-substring-search"
fi

if echo "$SELECTION" | grep -q "zsh-defer"; then
  install_git_plugin "zsh-defer" "https://github.com/romkatv/zsh-defer"
fi

if echo "$SELECTION" | grep -q "powerlevel10k"; then
  install_git_plugin "powerlevel10k" "https://github.com/romkatv/powerlevel10k" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
fi

# ===========================
#  Install Brew-Based Packages (Only If Selected)
# ===========================
if echo "$SELECTION" | grep -q "fzf"; then
  install_brew_package "fzf" "\"\$(brew --prefix)/opt/fzf/install\" --key-bindings --completion --no-update-rc"
fi

if echo "$SELECTION" | grep -q "autojump"; then
  install_brew_package "autojump"
fi

if echo "$SELECTION" | grep -q "zoxide"; then
  install_brew_package "zoxide"
fi

# ===========================
#  Generate .zshrc File with Configurations
# ===========================
echo "📝 Generating ~/.zshrc..."

{
  cat <<'EOF'
#==============================================
#              Zsh Configuration
# ==============================================

# -------------- PATH CONFIGURATION --------------
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
EOF

  # Conditionally add VS Code CLI support
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
    cat <<'EOF' >>~/.zshrc

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
plugins=()
EOF

  for plugin in $SELECTION; do
    echo "plugins+=($plugin)"
  done

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
if command -v brew &> /dev/null; then
  eval "$(brew shellenv)"
fi
EOF
} >~/.zshrc

echo "✅ .zshrc file created successfully."

# ===========================
#  Set Zsh as Default Shell
# ===========================
echo "🔄 Setting Zsh as the default shell..."
chsh -s "$(which zsh)"

# ===========================
#  Reload Zsh Configuration
# ===========================
echo "🔄 Zsh installation is complete!"

# Ask user if they want to restart the shell now
if gum confirm "Do you want to restart your shell now to apply changes?"; then
  echo "🔄 Restarting shell..."
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
