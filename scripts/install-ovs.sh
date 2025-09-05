#!/bin/bash
# install-ovs.sh
#
# Install Open vSwitch and prerequisites dynamically based on OS.

set -euo pipefail

CONFIG_FILE="/etc/ovs/interface-config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "Run discover-interfaces.sh first"; exit 1; }
source "$CONFIG_FILE"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
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
    apt update
    apt install -y openvswitch-switch openvswitch-common bridge-utils net-tools tcpdump ethtool
    systemctl enable openvswitch-switch
    systemctl start openvswitch-switch
}

install_rhel_centos() {
    log "Installing OVS on RHEL/CentOS/Rocky Linux..."
    dnf install -y epel-release
    dnf install -y openvswitch openvswitch-selinux-policy bridge-utils net-tools tcpdump ethtool
    systemctl enable --now openvswitch
    systemctl enable --now ovsdb-server
    systemctl enable --now ovs-vswitchd
}

install_fedora() {
    log "Installing OVS on Fedora..."
    dnf install -y openvswitch python3-openvswitch bridge-utils net-tools tcpdump ethtool
    systemctl enable --now openvswitch
}

verify_installation() {
    log "Verifying OVS installation..."
    local ovs_version=$(ovs-vsctl --version | head -1 || echo "Unknown")
    log "OVS Version: $ovs_version"

    if systemctl is-active --quiet openvswitch-switch || systemctl is-active --quiet openvswitch; then
        log "OVS services are running"
    else
        error "OVS services are not running"
    fi

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
        ubuntu|debian) install_ubuntu_debian ;;
        rhel|centos|rocky|almalinux) install_rhel_centos ;;
        fedora) install_fedora ;;
        *) error "Unsupported OS: $os_type. Please install OVS manually." ;;
    esac

    verify_installation
    log "OVS installation completed successfully"
}

main "$@"
