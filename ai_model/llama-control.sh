#!/bin/bash
# llama-control.sh - Comprehensive Ollama server management
# Provides start, stop, restart, status, logs, models, health, and metrics commands

set -euo pipefail

# Get script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Additional Constants
#############################################
SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

#############################################
# Health Check Function
#############################################
health_check() {
    local exit_code=0

    echo -e "${BLUE}Health Check${NC}"
    echo "----------------------------------------"

    # Check if server process is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]]; then
        echo -e "${RED}✗ Server not running (no PID file)${NC}"
        return 1
    fi

    local pid
    pid=$(cat "$OLLAMA_PID_FILE")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${RED}✗ Server process not found (PID: $pid)${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Server process running (PID: $pid)${NC}"

    # Check if server is responding
    if ! curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
        echo -e "${RED}✗ Server not responding to API requests${NC}"
        exit_code=1
    else
        echo -e "${GREEN}✓ Server responding to API requests${NC}"

        # Check loaded models
        local models
        models=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | wc -l)
        echo -e "${GREEN}✓ Models installed: $models${NC}"
    fi

    # Check VRAM/Memory usage
    local mem_usage
    mem_usage=$(ps -p "$pid" -o rss= | awk '{printf "%.1f GB", $1/1024/1024}')
    echo -e "${GREEN}✓ Memory usage: $mem_usage${NC}"

    # Test simple prompt response time
    echo -n "Testing response time... "
    local start_time end_time duration
    start_time=$(date +%s%N)

    if curl -sf -X POST "http://127.0.0.1:$OLLAMA_PORT/api/generate" \
        -H "Content-Type: application/json" \
        -d '{"model":"qwen2.5-coder:7b","prompt":"test","stream":false}' \
        >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 ))
        echo -e "${GREEN}${duration}ms${NC}"
    else
        echo -e "${YELLOW}(no model loaded)${NC}"
    fi

    echo "----------------------------------------"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ Overall health: Healthy${NC}"
    else
        echo -e "${RED}✗ Overall health: Unhealthy${NC}"
    fi

    return $exit_code
}

