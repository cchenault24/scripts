#!/bin/bash
#
# vscode.sh - VS Code extensions and settings for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh

# Get list of installed VS Code extensions (cached to avoid multiple calls)
get_installed_extensions() {
  # Use a global cache variable to avoid multiple code --list-extensions calls
  if [[ -z "${_INSTALLED_EXTENSIONS_CACHE:-}" ]] && command -v code &>/dev/null; then
    _INSTALLED_EXTENSIONS_CACHE=$(code --list-extensions 2>/dev/null || echo "")
  fi
  echo "${_INSTALLED_EXTENSIONS_CACHE:-}"
}

# Check if a specific VS Code extension is installed
is_extension_installed() {
  local ext_id="$1"
  local installed_extensions
  installed_extensions=$(get_installed_extensions)
  if [[ -z "$installed_extensions" ]]; then
    return 1
  fi
  echo "$installed_extensions" | grep -q "^${ext_id}$"
}

# Get friendly name for VS Code extension
get_extension_name() {
  local ext_id="$1"
  case "$ext_id" in
    "Continue.continue") echo "Continue.dev" ;;
    "dbaeumer.vscode-eslint") echo "ESLint" ;;
    "esbenp.prettier-vscode") echo "Prettier" ;;
    "pranaygp.vscode-css-peek") echo "CSS Peek" ;;
    "ms-vscode.vscode-typescript-next") echo "TypeScript" ;;
    "dsznajder.es7-react-js-snippets") echo "ES7+ React/Redux/React-Native snippets" ;;
    "formulahendry.auto-rename-tag") echo "Auto Rename Tag" ;;
    "christian-kohler.path-intellisense") echo "Path IntelliSense" ;;
    "esc5221.clipboard-diff-patch") echo "Clipboard Diff Patch" ;;
    *) echo "$ext_id" ;;
  esac
}

