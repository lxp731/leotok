#!/bin/bash
#
# DroidDL Backend Server Control Script
# Usage: start_server.sh {start|stop|restart|status}

set -e

BACKEND_DIR=""
PID_FILE="$HOME/server.pid"
LOG_FILE="$HOME/server.log"

# ---- Helpers ----

get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE" 2>/dev/null
    fi
}

is_running() {
    local pid
    pid=$(get_pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ---- Commands ----

do_status() {
    if is_running; then
        local pid
        pid=$(get_pid)
        local port
        port=$(ss -tlnp 2>/dev/null | grep -E ":8000\s" | head -1 | sed -E 's/.*:([0-9]+).*/\1/' || echo "?")
        echo "✅ Server is running (PID: $pid, Port: $port)"
    else
        echo "⭕ Server is not running"
        # Clean up stale PID file
        rm -f "$PID_FILE"
    fi
}

do_stop() {
    if is_running; then
        local pid
        pid=$(get_pid)
        echo -n "Stopping server (PID: $pid)... "
        kill "$pid" 2>/dev/null || true
        # Wait up to 5 seconds for graceful shutdown, then force kill
        for i in $(seq 1 10); do
            if ! kill -0 "$pid" 2>/dev/null; then
                echo "stopped"
                rm -f "$PID_FILE"
                return 0
            fi
            sleep 0.5
        done
        # Force kill
        kill -9 "$pid" 2>/dev/null || true
        sleep 0.5
        rm -f "$PID_FILE"
        echo "force-killed"
    else
        echo "⭕ Server is not running"
        rm -f "$PID_FILE"
    fi
}

do_start() {
    if [ -z "$BACKEND_DIR" ]; then
        echo "❌ BACKEND_DIR is not configured."
        echo "   Run setup.sh first, or edit this script to set BACKEND_DIR."
        return 1
    fi

    if is_running; then
        echo "⚠️  Server is already running (PID: $(get_pid))"
        return 1
    fi

    cd "$BACKEND_DIR"

    # Ensure storage is accessible
    if [ ! -d "/data/data/com.termux/files/home/storage/downloads" ]; then
        echo "⚠️  Storage not set up. Run: termux-setup-storage"
    fi

    export VD_OUTPUT_DIR="/data/data/com.termux/files/home/storage/downloads"

    # Start server in background
    source .venv/bin/activate
    nohup python3 server.py >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"

    # Wait a moment and verify it actually started
    sleep 1.5
    if kill -0 "$pid" 2>/dev/null; then
        echo "✅ Server started (PID: $pid)"
    else
        echo "❌ Server failed to start — check $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

do_restart() {
    echo "=== Restarting server ==="
    do_stop
    sleep 1
    do_start
}

# ---- Main ----

case "${1:-start}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
