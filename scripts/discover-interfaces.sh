#!/bin/bash
# discover-interfaces.sh - CI-friendly, multi-mode

set -euo pipefail

# ----------------------------
# Configuration Flags
# ----------------------------
TEST_MODE="${TEST_MODE:-false}"   # true to include dummy interfaces in testing
FORCE="${FORCE:-false}"           # true to skip interactive prompts
MANAGEMENT_INTERFACE="${MANAGEMENT_INTERFACE:-eth0}"
MIN_INTERFACES=2
CONFIG_FILE="/etc/ovs/interface-config.conf"

# ----------------------------
# Color Codes
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------
# Logging Functions
# ----------------------------
log()   { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn()  { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; exit 1; }

# ----------------------------
# Discover Interfaces
# ----------------------------
discover_interfaces() {
    log "Discovering network interfaces..."

    sudo mkdir -p /etc/ovs || true

    # List all interfaces excluding lo, bridges, docker, ovs
    local all_interfaces=()
    if command -v ip >/dev/null 2>&1; then
        all_interfaces=($(ip link show | grep -E "^[0-9]+: " | grep -v "lo:" | \
            grep -v "@" | grep -v "docker" | grep -v "br-" | grep -v "ovs-" | \
            awk -F': ' '{print $2}' | awk '{print $1}'))
    else
        warn "ip command not found. Cannot list interfaces."
    fi

    local available_interfaces=()
    for iface in "${all_interfaces[@]}"; do
        if [[ "$iface" != "$MANAGEMENT_INTERFACE" ]]; then
            # Accept dummy interfaces in test mode or physical interfaces
            if [[ "$TEST_MODE" == "true" ]] || [[ -d "/sys/class/net/$iface/device" ]]; then
                available_interfaces+=("$iface")
            fi
        fi
    done

    # Handle minimum interfaces
    if [[ ${#available_interfaces[@]} -lt $MIN_INTERFACES ]]; then
        if [[ "$TEST_MODE" == "true" ]]; then
            warn "TEST_MODE active — only ${#available_interfaces[@]} interface(s) detected. Attempting dummy interfaces..."
            # Try to add dummy interface
            if command -v modprobe >/dev/null 2>&1; then
                modprobe dummy 2>/dev/null || warn "Dummy module not available — skipping"
            fi
            if command -v ip >/dev/null 2>&1; then
                ip link add dummy0 type dummy 2>/dev/null || warn "Could not add dummy0"
                ip link set dummy0 up 2>/dev/null || warn "Could not bring dummy0 up"
                available_interfaces+=("dummy0")
            else
                warn "ip command not available — cannot add dummy interfaces"
            fi
            log "Available interfaces after dummy attempt: ${available_interfaces[*]}"
        else
            error "Need at least $MIN_INTERFACES interfaces. Found: ${#available_interfaces[@]}"
        fi
    fi

    log "Final list of interfaces: ${available_interfaces[*]}"

    # Save configuration
    cat > "$CONFIG_FILE" << EOF
# OVS Interface Configuration
# Generated: $(date)
MANAGEMENT_INTERFACE="$MANAGEMENT_INTERFACE"
SWITCH_INTERFACES=($(printf '"%s" ' "${available_interfaces[@]}"))
BRIDGE_NAME="br0"
TOTAL_INTERFACES=${#available_interfaces[@]}
EOF

    log "Configuration saved to $CONFIG_FILE"

    # Interactive confirmation (skip if FORCE or TEST_MODE)
    if [[ "$FORCE" != "true" && "$TEST_MODE" != "true" ]]; then
        echo -e "\n${YELLOW}Do you want to proceed with these interfaces? (y/N):${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Operation cancelled by user"
            exit 0
        fi
    else
        log "Skipping interactive confirmation (FORCE/TEST_MODE enabled)"
    fi
}

# ----------------------------
# Validate Interfaces
# ----------------------------
validate_interfaces() {
    local interfaces=("$@")
    local failed_interfaces=()

    log "Validating interfaces..."

    for iface in "${interfaces[@]}"; do
        [[ ! -d "/sys/class/net/$iface" ]] && { warn "$iface does not exist"; failed_interfaces+=("$iface"); continue; }

        if command -v bridge >/dev/null 2>&1 && bridge link show dev "$iface" 2>/dev/null | grep -q "master"; then
            warn "$iface is already part of a bridge"; failed_interfaces+=("$iface"); continue
        fi

        if command -v ip >/dev/null 2>&1 && ip addr show "$iface" | grep -q "inet "; then
            warn "$iface has IP addresses assigned"
            echo "  Run: ip addr flush dev $iface"
        fi
    done

    [[ ${#failed_interfaces[@]} -gt 0 ]] && warn "Validation warnings for: ${failed_interfaces[*]}"
    log "Interface validation complete"
}

# ----------------------------
# Show network configuration
# ----------------------------
show_network_config() {
    echo -e "\n${BLUE}=== Current Network Configuration ===${NC}"
    if command -v bridge >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Bridges:${NC}"
        bridge link show 2>/dev/null || echo "No bridges found"
    fi

    if command -v ovs-vsctl >/dev/null 2>&1; then
        echo -e "\n${YELLOW}OVS Bridges:${NC}"
        ovs-vsctl show 2>/dev/null || echo "No OVS bridges found"
    fi

    if command -v ip >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Interface Status:${NC}"
        ip link show | grep -E "^[0-9]+:|state"
    fi
}

# ----------------------------
# Main Execution
# ----------------------------
main() {
    log "Starting OVS Interface Discovery"

    [[ $EUID -ne 0 ]] && warn "Not running as root — some operations may fail in CI"

    show_network_config
    discover_interfaces

    source "$CONFIG_FILE"
    validate_interfaces "${SWITCH_INTERFACES[@]}"

    log "Interface discovery completed successfully"
    log "Configuration file: $CONFIG_FILE"
}

main "$@"