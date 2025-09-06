#!/bin/bash
# discover-interfaces.sh
#
# Discover and validate physical network interfaces for Open vSwitch setup.
# Excludes management interface, saves config, and provides a report.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE="/etc/ovs/interface-config.conf"
MIN_INTERFACES=2
MANAGEMENT_INTERFACE="${MANAGEMENT_INTERFACE:-eth0}"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Discover all physical network interfaces (excluding mgmt, loopback, virtual, docker, ovs)
discover_interfaces() {
    log "Discovering network interfaces..."
    sudo mkdir -p /etc/ovs

    local all_interfaces=($(ip link show | grep -E "^[0-9]+: " | grep -v "lo:" | \
        grep -v "@" | grep -v "docker" | grep -v "br-" | grep -v "ovs-" | \
        awk -F': ' '{print $2}' | awk '{print $1}'))

    local available_interfaces=()
    for iface in "${all_interfaces[@]}"; do
        if [[ "$iface" != "$MANAGEMENT_INTERFACE" ]]; then
            if [[ -d "/sys/class/net/$iface/device" ]]; then
                available_interfaces+=("$iface")
            fi
        fi
    done

    log "Found ${#available_interfaces[@]} available interfaces (excluding $MANAGEMENT_INTERFACE)"

    if [[ ${#available_interfaces[@]} -lt $MIN_INTERFACES ]]; then
        error "Need at least $MIN_INTERFACES interfaces for switching. Found: ${#available_interfaces[@]}"
    fi

    echo -e "\n${BLUE}=== Interface Discovery Report ===${NC}"
    printf "%-12s %-15s %-10s %-15s %-20s\n" "Interface" "MAC Address" "State" "Speed" "Driver"
    echo "-----------------------------------------------------------------------"

    for iface in "${available_interfaces[@]}"; do
        local mac=$(cat /sys/class/net/$iface/address 2>/dev/null || echo "N/A")
        local state=$(ip link show $iface | grep -o "state [A-Z]*" | awk '{print $2}' || echo "UNKNOWN")
        local speed=$(ethtool $iface 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "N/A")
        local driver=$(ethtool -i $iface 2>/dev/null | grep "driver:" | awk '{print $2}' || echo "N/A")

        printf "%-12s %-15s %-10s %-15s %-20s\n" "$iface" "$mac" "$state" "$speed" "$driver"
    done

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

    echo -e "\n${YELLOW}Do you want to proceed with these interfaces? (y/N):${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
    return 0
}

# Validate interfaces
validate_interfaces() {
    local interfaces=("$@")
    local failed_interfaces=()

    log "Validating interfaces..."

    for iface in "${interfaces[@]}"; do
        if [[ ! -d "/sys/class/net/$iface" ]]; then
            warn "Interface $iface does not exist"
            failed_interfaces+=("$iface")
            continue
        fi

        if bridge link show dev "$iface" 2>/dev/null | grep -q "master"; then
            warn "Interface $iface is already part of a bridge"
            failed_interfaces+=("$iface")
            continue
        fi

        if ip addr show "$iface" | grep -q "inet "; then
            warn "Interface $iface has IP addresses assigned"
            echo "  Run: sudo ip addr flush dev $iface"
        fi
    done

    if [[ ${#failed_interfaces[@]} -gt 0 ]]; then
        error "Validation failed for interfaces: ${failed_interfaces[*]}"
    fi

    log "All interfaces validated successfully"
}

# Show current network config
show_network_config() {
    echo -e "\n${BLUE}=== Current Network Configuration ===${NC}"

    echo -e "\n${YELLOW}Bridges:${NC}"
    bridge link show 2>/dev/null || echo "No bridges found"

    echo -e "\n${YELLOW}OVS Bridges:${NC}"
    sudo ovs-vsctl show 2>/dev/null || echo "No OVS bridges found"

    echo -e "\n${YELLOW}Interface Status:${NC}"
    ip link show | grep -E "^[0-9]+:|state"
}

main() {
    log "Starting OVS Interface Discovery"

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi

    show_network_config
    discover_interfaces
    source "$CONFIG_FILE"
    validate_interfaces "${SWITCH_INTERFACES[@]}"

    log "Interface discovery completed successfully"
    log "Configuration file: $CONFIG_FILE"

    echo -e "\n${GREEN}Next steps:${NC}"
    echo "1. Run: sudo ./install-ovs.sh"
    echo "2. Run: sudo ./setup-ovs-bridge.sh"
    echo "3. Run: sudo ./configure-switch.sh"
}

main "$@"