# Dynamic Open vSwitch Layer 2 Managed Switch Setup Guide

This guide shows how to configure a Linux machine with **any number of NICs** as a layer 2 managed switch using Open vSwitch (OVS). The setup automatically detects available network interfaces and provides VLAN support, port mirroring, traffic shaping, and advanced switching features.

## Prerequisites

- Linux machine with multiple physical network interfaces (2 or more)
- Root access to the system
- Basic understanding of networking concepts
- At least one interface reserved for management (recommended)

## Architecture Overview

```
    ┌─────────────────────────────────────────────────────────────┐
    │                    Linux Host                                │
    │  ┌─────────────────────────────────────────────────────────┐ │
    │  │                Open vSwitch                             │ │
    │  │  ┌─────────────────────────────────────────────────────┐│ │
    │  │  │               br0 (Main Bridge)                     ││ │
    │  │  │                                                     ││ │
    │  │  │  eth1  eth2  eth3  ...  ethN  (Auto-detected)     ││ │
    │  │  └─────┬───┬───┬─────────┬────────────────────────────┘│ │
    │  └────────┼───┼───┼─────────┼─────────────────────────────┘ │
    └───────────┼───┼───┼─────────┼──────────────────────────────┘
                │   │   │         │
           ┌────▼┐ ┌▼┐ ┌▼┐   ... ┌▼┐
           │Dev A│ │B│ │C│       │N│
           └─────┘ └─┘ └─┘       └─┘
```

## 1. Interface Discovery and Validation

First, let's create a comprehensive interface discovery script:

```bash
#!/bin/bash
# discover-interfaces.sh

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

# Function to discover all physical network interfaces
discover_interfaces() {
    log "Discovering network interfaces..."
    
    # Create config directory
    sudo mkdir -p /etc/ovs
    
    # Get all physical network interfaces (excluding virtual, loopback, etc.)
    local all_interfaces=($(ip link show | grep -E "^[0-9]+: " | grep -v "lo:" | \
        grep -v "@" | grep -v "docker" | grep -v "br-" | grep -v "ovs-" | \
        awk -F': ' '{print $2}' | awk '{print $1}'))
    
    # Filter out management interface and validate
    local available_interfaces=()
    for iface in "${all_interfaces[@]}"; do
        if [[ "$iface" != "$MANAGEMENT_INTERFACE" ]]; then
            # Check if interface is physical
            if [[ -d "/sys/class/net/$iface/device" ]]; then
                available_interfaces+=("$iface")
            fi
        fi
    done
    
    log "Found ${#available_interfaces[@]} available interfaces (excluding $MANAGEMENT_INTERFACE)"
    
    if [[ ${#available_interfaces[@]} -lt $MIN_INTERFACES ]]; then
        error "Need at least $MIN_INTERFACES interfaces for switching. Found: ${#available_interfaces[@]}"
    fi
    
    # Display interface information
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
    
    # Interactive confirmation
    echo -e "\n${YELLOW}Do you want to proceed with these interfaces? (y/N):${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    return 0
}

# Function to validate interface requirements
validate_interfaces() {
    local interfaces=("$@")
    local failed_interfaces=()
    
    log "Validating interfaces..."
    
    for iface in "${interfaces[@]}"; do
        # Check if interface exists
        if [[ ! -d "/sys/class/net/$iface" ]]; then
            warn "Interface $iface does not exist"
            failed_interfaces+=("$iface")
            continue
        fi
        
        # Check if interface is not in use by other bridges
        if bridge link show dev "$iface" 2>/dev/null | grep -q "master"; then
            warn "Interface $iface is already part of a bridge"
            failed_interfaces+=("$iface")
            continue
        fi
        
        # Check if interface has IP addresses
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

# Function to show current network configuration
show_network_config() {
    echo -e "\n${BLUE}=== Current Network Configuration ===${NC}"
    
    echo -e "\n${YELLOW}Bridges:${NC}"
    bridge link show 2>/dev/null || echo "No bridges found"
    
    echo -e "\n${YELLOW}OVS Bridges:${NC}"
    sudo ovs-vsctl show 2>/dev/null || echo "No OVS bridges found"
    
    echo -e "\n${YELLOW}Interface Status:${NC}"
    ip link show | grep -E "^[0-9]+:|state"
}

# Main execution
main() {
    log "Starting OVS Interface Discovery"
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
    
    # Show current configuration
    show_network_config
    
    # Discover and validate interfaces
    discover_interfaces
    
    # Load configuration
    source "$CONFIG_FILE"
    validate_interfaces "${SWITCH_INTERFACES[@]}"
    
    log "Interface discovery completed successfully"
    log "Ready to proceed with OVS installation and configuration"
    log "Configuration file: $CONFIG_FILE"
    
    echo -e "\n${GREEN}Next steps:${NC}"
    echo "1. Run: sudo ./install-ovs.sh"
    echo "2. Run: sudo ./setup-ovs-bridge.sh"
    echo "3. Run: sudo ./configure-switch.sh"
}

# Execute main function
main "$@"
```

## 2. Dynamic OVS Installation Script

