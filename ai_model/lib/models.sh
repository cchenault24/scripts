#!/bin/bash
#
# models.sh - Model selection, installation, validation, and benchmarking for setup-local-llm.sh
#
# Depends on: constants.sh, logger.sh, ui.sh, hardware.sh, ollama.sh

# Model eligibility check
is_model_eligible() {
  local model="$1"
  local tier="$2"
  
  # Embedding models are always eligible (very small)
  case "$model" in
    "nomic-embed-text"|"mxbai-embed-large"|"snowflake-arctic-embed2"|"granite-embedding"|"all-minilm")
      return 0 ;;
  esac
  
  case "$tier" in
    S) 
      # Tier S: All models allowed
      return 0 ;;
    A) 
      # Tier A: Exclude very large models (70B)
      [[ "$model" != "llama3.1:70b" && \
         "$model" != "llama3.3:70b" ]] ;;
    B) 
      # Tier B: Exclude large models (70B, 22B+), but allow smaller ones
      [[ "$model" != "llama3.1:70b" && \
         "$model" != "llama3.3:70b" && \
         "$model" != "codestral:22b" ]] ;;
    C) 
      # Tier C: Only small models (8B and below)
      [[ "$model" == "llama3.1:8b" || \
         "$model" == "codegemma:7b" || \
         "$model" == "starcoder2:7b" || \
         "$model" == "granite-code:8b" || \
         "$model" == "starcoder2:3b" || \
         "$model" == "llama3.2:3b" ]] ;;
    *) return 1 ;;
  esac
}

# Validate that a custom model exists in Ollama library
validate_model_exists() {
  local model="$1"
  
  # Basic format validation: should contain at least one colon or be a simple name
  if [[ -z "$model" ]]; then
    print_error "Model name cannot be empty"
    return 1
  fi
  
  # Sanitize model name first
  local sanitized_model
  if command -v sanitize_model_name &>/dev/null; then
    sanitized_model=$(sanitize_model_name "$model")
    if [[ -z "$sanitized_model" ]] || [[ "$sanitized_model" != "$model" ]]; then
      print_error "Model name contains invalid characters"
      return 1
    fi
  fi
  
  # Validate model name format and safety
  if command -v validate_model_name &>/dev/null; then
    if ! validate_model_name "$model"; then
      return 1
    fi
  else
    # Fallback validation
    if ! [[ "$model" =~ ^[a-zA-Z0-9._-]+(:[a-zA-Z0-9._-]+)?$ ]]; then
      print_error "Invalid model name format. Expected format: modelname:tag or modelname"
      print_info "Example: codellama:13b or llama3.1:8b"
      return 1
    fi
  fi
  
  # Check if model is already installed locally
  if is_model_installed "$model"; then
    print_success "Model $model is already installed locally"
    return 0
  fi
  
  # Quick check: try to get model info (works for locally installed models)
  print_info "Checking if model $model exists..."
  if ollama show "$model" &>/dev/null; then
    print_success "Model $model found"
    return 0
  fi
  
  # For models not yet installed, we can't verify existence without downloading
  # Format is valid, so accept it - full validation will happen during installation
  print_success "Model name format is valid: $model"
  print_info "Model availability will be verified during installation."
  return 0
}

# Check if a model is in the approved list
is_approved_model() {
  local model="$1"
  for approved in "${APPROVED_MODELS[@]}"; do
    if [[ "$model" == "$approved" ]]; then
      return 0
    fi
  done
  return 1
}

