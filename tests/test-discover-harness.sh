#!/bin/bash

# test-discover-harness.sh

# CI-friendly harness for testing discover-interfaces.sh

set -euo pipefail

# ––––––––––––––

# Environment Setup

# ––––––––––––––

export TEST_MODE=true
export FORCE=true
export MANAGEMENT_INTERFACE=”${MANAGEMENT_INTERFACE:-eth0}”
export DEBIAN_FRONTEND=noninteractive

# Directory variables - handle both local and VM execution contexts

if [[ -d “$(pwd)/scripts” ]]; then
SCRIPT_DIR=”$(pwd)/scripts”
elif [[ -d “/tmp/scripts” ]]; then
SCRIPT_DIR=”/tmp/scripts”
else
# Try to find it relative to the test script location
SCRIPT_DIR=”$(cd “$(dirname “${BASH_SOURCE[0]}”)/../scripts” && pwd)”
fi

# Ensure log directory exists and is writable

if [[ -w “$(pwd)” ]]; then
LOG_DIR=”$(pwd)/logs”
elif [[ -w “/tmp” ]]; then
LOG_DIR=”/tmp/logs”
else
LOG_DIR=”/var/tmp/logs”
fi

mkdir -p “$LOG_DIR”
chmod 755 “$LOG_DIR”

LOG_FILE=”$LOG_DIR/discover-interfaces-$(date +%Y%m%d-%H%M%S).log”

# ––––––––––––––

# Pre-flight Checks

# ––––––––––––––

echo “=== Pre-flight Checks ===”
echo “Script directory: $SCRIPT_DIR”
echo “Log directory: $LOG_DIR”
echo “Management interface: $MANAGEMENT_INTERFACE”
echo “Test mode: $TEST_MODE”

# Check if the discover script exists

DISCOVER_SCRIPT=”$SCRIPT_DIR/discover-interfaces.sh”
if [[ ! -f “$DISCOVER_SCRIPT” ]]; then
echo “❌ ERROR: discover-interfaces.sh not found at $DISCOVER_SCRIPT”
echo “Available files in $SCRIPT_DIR:”
ls -la “$SCRIPT_DIR” 2>/dev/null || echo “Directory not accessible”
exit 1
fi

# Check if script is executable

if [[ ! -x “$DISCOVER_SCRIPT” ]]; then
echo “⚠️  Making discover-interfaces.sh executable…”
chmod +x “$DISCOVER_SCRIPT”
fi

# Check sudo access

if ! sudo -n true 2>/dev/null; then
echo “⚠️  This script requires sudo access. Testing sudo…”
sudo echo “✅ Sudo access confirmed”
fi

# Display system information

echo -e “\n=== System Information ===”
echo “OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d’”’ -f2 || uname -s)”
echo “Kernel: $(uname -r)”
echo “Available network interfaces:”
ip link show | grep -E ‘^[0-9]+:’ | cut -d: -f2 | sed ‘s/^ */  /’

# Check if management interface exists

if ! ip link show “$MANAGEMENT_INTERFACE” &>/dev/null; then
echo “⚠️  Warning: Management interface ‘$MANAGEMENT_INTERFACE’ not found”
echo “Available interfaces:”
ip link show | grep -E ‘^[0-9]+:’ | cut -d: -f2 | sed ‘s/^ */  /’
fi

# ––––––––––––––

# Run the Discovery Script

# ––––––––––––––

echo -e “\n=== Running Discovery Script ===”
echo “Starting discover-interfaces.sh test…”
echo “Logging output to $LOG_FILE”
echo “Command: sudo bash $DISCOVER_SCRIPT”

# Create a more detailed log with both stdout and stderr

exec 3>&1 4>&2
exec 1> >(tee -a “$LOG_FILE”)
exec 2> >(tee -a “$LOG_FILE” >&2)

echo “=== Test started at $(date) ===” >> “$LOG_FILE”
echo “Environment variables:” >> “$LOG_FILE”
env | grep -E ‘^(TEST_MODE|FORCE|MANAGEMENT_INTERFACE|DEBIAN_FRONTEND)=’ >> “$LOG_FILE” || true