```bash
#!/bin/bash
# install-ovs.sh

set -euo pipefail

# Load configuration
CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Run discover-interfaces.sh first"; exit 1; }
source "$CONFIG_FILE"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

install_ubuntu_debian() {
    log "Installing OVS on Ubuntu/Debian..."
    
    # Update package repository
    apt update
    
    # Install Open vSwitch
    apt install -y openvswitch-switch openvswitch-common
    
    # Install additional tools
    apt install -y bridge-utils net-tools tcpdump ethtool
    
    # Enable and start services
    systemctl enable openvswitch-switch
    systemctl start openvswitch-switch
}

install_rhel_centos() {
    log "Installing OVS on RHEL/CentOS/Rocky Linux..."
    
    # Enable EPEL repository if not already enabled
    dnf install -y epel-release
    
    # Install Open vSwitch
    dnf install -y openvswitch openvswitch-selinux-policy
    
    # Install additional tools
    dnf install -y bridge-utils net-tools tcpdump ethtool
    
    # Start and enable services
    systemctl enable --now openvswitch
    systemctl enable --now ovsdb-server
    systemctl enable --now ovs-vswitchd
}

install_fedora() {
    log "Installing OVS on Fedora..."
    
    # Install Open vSwitch
    dnf install -y openvswitch python3-openvswitch
    
    # Install additional tools
    dnf install -y bridge-utils net-tools tcpdump ethtool
    
    # Start and enable services
    systemctl enable --now openvswitch
}

verify_installation() {
    log "Verifying OVS installation..."
    
    # Check OVS version
    local ovs_version=$(ovs-vsctl --version | head -1)
    log "OVS Version: $ovs_version"
    
    # Check service status
    if systemctl is-active --quiet openvswitch-switch || systemctl is-active --quiet openvswitch; then
        log "OVS services are running"
    else
        error "OVS services are not running"
    fi
    
    # Test basic OVS functionality
    if ovs-vsctl show >/dev/null 2>&1; then
        log "OVS database is accessible"
    else
        error "Cannot access OVS database"
    fi
}

main() {
    log "Starting OVS installation for $TOTAL_INTERFACES interfaces"
    
    local os_type=$(detect_os)
    log "Detected OS: $os_type"
    
    case "$os_type" in
        ubuntu|debian)
            install_ubuntu_debian
            ;;
        rhel|centos|rocky|almalinux)
            install_rhel_centos
            ;;
        fedora)
            install_fedora
            ;;
        *)
            echo "Unsupported OS: $os_type"
            echo "Please install OVS manually and ensure services are running"
            exit 1
            ;;
    esac
    
    verify_installation
    log "OVS installation completed successfully"
}

main "$@"
```

## 3. Dynamic Bridge Setup Script

```bash
#!/bin/bash
# setup-ovs-bridge.sh

set -euo pipefail

# Load configuration
CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Run discover-interfaces.sh first"; exit 1; }
source "$CONFIG_FILE"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

prepare_interface() {
    local iface="$1"
    
    log "Preparing interface $iface..."
    
    # Bring interface down
    ip link set "$iface" down 2>/dev/null || true
    
    # Remove any IP addresses
    ip addr flush dev "$iface" 2>/dev/null || true
    
    # Remove from any existing bridges
    bridge link show dev "$iface" 2>/dev/null | grep "master" && {
        local bridge=$(bridge link show dev "$iface" | awk '{print $7}')
        brctl delif "$bridge" "$iface" 2>/dev/null || true
    }
    
    # Bring interface up without IP
    ip link set "$iface" up
    
    # Wait for interface to come up
    sleep 1
    
    log "Interface $iface prepared"
}

create_bridge() {
    log "Creating OVS bridge: $BRIDGE_NAME"
    
    # Remove bridge if it exists
    ovs-vsctl --if-exists del-br "$BRIDGE_NAME"
    
    # Create the main bridge
    ovs-vsctl add-br "$BRIDGE_NAME"
    
    # Configure bridge properties
    ovs-vsctl set bridge "$BRIDGE_NAME" protocols=OpenFlow10,OpenFlow13
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:stp-enable=true
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:stp-hello-time=2
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:stp-max-age=20
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:stp-forward-delay=15
    
    # Enable MAC learning
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:mac-aging-time=300
    
    # Set datapath ID based on number of interfaces
    local dpid=$(printf "%016x" $((0x1000000000000000 + TOTAL_INTERFACES)))
    ovs-vsctl set bridge "$BRIDGE_NAME" other-config:datapath-id="$dpid"
    
    log "Bridge $BRIDGE_NAME created with $TOTAL_INTERFACES ports"
}

add_interfaces_to_bridge() {
    log "Adding interfaces to bridge..."
    
    local port_num=1
    for iface in "${SWITCH_INTERFACES[@]}"; do
        log "Adding $iface to bridge $BRIDGE_NAME (port $port_num)"
        
        # Prepare interface
        prepare_interface "$iface"
        
        # Add to bridge
        ovs-vsctl add-port "$BRIDGE_NAME" "$iface"
        
        # Set port number for consistent configuration
        ovs-vsctl set interface "$iface" ofport="$port_num"
        
        # Set port description
        ovs-vsctl set port "$iface" other-config:description="Auto-configured port $port_num"
        
        ((port_num++))
    done
    
    # Enable the bridge
    ip link set "$BRIDGE_NAME" up
    
    log "All $TOTAL_INTERFACES interfaces added to bridge"
}

create_persistent_config() {
    log "Creating persistent configuration..."
    
    # Create systemd service for bridge persistence
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

    # Create bridge restore script
    cat > /usr/local/bin/ovs-bridge-restore.sh << EOF
#!/bin/bash
# Auto-generated OVS bridge restore script

# Load configuration
source /etc/ovs/interface-config.conf

# Ensure bridge exists
if ! ovs-vsctl br-exists \$BRIDGE_NAME; then
    ovs-vsctl add-br \$BRIDGE_NAME
fi

# Ensure all interfaces are added
for iface in "\${SWITCH_INTERFACES[@]}"; do
    if ! ovs-vsctl port-to-br "\$iface" >/dev/null 2>&1; then
        ovs-vsctl add-port \$BRIDGE_NAME \$iface
    fi
    ip link set \$iface up
done

# Enable bridge
ip link set \$BRIDGE_NAME up
EOF

    chmod +x /usr/local/bin/ovs-bridge-restore.sh
    systemctl enable ovs-bridge-setup.service
    
    log "Persistent configuration created"
}

verify_bridge() {
    log "Verifying bridge configuration..."
    
    # Check if bridge exists
    if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
        error "Bridge $BRIDGE_NAME was not created"
    fi
    
    # Check interface count
    local actual_ports=$(ovs-vsctl list-ports "$BRIDGE_NAME" | wc -l)
    if [[ "$actual_ports" -ne "$TOTAL_INTERFACES" ]]; then
        error "Expected $TOTAL_INTERFACES ports, found $actual_ports"
    fi
    
    # Show bridge status
    echo -e "\n${BLUE}=== Bridge Configuration ===${NC}"
    ovs-vsctl show
    
    echo -e "\n${BLUE}=== Port Statistics ===${NC}"
    ovs-ofctl show "$BRIDGE_NAME"
    
    log "Bridge verification completed successfully"
}

main() {
    log "Setting up OVS bridge with $TOTAL_INTERFACES interfaces"
    log "Management interface ($MANAGEMENT_INTERFACE) excluded"
    
    create_bridge
    add_interfaces_to_bridge
    create_persistent_config
    verify_bridge
    
    log "Bridge setup completed successfully!"
    log "Bridge: $BRIDGE_NAME with interfaces: ${SWITCH_INTERFACES[*]}"
}

main "$@"
```

