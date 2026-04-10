#!/bin/bash
# lib/tui-advanced.sh - Advanced TUI features
#
# Provides:
# - Animated spinners
# - Progress bars
# - Box drawing utilities
# - Arrow key navigation
# - Time estimates
# - Interactive menus

set -euo pipefail

#############################################
# Terminal Capabilities
#############################################

# Check if terminal supports features
TERM_SUPPORTS_COLORS=false
TERM_SUPPORTS_UNICODE=false

if [[ -t 1 ]]; then
    TERM_SUPPORTS_COLORS=true
    if [[ "${LANG:-}" =~ UTF-8 ]]; then
        TERM_SUPPORTS_UNICODE=true
    fi
fi

#############################################
# Spinner Animation
#############################################

# Global spinner PID for cleanup
SPINNER_PID=""

# Start animated spinner with message
# Usage: start_spinner "Downloading..."
start_spinner() {
    local message="$1"
    local delay=0.1

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return  # No spinner in quiet mode
    fi

    # Unicode spinner frames (braille patterns)
    local spinstr='⣾⣽⣻⢿⡿⣟⣯⣷'

    # Background spinner process
    (
        while true; do
            local temp=${spinstr#?}
            printf "\r  %s %s" "${spinstr:0:1}" "$message"
            spinstr=$temp${spinstr%"$temp"}
            sleep $delay
        done
    ) &

    SPINNER_PID=$!
    trap "stop_spinner" EXIT INT TERM
}

# Stop the spinner
stop_spinner() {
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"  # Clear the line
    fi
}

#############################################
# Progress Bar
#############################################

# Draw a progress bar
# Usage: draw_progress_bar <current> <total> [width]
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return  # No progress bar in quiet mode
    fi

    local percent=0
    if [[ $total -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi

    local filled=$((width * current / total))
    if [[ $filled -lt 0 ]]; then filled=0; fi
    if [[ $filled -gt $width ]]; then filled=$width; fi

    # Build the bar
    printf "  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%$((width - filled))s" | tr ' ' '░'
    printf "] %3d%%" $percent
}

# Progress bar with size information
# Usage: draw_download_progress <downloaded_mb> <total_mb> <speed_mbps>
draw_download_progress() {
    local downloaded=$1
    local total=$2
    local speed=${3:-0}

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return
    fi

    local percent=0
    if [[ $total -gt 0 ]]; then
        percent=$((downloaded * 100 / total))
    fi

    # Calculate ETA
    local eta="--"
    if [[ $(echo "$speed > 0" | bc -l) -eq 1 ]]; then
        local remaining=$((total - downloaded))
        local eta_seconds=$(echo "$remaining / $speed" | bc -l)
        eta=$(printf "%.0f" "$eta_seconds")

        # Format ETA
        if [[ $eta -ge 3600 ]]; then
            local hours=$((eta / 3600))
            local mins=$(((eta % 3600) / 60))
            eta="${hours}h ${mins}m"
        elif [[ $eta -ge 60 ]]; then
            local mins=$((eta / 60))
            local secs=$((eta % 60))
            eta="${mins}m ${secs}s"
        else
            eta="${eta}s"
        fi
    fi

    draw_progress_bar "$downloaded" "$total" 40
    printf "  %.1fMB/%.1fMB  %.1fMB/s  ETA: %s\n" "$downloaded" "$total" "$speed" "$eta"
}

#############################################
# Box Drawing
#############################################

# Draw a box with content
# Usage: draw_box "title" "content"
draw_box() {
    local title="$1"
    local content="$2"
    local width=60

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return
    fi

    # Top border with title
    echo "╔═══════════════════════════════════════════════════════════╗"
    printf "║ %-57s ║\n" "$title"
    echo "╠═══════════════════════════════════════════════════════════╣"

    # Content (word wrap and pad)
    while IFS= read -r line; do
        printf "║ %-57s ║\n" "$line"
    done <<< "$content"

    # Bottom border
    echo "╚═══════════════════════════════════════════════════════════╝"
}

# Draw error box with actions
# Usage: draw_error_box "Error title" "Error description" "action1|action2|action3"
draw_error_box() {
    local title="$1"
    local description="$2"
    local actions="$3"

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    printf "║ ❌ %-55s ║\n" "$title"
    echo "╠═══════════════════════════════════════════════════════════╣"
    echo "║                                                           ║"

    # Description
    while IFS= read -r line; do
        printf "║ %-57s ║\n" "$line"
    done <<< "$description"

    echo "║                                                           ║"
    echo "╠═══════════════════════════════════════════════════════════╣"

    # Actions
    local i=1
    IFS='|' read -ra ACTION_ARRAY <<< "$actions"
    for action in "${ACTION_ARRAY[@]}"; do
        printf "║ [%d] %-54s ║\n" "$i" "$action"
        ((i++))
    done

    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

# Draw info box
# Usage: draw_info_box "Title" "line1" "line2" ...
draw_info_box() {
    local title="$1"
    shift

    echo ""
    echo "┌───────────────────────────────────────────────────────────┐"
    printf "│ %-57s │\n" "$title"
    echo "├───────────────────────────────────────────────────────────┤"

    for line in "$@"; do
        printf "│ %-57s │\n" "$line"
    done

    echo "└───────────────────────────────────────────────────────────┘"
    echo ""
}

#############################################
# Tree Display
#############################################

# Print tree node
# Usage: tree_node <depth> <is_last> <icon> <text>
tree_node() {
    local depth=$1
    local is_last=$2
    local icon="$3"
    local text="$4"

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return
    fi

    # Build prefix
    local prefix=""
    for ((i=0; i<depth; i++)); do
        prefix+="  "
    done

    # Add branch
    if [[ $is_last -eq 1 ]]; then
        prefix+="└─"
    else
        prefix+="├─"
    fi

    echo "${prefix} ${icon} ${text}"
}

# Start tree branch
tree_branch() {
    local depth=$1
    local text="$2"

    if [[ $VERBOSITY_LEVEL -eq 0 ]]; then
        return
    fi

    local prefix=""
    for ((i=0; i<depth; i++)); do
        prefix+="  "
    done

    echo "${prefix}${text}"
}

#############################################
# Interactive Menu
#############################################

# Show interactive menu with arrow key navigation
# Usage: result=$(show_menu "Title" "option1|option2|option3")
show_menu() {
    local title="$1"
    local options_str="$2"

    # Parse options
    IFS='|' read -ra OPTIONS <<< "$options_str"
    local num_options=${#OPTIONS[@]}
    local selected=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while true; do
        # Clear and redraw
        clear
        echo ""
        echo -e "${BOLD}${BLUE}$title${NC}"
        echo ""

        # Draw options
        for i in "${!OPTIONS[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e " ${GREEN}→ ${OPTIONS[$i]}${NC}"
            else
            echo "   ${OPTIONS[$i]}"
            fi
        done

        echo ""
        echo -e "${GRAY}Use ↑↓ arrows to move, Enter to select${NC}"

        # Read key
        read -rsn1 key

        # Handle arrow keys (escape sequences)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 key
            case "$key" in
                '[A') # Up arrow
                    ((selected--))
                    if [[ $selected -lt 0 ]]; then
                        selected=$((num_options - 1))
                    fi
                    ;;
                '[B') # Down arrow
                    ((selected++))
                    if [[ $selected -ge $num_options ]]; then
                        selected=0
                    fi
                    ;;
            esac
        elif [[ "$key" == "" ]]; then
            # Enter key
            break
        fi
    done

    # Show cursor
    tput cnorm 2>/dev/null || true

    echo "$selected"
}

#############################################
# Configuration Preview
#############################################

# Show configuration preview table
# Usage: show_config_preview
show_config_preview() {
    local chip="$1"
    local ram="$2"
    local cores="$3"
    local gemma_model="$4"
    local gemma_size="$5"
    local codegemma_model="${6:-}"
    local codegemma_size="${7:-}"
    local ide_tools="$8"

    # Check which models are already downloaded
    local gemma_exists=false
    local codegemma_exists=false
    if command -v ollama >/dev/null 2>&1; then
        if ollama list 2>/dev/null | grep -q "^${gemma_model}"; then
            gemma_exists=true
        fi
        if [[ -n "$codegemma_model" ]] && ollama list 2>/dev/null | grep -q "^${codegemma_model}"; then
            codegemma_exists=true
        fi
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                  Configuration Preview                    ║"
    echo "╠═══════════════════════════════════════════════════════════╣"
    echo "║                                                           ║"
    printf "║  Hardware: %s | %sGB RAM | %s cores%23s║\n" "$chip" "$ram" "$cores" ""
    echo "║                                                           ║"

    # Determine header based on what needs downloading
    if $gemma_exists && { [[ -z "$codegemma_model" ]] || $codegemma_exists; }; then
        echo "║  Models (Already Downloaded):                             ║"
    elif ! $gemma_exists && { [[ -z "$codegemma_model" ]] || ! $codegemma_exists; }; then
        echo "║  Will Download:                                           ║"
    else
        echo "║  Models:                                                  ║"
    fi

    # Show main model
    if $gemma_exists; then
        printf "║    ✓ %-18s %4sGB  (cached)%18s║\n" "$gemma_model" "$gemma_size" ""
    else
        printf "║    -> %-18s %4sGB  ~%2s min%18s║\n" "$gemma_model" "$gemma_size" "$(estimate_download_time "$gemma_size")" ""
    fi

    # Show FIM model if requested
    if [[ -n "$codegemma_model" ]]; then
        if $codegemma_exists; then
            printf "║    ✓ %-18s %4sGB  (cached)%18s║\n" "$codegemma_model" "$codegemma_size" ""
        else
            printf "║    -> %-18s %4sGB  ~%2s min%18s║\n" "$codegemma_model" "$codegemma_size" "$(estimate_download_time "$codegemma_size")" ""
        fi

        # Show totals only if at least one model needs downloading
        if ! $gemma_exists || ! $codegemma_exists; then
            local download_size=0
            local download_time=0
            if ! $gemma_exists; then
                download_size=$(echo "$download_size + $gemma_size" | bc)
                download_time=$(echo "$download_time + $(estimate_download_time "$gemma_size")" | bc)
            fi
            if ! $codegemma_exists; then
                download_size=$(echo "$download_size + $codegemma_size" | bc)
                download_time=$(echo "$download_time + $(estimate_download_time "$codegemma_size")" | bc)
            fi
            echo "║                         -------  --------                 ║"
            printf "║                          %4sGB  ~%-2.0f min%17s ║\n" "$download_size" "$download_time" ""
        fi
    fi

    echo "║                                                           ║"
    echo "║  Will Configure:                                          ║"
    printf "║    * IDE Tools: %-41s ║\n" "$ide_tools"
    echo "║    * Local Ollama provider                                ║"
    echo "║    * LaunchAgent for auto-start                           ║"
    echo "║                                                           ║"
    echo "╠═══════════════════════════════════════════════════════════╣"
    echo "║  [C]ontinue  [E]dit Configuration  [Q]uit                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

# Estimate download time based on size (assumes 10MB/s average)
estimate_download_time() {
    local size_gb=$1
    local speed_mbps=10
    local time_minutes=$(echo "$size_gb * 1024 / $speed_mbps / 60" | bc -l)
    printf "%.0f" "$time_minutes"
}

#############################################
# Final Summary Menu
#############################################

# Show interactive final summary with actions
# Usage: show_final_menu
show_final_menu() {
    local custom_model="$1"
    local ide_tools="$2"

    while true; do
        echo ""
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║            ✨ Setup Complete! ✨                          ║"
        echo "╠═══════════════════════════════════════════════════════════╣"
        echo "║  Quick Actions:                                           ║"
        echo "║                                                           ║"

        if [[ "$ide_tools" == *"OpenCode"* ]]; then
            echo "║    [1] 🚀 Launch OpenCode                                 ║"
        fi

        echo "║    [2] 🧪 Test Gemma4 model                               ║"

        if [[ "$ide_tools" == *"JetBrains"* ]]; then
            echo "║    [3] 📋 View JetBrains setup guide                      ║"
        fi

        echo "║    [4] 📊 Check system resources                          ║"
        echo "║    [5] 📝 View configuration files                        ║"
        echo "║    [H] 📚 View help & documentation                       ║"
        echo "║    [Q] Quit                                               ║"
        echo "║                                                           ║"
        echo "╠═══════════════════════════════════════════════════════════╣"
        echo "║  Tip: Run './setup-ai-opencode.sh -v' for verbose        ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""

        read -p "Select action: " -n 1 -r choice
        echo ""

        case "$choice" in
            1)
                if [[ "$ide_tools" == *"OpenCode"* ]]; then
                    echo "Launching OpenCode..."
                    opencode &
                fi
                ;;
            2)
                echo "Testing model..."
                ollama run "$custom_model" "Write a hello world function in Python"
                read -p "Press Enter to continue..."
                ;;
            3)
                if [[ "$ide_tools" == *"JetBrains"* ]]; then
                    if [[ -f "$HOME/.config/gemma4-setup/jetbrains-config-reference.txt" ]]; then
                        cat "$HOME/.config/gemma4-setup/jetbrains-config-reference.txt" | less
                    fi
                fi
                ;;
            4)
                echo ""
                show_system_resources
                read -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                echo "Configuration files:"
                echo "  OpenCode: $HOME/.config/opencode/opencode.json"
                echo "  LaunchAgent: $HOME/Library/LaunchAgents/com.ollama.custom.plist"
                echo "  Ollama models: ~/.ollama/models"
                read -p "Press Enter to continue..."
                ;;
            [Hh])
                ./setup-ai-opencode.sh --help | less
                ;;
            [Qq])
                echo "Goodbye!"
                break
                ;;
            *)
                echo "Invalid choice. Please try again."
                sleep 1
                ;;
        esac
    done
}

