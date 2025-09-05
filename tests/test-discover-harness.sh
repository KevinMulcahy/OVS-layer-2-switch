#!/bin/bash
# tests/test-discover-harness.sh
# Automated test harness for discover-interfaces.sh

SCRIPT="../scripts/discover-interfaces.sh"
LOG="test-results-$(hostname)-$(date +%Y%m%d%H%M).log"

echo "Running discover-interfaces.sh tests on $(hostname)" | tee "$LOG"
echo "===================================================" | tee -a "$LOG"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    echo -e "\n[TEST] $name" | tee -a "$LOG"
    if "$@" >>"$LOG" 2>&1; then
        echo "PASS: $name" | tee -a "$LOG"
        ((PASS++))
    else
        echo "FAIL: $name" | tee -a "$LOG"
        ((FAIL++))
    fi
}

# --- Test Cases ---

# 1. Run without sudo (expect fail)
run_test "Run without sudo" $SCRIPT || true

# 2. Run with sudo (expect success)
run_test "Run with sudo" sudo $SCRIPT <<EOF
y
EOF

# 3. Interface with IP assigned
sudo ip addr add 192.168.123.100/24 dev dummy0
run_test "Interface with IP assigned (expect warning, still success)" sudo $SCRIPT <<EOF
y
EOF
sudo ip addr flush dev dummy0

# 4. Only one available interface
sudo ip link set dummy1 down
run_test "Only one available interface (expect fail)" sudo $SCRIPT <<EOF
y
EOF
sudo ip link set dummy1 up

# 5. Run as root vs non-root (redundant check)
run_test "Run without sudo again" $SCRIPT || true

# Summary
echo -e "\n=== TEST SUMMARY ===" | tee -a "$LOG"
echo "Passed: $PASS" | tee -a "$LOG"
echo "Failed: $FAIL" | tee -a "$LOG"

# Exit with fail count as status
exit $FAIL
