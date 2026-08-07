#!/bin/bash
# Festival Pager — Service wrapper: starts notifier loop + web UI
# Pi 1 B+ base station
#
# Run by systemd via festival-pager.service.
# Starts the schedule notifier (background) and Flask web UI (foreground).
# When the web UI exits, the notifier is killed and the service restarts.

set -euo pipefail

PAGER_DIR="/home/pi/festival-pager"
VENV_DIR="$PAGER_DIR/venv"

# Activate virtualenv
source "$VENV_DIR/bin/activate"

cd "$PAGER_DIR"

# Start the notifier in background
echo "Starting notifier..."
python3 notifier.py --config config.json &
NOTIFIER_PID=$!

# Ensure notifier dies on exit
cleanup() {
    echo "Shutting down notifier (PID $NOTIFIER_PID)..."
    kill "$NOTIFIER_PID" 2>/dev/null || true
    wait "$NOTIFIER_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Start the web UI (foreground — systemd keeps us alive)
echo "Starting web UI..."
python3 webui.py 2>&1

# If we get here, web UI exited (shouldn't happen in normal operation)
echo "Web UI exited unexpectedly — service will restart"