# Validate total RAM usage and suggest optimizations
validate_total_ram_usage() {
  local tier="$1"
  shift
  local selected_models=("$@")
  
  if [[ ${#selected_models[@]} -eq 0 ]]; then
    return 0
  fi
  
  local total_ram=$(calculate_total_ram "${selected_models[@]}")
  local max_ram=$(get_tier_max_ram "$tier")
  
  # Convert to integers for comparison
  local total_int=$(echo "$total_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
  local max_int=$(echo "$max_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
  
  if [[ $total_int -gt $max_int ]]; then
    print_warn "Total RAM usage (~${total_ram}GB) exceeds recommended limit for $TIER_LABEL (~${max_ram}GB)"
    echo ""
    echo -e "${YELLOW}Selected models and RAM usage:${NC}"
    
    # Show unique models with their RAM
    local unique_models_str=$(get_unique_models "${selected_models[@]}")
    local unique_models=()
    if [[ -n "$unique_models_str" ]]; then
      # Convert space-separated string to array
      for model in $unique_models_str; do
        unique_models+=("$model")
      done
    fi
    for model in "${unique_models[@]}"; do
      local ram=$(get_model_ram "$model")
      local roles=$(get_model_role "$model")
      echo -e "  • ${BOLD}$model${NC}: ~${ram}GB (roles: ${roles// /, })"
    done
    
    echo ""
    echo -e "${CYAN}💡 Optimization suggestions:${NC}"
    echo -e "  1. Reuse models across roles (e.g., use same model for Agent Plan and Autocomplete)"
    echo -e "  2. Select smaller models for some roles"
    echo -e "  3. Consider using fewer roles"
    echo ""
    
    if ! prompt_yes_no "Continue with this selection anyway? (May cause performance issues)" "n"; then
      return 1
    fi
  else
    # Show summary even if under limit
    local unique_models_str=$(get_unique_models "${selected_models[@]}")
    local unique_models=()
    if [[ -n "$unique_models_str" ]]; then
      for model in $unique_models_str; do
        unique_models+=("$model")
      done
    fi
    if [[ ${#unique_models[@]} -gt 1 ]]; then
      print_info "Total RAM usage: ~${total_ram}GB (${#unique_models[@]} unique model(s))"
      log_info "Total RAM usage for selected models: ~${total_ram}GB"
    fi
  fi
  
  return 0
}

# Find models that can be reused for a role from already selected models
find_reusable_models() {
  local role="$1"
  shift
  local already_selected=("$@")
  local reusable=()
  
  # Handle empty array safely
  if [[ ${#already_selected[@]} -gt 0 ]]; then
    for model in "${already_selected[@]}"; do
      if can_model_serve_role "$model" "$role"; then
        reusable+=("$model")
      fi
    done
  fi
  
  # Return space-separated string (empty if no reusable models)
  if [[ ${#reusable[@]} -gt 0 ]]; then
    echo "${reusable[@]}"
  fi
}

# Select models for a specific role
select_models_by_role() {
  local role="$1"
  local role_display="$2"
  local tier="$3"
  # Models already selected for other roles (handle empty case safely)
  local already_selected_models=()
  shift 3
  if [[ $# -gt 0 ]]; then
    already_selected_models=("$@")
  fi
  
  
  local models_for_role=($(get_models_for_role "$role"))
  
  
  if [[ ${#models_for_role[@]} -eq 0 ]]; then
    # Return empty string instead of returning 1, so command substitution doesn't fail
    # This allows the calling code to handle empty results gracefully
    echo ""
    return 0
  fi
  
  local default_model=$(get_default_model_for_role "$role" "$tier")
  
  # Check for reusable models from already selected (prefer these!)
  # Handle empty array safely - always initialize as empty array
  local reusable_models=()
  if [[ ${#already_selected_models[@]} -gt 0 ]]; then
    local reusable_str=$(find_reusable_models "$role" "${already_selected_models[@]}")
    if [[ -n "$reusable_str" ]]; then
      for model in $reusable_str; do
        reusable_models+=("$model")
      done
    fi
  fi
  
  # If we have reusable models, prefer the largest eligible one as default
  if [[ ${#reusable_models[@]} -gt 0 ]]; then
    # Find the largest eligible reusable model
    local best_reusable=""
    local best_ram=0
    for model in "${reusable_models[@]}"; do
      if is_model_eligible "$model" "$tier"; then
        local ram=$(get_model_ram "$model")
        local ram_int=$(echo "$ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
        if [[ "$ram_int" =~ ^[0-9]+$ ]] && [[ $ram_int -gt $best_ram ]]; then
          best_reusable="$model"
          best_ram=$ram_int
        fi
      fi
    done
    
    # Use reusable model as default if found
    if [[ -n "$best_reusable" ]]; then
      default_model="$best_reusable"
    fi
  fi
  
  # Validate that the recommended model is actually eligible for this tier
  if ! is_model_eligible "$default_model" "$tier"; then
    # Fallback: find first eligible model
    for model in "${models_for_role[@]}"; do
      if is_model_eligible "$model" "$tier"; then
        default_model="$model"
        break
      fi
    done
  fi
  
  # Redirect all UI output to stderr so it displays but doesn't get captured in command substitution
  echo "" >&2
  echo -e "${CYAN}Select models for ${BOLD}$role_display${NC} role:" >&2
  
  # Check if default is a reusable model
  local is_default_reusable=false
  if [[ ${#reusable_models[@]} -gt 0 ]]; then
    for model in "${reusable_models[@]}"; do
      if [[ "$model" == "$default_model" ]]; then
        is_default_reusable=true
        break
      fi
    done
  fi
  
  if [[ "$is_default_reusable" == "true" ]]; then
    local default_ram=$(get_model_ram "$default_model")
    echo -e "${CYAN}Recommended for $TIER_LABEL: ${BOLD}$default_model${NC} ${GREEN}✓ (reuse - saves ~${default_ram}GB RAM)${NC}" >&2
  else
    echo -e "${CYAN}Recommended for $TIER_LABEL: ${BOLD}$default_model${NC}" >&2
  fi
  
  # Show reusable models if any (and default is not one of them)
  if [[ ${#reusable_models[@]} -gt 0 ]] && [[ "$is_default_reusable" == "false" ]]; then
    echo "" >&2
    echo -e "${GREEN}💡 Smart suggestion:${NC} You can reuse these already-selected models:" >&2
    for model in "${reusable_models[@]}"; do
      local ram=$(get_model_ram "$model")
      echo -e "  ${GREEN}✓${NC} ${BOLD}$model${NC} (~${ram}GB) - already selected" >&2
    done
    echo -e "  ${CYAN}Tip:${NC} Reusing models saves RAM and speeds up loading" >&2
  fi
  
  # Show current RAM usage if models already selected
  if [[ ${#already_selected_models[@]} -gt 0 ]]; then
    local current_ram
    current_ram=$(calculate_total_ram "${already_selected_models[@]}")
    local max_ram=$(get_tier_max_ram "$tier")
    local current_int=$(echo "$current_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
    local max_int=$(echo "$max_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
    
    echo "" >&2
    echo -e "${CYAN}Current RAM usage:${NC} ~${current_ram}GB / ~${max_ram}GB recommended" >&2
    if [[ $current_int -gt $max_int ]]; then
      echo -e "${YELLOW}⚠ Warning:${NC} Already over recommended limit" >&2
    fi
  fi
  
  echo "" >&2
  
  local gum_items=()
  local model_map=()
  local temp_items=()
  
  # Calculate maximum widths for alignment
  local max_model_width=0
  local max_ram_width=0
  
  for model in "${models_for_role[@]}"; do
    local model_len=${#model}
    if [[ $model_len -gt $max_model_width ]]; then
      max_model_width=$model_len
    fi
    
    local ram=$(get_model_ram "$model")
    local ram_display="${ram}GB"
    local ram_len=${#ram_display}
    if [[ $ram_len -gt $max_ram_width ]]; then
      max_ram_width=$ram_len
    fi
  done
  
  # Add padding
  max_model_width=$((max_model_width + 2))
  max_ram_width=$((max_ram_width + 1))
  
  # Build temporary array with priority flag, model name and formatted string
  for model in "${models_for_role[@]}"; do
    local is_recommended=false
    if [[ "$model" == "$default_model" ]]; then
      is_recommended=true
    fi
    
    # Check if this model is already selected (reusable)
    local is_reusable=false
    if [[ ${#already_selected_models[@]} -gt 0 ]]; then
      for existing in "${already_selected_models[@]}"; do
        if [[ "$model" == "$existing" ]]; then
          is_reusable=true
          break
        fi
      done
    fi
    
    local formatted=$(format_model_for_gum "$model" "$tier" "$is_recommended" "$max_model_width" "$max_ram_width")
    
    # Add reuse indicator to description if reusable
    if [[ "$is_reusable" == "true" ]]; then
      # Append reuse indicator (will be shown in the list)
      formatted="${formatted} ${GREEN}✓ (reuse)${NC}"
    fi
    
    local is_eligible=false
    if is_model_eligible "$model" "$tier"; then
      is_eligible=true
    fi
    
    # Prioritize: eligible reusable > eligible recommended > eligible > ineligible
    local priority="C"
    if [[ "$is_eligible" == "true" ]]; then
      if [[ "$is_reusable" == "true" ]]; then
        priority="A"  # Highest priority: eligible and reusable
      elif [[ "$is_recommended" == "true" ]]; then
        priority="B"  # Second: eligible and recommended
      else
        priority="C"  # Third: eligible but not recommended
      fi
    else
      priority="D"  # Lowest: ineligible
    fi
    
    temp_items+=("${priority}|${model}|${formatted}")
  done
  
  # Sort by priority (A=reusable, B=recommended, C=eligible, D=ineligible), then by model name
  IFS=$'\n' sorted_items=($(printf '%s\n' "${temp_items[@]}" | sort -t'|' -k1,1 -k2,2V))
  unset IFS
  
  # Extract sorted formatted strings and model names
  for item in "${sorted_items[@]}"; do
    local recommended_flag="${item%%|*}"
    local remaining="${item#*|}"
    local model_name="${remaining%%|*}"
    local formatted="${remaining#*|}"
    gum_items+=("$formatted")
    model_map+=("$model_name")
  done
  
  # Use gum choose with --limit=100 to enable visual selection feedback, but only process first selection
  echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to select, ${BOLD}Enter${NC} to confirm" >&2
  echo -e "${YELLOW}   Note:${NC} Only select one model. Subsequent selections will be discarded." >&2
  echo "" >&2
  
  local selected_lines
  
  # Capture gum output, but ensure stderr (UI messages) goes to terminal, not command substitution
  # Use a file descriptor to redirect stderr to the terminal while capturing stdout
  selected_lines=$(printf '%s\n' "${gum_items[@]}" | gum choose \
    --limit=100 \
    --height=15 \
    --cursor="→ " \
    --selected-prefix="✓ " \
    --unselected-prefix="  " \
    --selected.foreground="2" \
    --selected.background="0" \
    --cursor.foreground="6" \
    --header="🤖 Select $role_display Models for $TIER_LABEL" \
    --header.foreground="6" 2>/dev/tty)
  
  
  # If user cancelled (empty selection), return empty string immediately
  if [[ -z "$selected_lines" ]]; then
    echo ""
    return 0
  fi
  
  local selected_models_for_role=()
  if [[ -n "$selected_lines" ]]; then
    
    # Count selections and identify discarded items
    local selected_count=$(echo "$selected_lines" | grep -c '^[[:space:]]*[^[:space:]]' || echo 0)
    
    # Process only the first line (discard subsequent selections)
    local first_line=$(echo "$selected_lines" | head -n 1)
    
    # If multiple selections, log the discarded ones
    if [[ $selected_count -gt 1 ]]; then
      local discarded_lines=$(echo "$selected_lines" | tail -n +2)
      local discarded_items=()
      while IFS= read -r line; do
        if [[ -n "$line" ]]; then
          # Clean the line to get the model name
          local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
          line_clean="${line_clean#→ }"  # Remove cursor if present
          line_clean="${line_clean#✓ }"  # Remove selection prefix if present
          line_clean=$(echo "$line_clean" | sed 's/\x1b\[[0-9;]*m//g')  # Remove ANSI codes
          
          # Try to find matching model name
          local i=0
          local matched=false
          for item in "${gum_items[@]}"; do
            local item_clean=$(echo "$item" | sed 's/\x1b\[[0-9;]*m//g')
            if [[ "$item_clean" == "$line_clean" ]]; then
              discarded_items+=("${model_map[$i]}")
              matched=true
              break
            fi
            ((i++))
          done
        fi
      done <<< "$discarded_lines"
      
      if [[ ${#discarded_items[@]} -gt 0 ]]; then
        print_warn "Multiple models selected. Using first selection, discarding: ${discarded_items[*]}"
        log_info "Multiple models selected. Using first selection, discarding: ${discarded_items[*]}"
      fi
    fi
    if [[ -n "$first_line" ]]; then
      # Clean the line - remove leading whitespace, cursor, selection prefix, and any ANSI codes
      local line_clean="${first_line#"${first_line%%[![:space:]]*}"}"  # Remove leading whitespace
      line_clean="${line_clean#→ }"  # Remove cursor if present
      line_clean="${line_clean#✓ }"  # Remove selection prefix if present
      # Remove ANSI color codes
      line_clean=$(echo "$line_clean" | sed 's/\x1b\[[0-9;]*m//g')
      
      # Try to match the cleaned line to our formatted items
      local model_name=""
      local i=0
      for item in "${gum_items[@]}"; do
        # Remove ANSI codes from item for comparison
        local item_clean=$(echo "$item" | sed 's/\x1b\[[0-9;]*m//g')
        if [[ "$item_clean" == "$line_clean" ]]; then
          model_name="${model_map[$i]}"
          break
        fi
        ((i++))
      done
      
      # Only add if we found a valid model name
      
      if [[ -n "$model_name" ]]; then
        
        if is_approved_model "$model_name"; then
          selected_models_for_role+=("$model_name")
        fi
      fi
    fi
  fi
  
  # Return selected models as space-separated string (only valid model names)
  if [[ ${#selected_models_for_role[@]} -gt 0 ]]; then
    local return_value=$(printf '%s ' "${selected_models_for_role[@]}" | sed 's/ $//')  # Remove trailing space

    echo "$return_value"
  fi
}

# Model selection with role-based organization
select_models() {
  print_header "🤖 Model Selection by Role"
  
  echo -e "${CYAN}Select models to install organized by Continue.dev roles.${NC}"
  echo -e "${CYAN}Models are auto-tuned based on your hardware tier.${NC}"
  echo ""
  
  SELECTED_MODELS=()
  
  # Define roles with display names
  # Note: rerank is excluded since RERANK_MODELS is empty
  local roles=("agent_chat_edit" "autocomplete" "embed" "next_edit")
  local role_display=("Agent Plan/Chat/Edit" "Autocomplete" "Embed" "Next Edit")
  local role_descriptions=(
    "Complex coding tasks, refactoring, agent planning"
    "Fast, lightweight real-time code suggestions"
    "Code indexing and semantic search"
    "Predicting the next edit"
  )
  
  # First, let user select which roles they want
  echo -e "${CYAN}Select which roles you want to configure:${NC}"
  echo ""
  echo -e "${YELLOW}💡 Tip:${NC} Press ${BOLD}Space${NC} to toggle selection, ${BOLD}Enter${NC} to confirm" >&2
  echo "" >&2
  
  local role_items=()
  local role_map=()
  local i=0
  for role in "${roles[@]}"; do
    local display="${role_display[$i]}"
    local desc="${role_descriptions[$i]}"
    role_items+=("$display - $desc")
    role_map+=("$role")
    ((i++))
  done
  
  local selected_role_lines
  selected_role_lines=$(printf '%s\n' "${role_items[@]}" | gum choose \
    --limit=100 \
    --height=10 \
    --cursor="→ " \
    --selected-prefix="✓ " \
    --unselected-prefix="  " \
    --selected.foreground="2" \
    --selected.background="0" \
    --cursor.foreground="6" \
    --header="📋 Select Roles to Configure" \
    --header.foreground="6")
  
  if [[ -z "$selected_role_lines" ]]; then
    log_error "No roles selected"
    exit 1
  fi
  
  # Parse selected roles (process all selected lines)
  local selected_roles=()
  if [[ -n "$selected_role_lines" ]]; then
    while IFS= read -r line; do
      if [[ -z "$line" ]]; then
        continue
      fi
      
      local line_clean="${line#"${line%%[![:space:]]*}"}"  # Remove leading whitespace
      line_clean="${line_clean#→ }"  # Remove cursor if present
      line_clean="${line_clean#✓ }"  # Remove selection prefix if present
      # Remove ANSI color codes
      line_clean=$(echo "$line_clean" | sed 's/\x1b\[[0-9;]*m//g')
      
      local i=0
      for item in "${role_items[@]}"; do
        if [[ "$item" == "$line_clean" ]]; then
          selected_roles+=("${role_map[$i]}")
          break
        fi
        ((i++))
      done
    done <<< "$selected_role_lines"
  fi
  
  if [[ ${#selected_roles[@]} -eq 0 ]]; then
    log_error "No roles selected"
    exit 1
  fi
  
  
  # For each selected role, let user select models
  for role in "${selected_roles[@]}"; do
    # Find display name for this role
    local role_display_name=""
    local i=0
    for r in "${roles[@]}"; do
      if [[ "$r" == "$role" ]]; then
        role_display_name="${role_display[$i]}"
        break
      fi
      ((i++))
    done
    
    # Check if this role has any models available before trying to select
    local available_models=($(get_models_for_role "$role"))
    if [[ ${#available_models[@]} -eq 0 ]]; then
      echo ""
      print_warn "Skipping $role_display_name: No models available for this role"
      echo ""
      continue
    fi
    

    # Handle empty array safely for set -u compatibility
    # Use parameter expansion that handles empty arrays: "${array[@]:-}"
    # IMPORTANT: Declare local variable at start of loop iteration to avoid variable persistence
    local selected_for_role=""
    local selected_for_role_clean=""
    
    # Call function and capture only stdout (stderr goes to terminal via >&2 in function)
    # Use a subshell to ensure stderr redirection works correctly
    if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
      selected_for_role=$(select_models_by_role "$role" "$role_display_name" "$HARDWARE_TIER" "${SELECTED_MODELS[@]}" 2>/dev/tty)
    else
      selected_for_role=$(select_models_by_role "$role" "$role_display_name" "$HARDWARE_TIER" 2>/dev/tty)
    fi
    
    
    # Get selected models for this role (trim any trailing whitespace/newlines)
    local selected_for_role_clean=$(echo "$selected_for_role" | xargs)
    
    
    if [[ -n "$selected_for_role_clean" ]]; then
      # Add selected models to SELECTED_MODELS array
      # Split by space and process each model
      local models_array=()
      # Use read to properly split the space-separated string
      read -ra model_tokens <<< "$selected_for_role_clean"
      
      for model in "${model_tokens[@]}"; do
        # Trim whitespace and validate it's a real model name
        model=$(echo "$model" | xargs)
        # Only add if it's non-empty and is an approved model
        if [[ -n "$model" ]] && is_approved_model "$model"; then
          models_array+=("$model")
        fi
      done
      
      # Process each valid model
      for model in "${models_array[@]}"; do
        # Check if model is already in SELECTED_MODELS (models can belong to multiple roles)
        local found=0
        if [[ ${#SELECTED_MODELS[@]} -gt 0 ]]; then
          for existing in "${SELECTED_MODELS[@]}"; do
            if [[ "$model" == "$existing" ]]; then
              found=1
              break
            fi
          done
        fi
        
        if [[ $found -eq 0 ]]; then
          # New model - add it
          SELECTED_MODELS+=("$model")

          
          # Get model RAM and only show message if valid
          
          local model_ram=$(get_model_ram "$model")
          
          
          local model_ram_int=$(echo "$model_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
          
          
          # Only show RAM summary if model has valid RAM estimate
          if [[ "$model_ram_int" =~ ^[0-9]+$ ]] && [[ $model_ram_int -gt 0 ]]; then
            local current_ram=$(calculate_total_ram "${SELECTED_MODELS[@]}")
            local max_ram=$(get_tier_max_ram "$HARDWARE_TIER")
            local current_int=$(echo "$current_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
            local max_int=$(echo "$max_ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
            
            echo ""
            if [[ $current_int -gt $max_int ]]; then
              print_warn "RAM usage: ~${current_ram}GB / ~${max_ram}GB (exceeds limit by ~$((current_int - max_int))GB)"
            else
              print_info "RAM usage: ~${current_ram}GB / ~${max_ram}GB (${model_ram}GB added)"
            fi
            echo ""
          fi
        else
          # Model already selected - show reuse message (only if it's a meaningful reuse)
          # Skip if this is the same role (no need to announce)

          echo ""
          print_info "Reusing model $model for $role_display_name (saves RAM)"
          echo ""
        fi
      done
    fi
  done
  
  # Note: Custom model addition via interactive prompt has been disabled
  # The selection is now limited to predefined and approved models only.

  # Validate selection
  if [[ ${#SELECTED_MODELS[@]} -eq 0 ]]; then
    log_error "No models selected"
    exit 1
  fi
  
  # Show final summary before validation
  echo ""
  print_header "📊 Selection Summary"
  
  local unique_models_str=$(get_unique_models "${SELECTED_MODELS[@]}")
  local unique_models=()
  if [[ -n "$unique_models_str" ]]; then
    for model in $unique_models_str; do
      unique_models+=("$model")
    done
  fi
  local total_ram=$(calculate_total_ram "${SELECTED_MODELS[@]}")
  local max_ram=$(get_tier_max_ram "$HARDWARE_TIER")
  
  echo -e "${CYAN}Selected ${#unique_models[@]} unique model(s) across ${#selected_roles[@]} role(s):${NC}"
  echo ""
  
  # Show models grouped by role
  for role in "${selected_roles[@]}"; do
    local role_display_name=""
    local i=0
    for r in "${roles[@]}"; do
      if [[ "$r" == "$role" ]]; then
        role_display_name="${role_display[$i]}"
        break
      fi
      ((i++))
    done
    
    # Find models that serve this role
    local role_models=()
    for model in "${unique_models[@]}"; do
      if can_model_serve_role "$model" "$role"; then
        role_models+=("$model")
      fi
    done
    
    if [[ ${#role_models[@]} -gt 0 ]]; then
      echo -e "  ${BOLD}$role_display_name:${NC}"
      for model in "${role_models[@]}"; do
        local ram=$(get_model_ram "$model")
        echo -e "    • $model (~${ram}GB)"
      done
    fi
  done
  
  echo ""
  echo -e "${CYAN}Total RAM usage:${NC} ~${total_ram}GB / ~${max_ram}GB recommended for $TIER_LABEL"
  
  # Validate total RAM usage
  if ! validate_total_ram_usage "$HARDWARE_TIER" "${SELECTED_MODELS[@]}"; then
    print_info "Please adjust your model selection"
    # Return to selection (could loop back, but for now just exit)
    exit 1
  fi
  
  echo ""
  
  # Warn about ineligible models
  for model in "${SELECTED_MODELS[@]}"; do
    if ! is_model_eligible "$model" "$HARDWARE_TIER"; then
      print_warn "Model $model is not recommended for $TIER_LABEL hardware"
      if ! prompt_yes_no "Continue with this model anyway?" "n"; then
        SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
      fi
    fi
  done
  
  # Warn about large individual models
  for model in "${SELECTED_MODELS[@]}"; do
    # Check if this is a custom model (not in approved list)
    if ! is_approved_model "$model"; then
      # Custom model - show generic warning
      print_warn "Custom model $model selected - RAM requirements unknown"
      if ! prompt_yes_no "Ensure you have sufficient RAM for this model. Continue?" "y"; then
        SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
      fi
    else
      # Approved model - use known RAM estimates
      local ram=$(get_model_ram "$model")
      # Convert to integer for comparison (bash doesn't handle decimals in arithmetic)
      # Use awk to safely convert decimal to integer, default to 0 if not numeric
      local ram_int=$(echo "$ram" | awk '{if ($1+0 == $1) printf "%.0f", $1; else print "0"}')
      # Ensure ram_int is numeric before comparison
      if [[ "$ram_int" =~ ^[0-9]+$ ]] && [[ $ram_int -gt 20 ]]; then
        if ! prompt_yes_no "Model $model requires ~${ram}GB RAM. Continue?" "n"; then
          SELECTED_MODELS=($(printf '%s\n' "${SELECTED_MODELS[@]}" | grep -v "^${model}$"))
        fi
      fi
    fi
  done
  
  log_info "Selected models: ${SELECTED_MODELS[*]}"
  print_success "Selected ${#unique_models[@]} unique model(s) (~${total_ram}GB total RAM)"
}

# Auto-tune model parameters
# Supports dynamic optimizations via optional parameters
tune_model() {
  local model="$1"
  local tier="$2"
  local role="${3:-coding}"
  local use_optimizations="${4:-1}"  # Enable optimizations by default
  local task_type="${5:-general}"  # New: Task type for dynamic optimization
  local prompt_length="${6:-0}"  # New: Estimated prompt length
  
  # Use optimized tuning if available and enabled
  if [[ "$use_optimizations" == "1" ]] && command -v tune_model_optimized &>/dev/null; then
    tune_model_optimized "$model" "$tier" "$role" "$task_type" "$prompt_length"
    return
  fi
  
  # Original tuning logic (fallback)
  local context_size
  local max_tokens
  local temperature
  local top_p
  local keep_alive
  local num_gpu
  local num_thread
  
  # GPU and threading settings (from environment or calculated)
  num_gpu="${OLLAMA_NUM_GPU:-1}"
  num_thread="${OLLAMA_NUM_THREAD:-$((CPU_CORES - 2))}"
  if [[ $num_thread -lt 2 ]]; then
    num_thread=2
  fi
  
  case "$tier" in
    S)
      context_size=32768
      max_tokens=4096
      keep_alive="24h"
      ;;
    A)
      context_size=16384
      max_tokens=2048
      keep_alive="12h"
      ;;
    B)
      context_size=8192
      max_tokens=1024
      keep_alive="5m"
      ;;
    C)
      context_size=4096
      max_tokens=512
      keep_alive="5m"
      ;;
  esac
  
  # Role-specific temperature
  case "$role" in
    coding)
      temperature=0.7
      top_p=0.9
      ;;
    code-review)
      temperature=0.3
      top_p=0.95
      ;;
    documentation)
      temperature=0.5
      top_p=0.9
      ;;
    deep-analysis)
      temperature=0.6
      top_p=0.92
      ;;
    *)
      temperature=0.7
      top_p=0.9
      ;;
  esac
  
  # Return as JSON-like structure (will be used in config generation)
  cat <<EOF
{
  "context_size": $context_size,
  "max_tokens": $max_tokens,
  "temperature": $temperature,
  "top_p": $top_p,
  "keep_alive": "$keep_alive",
  "num_gpu": $num_gpu,
  "num_thread": $num_thread
}
EOF
}

# Install model
install_model() {
  local model="$1"
  
  # Validate and sanitize model name
  if ! validate_model_name "$model"; then
    log_error "Invalid model name: $model"
    return 1
  fi
  
  local sanitized_model
  sanitized_model=$(sanitize_model_name "$model")
  if [[ -z "$sanitized_model" ]] || [[ "$sanitized_model" != "$model" ]]; then
    log_error "Model name sanitization failed: $model"
    return 1
  fi
  
  print_info "Installing $sanitized_model..."
  print_info "Ollama will automatically select optimal quantization (Q4_K_M/Q5_K_M) for Apple Silicon"
  log_info "Installing model: $sanitized_model (Ollama auto-optimizes for Apple Silicon)"
  
  # Check if model is already installed
  if is_model_installed "$sanitized_model"; then
    print_success "$sanitized_model already installed, skipping download"
    INSTALLED_MODELS+=("$sanitized_model")
    # Initialize usage tracking for existing model
    if command -v init_usage_tracking &>/dev/null; then
      init_usage_tracking
    fi
    return 0
  fi
  
  # Check network connectivity before download
  if ! check_network_connectivity "https://ollama.com" 2 10 2; then
    log_error "Network connectivity check failed, cannot download model"
    print_error "Cannot download $sanitized_model: network connectivity failed"
    return 1
  fi
  
  # Download model with retry logic - Ollama automatically selects best quantization for Apple Silicon
  local download_success=false
  local max_download_attempts=3
  local download_attempt=1
  local download_delay=2
  local last_error_msg=""
  
  while [[ $download_attempt -le $max_download_attempts ]]; do
    log_info "Download attempt $download_attempt/$max_download_attempts for $sanitized_model"
    print_info "Download attempt $download_attempt of $max_download_attempts..."
    
    # Create a temp file to capture output for analysis
    local output_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/ollama_pull_XXXXXX.log" 2>/dev/null || echo "/tmp/ollama_pull_$$.log")
    
    # Use process substitution to capture exit code correctly
    # PIPESTATUS[0] gives us the exit code of ollama pull, not tee
    # Also capture output for error analysis
    ollama pull "$sanitized_model" 2>&1 | tee -a "$LOG_FILE" "$output_file"
    local pull_exit_code="${PIPESTATUS[0]}"
    
    # Analyze output for specific error conditions
    local pull_output=""
    if [[ -f "$output_file" ]]; then
      pull_output=$(cat "$output_file" 2>/dev/null || echo "")
      rm -f "$output_file" 2>/dev/null
    fi
    
    if [[ $pull_exit_code -eq 0 ]]; then
      # Verify the download actually completed (not just started)
      if echo "$pull_output" | grep -qiE "success|pulling.*done|verifying.*complete|writing.*manifest"; then
        download_success=true
        log_info "Download succeeded on attempt $download_attempt"
        break
      elif echo "$pull_output" | grep -qiE "already exists|up to date"; then
        download_success=true
        log_info "Model already exists, no download needed"
        break
      else
        # Exit code 0 but no clear success indicator - still treat as success
        # but log for debugging
        log_info "Download completed with exit code 0 (output: ${pull_output:0:100}...)"
        download_success=true
        break
      fi
    fi
    
    # Analyze failure reason
    if echo "$pull_output" | grep -qiE "not found|does not exist|unknown model"; then
      last_error_msg="Model '$sanitized_model' not found in Ollama library"
      log_error "$last_error_msg"
      print_error "$last_error_msg"
      print_info "Check available models at: https://ollama.com/library"
      rm -f "$output_file" 2>/dev/null
      return 1  # Don't retry if model doesn't exist
    elif echo "$pull_output" | grep -qiE "connection refused|network.*unreachable|timeout|timed out"; then
      last_error_msg="Network error during download"
      log_warn "$last_error_msg (attempt $download_attempt/$max_download_attempts)"
    elif echo "$pull_output" | grep -qiE "no space|disk full|not enough space"; then
      last_error_msg="Insufficient disk space for model"
      log_error "$last_error_msg"
      print_error "$last_error_msg"
      print_info "Free up disk space and try again"
      rm -f "$output_file" 2>/dev/null
      return 1  # Don't retry if no disk space
    elif echo "$pull_output" | grep -qiE "unauthorized|forbidden|access denied"; then
      last_error_msg="Access denied - model may require authentication"
      log_error "$last_error_msg"
      print_error "$last_error_msg"
      rm -f "$output_file" 2>/dev/null
      return 1  # Don't retry auth failures
    elif echo "$pull_output" | grep -qiE "rate limit|too many requests"; then
      last_error_msg="Rate limited by Ollama servers"
      log_warn "$last_error_msg"
      download_delay=$((download_delay * 3))  # Longer backoff for rate limits
    else
      last_error_msg="Download failed with exit code $pull_exit_code"
      log_warn "$last_error_msg (attempt $download_attempt/$max_download_attempts)"
    fi
    
    if [[ $download_attempt -lt $max_download_attempts ]]; then
      print_warn "Download failed: $last_error_msg"
      print_info "Retrying in ${download_delay}s..."
      sleep "$download_delay"
      download_delay=$((download_delay * 2))  # Exponential backoff
    fi
    
    ((download_attempt++))
  done
  
  if [[ "$download_success" == "true" ]]; then
    # Clear cache to force refresh
    if command -v clear_installed_models_cache &>/dev/null; then
      clear_installed_models_cache
    fi
    
    print_info "Verifying installation..."
    
    # Use the new wait_for_model_registration function if available
    # This handles timing issues with progressive backoff
    local verification_success=false
    
    if command -v wait_for_model_registration &>/dev/null; then
      # Wait up to 30 seconds for model registration with smart backoff
      if wait_for_model_registration "$sanitized_model" 30; then
        verification_success=true
      fi
    else
      # Fallback to original verification logic with improved timing
      local verification_attempts=0
      local max_verification_attempts=5
      local verification_delay=2
      
      # Initial wait - larger models need more time
      sleep 3
      
      while [[ $verification_attempts -lt $max_verification_attempts ]]; do
        # Clear cache before each check
        if command -v clear_installed_models_cache &>/dev/null; then
          clear_installed_models_cache
        fi
        
        # Try API verification first if available
        if command -v verify_model_via_api &>/dev/null && verify_model_via_api "$sanitized_model"; then
          verification_success=true
          break
        fi
        
        # Fallback to is_model_installed
        if is_model_installed "$sanitized_model"; then
          verification_success=true
          break
        fi
        
        verification_attempts=$((verification_attempts + 1))
        if [[ $verification_attempts -lt $max_verification_attempts ]]; then
          log_info "Model verification attempt $verification_attempts/$max_verification_attempts failed, retrying in ${verification_delay}s..."
          sleep "$verification_delay"
          verification_delay=$((verification_delay + 1))  # Progressive delay
        fi
      done
    fi
    
    if [[ "$verification_success" == "true" ]]; then
      print_success "$sanitized_model installed (automatically optimized for Apple Silicon)"
      log_info "Model $sanitized_model installed with automatic quantization optimization"
      INSTALLED_MODELS+=("$sanitized_model")
      # Initialize usage tracking for new model
      if command -v init_usage_tracking &>/dev/null; then
        init_usage_tracking
      fi
      return 0
    else
      log_error "Model download appeared successful but model is not installed: $sanitized_model"
      print_error "Installation verification failed for $sanitized_model"
      print_info "Troubleshooting steps:"
      print_info "  1. Check if the model is still being processed: ollama list"
      print_info "  2. Try manually pulling the model: ollama pull $sanitized_model"
      print_info "  3. Check Ollama logs for errors: cat ~/.ollama/logs/server.log"
      return 1
    fi
  else
    log_error "Failed to install $sanitized_model after $max_download_attempts attempts"
    print_error "Download failed for $sanitized_model"
    print_info "Possible causes:"
    print_info "  - Network connectivity issues"
    print_info "  - Model name may be incorrect"
    print_info "  - Ollama servers may be experiencing issues"
    print_info "Try again later or check: https://ollama.com/library"
    return 1
  fi
}

# Benchmark model performance
benchmark_model_performance() {
  local model="$1"
  
  print_info "Benchmarking $model performance..."
  log_info "Benchmarking model: $model"
  
  # Use smart loading if available
  if command -v smart_load_model &>/dev/null; then
    smart_load_model "$model" 0
  fi
  
  local test_prompt="Write a simple TypeScript function that adds two numbers and returns the result."
  local start_time=$(date +%s.%N 2>/dev/null || date +%s)
  local response
  local token_count=0
  
  # Track model usage
  if command -v track_model_usage &>/dev/null; then
    track_model_usage "$model"
  fi
  
  # Run model and capture response
  response=$(run_with_timeout 60 ollama run "$model" "$test_prompt" 2>&1)
  local end_time=$(date +%s.%N 2>/dev/null || date +%s)
  
  # Calculate duration (handle both formats)
  local duration
  if [[ "$start_time" =~ \. ]] && command -v bc &>/dev/null; then
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
  else
    # Fallback to integer arithmetic
    local start_int=${start_time%%.*}
    local end_int=${end_time%%.*}
    duration=$((end_int - start_int))
  fi
  
  # Estimate token count (rough: ~4 chars per token)
  if [[ -n "$response" ]]; then
    if command -v bc &>/dev/null; then
      token_count=$(echo "${#response} / 4" | bc 2>/dev/null || echo "0")
    else
      token_count=$(( ${#response} / 4 ))
    fi
  fi
  
  # Calculate tokens per second
  local tokens_per_sec=0
  # Use bc for floating point comparison if available, otherwise use integer comparison
  local duration_check=0
  if command -v bc &>/dev/null; then
    duration_check=$(echo "$duration > 0" | bc 2>/dev/null || echo "0")
  else
    # Integer comparison fallback
    local duration_int=${duration%%.*}
    if [[ $duration_int -gt 0 ]]; then
      duration_check=1
    fi
  fi
  
  if [[ $duration_check -eq 1 ]] && [[ $token_count -gt 0 ]]; then
    if command -v bc &>/dev/null; then
      tokens_per_sec=$(echo "scale=2; $token_count / $duration" | bc 2>/dev/null || echo "0")
    else
      # Integer division fallback
      local duration_int=${duration%%.*}
      tokens_per_sec=$(( token_count / duration_int ))
    fi
  fi
  
  # Check GPU usage via Ollama API
  local gpu_active=false
  local ps_response=$(curl -s http://localhost:11434/api/ps 2>/dev/null || echo "")
  # Detect CPU architecture if not already set (for fallback checks)
  local cpu_arch="${CPU_ARCH:-$(uname -m)}"
  
  if [[ -n "$ps_response" ]]; then
    # Try JSON parsing if jq is available
    if command -v jq &>/dev/null; then
      # Check for GPU-related fields in JSON response
      if echo "$ps_response" | jq -e '.models[]? | select(.gpu_layers != null or .gpu_layers > 0)' &>/dev/null; then
        gpu_active=true
      elif echo "$ps_response" | jq -e '.[]? | select(.gpu_layers != null or .gpu_layers > 0)' &>/dev/null; then
        gpu_active=true
      fi
    fi
    
    # Fallback: keyword search in response
    if [[ "$gpu_active" == "false" ]]; then
      if echo "$ps_response" | grep -qiE "gpu|metal|device|accelerat"; then
        gpu_active=true
      fi
    fi
  fi
  
  # Alternative: Check environment variables (OLLAMA_NUM_GPU > 0 indicates GPU should be used)
  if [[ "$gpu_active" == "false" ]] && [[ -n "${OLLAMA_NUM_GPU:-}" ]] && [[ "${OLLAMA_NUM_GPU}" -gt 0 ]]; then
    # On Apple Silicon, if OLLAMA_NUM_GPU is set, assume GPU is active
    if [[ "$cpu_arch" == "arm64" ]]; then
      gpu_active=true
    fi
  fi
  
  # On Apple Silicon, if Metal is available and Ollama is running, assume GPU is active
  if [[ "$gpu_active" == "false" ]] && [[ "$cpu_arch" == "arm64" ]]; then
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Metal"; then
      # Metal is available, and Ollama auto-detects it on Apple Silicon
      gpu_active=true
    fi
  fi
  
  # Display results
  if [[ -n "$response" && ${#response} -gt 10 ]]; then
    print_success "$model benchmark complete"
    print_info "  Response time: ${duration}s"
    if [[ $token_count -gt 0 ]]; then
      print_info "  Estimated tokens: ~$token_count"
      # Use bc for floating point comparison if available, otherwise use integer comparison
      local tokens_per_sec_check=0
      if command -v bc &>/dev/null; then
        tokens_per_sec_check=$(echo "$tokens_per_sec > 0" | bc 2>/dev/null || echo "0")
      else
        # Integer comparison fallback
        local tokens_per_sec_int=${tokens_per_sec%%.*}
        if [[ $tokens_per_sec_int -gt 0 ]]; then
          tokens_per_sec_check=1
        fi
      fi
      if [[ $tokens_per_sec_check -eq 1 ]]; then
        print_info "  Tokens/sec: ~${tokens_per_sec}"
      fi
    fi
    if [[ "$gpu_active" == "true" ]]; then
      print_info "  GPU acceleration: Active"
    else
      print_info "  GPU acceleration: Not verified (may still be active)"
    fi
    log_info "Model $model benchmark: ${duration}s, ~${tokens_per_sec} tokens/sec"
    return 0
  fi
  
  return 1
}

# Validate model (simple validation without benchmarking)
validate_model_simple() {
  local model="$1"
  
  print_info "Validating $model..."
  log_info "Validating model: $model"
  
  # Use smart loading if available
  if command -v smart_load_model &>/dev/null; then
    smart_load_model "$model" 0
  fi
  
  local test_prompt="Write a simple TypeScript function that adds two numbers."
  local start_time=$(date +%s)
  local response=""
  local response_file=""
  
  # Track model usage
  if command -v track_model_usage &>/dev/null; then
    track_model_usage "$model"
  fi
  
  # Create temp file to capture response (avoids pipeline issues)
  response_file=$(mktemp "${TMPDIR:-/tmp}/ollama_validate_XXXXXX.txt" 2>/dev/null || echo "/tmp/ollama_validate_$$.txt")
  
  # Test with timeout - capture to file to avoid pipeline exit code issues
  local validation_timeout=60  # Increased timeout for slower models
  run_with_timeout "$validation_timeout" ollama run "$model" "$test_prompt" > "$response_file" 2>&1
  local run_exit_code=$?
  
  # Read response from file
  if [[ -f "$response_file" ]]; then
    response=$(head -n 20 "$response_file" 2>/dev/null || cat "$response_file" 2>/dev/null || echo "")
    rm -f "$response_file" 2>/dev/null
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Log response info for debugging
  log_info "Validation response for $model: exit_code=$run_exit_code, response_length=${#response}, duration=${duration}s"
  
  # Check if we got a valid response
  # Success criteria: response > 10 chars AND doesn't look like an error message
  if [[ $run_exit_code -eq 0 ]] && [[ -n "$response" ]] && [[ ${#response} -gt 10 ]]; then
    # Check it's not just an error message
    if ! echo "$response" | grep -qiE "^error:|failed to|could not|unable to"; then
      print_success "$model validated (response time: ${duration}s)"
      log_info "Model $model validation successful (${duration}s)"
      return 0
    else
      log_warn "Response looks like error message: ${response:0:100}"
    fi
  elif [[ $run_exit_code -eq 124 ]]; then
    log_warn "Validation timed out after ${validation_timeout}s for $model"
  else
    log_warn "Validation got short/empty response (length=${#response}, exit=$run_exit_code)"
  fi
  
  # Retry once with longer timeout
  log_warn "Validation failed for $model, retrying with longer timeout..."
  sleep 3
  
  response_file=$(mktemp "${TMPDIR:-/tmp}/ollama_validate_XXXXXX.txt" 2>/dev/null || echo "/tmp/ollama_validate_retry_$$.txt")
  validation_timeout=90  # Even longer timeout for retry
  
  run_with_timeout "$validation_timeout" ollama run "$model" "$test_prompt" > "$response_file" 2>&1
  run_exit_code=$?
  
  if [[ -f "$response_file" ]]; then
    response=$(head -n 20 "$response_file" 2>/dev/null || cat "$response_file" 2>/dev/null || echo "")
    rm -f "$response_file" 2>/dev/null
  fi
  
  if [[ $run_exit_code -eq 0 ]] && [[ -n "$response" ]] && [[ ${#response} -gt 10 ]]; then
    if ! echo "$response" | grep -qiE "^error:|failed to|could not|unable to"; then
      print_success "$model validated (retry successful)"
      log_info "Model $model validation successful on retry"
      return 0
    fi
  fi
  
  # Provide helpful error message
  log_error "Validation failed for $model after retry"
  if [[ $run_exit_code -eq 124 ]]; then
    print_error "Model $model validation timed out - model may be too slow or unresponsive"
  elif [[ -z "$response" ]]; then
    print_error "Model $model returned empty response"
  elif [[ ${#response} -le 10 ]]; then
    print_error "Model $model returned very short response: '${response}'"
  else
    print_error "Model $model validation failed (response looks like error)"
  fi
  return 1
}

# Validate model (includes benchmarking for backward compatibility)
validate_model() {
  local model="$1"
  
  # Use the improved validate_model_simple for the actual validation
  if validate_model_simple "$model"; then
    # Quick performance check after successful validation
    print_info "Running quick performance check..."
    if benchmark_model_performance "$model"; then
      log_info "Model $model performance check passed"
    else
      log_warn "Model $model performance check had issues, but validation passed"
    fi
    return 0
  fi
  
  return 1
}

# Resolve actual installed model name
# Ollama uses base model names - quantization is handled internally
resolve_installed_model() {
  local model="$1"
  
  # Check if model is installed
  if is_model_installed "$model"; then
    echo "$model"
    return 0
  fi
  
  # Check in INSTALLED_MODELS array
  for installed in "${INSTALLED_MODELS[@]}"; do
    if [[ "$installed" == "$model" ]]; then
      echo "$installed"
      return 0
    fi
    # Check if base name matches (handles any variants)
    local installed_base="${installed%%:*}"
    local model_base="${model%%:*}"
    if [[ "$installed_base" == "$model_base" ]]; then
      echo "$installed"
      return 0
    fi
  done
  
  # Fallback: return model name (Ollama will handle it)
  echo "$model"
}