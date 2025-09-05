#!/bin/bash

# step-by-step-debug.sh - Test each component individually

echo “=== STEP 1: Basic Shell Test ===”
echo “Shell: $SHELL”
echo “Bash version: $BASH_VERSION”
echo “Current user: $(whoami)”
echo “Current directory: $(pwd)”
echo “✓ Basic shell works”

echo -e “\n=== STEP 2: Directory Listing ===”
echo “Current directory contents:”
ls -la . | head -20
echo “✓ Directory listing works”

echo -e “\n=== STEP 3: Environment Variables ===”
echo “TEST_MODE: ${TEST_MODE:-NOT_SET}”
echo “FORCE: ${FORCE:-NOT_SET}”
echo “MANAGEMENT_INTERFACE: ${MANAGEMENT_INTERFACE:-NOT_SET}”
echo “✓ Environment variable access works”

echo -e “\n=== STEP 4: File System Access ===”
if [[ -d “scripts” ]]; then
echo “✓ scripts directory exists”
echo “Contents of scripts directory:”
ls -la scripts/ | head -10
else
echo “✗ scripts directory not found”
echo “Looking for alternatives…”
find . -name “discover-interfaces.sh” -type f 2>/dev/null | head -5
fi

echo -e “\n=== STEP 5: Command Availability ===”
COMMANDS=(“bash” “sudo” “ip” “mkdir” “chmod” “date” “grep” “awk”)
for cmd in “${COMMANDS[@]}”; do
if command -v “$cmd” >/dev/null 2>&1; then
echo “✓ $cmd available at $(which “$cmd”)”
else
echo “✗ $cmd NOT available”
fi
done

echo -e “\n=== STEP 6: Sudo Test ===”
if sudo -n true 2>/dev/null; then
echo “✓ Passwordless sudo works”
sudo echo “✓ Sudo echo test works”
else
echo “⚠ Passwordless sudo not available”
echo “Testing regular sudo…”
if timeout 5 sudo echo “Sudo test” 2>/dev/null; then
echo “✓ Sudo works (with password prompt)”
else
echo “✗ Sudo failed or timed out”
fi
fi

echo -e “\n=== STEP 7: Network Interface Check ===”
if command -v ip >/dev/null 2>&1; then
echo “Available network interfaces:”
ip link show 2>/dev/null | grep -E ‘^[0-9]+:’ | head -5
echo “✓ Network interface listing works”
else
echo “✗ ip command not available”
fi

echo -e “\n=== STEP 8: Log Directory Creation ===”
LOG_DIRS=(”./logs” “/tmp/logs” “/var/tmp/logs”)
for dir in “${LOG_DIRS[@]}”; do
if mkdir -p “$dir” 2>/dev/null; then
if [[ -w “$dir” ]]; then
echo “✓ $dir is writable”
# Test file creation
if echo “test” > “$dir/test-file” 2>/dev/null; then
echo “✓ Can create files in $dir”
rm -f “$dir/test-file”
WORKING_LOG_DIR=”$dir”
break
else
echo “✗ Cannot create files in $dir”
fi
else
echo “✗ $dir not writable”
fi
else
echo “✗ Cannot create $dir”
fi
done

if [[ -n “${WORKING_LOG_DIR:-}” ]]; then
echo “✓ Working log directory: $WORKING_LOG_DIR”
else
echo “✗ No working log directory found!”
fi

echo -e “\n=== STEP 9: Script Location Detection ===”
SCRIPT_LOCATIONS=(
“scripts/discover-interfaces.sh”
“./scripts/discover-interfaces.sh”
“../scripts/discover-interfaces.sh”
“/tmp/scripts/discover-interfaces.sh”
“discover-interfaces.sh”
“./discover-interfaces.sh”
)

FOUND_SCRIPT=””
for script in “${SCRIPT_LOCATIONS[@]}”; do
echo “Checking: $script”
if [[ -f “$script” ]]; then
echo “✓ Found: $script”
ls -la “$script”
FOUND_SCRIPT=”$script”
break
else
echo “✗ Not found: $script”
fi
done

if [[ -n “$FOUND_SCRIPT” ]]; then
echo “✓ Script found at: $FOUND_SCRIPT”

```
echo -e "\n=== STEP 10: Script Validation ==="
echo "File permissions: $(stat -c '%A' "$FOUND_SCRIPT" 2>/dev/null || echo 'unknown')"
echo "File size: $(stat -c '%s' "$FOUND_SCRIPT" 2>/dev/null || echo 'unknown') bytes"

echo "First 10 lines of script:"
head -10 "$FOUND_SCRIPT" 2>/dev/null || echo "Cannot read script"

echo "Testing syntax:"
if bash -n "$FOUND_SCRIPT" 2>&1; then
    echo "✓ Script syntax is valid"
else
    echo "✗ Script has syntax errors!"
fi

echo -e "\n=== STEP 11: Environment Setup Test ==="
export TEST_MODE=true
export FORCE=true
export MANAGEMENT_INTERFACE="${MANAGEMENT_INTERFACE:-eth0}"
echo "Environment variables set and exported"

echo -e "\n=== STEP 12: Minimal Execution Test ==="
echo "Attempting to run script with minimal command:"
echo "Command: bash -c 'echo Starting...; export TEST_MODE=true FORCE=true; echo Env set...; echo About to run script...; timeout 30 bash \"$FOUND_SCRIPT\"'"

# Use timeout to prevent hanging
timeout 30 bash -c "
    echo 'Script execution starting...'
    export TEST_MODE=true
    export FORCE=true
    export MANAGEMENT_INTERFACE=eth0
    echo 'Environment set, running script...'
    bash '$FOUND_SCRIPT'
" 2>&1 | head -50

EXIT_CODE=${PIPESTATUS[0]}
echo "Script exit code: $EXIT_CODE"
```

else
echo “✗ No script found! Please check file locations.”
echo “Complete directory structure:”
find . -type f -name “*.sh” 2>/dev/null | head -20
fi

echo -e “\n=== DEBUG SUMMARY ===”
echo “If all steps above show ✓, the issue might be in the script logic itself.”
echo “If any step shows ✗, that’s likely the root cause of the immediate failure.”