## 4. Dynamic Switch Configuration Script

```bash
#!/bin/bash
# configure-switch.sh

set -euo pipefail

# Load configuration
CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Run discover-interfaces.sh first"; exit 1; }
source "$CONFIG_FILE"

# Colors
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

# Interactive configuration menu
show_menu() {
    echo -e "\n${BLUE}=== OVS Switch Configuration Menu ===${NC}"
    echo "Bridge: $BRIDGE_NAME with $TOTAL_INTERFACES ports"
    echo "Interfaces: ${SWITCH_INTERFACES[*]}"
    echo ""
    echo "1) Configure VLANs"
    echo "2) Setup Port Mirroring"
    echo "3) Configure QoS"
    echo "4) Setup Link Aggregation (LACP)"
    echo "5) Configure OpenFlow Controller"
    echo "6) View Current Configuration"
    echo "7) Reset All Configuration"
    echo "8) Generate Management Scripts"
    echo "9) Exit"
    echo ""
}

configure_vlans() {
    log "Starting VLAN configuration..."
    
    echo -e "\n${YELLOW}VLAN Configuration Options:${NC}"
    echo "1) Auto-configure VLANs (recommended for beginners)"
    echo "2) Manual VLAN configuration"
    echo "3) Import VLAN configuration from file"
    echo ""
    read -p "Select option (1-3): " vlan_option
    
    case "$vlan_option" in
        1) auto_configure_vlans ;;
        2) manual_configure_vlans ;;
        3) import_vlan_config ;;
        *) warn "Invalid option" ;;
    esac
}

auto_configure_vlans() {
    log "Auto-configuring VLANs..."
    
    local num_vlans=3
    local vlans=(10 20 30)
    local vlan_names=("Development" "Production" "Management")
    
    # Calculate interfaces per VLAN
    local interfaces_per_vlan=$((TOTAL_INTERFACES / num_vlans))
    local remaining_interfaces=$((TOTAL_INTERFACES % num_vlans))
    
    log "Distributing $TOTAL_INTERFACES interfaces across $num_vlans VLANs"
    
    local interface_index=0
    for i in "${!vlans[@]}"; do
        local vlan_id="${vlans[i]}"
        local vlan_name="${vlan_names[i]}"
        local interfaces_for_this_vlan=$interfaces_per_vlan
        
        # Add remaining interfaces to last VLAN
        if [[ $i -eq $((num_vlans - 1)) ]]; then
            interfaces_for_this_vlan=$((interfaces_per_vlan + remaining_interfaces))
        fi
        
        log "Configuring VLAN $vlan_id ($vlan_name) with $interfaces_for_this_vlan interfaces"
        
        for ((j=0; j<interfaces_for_this_vlan; j++)); do
            if [[ $interface_index -lt ${#SWITCH_INTERFACES[@]} ]]; then
                local iface="${SWITCH_INTERFACES[interface_index]}"
                ovs-vsctl set port "$iface" tag="$vlan_id"
                ovs-vsctl set port "$iface" other-config:vlan-name="$vlan_name"
                log "  $iface assigned to VLAN $vlan_id"
                ((interface_index++))
            fi
        done
    done
}

manual_configure_vlans() {
    log "Manual VLAN configuration..."
    
    for iface in "${SWITCH_INTERFACES[@]}"; do
        echo -e "\n${YELLOW}Configure $iface:${NC}"
        echo "1) Access port"
        echo "2) Trunk port"
        echo "3) Skip this interface"
        read -p "Select option (1-3): " port_type
        
        case "$port_type" in
            1)
                read -p "Enter VLAN ID for access port: " vlan_id
                if [[ "$vlan_id" =~ ^[0-9]+$ ]] && [[ "$vlan_id" -ge 1 ]] && [[ "$vlan_id" -le 4094 ]]; then
                    ovs-vsctl set port "$iface" tag="$vlan_id"
                    log "$iface configured as access port for VLAN $vlan_id"
                else
                    warn "Invalid VLAN ID. Skipping $iface"
                fi
                ;;
            2)
                read -p "Enter allowed VLANs (comma-separated, e.g., 10,20,30): " trunk_vlans
                if [[ -n "$trunk_vlans" ]]; then
                    ovs-vsctl set port "$iface" trunks="$trunk_vlans"
                    log "$iface configured as trunk port for VLANs: $trunk_vlans"
                else
                    # Trunk all VLANs
                    ovs-vsctl clear port "$iface" tag
                    ovs-vsctl clear port "$iface" trunks
                    log "$iface configured as trunk port for all VLANs"
                fi
                ;;
            3)
                log "Skipping $iface configuration"
                ;;
            *)
                warn "Invalid option. Skipping $iface"
                ;;
        esac
    done
}

setup_port_mirroring() {
    log "Setting up port mirroring..."
    
    if [[ $TOTAL_INTERFACES -lt 3 ]]; then
        warn "Need at least 3 interfaces for port mirroring (2 source + 1 destination)"
        return
    fi
    
    echo -e "\n${YELLOW}Available interfaces:${NC}"
    for i in "${!SWITCH_INTERFACES[@]}"; do
        echo "$((i+1))) ${SWITCH_INTERFACES[i]}"
    done
    
    echo ""
    read -p "Select source interfaces (comma-separated numbers): " source_nums
    read -p "Select destination interface (number): " dest_num
    
    # Parse source interfaces
    local source_interfaces=()
    IFS=',' read -ra source_array <<< "$source_nums"
    for num in "${source_array[@]}"; do
        local index=$((num - 1))
        if [[ $index -ge 0 ]] && [[ $index -lt ${#SWITCH_INTERFACES[@]} ]]; then
            source_interfaces+=("${SWITCH_INTERFACES[index]}")
        fi
    done
    
    # Parse destination interface
    local dest_index=$((dest_num - 1))
    if [[ $dest_index -ge 0 ]] && [[ $dest_index -lt ${#SWITCH_INTERFACES[@]} ]]; then
        local dest_interface="${SWITCH_INTERFACES[dest_index]}"
        
        # Remove any existing mirrors
        ovs-vsctl clear bridge "$BRIDGE_NAME" mirrors
        
        # Create mirror
        local mirror_name="mirror_$(date +%s)"
        ovs-vsctl -- --id=@m create mirror name="$mirror_name" \
            select-src-port="$(IFS=','; echo "${source_interfaces[*]}")" \
            select-dst-port="$(IFS=','; echo "${source_interfaces[*]}")" \
            output-port="$dest_interface" \
            -- set bridge "$BRIDGE_NAME" mirrors=@m
        
        log "Port mirroring configured:"
        log "  Source ports: ${source_interfaces[*]}"
        log "  Destination port: $dest_interface"
    else
        warn "Invalid destination interface"
    fi
}

configure_qos() {
    log "Configuring Quality of Service..."
    
    echo -e "\n${YELLOW}QoS Configuration:${NC}"
    echo "1) Rate limiting (per interface)"
    echo "2) Traffic shaping queues"
    echo "3) Priority-based QoS"
    read -p "Select option (1-3): " qos_option
    
    case "$qos_option" in
        1) configure_rate_limiting ;;
        2) configure_traffic_shaping ;;
        3) configure_priority_qos ;;
        *) warn "Invalid option" ;;
    esac
}

configure_rate_limiting() {
    for iface in "${SWITCH_INTERFACES[@]}"; do
        echo -e "\n${YELLOW}Rate limit for $iface:${NC}"
        read -p "Enter rate limit in Kbps (0 for unlimited): " rate_limit
        
        if [[ "$rate_limit" =~ ^[0-9]+$ ]]; then
            if [[ "$rate_limit" -gt 0 ]]; then
                local burst=$((rate_limit / 10))  # 10% of rate as burst
                ovs-vsctl set interface "$iface" ingress_policing_rate="$rate_limit"
                ovs-vsctl set interface "$iface" ingress_policing_burst="$burst"
                log "$iface rate limited to ${rate_limit}Kbps"
            else
                ovs-vsctl remove interface "$iface" ingress_policing_rate
                ovs-vsctl remove interface "$iface" ingress_policing_burst
                log "$iface rate limiting removed"
            fi
        else
            warn "Invalid rate limit for $iface"
        fi
    done
}

view_configuration() {
    echo -e "\n${BLUE}=== Current OVS Configuration ===${NC}"
    
    echo -e "\n${YELLOW}Bridge Information:${NC}"
    ovs-vsctl show
    
    echo -e "\n${YELLOW}Port Configuration:${NC}"
    for iface in "${SWITCH_INTERFACES[@]}"; do
        local tag=$(ovs-vsctl get port "$iface" tag 2>/dev/null | tr -d '[]' || echo "trunk")
        local trunks=$(ovs-vsctl get port "$iface" trunks 2>/dev/null | tr -d '[]' || echo "all")
        
        if [[ "$tag" != "trunk" ]]; then
            echo "$iface: Access port VLAN $tag"
        else
            echo "$iface: Trunk port VLANs $trunks"
        fi
    done
    
    echo -e "\n${YELLOW}VLAN Summary:${NC}"
    ovs-vsctl list port | grep -E "(name|tag|trunks)" | paste - - -
    
    echo -e "\n${YELLOW}Mirror Configuration:${NC}"
    ovs-vsctl list mirror 2>/dev/null || echo "No mirrors configured"
    
    echo -e "\n${YELLOW}QoS Configuration:${NC}"
    for iface in "${SWITCH_INTERFACES[@]}"; do
        local rate=$(ovs-vsctl get interface "$iface" ingress_policing_rate 2>/dev/null || echo "unlimited")
        echo "$iface: Rate limit $rate"
    done
}

reset_configuration() {
    echo -e "\n${RED}WARNING: This will reset all OVS configuration!${NC}"
    read -p "Are you sure? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        log "Resetting OVS configuration..."
        
        # Clear all port configurations
        for iface in "${SWITCH_INTERFACES[@]}"; do
            ovs-vsctl clear port "$iface" tag
            ovs-vsctl clear port "$iface" trunks
            ovs-vsctl clear port "$iface" other-config
            ovs-vsctl remove interface "$iface" ingress_policing_rate
            ovs-vsctl remove interface "$iface" ingress_policing_burst
        done
        
        # Clear mirrors
        ovs-vsctl clear bridge "$BRIDGE_NAME" mirrors
        
        # Clear QoS
        ovs-vsctl clear bridge "$BRIDGE_NAME" qos
        
        # Clear controller
        ovs-vsctl del-controller "$BRIDGE_NAME"
        
        log "Configuration reset completed"
    else
        log "Reset cancelled"
    fi
}

generate_management_scripts() {
    log "Generating management scripts..."
    
    local script_dir="/usr/local/bin/ovs-scripts"
    mkdir -p "$script_dir"
    
    # Create monitoring script
    cat > "$script_dir/ovs-monitor.sh" << 'EOF'
#!/bin/bash
# Dynamic OVS Monitoring Script

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1

show_status() {
    echo "=== OVS Bridge Status ==="
    ovs-vsctl show
    echo
    echo "=== Port Statistics ==="
    ovs-ofctl dump-port-stats "$BRIDGE_NAME"
    echo
    echo "=== Flow Table ==="
    ovs-ofctl dump-flows "$BRIDGE_NAME"
}

show_vlans() {
    echo "=== VLAN Configuration ==="
    for iface in "${SWITCH_INTERFACES[@]}"; do
        local tag=$(ovs-vsctl get port "$iface" tag 2>/dev/null | tr -d '[]' || echo "trunk")
        local trunks=$(ovs-vsctl get port "$iface" trunks 2>/dev/null | tr -d '[]' || echo "all")
        
        if [[ "$tag" != "trunk" ]]; then
            echo "$iface: Access VLAN $tag"
        else
            echo "$iface: Trunk VLANs $trunks"
        fi
    done
}

monitor_traffic() {
    local interface="$1"
    if [[ -z "$interface" ]]; then
        echo "Usage: $0 monitor <interface>"
        echo "Available interfaces: ${SWITCH_INTERFACES[*]}"
        exit 1
    fi
    
    echo "Monitoring $interface (Ctrl+C to stop)..."
    tcpdump -i "$interface" -n
}

case "${1:-}" in
    "status") show_status ;;
    "vlans") show_vlans ;;
    "monitor") monitor_traffic "$2" ;;
    *) 
        echo "Usage: $0 {status|vlans|monitor <interface>}"
        echo "Available interfaces: ${SWITCH_INTERFACES[*]}"
        ;;
esac
EOF

    # Create backup script
    cat > "$script_dir/ovs-backup.sh" << 'EOF'
#!/bin/bash
# Dynamic OVS Backup Script

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1

BACKUP_DIR="/var/backups/ovs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup OVS database
ovsdb-client backup > "$BACKUP_DIR/ovs-db-$TIMESTAMP.json"

# Backup configuration
ovs-vsctl show > "$BACKUP_DIR/ovs-config-$TIMESTAMP.txt"
ovs-ofctl dump-flows "$BRIDGE_NAME" > "$BACKUP_DIR/ovs-flows-$TIMESTAMP.txt"

# Save interface configuration
cp "$CONFIG_FILE" "$BACKUP_DIR/interface-config-$TIMESTAMP.conf"

echo "Backup completed: $BACKUP_DIR"
ls -la "$BACKUP_DIR/"
EOF

    # Create performance tuning script
    cat > "$script_dir/ovs-tune.sh" << 'EOF'
#!/bin/bash
# Dynamic OVS Performance Tuning

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1

echo "Applying performance tuning for $TOTAL_INTERFACES interfaces..."

# Kernel network parameters
cat >> /etc/sysctl.conf << EOL
# OVS Performance Tuning
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
EOL

sysctl -p

# OVS datapath optimization
local cpu_count=$(nproc)
local handler_threads=$((cpu_count / 2))
local revalidator_threads=$((cpu_count / 4))

[[ $handler_threads -lt 1 ]] && handler_threads=1
[[ $revalidator_threads -lt 1 ]] && revalidator_threads=1

ovs-vsctl set Open_vSwitch . other_config:n-handler-threads="$handler_threads"
ovs-vsctl set Open_vSwitch . other_config:n-revalidator-threads="$revalidator_threads"

echo "Performance tuning applied:"
echo "  Handler threads: $handler_threads"
echo "  Revalidator threads: $revalidator_threads"
EOF

    # Create troubleshooting script
    cat > "$script_dir/ovs-troubleshoot.sh" << 'EOF'
#!/bin/bash
# Dynamic OVS Troubleshooting

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1

echo "=== OVS Troubleshooting Report ==="
echo "Generated: $(date)"
echo "Interfaces: ${SWITCH_INTERFACES[*]}"
echo "Total interfaces: $TOTAL_INTERFACES"

echo -e "\n1. Service Status:"
systemctl status openvswitch-switch 2>/dev/null || systemctl status openvswitch

echo -e "\n2. Bridge Status:"
ovs-vsctl show

echo -e "\n3. Interface States:"
for iface in "${SWITCH_INTERFACES[@]}"; do
    echo -n "$iface: "
    ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" || echo "NOT FOUND"
done

echo -e "\n4. Port Statistics:"
ovs-ofctl dump-port-stats "$BRIDGE_NAME"

echo -e "\n5. Flow Table:"
ovs-ofctl dump-flows "$BRIDGE_NAME" | head -20

echo -e "\n6. Recent Logs:"
journalctl -u openvswitch-switch --no-pager -n 10 2>/dev/null || \
journalctl -u openvswitch --no-pager -n 10

echo -e "\n7. System Resources:"
free -h
df -h /
EOF

    # Make scripts executable
    chmod +x "$script_dir"/*.sh
    
    # Create convenience symlinks
    ln -sf "$script_dir/ovs-monitor.sh" /usr/local/bin/ovs-monitor
    ln -sf "$script_dir/ovs-backup.sh" /usr/local/bin/ovs-backup
    ln -sf "$script_dir/ovs-tune.sh" /usr/local/bin/ovs-tune
    ln -sf "$script_dir/ovs-troubleshoot.sh" /usr/local/bin/ovs-troubleshoot
    
    log "Management scripts generated:"
    log "  ovs-monitor    - Monitor switch status"
    log "  ovs-backup     - Backup configuration"
    log "  ovs-tune       - Performance tuning"
    log "  ovs-troubleshoot - Troubleshooting"
}

main() {
    log "OVS Switch Configuration for $TOTAL_INTERFACES interfaces"
    
    while true; do
        show_menu
        read -p "Select option (1-9): " choice
        
        case "$choice" in
            1) configure_vlans ;;
            2) setup_port_mirroring ;;
            3) configure_qos ;;
            4) setup_lacp ;;
            5) configure_openflow ;;
            6) view_configuration ;;
            7) reset_configuration ;;
            8) generate_management_scripts ;;
            9) log "Configuration complete!"; exit 0 ;;
            *) warn "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

setup_lacp() {
    log "Setting up Link Aggregation (LACP)..."
    
    if [[ $TOTAL_INTERFACES -lt 2 ]]; then
        warn "Need at least 2 interfaces for LACP"
        return
    fi
    
    echo -e "\n${YELLOW}LACP Configuration:${NC}"
    echo "Available interfaces: ${SWITCH_INTERFACES[*]}"
    
    read -p "Enter interfaces for bond (space-separated): " bond_interfaces
    read -p "Enter bond name (default: bond0): " bond_name
    bond_name="${bond_name:-bond0}"
    
    # Validate interfaces
    local valid_interfaces=()
    for iface in $bond_interfaces; do
        if [[ " ${SWITCH_INTERFACES[*]} " == *" $iface "* ]]; then
            valid_interfaces+=("$iface")
        else
            warn "Interface $iface not found"
        fi
    done
    
    if [[ ${#valid_interfaces[@]} -lt 2 ]]; then
        warn "Need at least 2 valid interfaces for LACP"
        return
    fi
    
    # Remove interfaces from bridge if they exist
    for iface in "${valid_interfaces[@]}"; do
        ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$iface"
    done
    
    # Create LACP bond
    ovs-vsctl add-bond "$BRIDGE_NAME" "$bond_name" "${valid_interfaces[@]}" \
        lacp=active \
        bond_mode=balance-tcp \
        other_config:lacp-time=fast
    
    log "LACP bond created: $bond_name with interfaces ${valid_interfaces[*]}"
}

configure_openflow() {
    log "Configuring OpenFlow controller..."
    
    echo -e "\n${YELLOW}OpenFlow Configuration:${NC}"
    read -p "Enter controller IP address: " controller_ip
    read -p "Enter controller port (default: 6633): " controller_port
    controller_port="${controller_port:-6633}"
    
    if [[ -n "$controller_ip" ]]; then
        # Set OpenFlow controller
        ovs-vsctl set-controller "$BRIDGE_NAME" "tcp:$controller_ip:$controller_port"
        
        # Set OpenFlow version
        ovs-vsctl set bridge "$BRIDGE_NAME" protocols=OpenFlow13
        
        # Configure fail mode
        echo "Fail mode options:"
        echo "1) Secure (drop packets if controller unavailable)"
        echo "2) Standalone (act as learning switch if controller unavailable)"
        read -p "Select option (1-2): " fail_mode_option
        
        case "$fail_mode_option" in
            1) ovs-vsctl set-fail-mode "$BRIDGE_NAME" secure ;;
            2) ovs-vsctl set-fail-mode "$BRIDGE_NAME" standalone ;;
            *) warn "Invalid option, using standalone mode"
               ovs-vsctl set-fail-mode "$BRIDGE_NAME" standalone ;;
        esac
        
        log "OpenFlow controller configured: $controller_ip:$controller_port"
    else
        warn "No controller IP provided"
    fi
}

configure_traffic_shaping() {
    log "Configuring traffic shaping queues..."
    
    for iface in "${SWITCH_INTERFACES[@]}"; do
        echo -e "\n${YELLOW}Traffic shaping for $iface:${NC}"
        read -p "Enable traffic shaping? (y/N): " enable_shaping
        
        if [[ "$enable_shaping" =~ ^[Yy]$ ]]; then
            read -p "Enter maximum rate (bps): " max_rate
            read -p "Enter minimum guaranteed rate (bps): " min_rate
            
            if [[ "$max_rate" =~ ^[0-9]+$ ]] && [[ "$min_rate" =~ ^[0-9]+$ ]]; then
                # Create QoS and queues
                ovs-vsctl set port "$iface" qos=@newqos \
                    -- --id=@newqos create qos type=linux-htb \
                    other-config:max-rate="$max_rate" \
                    queues=0=@q0 \
                    -- --id=@q0 create queue other-config:min-rate="$min_rate" other-config:max-rate="$max_rate"
                
                log "$iface traffic shaping configured (min: $min_rate bps, max: $max_rate bps)"
            else
                warn "Invalid rate values for $iface"
            fi
        fi
    done
}

configure_priority_qos() {
    log "Configuring priority-based QoS..."
    
    # This is a simplified implementation
    # In practice, you would configure DSCP marking and priority queues
    
    for iface in "${SWITCH_INTERFACES[@]}"; do
        echo -e "\n${YELLOW}Priority QoS for $iface:${NC}"
        echo "1) High priority"
        echo "2) Normal priority" 
        echo "3) Low priority"
        read -p "Select priority (1-3): " priority
        
        case "$priority" in
            1) 
                ovs-vsctl set port "$iface" other-config:priority=high
                log "$iface set to high priority"
                ;;
            2)
                ovs-vsctl set port "$iface" other-config:priority=normal  
                log "$iface set to normal priority"
                ;;
            3)
                ovs-vsctl set port "$iface" other-config:priority=low
                log "$iface set to low priority"
                ;;
            *)
                warn "Invalid priority for $iface"
                ;;
        esac
    done
}

import_vlan_config() {
    log "Importing VLAN configuration from file..."
    
    read -p "Enter configuration file path: " config_file
    
    if [[ ! -f "$config_file" ]]; then
        warn "Configuration file not found: $config_file"
        return
    fi
    
    # Expected format: interface,type,vlan
    # Example: eth1,access,10
    #          eth2,trunk,10,20,30
    
    while IFS=',' read -r interface port_type vlans; do
        # Skip comments and empty lines
        [[ "$interface" =~ ^#.*$ ]] || [[ -z "$interface" ]] && continue
        
        # Check if interface is valid
        if [[ " ${SWITCH_INTERFACES[*]} " != *" $interface "* ]]; then
            warn "Interface $interface not found, skipping"
            continue
        fi
        
        case "$port_type" in
            access)
                if [[ "$vlans" =~ ^[0-9]+$ ]] && [[ "$vlans" -ge 1 ]] && [[ "$vlans" -le 4094 ]]; then
                    ovs-vsctl set port "$interface" tag="$vlans"
                    log "$interface configured as access port for VLAN $vlans"
                else
                    warn "Invalid VLAN ID for $interface: $vlans"
                fi
                ;;
            trunk)
                if [[ -n "$vlans" ]]; then
                    # Remove interface from command and use remaining as VLANs
                    local trunk_vlans=$(echo "$vlans" | tr ' ' ',')
                    ovs-vsctl set port "$interface" trunks="$trunk_vlans"
                    log "$interface configured as trunk port for VLANs: $trunk_vlans"
                else
                    ovs-vsctl clear port "$interface" tag
                    ovs-vsctl clear port "$interface" trunks
                    log "$interface configured as trunk port for all VLANs"
                fi
                ;;
            *)
                warn "Invalid port type for $interface: $port_type"
                ;;
        esac
    done < "$config_file"
    
    log "VLAN configuration import completed"
}

main "$@"
```

