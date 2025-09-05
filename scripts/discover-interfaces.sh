#!/bin/bash

# discover-interfaces.sh - CI-friendly, multi-mode

set -euo pipefail

# ––––––––––––––

# Configuration Flags

# ––––––––––––––

TEST_MODE=”${TEST_MODE:-false}”   # true to include dummy interfaces in testing
FORCE=”${FORCE:-false}”           # true to skip interactive prompts
MANAGEMENT_INTERFACE=”${MANAGEMENT_INTERFACE:-eth0}”
MIN_INTERFACES=2
CONFIG_DIR=”/etc/ovs”
CONFIG_FILE=”$CONFIG_DIR/interface-config.conf”

# ––––––––––––––

# Color Codes (disabled in non-interactive environments)

# ––––––––––––––

if [[ -t 1 ]] && [[ “${TERM:-}” != “dumb” ]]; then
RED=’\033[0;31m’
GREEN=’\033[0;32m’
YELLOW=’\033[1;33m’
BLUE=’\033[0;34m’
NC=’\033[0m’
else
RED=’’
GREEN=’’
YELLOW=’’
BLUE=’’
NC=’’
fi

# ––––––––––––––

# Logging Functions

# ––––––––––––––

log()   { echo -e “${GREEN}[$(date ‘+%Y-%m-%d %H:%M:%S’)]${NC} $1” >&2; }
warn()  { echo -e “${YELLOW}[$(date ‘+%Y-%m-%d %H:%M:%S’)] WARNING:${NC} $1” >&2; }
error() { echo -e “${RED}[$(date ‘+%Y-%m-%d %H:%M:%S’)] ERROR:${NC} $1” >&2; exit 1; }
debug() { [[ “${DEBUG:-false}” == “true” ]] && echo -e “[DEBUG] $1” >&2 || true; }

# ––––––––––––––

# System Detection

# ––––––––––––––

detect_system() {
local os_info=””
if [[ -f /etc/os-release ]]; then
os_info=$(grep PRETTY_NAME /etc/os-release | cut -d’”’ -f2)
else
os_info=$(uname -s)
fi
log “Detected system: $os_info”
debug “Kernel: $(uname -r)”
debug “User: $(whoami), UID: $EUID”
}

# ––––––––––––––

# Check Dependencies

# ––––––––––––––

check_dependencies() {
local missing_deps=()
local optional_deps=()

```
# Required commands
for cmd in ip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_deps+=("$cmd")
    fi
done

# Optional commands
for cmd in bridge ovs-vsctl modprobe; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        optional_deps+=("$cmd")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    error "Missing required dependencies: ${missing_deps[*]}"
fi

if [[ ${#optional_deps[@]} -gt 0 ]]; then
    warn "Optional dependencies not found: ${optional_deps[*]}"
fi

log "Dependency check completed"
```

}

# ––––––––––––––

# Create Configuration Directory

# ––––––––––––––

setup_config_dir() {
if [[ ! -d “$CONFIG_DIR” ]]; then
log “Creating configuration directory: $CONFIG_DIR”
if ! mkdir -p “$CONFIG_DIR” 2>/dev/null; then
if [[ $EUID -ne 0 ]]; then
log “Creating config directory with sudo…”
sudo mkdir -p “$CONFIG_DIR” || error “Failed to create $CONFIG_DIR”
sudo chown “$USER:$USER” “$CONFIG_DIR” 2>/dev/null || true
else
error “Failed to create $CONFIG_DIR”
fi
fi
fi

```
# Ensure directory is writable
if [[ ! -w "$CONFIG_DIR" ]]; then
    if [[ $EUID -ne 0 ]]; then
        sudo chown "$USER:$USER" "$CONFIG_DIR" 2>/dev/null || \
            warn "Cannot make $CONFIG_DIR writable. Configuration may fail."
    else
        chmod 755 "$CONFIG_DIR"
    fi
fi
```

}

# ––––––––––––––

# Discover Interfaces

# ––––––––––––––

discover_interfaces() {
log “Discovering network interfaces…”

```
setup_config_dir

# Get all network interfaces
local all_interfaces=()
debug "Listing all network interfaces..."

# Use ip link to get interfaces
while IFS= read -r line; do
    if [[ $line =~ ^[0-9]+:\ ([^:@]+) ]]; then
        local iface="${BASH_REMATCH[1]}"
        # Skip loopback, virtual interfaces, and known problematic ones
        if [[ "$iface" != "lo" ]] && \
           [[ "$iface" != *"@"* ]] && \
           [[ "$iface" != "docker"* ]] && \
           [[ "$iface" != "br-"* ]] && \
           [[ "$iface" != "ovs-"* ]] && \
           [[ "$iface" != "veth"* ]] && \
           [[ "$iface" != "virbr"* ]]; then
            all_interfaces+=("$iface")
            debug "Found interface: $iface"
        else
            debug "Skipping interface: $iface"
        fi
    fi
done < <(ip link show 2>/dev/null)

log "Total interfaces found: ${#all_interfaces[@]} (${all_interfaces[*]})"

# Filter available interfaces (excluding management interface)
local available_interfaces=()
for iface in "${all_interfaces[@]}"; do
    if [[ "$iface" != "$MANAGEMENT_INTERFACE" ]]; then
        # In test mode, accept any interface; otherwise check for physical interfaces
        if [[ "$TEST_MODE" == "true" ]]; then
            available_interfaces+=("$iface")
            debug "Added interface (test mode): $iface"
        elif [[ -d "/sys/class/net/$iface/device" ]] || [[ -L "/sys/class/net/$iface/device" ]]; then
            available_interfaces+=("$iface")
            debug "Added physical interface: $iface"
        else
            debug "Skipping non-physical interface: $iface"
        fi
    else
        debug "Skipping management interface: $iface"
    fi
done

log "Available interfaces (excluding $MANAGEMENT_INTERFACE): ${#available_interfaces[@]}"
[[ ${#available_interfaces[@]} -gt 0 ]] && log "  ${available_interfaces[*]}"

# Handle minimum interfaces requirement
if [[ ${#available_interfaces[@]} -lt $MIN_INTERFACES ]]; then
    if [[ "$TEST_MODE" == "true" ]]; then
        warn "Only ${#available_interfaces[@]} interface(s) detected. Creating dummy interfaces for testing..."
        create_dummy_interfaces available_interfaces
    else
        error "Need at least $MIN_INTERFACES interfaces for OVS bridge. Found: ${#available_interfaces[@]}"
    fi
fi

# Validate we have enough interfaces now
if [[ ${#available_interfaces[@]} -lt $MIN_INTERFACES ]]; then
    error "Still insufficient interfaces after dummy creation. Need $MIN_INTERFACES, have ${#available_interfaces[@]}"
fi

log "Final interface list: ${available_interfaces[*]} (${#available_interfaces[@]} total)"

# Create configuration file
create_config_file "${available_interfaces[@]}"

# Interactive confirmation (skip if FORCE or TEST_MODE)
if [[ "$FORCE" != "true" ]] && [[ "$TEST_MODE" != "true" ]] && [[ -t 0 ]]; then
    echo -e "\n${YELLOW}Detected interfaces for OVS bridge: ${available_interfaces[*]}${NC}"
    echo -e "${YELLOW}Management interface (excluded): $MANAGEMENT_INTERFACE${NC}"
    echo -e "\n${YELLOW}Do you want to proceed with this configuration? (y/N):${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
else
    log "Skipping interactive confirmation (FORCE=$FORCE, TEST_MODE=$TEST_MODE, non-interactive=$([ ! -t 0 ] && echo true || echo false))"
fi
```

}

# ––––––––––––––

# Create Dummy Interfaces for Testing

# ––––––––––––––

create_dummy_interfaces() {
local -n interfaces_ref=$1
local dummy_count=0
local needed=$((MIN_INTERFACES - ${#interfaces_ref[@]}))

```
log "Attempting to create $needed dummy interface(s)..."

# Try to load dummy module
if command -v modprobe >/dev/null 2>&1; then
    if modprobe dummy numdummies=4 2>/dev/null; then
        debug "Loaded dummy module with 4 interfaces"
    elif modprobe dummy 2>/dev/null; then
        debug "Loaded dummy module (default)"
    else
        warn "Could not load dummy kernel module"
    fi
else
    warn "modprobe not available - cannot load dummy module"
fi

# Create dummy interfaces
for i in $(seq 0 5); do
    local dummy_name="dummy$i"
    
    # Skip if already exists
    if ip link show "$dummy_name" >/dev/null 2>&1; then
        debug "Dummy interface $dummy_name already exists"
    else
        # Try to create dummy interface
        if ip link add "$dummy_name" type dummy 2>/dev/null; then
            debug "Created dummy interface: $dummy_name"
        else
            debug "Failed to create dummy interface: $dummy_name"
            continue
        fi
    fi
    
    # Bring interface up
    if ip link set "$dummy_name" up 2>/dev/null; then
        debug "Brought up dummy interface: $dummy_name"
        interfaces_ref+=("$dummy_name")
        ((dummy_count++))
        
        # Stop if we have enough
        if [[ ${#interfaces_ref[@]} -ge $MIN_INTERFACES ]]; then
            break
        fi
    else
        warn "Failed to bring up dummy interface: $dummy_name"
    fi
done

log "Created $dummy_count dummy interface(s). Total interfaces: ${#interfaces_ref[@]}"
```

}

# ––––––––––––––

# Create Configuration File

# ––––––––––––––

create_config_file() {
local interfaces=(”$@”)

```
log "Creating configuration file: $CONFIG_FILE"

# Create temporary file first, then move to avoid partial writes
local temp_file
temp_file=$(mktemp) || error "Failed to create temporary file"

cat > "$temp_file" << EOF
```

# OVS Interface Configuration

# Generated by discover-interfaces.sh on $(date)

# System: $(uname -a 2>/dev/null | head -c 100)…

# 

# This file contains the discovered network interface configuration

# for Open vSwitch bridge setup.

# Management interface (excluded from bridge)

MANAGEMENT_INTERFACE=”$MANAGEMENT_INTERFACE”

# Interfaces to be added to the OVS bridge

SWITCH_INTERFACES=($(printf ’”%s” ’ “${interfaces[@]}”))

# Bridge configuration

BRIDGE_NAME=“br0”

# Statistics

TOTAL_INTERFACES=${#interfaces[@]}
DISCOVERY_DATE=”$(date -Iseconds)”
TEST_MODE=”$TEST_MODE”

# Interface details

$(for iface in “${interfaces[@]}”; do
echo “# $iface: $(ip link show “$iface” 2>/dev/null | head -1 | cut -d: -f3- | xargs || echo “details unavailable”)”
done)
EOF

```
# Move temp file to final location
if ! mv "$temp_file" "$CONFIG_FILE" 2>/dev/null; then
    if [[ $EUID -ne 0 ]]; then
        sudo mv "$temp_file" "$CONFIG_FILE" || error "Failed to write configuration file"
        sudo chown "$USER:$USER" "$CONFIG_FILE" 2>/dev/null || true
    else
        error "Failed to write configuration file"
    fi
fi

# Set appropriate permissions
chmod 644 "$CONFIG_FILE" 2>/dev/null || \
    sudo chmod 644 "$CONFIG_FILE" 2>/dev/null || \
    warn "Could not set permissions on $CONFIG_FILE"

log "Configuration saved successfully"
debug "Configuration file contents:"
[[ "${DEBUG:-false}" == "true" ]] && cat "$CONFIG_FILE" || true
```

}

# ––––––––––––––

# Validate Interfaces

# ––––––––––––––

validate_interfaces() {
local interfaces=(”$@”)
local failed_interfaces=()
local warnings=()

```
log "Validating ${#interfaces[@]} interface(s)..."

for iface in "${interfaces[@]}"; do
    debug "Validating interface: $iface"
    
    # Check if interface exists
    if [[ ! -d "/sys/class/net/$iface" ]]; then
        warn "Interface $iface does not exist in /sys/class/net/"
        failed_interfaces+=("$iface")
        continue
    fi

    # Check if interface is already part of a bridge
    if command -v bridge >/dev/null 2>&1; then
        if bridge link show dev "$iface" 2>/dev/null | grep -q "master"; then
            local master
            master=$(bridge link show dev "$iface" 2>/dev/null | grep master | awk '{print $7}')
            warn "Interface $iface is already part of bridge: $master"
            warnings+=("$iface (bridge: $master)")
        fi
    fi

    # Check if interface has IP addresses
    if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
        local ips
        ips=$(ip addr show "$iface" | grep "inet " | awk '{print $2}' | tr '\n' ' ')
        warn "Interface $iface has IP addresses: $ips"
        warnings+=("$iface (IPs: $ips)")
        echo "  ${YELLOW}Recommendation: ip addr flush dev $iface${NC}"
    fi

    # Check interface state
    local state
    state=$(ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" | cut -d' ' -f2)
    debug "Interface $iface state: ${state:-UNKNOWN}"
    
    # Check if interface is a physical device (in non-test mode)
    if [[ "$TEST_MODE" != "true" ]] && [[ ! -d "/sys/class/net/$iface/device" ]] && [[ ! -L "/sys/class/net/$iface/device" ]]; then
        warn "Interface $iface may not be a physical device"
    fi
done

# Report validation results
if [[ ${#failed_interfaces[@]} -gt 0 ]]; then
    error "Validation failed for interfaces: ${failed_interfaces[*]}"
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
    warn "Validation warnings for: ${warnings[*]}"
    log "These warnings may not prevent OVS bridge creation but should be reviewed"
else
    log "All interfaces passed validation"
fi
```

}

# ––––––––––––––

# Show Network Configuration

# ––––––––––––––

show_network_config() {
echo -e “\n${BLUE}=== Current Network Configuration ===${NC}”

```
# Show basic interface information
echo -e "\n${YELLOW}Network Interfaces:${NC}"
if command -v ip >/dev/null 2>&1; then
    ip -brief link show 2>/dev/null || ip link show | grep -E "^[0-9]+:|state"
else
    warn "ip command not available"
fi

# Show bridges
if command -v bridge >/dev/null 2>&1; then
    echo -e "\n${YELLOW}Linux Bridges:${NC}"
    local bridges
    if bridges=$(bridge link show 2>/dev/null); then
        [[ -n "$bridges" ]] && echo "$bridges" || echo "No Linux bridges found"
    else
        echo "Cannot query Linux bridges"
    fi
fi

# Show OVS bridges
if command -v ovs-vsctl >/dev/null 2>&1; then
    echo -e "\n${YELLOW}OVS Bridges:${NC}"
    if ovs-vsctl show 2>/dev/null | grep -q "Bridge"; then
        ovs-vsctl show 2>/dev/null
    else
        echo "No OVS bridges found"
    fi
fi

echo ""
```

}

# ––––––––––––––

# Main Execution

# ––––––––––––––

main() {
log “Starting OVS Interface Discovery”
log “Configuration: TEST_MODE=$TEST_MODE, FORCE=$FORCE, MGMT_IFACE=$MANAGEMENT_INTERFACE”

```
detect_system
check_dependencies

if [[ $EUID -ne 0 ]]; then
    warn "Not running as root - some operations may require sudo"
    debug "Current user: $(whoami), groups: $(groups)"
fi

show_network_config
discover_interfaces

# Source and validate configuration
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    validate_interfaces "${SWITCH_INTERFACES[@]}"
else
    error "Configuration file not created: $CONFIG_FILE"
fi

log "Interface discovery completed successfully"
log "Configuration file: $CONFIG_FILE"
log "Total interfaces for OVS bridge: $TOTAL_INTERFACES"

if [[ "$TEST_MODE" == "true" ]]; then
    log "TEST_MODE was enabled - remember to clean up dummy interfaces if needed"
fi
```

}

# ––––––––––––––

# Signal Handlers

# ––––––––––––––

cleanup() {
local exit_code=$?
if [[ “$TEST_MODE” == “true” ]] && [[ $exit_code -ne 0 ]]; then
log “Cleaning up dummy interfaces due to error…”
for i in {0..5}; do
if ip link show “dummy$i” >/dev/null 2>&1; then
ip link delete “dummy$i” 2>/dev/null || true
fi
done
fi
exit $exit_code
}

trap cleanup EXIT INT TERM

# Run main function

main “$@”