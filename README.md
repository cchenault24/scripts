# 🚀 Zsh Setup & Uninstall Scripts

This repository contains two scripts for **installing** and **uninstalling** a fully customized **Zsh** shell with Oh My Zsh, plugins, themes, and productivity tools.

- **[`setup_zsh.sh`](#-setup-script)** → Installs and configures Zsh with plugins and themes.
- **[`uninstall_zsh.sh`](#-uninstall-script)** → Removes Zsh customizations while keeping Zsh installed.

---

## 📥 **Setup Script (`setup_zsh.sh`)**

### ✨ **Features**
- **Installs Zsh** and sets it as the default shell.
- **Installs Oh My Zsh** for plugin and theme management.
- **Installs essential plugins** like:
  - `autojump` (Quickly jump to directories)
  - `fzf` (Fuzzy search)
  - `zoxide` (Smarter `cd` alternative)
  - `zsh-autosuggestions`, `zsh-completions`, `zsh-syntax-highlighting`, etc.
- **Installs Powerlevel10k (`p10k`) Theme** with instant prompt support.
- **Configures `.zshrc`** with performance optimizations, aliases, and plugin settings.
- **Prompts user** to add VS Code CLI (`code`) to PATH.

---

### 📌 **Installation**
#### 🔹 **Run the setup script**
```bash
curl -fsSL https://your-repo-link/setup_zsh.sh | bash
```
or, if you’ve downloaded the script:
```bash
chmod +x setup_zsh.sh
./setup_zsh.sh
```

---

### ⚙️ **Configuration**
Once installed, **restart your terminal** or run:
```bash
exec zsh
```

To configure **Powerlevel10k**, run:
```bash
p10k configure
```

To **manually change the default shell to Zsh**, use:
```bash
chsh -s $(which zsh)
```

---

## 🗑 **Uninstall Script (`uninstall_zsh.sh`)**
If you want to remove **Oh My Zsh, plugins, themes, and configurations** while keeping Zsh **installed**, use the uninstall script.

### ✨ **What It Removes**
✅ **Oh My Zsh** and all installed plugins.  
✅ **Powerlevel10k theme**.  
✅ **Homebrew packages** (`fzf`, `autojump`, `zoxide`, `gum`).  
✅ **Configuration files** (`.zshrc`, `.p10k.zsh`, `.zsh_history`, etc.).  
✅ **Prevents `zsh-newuser-install` from prompting on restart**.  
❌ **Does NOT remove Zsh itself**.

---

### 📌 **Uninstallation**
#### 🔹 **Run the uninstall script**
```bash
curl -fsSL https://your-repo-link/uninstall_zsh.sh | bash
```
or, if you’ve downloaded the script:
```bash
chmod +x uninstall_zsh.sh
./uninstall_zsh.sh
```

After running the script, restart your terminal:
```bash
exec zsh
```

---

## 📂 **File Breakdown**
| File               | Description |
|--------------------|-------------|
| `setup_zsh.sh`     | Installs and configures Zsh, Oh My Zsh, plugins, and themes. |
| `uninstall_zsh.sh` | Removes Zsh customizations, plugins, and themes while keeping Zsh. |
| `.zshrc` (Generated) | Configures plugins, aliases, and optimizations for Zsh. |
| `.p10k.zsh` (Generated) | Stores Powerlevel10k theme settings. |

---

## 📖 **Documentation & Resources**
- **Zsh** → [https://www.zsh.org/](https://www.zsh.org/)
- **Oh My Zsh** → [https://ohmyz.sh/](https://ohmyz.sh/)
- **Powerlevel10k** → [https://github.com/romkatv/powerlevel10k](https://github.com/romkatv/powerlevel10k)
- **FZF** → [https://github.com/junegunn/fzf](https://github.com/junegunn/fzf)
- **Zoxide** → [https://github.com/ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide)
- **Autojump** → [https://github.com/wting/autojump](https://github.com/wting/autojump)

---

## 🚀 **Contributions & Issues**
Feel free to contribute by opening an issue or submitting a pull request!

📩 **Maintainer:** [Your Name]  
📧 **Contact:** your-email@example.com

---

**Happy coding!** 🎉🚀