#############################################
# Metrics Function
#############################################
show_metrics() {
    local json_output=false
    [[ "${1:-}" == "--json" ]] && json_output=true

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]]; then
        if $json_output; then
            echo '{"error":"Server not running","status":"stopped"}'
        else
            print_error "Server is not running"
        fi
        return 1
    fi

    local pid
    pid=$(cat "$OLLAMA_PID_FILE")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        if $json_output; then
            echo '{"error":"Process not found","status":"stopped","pid":"'$pid'"}'
        else
            print_error "Server process not found (PID: $pid)"
        fi
        return 1
    fi

    # Collect metrics
    local mem_mb mem_gb cpu_percent
    mem_mb=$(ps -p "$pid" -o rss= | awk '{print int($1/1024)}')
    mem_gb=$(echo "$mem_mb" | awk '{printf "%.2f", $1/1024}')
    cpu_percent=$(ps -p "$pid" -o %cpu= | awk '{printf "%.1f", $1}')

    # Get active models
    local model_count=0
    local active_models=""
    if curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
        model_count=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | wc -l | tr -d ' ')
        active_models=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | tr '\n' ',' | sed 's/,$//')
    fi

    # Test tokens/sec with a small prompt (if model loaded)
    local tokens_per_sec="N/A"
    if [[ $model_count -gt 0 ]]; then
        local test_model
        test_model=$(echo "$active_models" | cut -d',' -f1)

        # Small test prompt
        local start_time end_time
        start_time=$(date +%s%N)
        local response
        response=$(curl -sf -X POST "http://127.0.0.1:$OLLAMA_PORT/api/generate" \
            -H "Content-Type: application/json" \
            -d '{"model":"'$test_model'","prompt":"Hi","stream":false}' 2>/dev/null || echo "")

        if [[ -n "$response" ]]; then
            end_time=$(date +%s%N)
            local duration_ms=$(( (end_time - start_time) / 1000000 ))
            local total_tokens=$(echo "$response" | grep -o '"eval_count":[0-9]*' | cut -d':' -f2 || echo "0")

            if [[ $total_tokens -gt 0 && $duration_ms -gt 0 ]]; then
                tokens_per_sec=$(echo "$total_tokens $duration_ms" | awk '{printf "%.1f", ($1 / $2) * 1000}')
            fi
        fi
    fi

    # Get GPU utilization (macOS specific)
    local gpu_util="N/A"
    if command -v powermetrics >/dev/null 2>&1; then
        # Note: powermetrics requires sudo, so we'll skip actual GPU metrics
        # In production, you might want to use ioreg or other tools
        gpu_util="Available via powermetrics (requires sudo)"
    fi

    # Get uptime
    local start_time_unix uptime_seconds uptime_formatted
    start_time_unix=$(ps -p "$pid" -o lstart= | xargs -I{} date -j -f "%a %b %d %T %Y" "{}" "+%s" 2>/dev/null || echo "0")
    if [[ $start_time_unix -gt 0 ]]; then
        local current_time
        current_time=$(date +%s)
        uptime_seconds=$((current_time - start_time_unix))

        local days hours minutes
        days=$((uptime_seconds / 86400))
        hours=$(( (uptime_seconds % 86400) / 3600 ))
        minutes=$(( (uptime_seconds % 3600) / 60 ))

        if [[ $days -gt 0 ]]; then
            uptime_formatted="${days}d ${hours}h ${minutes}m"
        elif [[ $hours -gt 0 ]]; then
            uptime_formatted="${hours}h ${minutes}m"
        else
            uptime_formatted="${minutes}m"
        fi
    else
        uptime_formatted="unknown"
    fi

    # Output results
    if $json_output; then
        cat <<EOF
{
  "status": "running",
  "pid": $pid,
  "uptime": "$uptime_formatted",
  "memory_mb": $mem_mb,
  "memory_gb": $mem_gb,
  "cpu_percent": $cpu_percent,
  "models_installed": $model_count,
  "active_models": "$active_models",
  "tokens_per_sec": "$tokens_per_sec",
  "gpu_utilization": "$gpu_util",
  "port": "$OLLAMA_PORT",
  "host": "$OLLAMA_HOST"
}
EOF
    else
        echo -e "${BLUE}Ollama Server Metrics${NC}"
        echo "========================================"
        echo -e "${GREEN}Status:${NC}           Running"
        echo -e "${GREEN}PID:${NC}              $pid"
        echo -e "${GREEN}Uptime:${NC}           $uptime_formatted"
        echo "----------------------------------------"
        echo -e "${GREEN}Memory Usage:${NC}     ${mem_gb} GB (${mem_mb} MB)"
        echo -e "${GREEN}CPU Usage:${NC}        ${cpu_percent}%"
        echo -e "${GREEN}Models:${NC}           $model_count installed"
        if [[ -n "$active_models" ]]; then
            echo -e "${GREEN}Active Models:${NC}    $active_models"
        fi
        echo -e "${GREEN}Tokens/sec:${NC}       $tokens_per_sec"
        echo "----------------------------------------"
        echo -e "${GREEN}GPU Util:${NC}         $gpu_util"
        echo -e "${GREEN}Port:${NC}             $OLLAMA_PORT"
        echo -e "${GREEN}Host:${NC}             $OLLAMA_HOST"
        echo "========================================"
    fi
}