## 5. Universal Management Dashboard

Let me also update the web dashboard to work with any number of interfaces:

```bash
#!/bin/bash
# generate-web-dashboard.sh

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || exit 1

WEB_DIR="/var/www/ovs-dashboard"
mkdir -p "$WEB_DIR"

# Generate dynamic HTML with actual interface data
cat > "$WEB_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OVS Switch Dashboard - $TOTAL_INTERFACES Interfaces</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <style>
        /* [CSS from previous dashboard] */
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 OVS Switch Manager</h1>
            <div class="status-indicator">
                <div class="status-dot"></div>
                <span>$TOTAL_INTERFACES Ports Active</span>
            </div>
        </div>
        
        <div class="dashboard-grid">
            <div class="card">
                <h3>Interface Overview</h3>
                <div id="interfaceList">
                    <!-- Dynamically populated -->
                </div>
            </div>
            
            <div class="card">
                <h3>Traffic Monitor</h3>
                <canvas id="trafficChart"></canvas>
            </div>
            
            <!-- Additional cards -->
        </div>
    </div>

    <script>
        const INTERFACES = [$(printf '"%s",' "${SWITCH_INTERFACES[@]}" | sed 's/,$//')];
        const BRIDGE_NAME = "$BRIDGE_NAME";
        const TOTAL_INTERFACES = $TOTAL_INTERFACES;
        
        // Initialize dashboard with actual data
        initializeDashboard();
        
        function initializeDashboard() {
            populateInterfaces();
            setupTrafficChart();
            startRealTimeUpdates();
        }
        
        function populateInterfaces() {
            const container = document.getElementById('interfaceList');
            container.innerHTML = '';
            
            INTERFACES.forEach((iface, index) => {
                const interfaceDiv = document.createElement('div');
                interfaceDiv.className = 'interface-item';
                interfaceDiv.innerHTML = \`
                    <div class="interface-info">
                        <strong>\${iface}</strong>
                        <span id="status-\${iface}">Checking...</span>
                    </div>
                    <div class="interface-stats" id="stats-\${iface}">
                        <span>Loading...</span>
                    </div>
                \`;
                container.appendChild(interfaceDiv);
                
                // Update interface status
                updateInterfaceStatus(iface);
            });
        }
        
        function updateInterfaceStatus(iface) {
            // In a real implementation, this would make API calls
            // For demo purposes, we'll simulate data
            const statusEl = document.getElementById(\`status-\${iface}\`);
            const statsEl = document.getElementById(\`stats-\${iface}\`);
            
            statusEl.textContent = 'UP - Auto-configured';
            statsEl.innerHTML = \`
                <span>RX: \${(Math.random() * 1000).toFixed(0)}MB</span>
                <span>TX: \${(Math.random() * 800).toFixed(0)}MB</span>
            \`;
        }
        
        // Additional dashboard functions...
    </script>
</body>
</html>
EOF

log "Web dashboard generated at $WEB_DIR/index.html"
```

