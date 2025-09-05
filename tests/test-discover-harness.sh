#!/bin/bash
# test-discover-harness.sh
# CI-friendly harness for testing discover-interfaces.sh

set -euo pipefail

# ----------------------------
# Environment Setup
# ----------------------------
export TEST_MODE=true
export FORCE=true
export MANAGEMENT_INTERFACE="${MANAGEMENT_INTERFACE:-eth0}"

# Directory variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
LOG_DIR="$(pwd)/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/discover-interfaces-$(date +%Y%m%d-%H%M%S).log"

# ----------------------------
# Run the Discovery Script
# ----------------------------
echo "Starting discover-interfaces.sh test..."
echo "Logging output to $LOG_FILE"

set +e
sudo bash "$SCRIPT_DIR/discover-interfaces.sh" &> "$LOG_FILE"
EXIT_CODE=$?
set -e

# ----------------------------
# Verify Results
# ----------------------------
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ discover-interfaces.sh completed successfully."
    echo "Log file: $LOG_FILE"
else
    echo "❌ discover-interfaces.sh failed with exit code $EXIT_CODE."
    echo "Check the log for details: $LOG_FILE"
    exit $EXIT_CODE
fi

# ----------------------------
# Optional: Display Summary
# ----------------------------
echo -e "\n=== Detected Interfaces ==="
if [[ -f /etc/ovs/interface-config.conf ]]; then
    grep -E '^SWITCH_INTERFACES=' /etc/ovs/interface-config.conf
else
    echo "No configuration file found. Discovery may have failed."
fi