#############################################
# System Resource Monitor
#############################################

# Show current system resources
show_system_resources() {
    echo "┌─ System Resources ─────────────────────────────────────┐"

    # CPU
    local cpu_usage=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
    local cpu_cores=$(sysctl -n hw.ncpu)
    local cpu_percent=$(echo "$cpu_usage / $cpu_cores" | bc)
    draw_resource_bar "CPU" "$cpu_percent" "($cpu_usage% / ${cpu_cores} cores)"

    # RAM
    local ram_total=$(sysctl -n hw.memsize)
    local ram_total_gb=$((ram_total / 1024 / 1024 / 1024))
    local ram_used=$(vm_stat | awk '/Pages active/ {print $3}' | tr -d '.')
    local ram_used_gb=$((ram_used * 4096 / 1024 / 1024 / 1024))
    local ram_percent=$((ram_used_gb * 100 / ram_total_gb))
    draw_resource_bar "RAM" "$ram_percent" "(${ram_used_gb}GB / ${ram_total_gb}GB)"

    # Disk
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    local disk_avail=$(echo "$disk_info" | awk '{print $4}')
    draw_resource_bar "Disk" "$disk_used" "($disk_avail free)"

    echo "└────────────────────────────────────────────────────────┘"
}

# Draw resource bar
draw_resource_bar() {
    local label="$1"
    local percent="$2"
    local info="$3"

    local width=20
    local filled=$((width * percent / 100))

    printf "│ %-5s " "$label"
    printf "%${filled}s" | tr ' ' '█'
    printf "%$((width - filled))s" | tr ' ' '░'
    printf " %3d%%  %-20s │\n" "$percent" "$info"
}