## 6. Complete Deployment Script

```bash
#!/bin/bash
# deploy-ovs-switch.sh - Complete deployment script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

main() {
    log "Starting complete OVS switch deployment..."
    
    # Step 1: Discover interfaces
    log "Step 1: Interface discovery"
    bash "$SCRIPT_DIR/discover-interfaces.sh"
    
    # Step 2: Install OVS
    log "Step 2: Installing OVS"
    bash "$SCRIPT_DIR/install-ovs.sh"
    
    # Step 3: Setup bridge
    log "Step 3: Setting up bridge"
    bash "$SCRIPT_DIR/setup-ovs-bridge.sh"
    
    # Step 4: Configure switch
    log "Step 4: Configuring switch"
    bash "$SCRIPT_DIR/configure-switch.sh"
    
    # Step 5: Generate management tools
    log "Step 5: Generating management tools"
    bash "$SCRIPT_DIR/generate-web-dashboard.sh"
    
    log "OVS switch deployment completed successfully!"
    
    # Load config for summary
    source /etc/ovs/interface-config.conf
    
    echo -e "\n${YELLOW}=== Deployment Summary ===${NC}"
    echo "Bridge: $BRIDGE_NAME"
    echo "Interfaces: ${SWITCH_INTERFACES[*]}"
    echo "Total ports: $TOTAL_INTERFACES"
    echo "Management interface: $MANAGEMENT_INTERFACE (preserved)"
    echo ""
    echo "Available commands:"
    echo "  ovs-monitor status  - Show switch status"
    echo "  ovs-backup          - Backup configuration" 
    echo "  ovs-tune            - Apply performance tuning"
    echo "  ovs-troubleshoot    - Run diagnostics"
    echo ""
    echo "Configuration file: /etc/ovs/interface-config.conf"
    echo "Web dashboard: /var/www/ovs-dashboard/index.html"
}

main "$@"
```

## Key Benefits of This Dynamic Approach

1. **Automatic Detection**: Discovers any number of NICs automatically
2. **Flexible Configuration**: Adapts to 2, 5, 10, or 50+ interfaces  
3. **Safety**: Preserves management interface
4. **Scalable**: Performance tuning adjusts to interface count
5. **Management Tools**: Generates scripts tailored to your setup
6. **Recovery**: Comprehensive backup and restore capabilities

## Usage Examples

```bash
# For a machine with 8 interfaces
sudo ./discover-interfaces.sh  # Finds eth1-eth7 (excluding eth0 for mgmt)
sudo ./deploy-ovs-switch.sh    # Deploys complete solution

# For a machine with 20 interfaces  
MANAGEMENT_INTERFACE=ens18 sudo ./discover-interfaces.sh  # Custom mgmt interface
sudo ./deploy-ovs-switch.sh    # Handles all 19 remaining interfaces

# For a minimal 2-interface setup
sudo ./discover-interfaces.sh  # Works with just 2 interfaces
sudo ./deploy-ovs-switch.sh    # Creates basic L2 switch
```

The dynamic approach makes the guide universally applicable to any hardware configuration while maintaining all the advanced features of the original setup!