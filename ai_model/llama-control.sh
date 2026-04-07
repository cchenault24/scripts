#!/bin/bash
#
# Ollama Server Control Script
# Manages the Ollama server with proper settings
#

set -euo pipefail

OLLAMA_BUILD_DIR="/tmp/ollama-build"
PORT="3456"
LOG_FILE="$HOME/.local/var/log/ollama-server.log"
PID_FILE="$HOME/.local/var/ollama-server.pid"

case "${1:-}" in
    start)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if ps -p "$PID" > /dev/null 2>&1; then
                echo "Ollama server already running (PID: $PID)"
                exit 0
            fi
        fi

        echo "Starting Ollama server on port $PORT..."
        echo "Keep-alive: enabled (models stay in memory)"
        mkdir -p "$(dirname "$LOG_FILE")"
        OLLAMA_HOST=127.0.0.1:$PORT OLLAMA_KEEP_ALIVE=-1 nohup "$OLLAMA_BUILD_DIR/ollama" serve > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo "Server started (PID: $(cat "$PID_FILE"))"
        ;;

    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            echo "Stopping Ollama server (PID: $PID)..."
            kill "$PID" 2>/dev/null || echo "Process not found"
            rm -f "$PID_FILE"
            echo "Server stopped"
        else
            echo "No PID file found"
        fi
        ;;

    restart)
        $0 stop
        sleep 2
        $0 start
        ;;

    status)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if ps -p "$PID" > /dev/null 2>&1; then
                echo "Ollama server is running (PID: $PID)"
                echo "Port: $PORT"
                echo "Log: $LOG_FILE"
                echo ""
                echo "Installed models:"
                MODELS=$(curl -s http://127.0.0.1:$PORT/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null)
                if [ -n "$MODELS" ]; then
                    echo "$MODELS" | while IFS= read -r model; do
                        echo "  • $model"
                    done
                else
                    echo "  (none)"
                fi
            else
                echo "Ollama server is not running (stale PID file)"
            fi
        else
            echo "Ollama server is not running"
        fi
        ;;

    logs)
        tail -f "$LOG_FILE"
        ;;

    models)
        if curl -s http://127.0.0.1:$PORT/api/tags >/dev/null 2>&1; then
            echo "Installed models:"
            MODELS=$(curl -s http://127.0.0.1:$PORT/api/tags | jq -r '.models[] | "\(.name) (\(.size / 1024 / 1024 / 1024 | floor)GB)"' 2>/dev/null)
            if [ -n "$MODELS" ]; then
                echo "$MODELS" | while IFS= read -r model; do
                    echo "  • $model"
                done
            else
                echo "  (none installed)"
            fi
        else
            echo "Error: Ollama server not running on port $PORT"
            echo "Start with: $0 start"
            exit 1
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|logs|models}"
        exit 1
        ;;
esac
