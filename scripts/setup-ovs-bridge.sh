#!/bin/bash
# setup-ovs-bridge.sh
#
# Configure OVS bridge and add interfaces dynamically.

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

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

prepare_interface() {
    local iface="$1"
    log "Preparing interface $iface..."
    ip link set "$iface" down 2>/dev/null || true
    ip addr flush dev "$iface" 2>/dev/null || true

    if bridge link show dev "$iface" 2>/dev/null | grep -q "master"; then
        local br=$(bridge link show dev "$iface" | awk '{print $7}')
        brctl delif "$br" "$iface" 2>/dev/null || true
    fi

    ip link set "$iface" up
    sleep 1
    log "Interface $iface prepared"
}

create_bridge() {
    log "Creating OVS bridge: $BRIDGE_NAME"
    ovs-vsctl --if-exists del-br "$BRIDGE_NAME"
    ovs-vsctl add-br "$BRIDGE_NAME"
    ovs-vsctl set bridge "$BRIDGE_NAME" protocols=OpenFlow10,OpenFlow13
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:stp-enable=true
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:mac-aging-time=300
    local dpid=$(printf "%016x" $((0x1000000000000000 + TOTAL_INTERFACES)))
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:datapath-id="$dpid"
}

add_interfaces_to_bridge() {
    log "Adding interfaces to $BRIDGE_NAME..."
    local port_num=1
    for iface in "${SWITCH_INTERFACES[@]}"; do
        log "Adding $iface as port $port_num"
        prepare_interface "$iface"
        ovs-vsctl add-port "$BRIDGE_NAME" "$iface"
        ovs-vsctl set port "$iface" other-config:description="Auto-configured port $port_num"
        ((port_num++))
    done
    ip link set "$BRIDGE_NAME" up
}

create_persistent_config() {
    log "Creating persistent configuration..."
    cat > /etc/systemd/system/ovs-bridge-setup.service << EOF
[Unit]
Description=OVS Bridge Setup
After=openvswitch.service
Requires=openvswitch.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/ovs-bridge-restore.sh
ExecStop=/bin/true

[Install]
WantedBy=multi-user.target
EOF

    cat > /usr/local/bin/ovs-bridge-restore.sh << EOF
#!/bin/bash
source /etc/ovs/interface-config.conf
if ! ovs-vsctl br-exists \$BRIDGE_NAME; then
    ovs-vsctl add-br \$BRIDGE_NAME
fi
for iface in "\${SWITCH_INTERFACES[@]}"; do
    if ! ovs-vsctl port-to-br "\$iface" >/dev/null 2>&1; then
        ovs-vsctl add-port \$BRIDGE_NAME \$iface
    fi
    ip link set \$iface up
done
ip link set \$BRIDGE_NAME up
EOF

    chmod +x /usr/local/bin/ovs-bridge-restore.sh
    systemctl enable ovs-bridge-setup.service
}

verify_bridge() {
    log "Verifying bridge configuration..."
    if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
        error "Bridge $BRIDGE_NAME was not created"
    fi
    local actual_ports=$(ovs-vsctl list-ports "$BRIDGE_NAME" | wc -l)
    if [[ "$actual_ports" -ne "$TOTAL_INTERFACES" ]]; then
        error "Expected $TOTAL_INTERFACES ports, found $actual_ports"
    fi

    echo -e "\n${BLUE}=== Bridge Configuration ===${NC}"
    ovs-vsctl show
    echo -e "\n${BLUE}=== Port Statistics ===${NC}"
    ovs-ofctl show "$BRIDGE_NAME"
}

main() {
    log "Setting up OVS bridge with $TOTAL_INTERFACES interfaces"
    log "Management interface ($MANAGEMENT_INTERFACE) excluded"
    create_bridge
    add_interfaces_to_bridge
    create_persistent_config
    verify_bridge
    log "Bridge setup completed successfully!"
}

main "$@"
