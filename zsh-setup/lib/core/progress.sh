#!/usr/bin/env bash

#==============================================================================
# progress.sh - Progress Indicators
#
# Provides spinner and progress bar functionality with overwriting output
#==============================================================================

#------------------------------------------------------------------------------
# Spinner Functions
#------------------------------------------------------------------------------

# Start a spinner (runs in background)
# Usage: zsh_setup::core::progress::spinner_start "message"
# Returns: PID of spinner process
zsh_setup::core::progress::spinner_start() {
    local message="$1"
    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_idx=0
    local parent_pid=$$
    
    # Create unique flag file path
    local flag_file="/tmp/zsh_setup_spinner_${parent_pid}_${RANDOM}.flag"
    touch "$flag_file"
    
    # Start spinner in background
    (
        while [[ -f "$flag_file" ]]; do
            local spinner="${spinner_chars[$spinner_idx]}"
            printf "\r\033[K%s %s" "$spinner" "$message" >&2
            spinner_idx=$(((spinner_idx + 1) % ${#spinner_chars[@]}))
            sleep 0.1
        done
        
        # Clean up flag file
        rm -f "$flag_file" 2>/dev/null
    ) &
    
    local spinner_pid=$!
    # Store flag file path for cleanup
    export ZSH_SETUP_SPINNER_FLAG_${spinner_pid}="$flag_file"
    
    echo $spinner_pid
}

# Stop a spinner
# Usage: zsh_setup::core::progress::spinner_stop <spinner_pid> [success_message] [error_message] [exit_code]
zsh_setup::core::progress::spinner_stop() {
    local spinner_pid="$1"
    local success_msg="${2:-}"
    local error_msg="${3:-}"
    local exit_code="${4:-0}"
    
    # Remove flag file to stop spinner
    local flag_var="ZSH_SETUP_SPINNER_FLAG_${spinner_pid}"
    if [[ -n "${!flag_var:-}" ]]; then
        rm -f "${!flag_var}" 2>/dev/null
        unset "$flag_var"
    fi
    
    # Kill spinner process if still running
    kill "$spinner_pid" 2>/dev/null
    wait "$spinner_pid" 2>/dev/null
    
    # Clear spinner line
    printf "\r\033[K" >&2
    
    # Print result message
    if [[ $exit_code -eq 0 ]] && [[ -n "$success_msg" ]]; then
        printf "%s\n" "$success_msg" >&2
    elif [[ $exit_code -ne 0 ]] && [[ -n "$error_msg" ]]; then
        printf "%s\n" "$error_msg" >&2
    fi
}

# Run a command with spinner
# Usage: zsh_setup::core::progress::with_spinner "message" <command>
zsh_setup::core::progress::with_spinner() {
    local message="$1"
    shift
    local cmd=("$@")
    
    local spinner_pid=$(zsh_setup::core::progress::spinner_start "$message")
    local exit_code=0
    
    # Run command, capturing output
    if "${cmd[@]}" >/dev/null 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    zsh_setup::core::progress::spinner_stop "$spinner_pid" "" "" "$exit_code"
    return $exit_code
}

#------------------------------------------------------------------------------
# Progress Bar Functions
#------------------------------------------------------------------------------

# Initialize progress bar
# Usage: zsh_setup::core::progress::bar_init <total> [message]
zsh_setup::core::progress::bar_init() {
    local total="$1"
    local message="${2:-Progress}"
    local bar_width=50
    
    # Store progress state
    export ZSH_SETUP_PROGRESS_TOTAL="$total"
    export ZSH_SETUP_PROGRESS_CURRENT="0"
    export ZSH_SETUP_PROGRESS_MESSAGE="$message"
    export ZSH_SETUP_PROGRESS_BAR_WIDTH="$bar_width"
}

# Update progress bar
# Usage: zsh_setup::core::progress::bar_update <current> [message]
zsh_setup::core::progress::bar_update() {
    local current="$1"
    local message="${2:-$ZSH_SETUP_PROGRESS_MESSAGE}"
    local total="${ZSH_SETUP_PROGRESS_TOTAL:-100}"
    local bar_width="${ZSH_SETUP_PROGRESS_BAR_WIDTH:-50}"
    
    # Calculate percentage
    local percent=$((current * 100 / total))
    
    # Calculate filled and empty parts
    local filled=$((current * bar_width / total))
    local empty=$((bar_width - filled))
    
    # Build progress bar
    local bar=""
    local i=0
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # Print progress bar (overwrites line)
    printf "\r\033[K[%s] %3d%% %s" "$bar" "$percent" "$message" >&2
}

# Complete progress bar
# Usage: zsh_setup::core::progress::bar_complete [message]
zsh_setup::core::progress::bar_complete() {
    local message="${1:-$ZSH_SETUP_PROGRESS_MESSAGE}"
    local total="${ZSH_SETUP_PROGRESS_TOTAL:-100}"
    local bar_width="${ZSH_SETUP_PROGRESS_BAR_WIDTH:-50}"
    
    # Fill bar completely
    local bar=""
    local i=0
    for ((i=0; i<bar_width; i++)); do
        bar+="█"
    done
    
    # Print final state
    printf "\r\033[K[%s] 100%% %s\n" "$bar" "$message" >&2
    
    # Clean up
    unset ZSH_SETUP_PROGRESS_TOTAL
    unset ZSH_SETUP_PROGRESS_CURRENT
    unset ZSH_SETUP_PROGRESS_MESSAGE
    unset ZSH_SETUP_PROGRESS_BAR_WIDTH
}

# Increment progress bar
# Usage: zsh_setup::core::progress::bar_increment [amount] [message]
zsh_setup::core::progress::bar_increment() {
    local amount="${1:-1}"
    local message="${2:-$ZSH_SETUP_PROGRESS_MESSAGE}"
    local current="${ZSH_SETUP_PROGRESS_CURRENT:-0}"
    local total="${ZSH_SETUP_PROGRESS_TOTAL:-100}"
    
    current=$((current + amount))
    export ZSH_SETUP_PROGRESS_CURRENT="$current"
    
    zsh_setup::core::progress::bar_update "$current" "$message"
    
    # Auto-complete if reached total
    if [[ $current -ge $total ]]; then
        zsh_setup::core::progress::bar_complete "$message"
    fi
}

#------------------------------------------------------------------------------
# Status Update Functions (for overwriting lines)
#------------------------------------------------------------------------------

# Print a status line that can be overwritten
# Usage: zsh_setup::core::progress::status "message"
zsh_setup::core::progress::status() {
    local message="$1"
    printf "\r\033[K%s" "$message" >&2
}

# Print a status line and move to next line
# Usage: zsh_setup::core::progress::status_line "message"
zsh_setup::core::progress::status_line() {
    local message="$1"
    printf "\r\033[K%s\n" "$message" >&2
}

# Clear current line
# Usage: zsh_setup::core::progress::clear_line
zsh_setup::core::progress::clear_line() {
    printf "\r\033[K" >&2
}
