#!/bin/bash
# configure-switch.sh
#
# Interactive switch configuration for VLANs, mirroring, QoS, and controllers.

set -euo pipefail

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Run discover-interfaces.sh first"; exit 1; }
source "$CONFIG_FILE"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

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

# VLAN Configuration
configure_vlans() {
    echo -e "\n${BLUE}=== VLAN Configuration ===${NC}"
    echo "Available interfaces: ${SWITCH_INTERFACES[*]}"

    while true; do
        read -p "Assign VLAN? (y/N): " resp
        [[ ! "$resp" =~ ^[Yy]$ ]] && break

        read -p "Enter interface name: " iface
        read -p "Enter VLAN ID (1-4094): " vlan_id
        ovs-vsctl set port "$iface" tag="$vlan_id"
        log "Assigned VLAN $vlan_id to $iface"
    done
}

# Port Mirroring
configure_mirroring() {
    echo -e "\n${BLUE}=== Port Mirroring ===${NC}"
    read -p "Configure port mirroring? (y/N): " resp
    [[ ! "$resp" =~ ^[Yy]$ ]] && return

    read -p "Enter source interface: " src
    read -p "Enter destination interface: " dst

    ovs-vsctl -- --id=@src get port "$src" \
        -- --id=@dst get port "$dst" \
        -- --id=@m create mirror name=m0 select-src-port=@src output-port=@dst \
        -- set bridge "$BRIDGE_NAME" mirrors=@m

    log "Mirroring traffic from $src to $dst"
}

# QoS Configuration
configure_qos() {
    echo -e "\n${BLUE}=== QoS Configuration ===${NC}"
    read -p "Configure QoS? (y/N): " resp
    [[ ! "$resp" =~ ^[Yy]$ ]] && return

    read -p "Enter interface for QoS: " iface
    read -p "Enter max rate (in Mbps): " rate

    ovs-vsctl set port "$iface" qos=@newqos \
        -- --id=@newqos create qos type=linux-htb \
        other-config:max-rate=$((rate * 1000000)) \
        queues:123=@q1 -- --id=@q1 create queue \
        other-config:max-rate=$((rate * 1000000))

    log "QoS applied to $iface with max rate ${rate}Mbps"
}

# Controller Setup
configure_controller() {
    echo -e "\n${BLUE}=== OpenFlow Controller ===${NC}"
    read -p "Configure controller? (y/N): " resp
    [[ ! "$resp" =~ ^[Yy]$ ]] && return

    read -p "Enter controller IP (e.g. 192.168.1.10): " ctrl_ip
    read -p "Enter controller port (default 6633): " ctrl_port
    ctrl_port=${ctrl_port:-6633}

    ovs-vsctl set-controller "$BRIDGE_NAME" tcp:"$ctrl_ip":"$ctrl_port"
    ovs-vsctl set bridge "$BRIDGE_NAME" fail-mode=secure

    log "Controller set to $ctrl_ip:$ctrl_port"
}

# Show current config
show_config() {
    echo -e "\n${BLUE}=== Current Switch Configuration ===${NC}"
    ovs-vsctl show
    echo -e "\n${BLUE}=== Flow Table (OpenFlow) ===${NC}"
    ovs-ofctl dump-flows "$BRIDGE_NAME"
}

main() {
    log "Starting interactive switch configuration"
    configure_vlans
    configure_mirroring
    configure_qos
    configure_controller
    show_config
    log "Switch configuration completed!"
}

main "$@"
