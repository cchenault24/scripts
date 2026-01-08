#!/bin/bash
#
# continue.sh - Continue.dev configuration and verification for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh, models.sh

# Helper function to generate friendly model names
get_friendly_model_name() {
  local model="$1"
  case "$model" in
    "qwen2.5-coder:14b") echo "Qwen2.5-Coder 14B" ;;
    "qwen2.5-coder:7b") echo "Qwen2.5-Coder 7B" ;;
    "llama3.1:8b") echo "Llama 3.1 8B" ;;
    "llama3.1:70b") echo "Llama 3.1 70B" ;;
    "codestral:22b") echo "Codestral 22B" ;;
    *) echo "${model%%:*}" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g' | sed 's/-/ /g' ;;
  esac
}

# Generate Continue.dev config
generate_continue_config() {
  print_header "📝 Generating Continue.dev Configuration"
  
  local continue_dir="$HOME/.continue"
  local config_file="$continue_dir/config.yaml"
  
  mkdir -p "$continue_dir"
  
  # Backup existing config if it exists
  if [[ -f "$config_file" ]]; then
    local backup_file="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$config_file" "$backup_file"
    print_info "Backed up existing config to: $backup_file"
    log_info "Backed up existing config to: $backup_file"
  fi
  
  # Separate coding models from embedding models
  local coding_models=()
  local embed_model=""
  
  # Process all selected models (guard against empty array for set -u compatibility)
  if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
    for model_base in "${SELECTED_MODELS[@]}"; do
      # Resolve actual installed model name (may be optimized variants)
      local model=$(resolve_installed_model "$model_base")
      
      # Check if it's an embedding model
      if [[ "$model" == *"embed"* ]] || [[ "$model" == *"nomic-embed"* ]]; then
        embed_model="$model"
      else
        # Add to coding models array (avoid duplicates)
        local found=0
        # Guard against empty array access (fixes unbound variable error with set -u)
        if [[ ${#coding_models[@]} -gt 0 ]]; then
          for existing in "${coding_models[@]}"; do
            if [[ "$existing" == "$model" ]]; then
              found=1
              break
            fi
          done
        fi
        if [[ $found -eq 0 ]]; then
          coding_models+=("$model")
        fi
      fi
    done
  fi
  
  # If no coding models found, log warning and return
  if [[ ${#coding_models[@]} -eq 0 ]]; then
    print_warn "No coding models found in selected models"
    log_warn "No coding models to add to Continue.dev config"
    return 1
  fi
  
  # Determine default model (first/largest for chat) and autocomplete model
  local default_model="${coding_models[0]}"
  local default_model_name=$(get_friendly_model_name "$default_model")
  
  # Find best autocomplete model (prefer smallest/fastest)
  local autocomplete_model=""
  local autocomplete_model_name=""
  # Prefer 7b models for autocomplete (faster responses)
  for model in "${coding_models[@]}"; do
    if [[ "$model" == *"7b"* ]] || [[ "$model" == *":7b"* ]]; then
      autocomplete_model="$model"
      autocomplete_model_name=$(get_friendly_model_name "$model")
      break
    fi
  done
  # Fallback to 8b if no 7b found
  if [[ -z "$autocomplete_model" ]]; then
    for model in "${coding_models[@]}"; do
      if [[ "$model" == *"8b"* ]] || [[ "$model" == *":8b"* ]]; then
        autocomplete_model="$model"
        autocomplete_model_name=$(get_friendly_model_name "$model")
        break
      fi
    done
  fi
  # Use first model as fallback if no small model found
  if [[ -z "$autocomplete_model" && ${#coding_models[@]} -gt 0 ]]; then
    autocomplete_model="${coding_models[0]}"
    autocomplete_model_name="$default_model_name"
  fi
  
  # Start building config YAML
  local config_yaml=$(cat <<EOF
name: Local Config
version: 1.0.0
schema: v1

# Default model for chat (uses first/largest model)
defaultModel: $default_model_name

# Default completion options (optimized for coding tasks)
defaultCompletionOptions:
  temperature: 0.7
  maxTokens: 2048

# Privacy: Disable telemetry for local-only setup
allowAnonymousTelemetry: false

models:
EOF
  )
  
  # Add all coding models with chat, edit, apply roles
  for model in "${coding_models[@]}"; do
    local friendly_name=$(get_friendly_model_name "$model")
    
    # Build roles list
    local roles_yaml="      - chat
      - edit
      - apply"
    
    # Add autocomplete role if this is the autocomplete model
    if [[ "$model" == "$autocomplete_model" ]]; then
      roles_yaml="$roles_yaml
      - autocomplete"
    fi
    
    config_yaml+=$(cat <<EOF

  - name: $friendly_name
    provider: ollama
    model: $model
    apiBase: http://localhost:11434
    contextLength: 16384
    roles:
$roles_yaml
EOF
    )
  done
  
  # Add embeddings model (use found embedding model or default)
  local embed_model_to_use="${embed_model:-nomic-embed-text:latest}"
  config_yaml+=$(cat <<EOF

  - name: Nomic Embed
    provider: ollama
    model: $embed_model_to_use
    apiBase: http://localhost:11434
    roles:
      - embed
    embedOptions:
      maxChunkSize: 512
      maxBatchSize: 10
EOF
  )
  
  # Add autocomplete model reference (if different from default)
  if [[ "$autocomplete_model" != "$default_model" && -n "$autocomplete_model" ]]; then
    config_yaml+=$(cat <<EOF

# Autocomplete model (optimized for fast suggestions)
tabAutocompleteModel: $autocomplete_model_name
EOF
    )
  fi
  
  # Add embeddings provider
  config_yaml+=$(cat <<EOF

# Embeddings provider for codebase search
embeddingsProvider:
  provider: ollama
  model: $embed_model_to_use
  apiBase: http://localhost:11434
EOF
  )
  
  # Add context providers for better code understanding
  config_yaml+=$(cat <<EOF

# Context providers for enhanced code understanding
contextProviders:
  - name: codebase
  - name: code
  - name: docs
  - name: diff
  - name: terminal
  - name: problems
  - name: folder
EOF
  )
  
  # Write config
  echo "$config_yaml" > "$config_file"
  print_success "Continue.dev config generated: $config_file"
  log_info "Continue.dev config written to $config_file with ${#coding_models[@]} coding model(s)"
  
  CONTINUE_PROFILES=("chat" "edit" "apply" "autocomplete")
}

# Check if Continue CLI is installed
check_continue_cli() {
  if command -v cn &>/dev/null; then
    return 0
  elif command -v npx &>/dev/null && npx --yes @continuedev/cli --version &>/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Install Continue CLI (optional)
install_continue_cli() {
  if check_continue_cli; then
    print_success "Continue CLI found"
    return 0
  fi
  
  if ! command -v npm &>/dev/null; then
    print_warn "npm not found. Continue CLI requires Node.js/npm"
    print_info "Install Node.js from https://nodejs.org/ to use Continue CLI"
    return 1
  fi
  
  print_info "Continue CLI not found"
  if prompt_yes_no "Install Continue CLI (cn) for better verification and setup?" "y"; then
    print_info "Installing @continuedev/cli globally..."
    
    # Try installation first
    set +e
    local install_output
    install_output=$(npm install -g @continuedev/cli 2>&1)
    local install_exit_code=$?
    set -e
    
    echo "$install_output" | tee -a "$LOG_FILE" >/dev/null 2>&1 || true
    
    # Check for certificate errors
    if [[ $install_exit_code -ne 0 ]] && echo "$install_output" | grep -qiE "(self.?signed|certificate|cert|tls|ssl|UNABLE_TO_VERIFY_LEAF_SIGNATURE)"; then
      log_warn "Certificate error detected during Continue CLI installation"
      print_warn "Certificate validation error detected"
      echo ""
      
      if prompt_yes_no "Would you like to disable strict SSL checking for npm (npm config set strict-ssl false)?" "y"; then
        print_info "Configuring npm to disable strict SSL checking..."
        npm config set strict-ssl false
        log_info "npm configured: strict-ssl = false"
        print_success "npm configured to disable strict SSL"
        
        # Retry installation
        print_info "Retrying Continue CLI installation..."
        set +e
        install_output=$(npm install -g @continuedev/cli 2>&1)
        install_exit_code=$?
        set -e
        
        echo "$install_output" | tee -a "$LOG_FILE" >/dev/null 2>&1 || true
      fi
    fi
    
    if [[ $install_exit_code -eq 0 ]]; then
      print_success "Continue CLI installed"
      log_info "Continue CLI installed successfully"
      return 0
    else
      log_warn "Failed to install Continue CLI"
      print_warn "Continue CLI installation failed, but setup can continue"
      if [[ -n "$install_output" ]]; then
        echo "$install_output" | sed 's/^/  /'
      fi
      return 1
    fi
  else
    print_info "Skipping Continue CLI installation"
    return 1
  fi
}

# Configure Continue.dev models from installed Ollama models
configure_continue_models_from_ollama() {
  local config_file="${1:-$HOME/.continue/config.yaml}"
  local continue_dir="$HOME/.continue"
  
  mkdir -p "$continue_dir"
  
  # Check if Ollama is running
  if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_error "Ollama service is not running"
    print_info "Start it with: brew services start ollama"
    return 1
  fi
  
  # Get installed models
  local installed_models
  installed_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$installed_models" ]]; then
    print_warn "No Ollama models installed"
    print_info "Install models with: ollama pull <model-name>"
    return 1
  fi
  
  # Filter out embedding models and separate coding models
  local coding_models=()
  local embed_model=""
  
  while IFS= read -r model; do
    if [[ -n "$model" ]]; then
      if [[ "$model" == *"embed"* ]] || [[ "$model" == *"nomic-embed"* ]]; then
        embed_model="$model"
      else
        coding_models+=("$model")
      fi
    fi
  done <<< "$installed_models"
  
  if [[ ${#coding_models[@]} -eq 0 ]]; then
    print_warn "No coding models found (only embedding models detected)"
    return 1
  fi
  
  print_info "Found ${#coding_models[@]} coding model(s) available"
  echo ""
  
  # Let user select primary model
  echo "Available models:"
  local index=1
  local selected_models=()
  for model in "${coding_models[@]}"; do
    echo "  $index) $model"
    ((index++))
  done
  echo ""
  
  # Select primary model (for chat, edit, apply roles)
  local primary_choice
  read -p "Select primary model for chat/edit/apply (1-${#coding_models[@]}): " primary_choice
  
  if [[ ! "$primary_choice" =~ ^[0-9]+$ ]] || [[ $primary_choice -lt 1 || $primary_choice -gt ${#coding_models[@]} ]]; then
    print_error "Invalid selection"
    return 1
  fi
  
  local primary_model="${coding_models[$((primary_choice-1))]}"
  selected_models+=("$primary_model")
  
  # Ask if user wants to add another model for autocomplete
  if [[ ${#coding_models[@]} -gt 1 ]]; then
    if prompt_yes_no "Add another model for autocomplete? (recommended for faster suggestions)" "n"; then
      echo ""
      echo "Available models (excluding primary):"
      local available_models=()
      local index=1
      for model in "${coding_models[@]}"; do
        if [[ "$model" != "$primary_model" ]]; then
          echo "  $index) $model"
          available_models+=("$model")
          ((index++))
        fi
      done
      echo ""
      
      if [[ ${#available_models[@]} -gt 0 ]]; then
        local autocomplete_choice
        read -p "Select autocomplete model (1-${#available_models[@]}): " autocomplete_choice
        
        if [[ "$autocomplete_choice" =~ ^[0-9]+$ ]] && [[ $autocomplete_choice -ge 1 && $autocomplete_choice -le ${#available_models[@]} ]]; then
          local autocomplete_model="${available_models[$((autocomplete_choice-1))]}"
          selected_models+=("$autocomplete_model")
        else
          print_warn "Invalid selection, skipping autocomplete model"
        fi
      else
        print_info "No other models available for autocomplete"
      fi
    fi
  fi
  
  # Backup existing config
  if [[ -f "$config_file" ]]; then
    local backup_file="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$config_file" "$backup_file"
    print_info "Backed up existing config to: $backup_file"
    log_info "Backed up existing config to: $backup_file"
  fi
  
  # Generate config YAML
  local primary_name=$(get_friendly_model_name "$primary_model")
  local config_yaml=$(cat <<EOF
name: Local Config
version: 1.0.0
schema: v1
models:
  - name: $primary_name
    provider: ollama
    model: $primary_model
    roles:
      - chat
      - edit
      - apply
EOF
  )
  
  # Add autocomplete model if different
  if [[ ${#selected_models[@]} -gt 1 ]]; then
    local autocomplete_model="${selected_models[1]}"
    local autocomplete_name=$(get_friendly_model_name "$autocomplete_model")
    config_yaml+=$(cat <<EOF

  - name: $autocomplete_name
    provider: ollama
    model: $autocomplete_model
    roles:
      - autocomplete
EOF
    )
  fi
  
  # Add embeddings model (use existing or default)
  local embed_model_to_use="${embed_model:-nomic-embed-text:latest}"
  config_yaml+=$(cat <<EOF

  - name: Nomic Embed
    provider: ollama
    model: $embed_model_to_use
    roles:
      - embed
EOF
  )
  
  # Write config
  echo "$config_yaml" > "$config_file"
  print_success "Continue.dev config updated: $config_file"
  log_info "Continue.dev config updated with models: ${selected_models[*]}"
  
  return 0
}

# Verify Continue.dev setup
verify_continue_setup() {
  print_header "✅ Verifying Continue.dev Setup"
  
  local issues=0
  
  # Check if Continue.dev extension is installed
  if [[ "$VSCODE_AVAILABLE" == "true" ]]; then
    local continue_installed=$(code --list-extensions 2>/dev/null | grep -i "Continue.continue" || echo "")
    if [[ -n "$continue_installed" ]]; then
      print_success "Continue.dev extension is installed"
    else
      print_warn "Continue.dev extension not found in installed extensions"
      print_info "You may need to install it manually or restart VS Code"
      ((issues++))
    fi
  else
    print_warn "VS Code CLI not available, cannot verify extension installation"
  fi
  
  # Check if config file exists (try YAML first, then JSON for backward compatibility)
  local config_file="$HOME/.continue/config.yaml"
  local config_file_json="$HOME/.continue/config.json"
  
  if [[ -f "$config_file" ]]; then
    print_success "Continue.dev config file found: $config_file"
    
    # Validate YAML structure (basic check)
    if grep -q "^models:" "$config_file" 2>/dev/null; then
      print_success "Config file appears to be valid YAML"
      
      # Check for models (match indented YAML format)
      local model_count
      model_count=$(grep -c "^[[:space:]]*- name:" "$config_file" 2>/dev/null || echo "0")
      model_count=${model_count//[^0-9]/}  # Remove all non-numeric characters
      model_count=${model_count:-0}  # Default to 0 if empty
      if (( model_count > 0 )); then
        print_success "Found $model_count model(s) in config"
      else
        print_warn "No models configured in config file"
        # Offer to configure models from installed Ollama models
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
          if prompt_yes_no "Would you like to configure models from installed Ollama models?" "y"; then
            configure_continue_models_from_ollama "$config_file"
            # Re-check model count after configuration
            model_count=$(grep -c "^[[:space:]]*- name:" "$config_file" 2>/dev/null || echo "0")
            model_count=${model_count//[^0-9]/}
            model_count=${model_count:-0}
            if (( model_count > 0 )); then
              print_success "Models configured successfully"
            else
              ((issues++))
            fi
          else
            ((issues++))
          fi
        else
          ((issues++))
        fi
      fi
    else
      print_warn "Config file structure may be invalid"
      ((issues++))
    fi
  elif [[ -f "$config_file_json" ]]; then
    print_warn "Found old JSON config file: $config_file_json"
    print_info "Consider migrating to YAML format (config.yaml)"
    # Validate JSON if jq is available
    if command -v jq &>/dev/null; then
      if jq empty "$config_file_json" 2>/dev/null; then
        print_success "Config file is valid JSON"
        
        # Check for models
        local model_count
        model_count=$(jq '.models | length' "$config_file_json" 2>/dev/null || echo "0")
        model_count=${model_count//[^0-9]/}  # Remove all non-numeric characters
        model_count=${model_count:-0}  # Default to 0 if empty
        if (( model_count > 0 )); then
          print_success "Found $model_count model profile(s) in config"
        else
          print_warn "No models configured in config file"
          ((issues++))
        fi
      else
        print_error "Config file is not valid JSON"
        ((issues++))
      fi
    fi
  else
    print_error "Continue.dev config file not found at $config_file or $config_file_json"
    ((issues++))
  fi
  
  # Check if Ollama is running
  if curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_success "Ollama service is running"
  else
    print_warn "Ollama service is not running"
    print_info "Start it with: brew services start ollama"
    ((issues++))
  fi
  
  # Check Continue CLI (optional but helpful)
  if check_continue_cli; then
    print_success "Continue CLI (cn) is available"
    print_info "You can use 'cn' in terminal for interactive Continue workflows"
  else
    print_info "Continue CLI (cn) not installed (optional)"
    if prompt_yes_no "Would you like to install Continue CLI (cn) now?" "n"; then
      print_info "Installing @continuedev/cli globally..."
      
      # Try installation first
      set +e
      local install_output
      install_output=$(npm install -g @continuedev/cli 2>&1)
      local install_exit_code=$?
      set -e
      
      echo "$install_output" | tee -a "$LOG_FILE" >/dev/null 2>&1 || true
      
      # Check for certificate errors
      if [[ $install_exit_code -ne 0 ]] && echo "$install_output" | grep -qiE "(self.?signed|certificate|cert|tls|ssl|UNABLE_TO_VERIFY_LEAF_SIGNATURE)"; then
        log_warn "Certificate error detected during Continue CLI installation"
        print_warn "Certificate validation error detected"
        echo ""
        
        if prompt_yes_no "Would you like to disable strict SSL checking for npm (npm config set strict-ssl false)?" "y"; then
          print_info "Configuring npm to disable strict SSL checking..."
          npm config set strict-ssl false
          log_info "npm configured: strict-ssl = false"
          print_success "npm configured to disable strict SSL"
          
          # Retry installation
          print_info "Retrying Continue CLI installation..."
          set +e
          install_output=$(npm install -g @continuedev/cli 2>&1)
          install_exit_code=$?
          set -e
          
          echo "$install_output" | tee -a "$LOG_FILE" >/dev/null 2>&1 || true
        fi
      fi
      
      if [[ $install_exit_code -eq 0 ]]; then
        print_success "Continue CLI installed successfully"
      else
        print_warn "Continue CLI installation failed, but setup can continue"
        if [[ -n "$install_output" ]]; then
          echo "$install_output" | sed 's/^/  /'
        fi
      fi
    else
      print_info "You can install it later with: npm i -g @continuedev/cli"
    fi
  fi
  
  if [[ $issues -eq 0 ]]; then
    print_success "Continue.dev setup verified successfully"
    return 0
  else
    print_warn "Found $issues issue(s) with Continue.dev setup"
    return 1
  fi
}
