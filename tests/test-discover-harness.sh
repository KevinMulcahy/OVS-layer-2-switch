#!/bin/bash

# debug-test-harness.sh - Debug version to identify immediate failures

set -euo pipefail

echo “=== DEBUG: Starting test harness debug ===”
echo “Current directory: $(pwd)”
echo “Script location: $0”
echo “Script directory: $(dirname “$0”)”

# ––––––––––––––

# Environment Check

# ––––––––––––––

echo -e “\n=== DEBUG: Environment Variables ===”
echo “TEST_MODE: ${TEST_MODE:-unset}”
echo “FORCE: ${FORCE:-unset}”
echo “MANAGEMENT_INTERFACE: ${MANAGEMENT_INTERFACE:-unset}”
echo “USER: ${USER:-unset}”
echo “HOME: ${HOME:-unset}”
echo “PWD: $(pwd)”

# ––––––––––––––

# Directory Structure Check

# ––––––––––––––

echo -e “\n=== DEBUG: Directory Structure ===”
echo “Contents of current directory:”
ls -la . || echo “Cannot list current directory”

echo -e “\nLooking for scripts directory:”
for dir in “scripts” “./scripts” “../scripts” “/tmp/scripts”; do
if [[ -d “$dir” ]]; then
echo “  ✓ Found: $dir”
echo “    Contents:”
ls -la “$dir” | head -10
else
echo “  ✗ Not found: $dir”
fi
done

# ––––––––––––––

# Script Location Detection

# ––––––––––––––

echo -e “\n=== DEBUG: Script Location Detection ===”
SCRIPT_CANDIDATES=(
“scripts/discover-interfaces.sh”
“./scripts/discover-interfaces.sh”
“../scripts/discover-interfaces.sh”
“/tmp/scripts/discover-interfaces.sh”
“discover-interfaces.sh”
“./discover-interfaces.sh”
“/tmp/discover-interfaces.sh”
)

FOUND_SCRIPT=””
for script_path in “${SCRIPT_CANDIDATES[@]}”; do
if [[ -f “$script_path” ]]; then
echo “  ✓ Found script: $script_path”
FOUND_SCRIPT=”$script_path”
echo “    File info:”
ls -la “$script_path”
echo “    Permissions: $(stat -c ‘%A’ “$script_path” 2>/dev/null || echo ‘unknown’)”
echo “    First few lines:”
head -5 “$script_path” 2>/dev/null || echo “Cannot read file”
break
else
echo “  ✗ Not found: $script_path”
fi
done

if [[ -z “$FOUND_SCRIPT” ]]; then
echo “❌ ERROR: No discover-interfaces.sh script found!”
echo “Please check that the script exists and is in the expected location.”
exit 1
fi

# ––––––––––––––

# Permissions Check

# ––––––––––––––

echo -e “\n=== DEBUG: Permissions Check ===”
echo “Current user: $(whoami)”
echo “Current UID: $EUID”
echo “Current groups: $(groups 2>/dev/null || echo ‘unknown’)”

# Test sudo access

echo “Testing sudo access:”
if sudo -n true 2>/dev/null; then
echo “  ✓ Passwordless sudo available”
elif sudo -l 2>/dev/null | grep -q “NOPASSWD”; then
echo “  ✓ NOPASSWD sudo available”
else
echo “  ⚠ Sudo may require password”
# Try with timeout
if timeout 5 sudo echo “Sudo test” 2>/dev/null; then
echo “  ✓ Sudo access confirmed”
else
echo “  ❌ Sudo access failed or timed out”
fi
fi

# ––––––––––––––

# System Info

# ––––––––––––––

echo -e “\n=== DEBUG: System Information ===”
echo “OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d’”’ -f2 || uname -s)”
echo “Kernel: $(uname -r)”
echo “Shell: $SHELL”
echo “Bash version: $BASH_VERSION”

# Check required commands

echo -e “\nRequired commands:”
for cmd in bash sudo ip mkdir chmod; do
if command -v “$cmd” >/dev/null 2>&1; then
echo “  ✓ $cmd: $(which “$cmd”)”
else
echo “  ❌ $cmd: NOT FOUND”
fi
done

# ––––––––––––––

# Log Directory Check

# ––––––––––––––

echo -e “\n=== DEBUG: Log Directory Setup ===”
LOG_CANDIDATES=(”./logs” “/tmp/logs” “/var/tmp/logs”)

for log_dir in “${LOG_CANDIDATES[@]}”; do
echo “Testing log directory: $log_dir”
if mkdir -p “$log_dir” 2>/dev/null; then
if [[ -w “$log_dir” ]]; then
echo “  ✓ $log_dir is writable”
LOG_DIR=”$log_dir”
break
else
echo “  ⚠ $log_dir exists but not writable”
fi
else
echo “  ❌ Cannot create $log_dir”
fi
done

if [[ -z “${LOG_DIR:-}” ]]; then
echo “❌ ERROR: No writable log directory found!”
exit 1
fi

# ––––––––––––––

# Network Interface Check

# ––––––––––––––

echo -e “\n=== DEBUG: Network Interfaces ===”
if command -v ip >/dev/null 2>&1; then
echo “Available network interfaces:”
ip link show | grep -E ‘^[0-9]+:’ | head -10

```
echo -e "\nManagement interface check:"
MGMT_IFACE="${MANAGEMENT_INTERFACE:-eth0}"
if ip link show "$MGMT_IFACE" >/dev/null 2>&1; then
    echo "  ✓ Management interface '$MGMT_IFACE' exists"
else
    echo "  ⚠ Management interface '$MGMT_IFACE' not found"
    echo "  Available interfaces:"
    ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | sed 's/^ */    /'
fi
```

else
echo “❌ ip command not available - this will cause the script to fail”
fi

# ––––––––––––––

# Test Script Execution (Dry Run)

# ––––––––––––––

echo -e “\n=== DEBUG: Test Script Syntax ===”
if bash -n “$FOUND_SCRIPT”; then
echo “  ✓ Script syntax is valid”
else
echo “  ❌ Script has syntax errors!”
exit 1
fi

echo -e “\n=== DEBUG: Test Script Help/Version ===”

# Try to run script with –help or see if it starts without error

timeout 10 bash “$FOUND_SCRIPT” –help 2>&1 || echo “Script doesn’t support –help or timed out”

# ––––––––––––––

# Environment Setup Test

# ––––––––––––––

echo -e “\n=== DEBUG: Environment Setup Test ===”
export TEST_MODE=true
export FORCE=true
export MANAGEMENT_INTERFACE=”${MANAGEMENT_INTERFACE:-eth0}”

echo “Environment variables set:”
env | grep -E ‘^(TEST_MODE|FORCE|MANAGEMENT_INTERFACE)=’

# ––––––––––––––

# Final Readiness Check

# ––––––––––––––

echo -e “\n=== DEBUG: Final Readiness Check ===”
echo “Script to execute: $FOUND_SCRIPT”
echo “Log directory: $LOG_DIR”
echo “Test mode: $TEST_MODE”
echo “Force mode: $FORCE”
echo “Management interface: $MANAGEMENT_INTERFACE”

echo -e “\n=== DEBUG: Ready to run actual test ===”
echo “If you see this message, the basic setup looks correct.”
echo “The failure is likely within the discover-interfaces.sh script itself.”
echo “Try running it manually:”
echo “  sudo bash $FOUND_SCRIPT”
echo “”
echo “Or run with debug enabled:”
echo “  DEBUG=true sudo -E bash $FOUND_SCRIPT”