# VS Code extensions
# Accepts array of extension IDs to install (passed as arguments)
setup_vscode_extensions() {
  print_header "🔌 VS Code Extensions"
  
  if [[ "$VSCODE_AVAILABLE" != "true" ]]; then
    print_warn "VS Code CLI not available. Skipping extension installation."
    return 0
  fi
  
  # Get selected extensions from arguments or use empty array
  local selected_extensions=("$@")
  
  # Recommended extensions (for generating recommendations file)
  local all_extensions=(
    "Continue.continue"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "pranaygp.vscode-css-peek"
    "ms-vscode.vscode-typescript-next"
    "dsznajder.es7-react-js-snippets"
    "formulahendry.auto-rename-tag"
    "christian-kohler.path-intellisense"
    "esc5221.clipboard-diff-patch"
  )
  
  if [[ ${#selected_extensions[@]} -gt 0 ]]; then
    # Double-check that code command is available
    if ! command -v code &>/dev/null; then
      log_error "VS Code CLI (code) command not found, cannot install extensions"
      print_warn "VS Code CLI not available. Skipping extension installation."
      VSCODE_EXTENSIONS_INSTALLED=false
      return 1
    fi
    
    local installed=0
    local skipped=0
    local certificate_error_detected=false
    local certificate_prompt_shown=false
    
    # Get VS Code settings directory
    local vscode_settings_dir=""
    if [[ "$(uname)" == "Darwin" ]]; then
      vscode_settings_dir="$HOME/Library/Application Support/Code/User"
    else
      vscode_settings_dir="$HOME/.config/Code/User"
    fi
    
    for ext in "${selected_extensions[@]}"; do
      # Check if extension is already installed
      if is_extension_installed "$ext"; then
        print_info "$ext already installed, skipping"
        ((skipped++))
        continue
      fi
      
      # Install only if not already installed
      # Capture install output and exit code separately
      # This prevents tee failures from masking successful installs
      # Use set +e temporarily to prevent script exit on command failure
      local install_output install_exit_code
      set +e
      install_output=$(code --install-extension "$ext" 2>&1)
      install_exit_code=$?
      set -e
      
      # Log output to file, but don't echo to stdout to avoid duplicates
      echo "$install_output" >> "$LOG_FILE" 2>/dev/null || true
      
      # Check for certificate errors
      if [[ $install_exit_code -ne 0 ]] && echo "$install_output" | grep -qiE "(self.?signed|certificate|cert|tls|ssl)"; then
        certificate_error_detected=true
        log_warn "Certificate error detected for $ext"
        
        # Prompt user once to disable strict SSL
        if [[ "$certificate_prompt_shown" == "false" ]]; then
          certificate_prompt_shown=true
          echo ""
          print_warn "⚠️  Certificate validation error detected (likely corporate proxy/firewall)"
          print_info "This is blocking extension installation."
          echo ""
          
          if prompt_yes_no "Would you like to disable strict SSL checking in VS Code (http.proxyStrictSSL = false)?" "y"; then
            # Update VS Code settings
            if [[ -d "$vscode_settings_dir" ]]; then
              local settings_file="$vscode_settings_dir/settings.json"
              
              # Backup existing settings
              if [[ -f "$settings_file" ]]; then
                cp "$settings_file" "${settings_file}.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
              fi
              
              # Update settings using jq if available
              if command -v jq &>/dev/null && [[ -f "$settings_file" ]]; then
                # Merge in the http.proxyStrictSSL setting
                local updated_settings=$(jq '. + {"http.proxyStrictSSL": false}' "$settings_file" 2>/dev/null)
                if [[ -n "$updated_settings" ]]; then
                  echo "$updated_settings" > "$settings_file"
                  log_info "Updated VS Code settings: http.proxyStrictSSL = false"
                  print_success "VS Code settings updated: http.proxyStrictSSL = false"
                fi
              elif [[ ! -f "$settings_file" ]]; then
                # Create new settings file
                mkdir -p "$vscode_settings_dir"
                echo '{"http.proxyStrictSSL": false}' > "$settings_file"
                log_info "Created VS Code settings with http.proxyStrictSSL = false"
                print_success "VS Code settings created: http.proxyStrictSSL = false"
              fi
              
              print_info "⚠️  You may need to restart VS Code for this setting to take effect"
              print_info "After restarting, you can run this script again to install the extensions"
              echo ""
            else
              print_warn "VS Code settings directory not found. Please configure manually:"
              print_info "1. Open VS Code Settings (Cmd+,)"
              print_info "2. Search for: http.proxyStrictSSL"
              print_info "3. Uncheck the option (set to false)"
              echo ""
            fi
          else
            print_info "Skipping certificate fix. Extensions may fail to install."
            print_info "You can configure http.proxyStrictSSL manually in VS Code settings if needed."
            echo ""
          fi
        fi
        
        # Log the failed extension
        log_warn "Failed to install $ext (certificate error)"
      elif [ $install_exit_code -eq 0 ]; then
        print_success "$ext installed"
        ((installed++))
      else
        log_warn "Failed to install $ext"
        # Show error output for failed installs
        if [[ -n "$install_output" ]]; then
          echo "$install_output" | sed 's/^/  /'
        fi
      fi
    done
    
    if [[ $installed -gt 0 ]]; then
      print_success "Installed $installed new extension(s)"
    fi
    if [[ $skipped -gt 0 ]]; then
      print_info "Skipped $skipped already installed extension(s)"
    fi
    VSCODE_EXTENSIONS_INSTALLED=true
  else
    print_info "No extensions selected for installation"
    VSCODE_EXTENSIONS_INSTALLED=false
  fi
  
  # Generate recommendations file
  local vscode_dir="$SCRIPT_DIR/vscode"
  mkdir -p "$vscode_dir"
  
  local extensions_json=$(cat <<EOF
{
  "recommendations": [
$(printf '    "%s",\n' "${all_extensions[@]}" | sed '$s/,$//')
  ]
}
EOF
  )
  
  echo "$extensions_json" > "$vscode_dir/extensions.json"
  print_success "Extension recommendations saved to $vscode_dir/extensions.json"
}

# Prompt for VS Code extensions (separated from installation)
# Returns selected extension IDs via SELECTED_EXTENSIONS array
prompt_vscode_extensions() {
  SELECTED_EXTENSIONS=()
  
  if [[ "$VSCODE_AVAILABLE" != "true" ]]; then
    return 1
  fi
  
  # Recommended extensions
  local extensions=(
    "Continue.continue"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "pranaygp.vscode-css-peek"
    "ms-vscode.vscode-typescript-next"
    "dsznajder.es7-react-js-snippets"
    "formulahendry.auto-rename-tag"
    "christian-kohler.path-intellisense"
    "esc5221.clipboard-diff-patch"
  )
  
  echo "Select VS Code extensions for React+TypeScript+Redux-Saga stack:"
  echo ""
  
  # Build gum input with all extensions
  local gum_items=()
  local ext_map=()
  
  # Get list of installed extensions once (avoid duplicate checks)
  local installed_extensions_list
  installed_extensions_list=$(get_installed_extensions)
  
  # Calculate maximum width for extension names and build parallel arrays for status
  local max_name_width=0
  local ext_names=()
  local ext_installed_flags=()
  
  for ext in "${extensions[@]}"; do
    local friendly_name=$(get_extension_name "$ext")
    local is_installed=false
    
    # Check if extension is already installed
    if is_extension_installed "$ext"; then
      is_installed=true
    fi
    
    # Store for later use
    ext_names+=("$friendly_name")
    ext_installed_flags+=("$is_installed")
    
    # Calculate name width
    local name_len=${#friendly_name}
    if [[ $name_len -gt $max_name_width ]]; then
      max_name_width=$name_len
    fi
  done
  
  # Add padding
  max_name_width=$((max_name_width + 2))
  
  # Build formatted items using stored data
  local i=0
  for ext in "${extensions[@]}"; do
    local friendly_name="${ext_names[$i]}"
    local is_installed="${ext_installed_flags[$i]}"
    local formatted=$(format_extension_for_gum "$ext" "$friendly_name" "$is_installed" "$max_name_width")
    gum_items+=("$formatted")
    ext_map+=("$ext")
    ((i++))
  done
  
  # Use gum choose for multi-select
  echo ""
  echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to select, ${BOLD}Enter${NC} to confirm"
  echo ""
  
  local selected_lines
  # Minimal UI: Color-based selection, no prefix symbols, compact layout
  selected_lines=$(printf '%s\n' "${gum_items[@]}" | gum choose \
    --limit=100 \
    --height=15 \
    --cursor="→ " \
    --selected-prefix="" \
    --unselected-prefix="" \
    --selected.foreground="2" \
    --selected.background="0" \
    --cursor.foreground="6" \
    --header="🔌 VS Code Extensions" \
    --header.foreground="6")
  
  if [[ -z "$selected_lines" ]]; then
    print_info "No extensions selected"
    return 1
  fi
  
  # Parse gum output
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    
    # Find matching extension from the map
    # With minimal UI (no prefixes), gum outputs the formatted string directly
    # Strip any leading whitespace or cursor symbols that might be present
    local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
    line_clean="${line_clean#→ }"  # Remove cursor if present
    
    local ext_id=""
    local i=0
    for item in "${gum_items[@]}"; do
      # Direct match (gum outputs selected items as-is with no prefix)
      if [[ "$item" == "$line_clean" ]]; then
        ext_id="${ext_map[$i]}"
        break
      fi
      ((i++))
    done
    
    # If we found an extension ID, add it
    if [[ -n "$ext_id" ]]; then
      SELECTED_EXTENSIONS+=("$ext_id")
    fi
  done <<< "$selected_lines"
  
  # Remove duplicates (bash 3.2 compatible)
  local unique_extensions=()
  for ext in "${SELECTED_EXTENSIONS[@]}"; do
    local found=0
    if [[ ${#unique_extensions[@]} -gt 0 ]]; then
      for existing in "${unique_extensions[@]}"; do
        if [[ "$ext" == "$existing" ]]; then
          found=1
          break
        fi
      done
    fi
    [[ $found -eq 0 ]] && unique_extensions+=("$ext")
  done
  SELECTED_EXTENSIONS=("${unique_extensions[@]}")
  
  if [[ ${#SELECTED_EXTENSIONS[@]} -eq 0 ]]; then
    return 1
  fi
  
  return 0
}

# Generate VS Code settings
generate_vscode_settings() {
  print_header "⚙️ Generating VS Code Settings"
  
  local vscode_dir="$SCRIPT_DIR/vscode"
  mkdir -p "$vscode_dir"
  
  local settings_json=$(cat <<'EOF'
{
  "typescript.preferences.strictNullChecks": true,
  "typescript.preferences.noImplicitAny": true,
  "typescript.suggest.autoImports": true,
  "typescript.updateImportsOnFileMove.enabled": "always",
  "javascript.preferences.strictNullChecks": true,
  "javascript.preferences.noImplicitAny": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "explicit"
  },
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "files.associations": {
    "*.tsx": "typescriptreact",
    "*.ts": "typescript"
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true
  },
  "files.exclude": {
    "**/.git": true,
    "**/.DS_Store": true
  }
}
EOF
  )
  
  echo "$settings_json" > "$vscode_dir/settings.json"
  print_success "VS Code settings saved to $vscode_dir/settings.json"
  log_info "VS Code settings written"
}

# Copy and merge VS Code settings to current project
copy_vscode_settings() {
  local source_settings="$SCRIPT_DIR/vscode/settings.json"
  local target_dir=".vscode"
  local target_settings="$target_dir/settings.json"
  
  if [[ ! -f "$source_settings" ]]; then
    log_warn "Source VS Code settings not found: $source_settings"
    return 0
  fi
  
  # Create .vscode directory if it doesn't exist
  mkdir -p "$target_dir"
  
  if [[ -f "$target_settings" ]]; then
    # Merge existing settings with new settings
    if command -v jq &>/dev/null; then
      # Deep merge: new settings take precedence, but existing settings are preserved
      # jq * operator merges right into left, so [1] * [0] gives precedence to [1] (new settings)
      local merged=$(jq -s '.[1] * .[0]' "$target_settings" "$source_settings" 2>/dev/null || echo "")
      if [[ $? -eq 0 && -n "$merged" ]]; then
        echo "$merged" > "$target_settings"
        print_success "VS Code settings merged into $target_settings"
        log_info "VS Code settings merged (existing file found)"
      else
        # Fallback: backup and copy
        local backup="$target_settings.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$target_settings" "$backup"
        cp "$source_settings" "$target_settings"
        print_warn "VS Code settings copied (merge failed, backup saved to $backup)"
        log_warn "VS Code settings merge failed, used copy with backup"
      fi
    else
      # No jq available: backup and copy
      local backup="$target_settings.backup-$(date +%Y%m%d-%H%M%S)"
      cp "$target_settings" "$backup"
      cp "$source_settings" "$target_settings"
      print_warn "VS Code settings copied (jq not available for merge, backup saved to $backup)"
      log_warn "VS Code settings copied without merge (jq not available)"
    fi
  else
    # No existing file, just copy
    cp "$source_settings" "$target_settings"
    print_success "VS Code settings copied to $target_settings"
    log_info "VS Code settings copied to project"
  fi
}