#############################################
# Enhanced Status Function
#############################################
show_status() {
    print_header "Ollama Server Status"

    # Check Ollama installation
    if command -v ollama &> /dev/null; then
        local version
        version=$(ollama --version 2>&1 | head -1)
        print_status "Ollama installed: $version"
        print_info "Location: $(which ollama)"
    else
        print_warning "Ollama not installed"
    fi

    # Check server process
    if [[ -f "$OLLAMA_PID_FILE" ]]; then
        local pid
        pid=$(cat "$OLLAMA_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "Server: Running (PID: $pid)"

            # Show memory usage
            local mem_usage
            mem_usage=$(ps -p "$pid" -o rss= | awk '{printf "%.1f GB", $1/1024/1024}')
            print_info "Memory usage: $mem_usage"

            # Show CPU usage
            local cpu_usage
            cpu_usage=$(ps -p "$pid" -o %cpu= | awk '{printf "%.1f%%", $1}')
            print_info "CPU usage: $cpu_usage"

            # Try to get loaded models
            if curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/tags" > /dev/null 2>&1; then
                print_status "Health check: Responding at http://127.0.0.1:$OLLAMA_PORT"

                echo -e "\n${BLUE}Loaded Models:${NC}"
                curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" | \
                    grep -o '"name":"[^"]*"' | \
                    cut -d'"' -f4 | \
                    sed 's/^/  - /' || echo "  (none)"
            else
                print_warning "Health check: Process running but not responding"
            fi
        else
            print_warning "Server: Not running (stale PID file)"
            rm -f "$OLLAMA_PID_FILE"
        fi
    else
        print_warning "Server: Not running"
    fi

    # Check log file
    if [[ -f "$OLLAMA_LOG_FILE" ]]; then
        local log_size
        log_size=$(du -h "$OLLAMA_LOG_FILE" | cut -f1)
        print_info "Log file: $OLLAMA_LOG_FILE ($log_size)"
    fi
}

#############################################
# Logs Function
#############################################
show_logs() {
    local lines="${1:-50}"

    if [[ ! -f "$OLLAMA_LOG_FILE" ]]; then
        print_error "Log file not found: $OLLAMA_LOG_FILE"
        return 1
    fi

    if [[ "$lines" == "follow" ]] || [[ "$lines" == "-f" ]]; then
        print_info "Following logs (Ctrl+C to stop)..."
        tail -f "$OLLAMA_LOG_FILE"
    else
        print_info "Last $lines lines of logs:"
        tail -n "$lines" "$OLLAMA_LOG_FILE"
    fi
}

#############################################
# Models Function
#############################################
list_installed_models() {
    print_header "Installed Models"

    # Check if server is running
    if [[ ! -f "$OLLAMA_PID_FILE" ]] || ! ps -p "$(cat "$OLLAMA_PID_FILE")" > /dev/null 2>&1; then
        print_error "Ollama server is not running"
        print_info "Start the server first with: $SCRIPT_NAME start"
        return 1
    fi

    # Check if Ollama is installed
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama is not installed"
        return 1
    fi

    ollama list
}

#############################################
# Restart Function
#############################################
restart_server() {
    print_header "Restarting Ollama Server"

    # Stop if running
    if [[ -f "$OLLAMA_PID_FILE" ]]; then
        print_info "Stopping server..."
        stop_ollama_server
        sleep 2
    fi

    # Start server
    print_info "Starting server..."
    start_ollama_server
}

#############################################
# Help Function
#############################################
show_help() {
    cat <<EOF
${BLUE}llama-control.sh${NC} - Comprehensive Ollama Server Management
Version: $VERSION

${BLUE}USAGE:${NC}
    $SCRIPT_NAME <command> [options]

${BLUE}COMMANDS:${NC}
    ${GREEN}start${NC}               Start the Ollama server
    ${GREEN}stop${NC}                Stop the Ollama server
    ${GREEN}restart${NC}             Restart the Ollama server
    ${GREEN}status${NC}              Show detailed server status
    ${GREEN}logs${NC} [lines|follow] Show server logs (default: 50 lines)
                          Use 'follow' or '-f' to tail logs
    ${GREEN}models${NC}              List all installed models
    ${GREEN}health${NC}              Perform health check (returns exit code)
    ${GREEN}metrics${NC} [--json]    Show performance metrics
                          Use --json for JSON output
    ${GREEN}help${NC}                Show this help message

${BLUE}EXAMPLES:${NC}
    $SCRIPT_NAME start              # Start the server
    $SCRIPT_NAME status             # Check server status
    $SCRIPT_NAME logs follow        # Follow logs in real-time
    $SCRIPT_NAME health             # Check if server is healthy
    $SCRIPT_NAME metrics            # Show performance metrics
    $SCRIPT_NAME metrics --json     # Show metrics in JSON format
    $SCRIPT_NAME stop               # Stop the server

${BLUE}CONFIGURATION:${NC}
    Port:               $OLLAMA_PORT
    Host:               $OLLAMA_HOST
    PID file:           $OLLAMA_PID_FILE
    Log file:           $OLLAMA_LOG_FILE

${BLUE}HEALTH CHECK:${NC}
    The health command returns exit code 0 if healthy, 1 if unhealthy.
    Useful for monitoring and automation scripts.

${BLUE}METRICS:${NC}
    Shows real-time performance data including:
    - Memory and CPU usage
    - Active models
    - Tokens per second (estimated)
    - Server uptime

    Use --json flag for machine-readable output.
EOF
}

#############################################
# Main Command Router
#############################################
main() {
    local command="${1:-}"

    case "$command" in
        start)
            start_ollama_server
            ;;
        stop)
            stop_ollama_server
            ;;
        restart)
            restart_server
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-50}"
            ;;
        models)
            list_installed_models
            ;;
        health)
            health_check
            ;;
        metrics)
            show_metrics "${2:-}"
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