set +e
START_TIME=$(date +%s)
sudo -E bash “$DISCOVER_SCRIPT”
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
set -e

echo “=== Test completed at $(date) (duration: ${DURATION}s) ===” >> “$LOG_FILE”

# Restore stdout/stderr

exec 1>&3 2>&4
exec 3>&- 4>&-

# ––––––––––––––

# Analyze Results

# ––––––––––––––

echo -e “\n=== Test Results Analysis ===”
if [[ $EXIT_CODE -eq 0 ]]; then
echo “✅ discover-interfaces.sh completed successfully in ${DURATION}s”
else
echo “❌ discover-interfaces.sh failed with exit code $EXIT_CODE after ${DURATION}s”
fi

echo “Log file: $LOG_FILE”
echo “Log file size: $(du -h “$LOG_FILE” 2>/dev/null | cut -f1 || echo ‘unknown’)”

# ––––––––––––––

# Verify Configuration Output

# ––––––––––––––

echo -e “\n=== Configuration Verification ===”
CONFIG_FILES=(
“/etc/ovs/interface-config.conf”
“/etc/systemd/system/ovs-setup.service”
“/usr/local/bin/ovs-setup.sh”
)

FOUND_CONFIG=false
for config_file in “${CONFIG_FILES[@]}”; do
if [[ -f “$config_file” ]]; then
echo “✅ Found configuration: $config_file”
echo “  File size: $(du -h “$config_file” | cut -f1)”
echo “  Last modified: $(stat -c ‘%y’ “$config_file”)”

```
    # Show relevant content based on file type
    case "$config_file" in
        *.conf)
            echo "  Content preview:"
            grep -E '^(SWITCH_INTERFACES|MANAGEMENT_INTERFACE|BRIDGE_NAME)=' "$config_file" 2>/dev/null | sed 's/^/    /' || true
            ;;
        *.service)
            echo "  Service status:"
            systemctl is-enabled "$(basename "$config_file")" 2>/dev/null | sed 's/^/    /' || echo "    not installed"
            ;;
    esac
    FOUND_CONFIG=true
else
    echo "❌ Missing configuration: $config_file"
fi
```

done

if [[ “$FOUND_CONFIG” == “false” ]]; then
echo “⚠️  No expected configuration files found. Discovery may have failed.”
fi

# ––––––––––––––

# Log Analysis

# ––––––––––––––

echo -e “\n=== Log Analysis ===”
if [[ -f “$LOG_FILE” ]]; then
ERROR_COUNT=$(grep -c -i “error” “$LOG_FILE” 2>/dev/null || echo “0”)
WARNING_COUNT=$(grep -c -i “warning” “$LOG_FILE” 2>/dev/null || echo “0”)

```
echo "Errors found: $ERROR_COUNT"
echo "Warnings found: $WARNING_COUNT"

if [[ $ERROR_COUNT -gt 0 ]]; then
    echo "Recent errors:"
    grep -i "error" "$LOG_FILE" | tail -5 | sed 's/^/  /'
fi

if [[ $WARNING_COUNT -gt 0 ]]; then
    echo "Recent warnings:"
    grep -i "warning" "$LOG_FILE" | tail -3 | sed 's/^/  /'
fi
```

fi

# ––––––––––––––

# Cleanup and Exit

# ––––––––––––––

echo -e “\n=== Test Summary ===”
echo “Test completed with exit code: $EXIT_CODE”
echo “Duration: ${DURATION} seconds”
echo “Log file: $LOG_FILE”

if [[ $EXIT_CODE -ne 0 ]]; then
echo “❌ Test FAILED”
echo “For debugging, check the full log: $LOG_FILE”
exit $EXIT_CODE
else
echo “✅ Test PASSED”
fi

# Optional: Copy logs to a standard location for CI collection

if [[ -n “${CI:-}” ]] && [[ -d “/tmp/logs” ]]; then
cp “$LOG_FILE” “/tmp/logs/” 2>/dev/null || true
fi

exit $EXIT_CODE