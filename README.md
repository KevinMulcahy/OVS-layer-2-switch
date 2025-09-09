# OVS Layer 2 Switch

A comprehensive Open vSwitch (OVS) management solution that provides both command-line and graphical interfaces for managing layer 2 switching operations. This project simplifies OVS bridge management, port configuration, VLAN setup, and OpenFlow rule management through intuitive tools and automation capabilities.

## 🚀 Features

### Core Functionality
- **Bridge Management**: Create, configure, and monitor OVS bridges with ease
- **Port Operations**: Add, remove, and configure switch ports dynamically
- **VLAN Configuration**: Comprehensive VLAN tagging and trunking support
- **Flow Table Management**: Create and modify OpenFlow rules with precision
- **Real-time Monitoring**: Live statistics and traffic analysis
- **Automation Support**: Scriptable operations for DevOps and CI/CD workflows

### User Interface
- **Visual Network Topology**: Interactive network diagram for better visualization
- **Drag-and-Drop Configuration**: Intuitive switch setup interface
- **Real-time Dashboard**: Live network monitoring with comprehensive statistics
- **Flow Rule Editor**: Visual OpenFlow rule creation and editing
- **VLAN Management**: Graphical VLAN configuration interface
- **Multi-theme Support**: Light, dark, and high-contrast themes for accessibility

## 📋 Prerequisites

Before installing, ensure your system meets these requirements:

- **Open vSwitch**: Version 2.15 or higher, installed and running
- **Node.js**: Version 18+ (required for GUI and development features)
- **Python**: Version 3.8+ (required for CLI tools and backend operations)
- **Operating System**: Linux system with network namespaces support
- **Permissions**: Root or sudo access for network operations

### Verify Prerequisites

```bash
# Check Open vSwitch installation
ovs-vsctl --version

# Check Node.js version
node --version

# Check Python version
python3 --version

# Verify network namespace support
ls /proc/*/ns/net | head -5
```

## 🛠️ Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/KevinMulcahy/OVS-layer-2-switch.git
cd OVS-layer-2-switch

# Setup development environment
make setup-dev

# Build all components
make build

# Run comprehensive tests
make test
```

### Manual Installation

If you prefer manual setup or encounter issues with the automated process:

```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Install Node.js dependencies
npm install

# Build the GUI application
npm run build

# Make CLI tools executable
chmod +x bin/ovs-cli
```

## 📚 Usage

### Command Line Interface (CLI)

```bash
# Create a new bridge
./bin/ovs-cli bridge create br0

# Add a port to the bridge
./bin/ovs-cli port add eth0 br0

# Configure VLAN on a port
./bin/ovs-cli vlan set eth0 100

# View bridge statistics
./bin/ovs-cli stats show br0

# Create a flow rule
./bin/ovs-cli flow add br0 "priority=100,in_port=1,actions=output:2"
```

### Graphical User Interface (GUI)

```bash
# Start the GUI application
npm run gui

# Or run in development mode with hot reload
npm run dev
```

The GUI will be available at `http://localhost:3000` by default.

### Python API

```python
from ovs_manager import OVSBridge, OVSPort

# Create and configure a bridge
bridge = OVSBridge('br0')
bridge.create()

# Add ports with VLAN configuration
port = OVSPort('eth0', bridge)
port.add()
port.set_vlan(100)

# Monitor traffic
stats = bridge.get_statistics()
print(f"Packets: {stats.packets}, Bytes: {stats.bytes}")
```

## 📖 Documentation

Comprehensive guides and documentation are available:

- 📘 [CLI Guide](docs/guides/cli-guide.md) - Complete command-line interface reference
- 🖥️ [GUI Guide](docs/guides/gui-guide.md) - Desktop application user manual
- 🌐 [API Documentation](docs/guides/api-documentation.md) - REST API reference and examples
- 🚀 [Deployment Guide](docs/guides/deployment-guide.md) - Production deployment instructions
- 🔧 [Configuration Reference](docs/configuration.md) - Detailed configuration options
- 🐛 [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web GUI       │    │   CLI Tools     │    │   REST API      │
│   (React/JS)    │    │   (Python)      │    │   (FastAPI)     │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────┴───────────┐
                    │   OVS Management Core   │
                    │   (Python Library)      │
                    └─────────────┬───────────┘
                                  │
                    ┌─────────────┴───────────┐
                    │   Open vSwitch (OVS)    │
                    │   Kernel Module         │
                    └─────────────────────────┘
```

## 🧪 Testing

The project includes comprehensive testing suites:

```bash
# Run all tests
make test

# Run specific test suites
make test-unit          # Unit tests only
make test-integration   # Integration tests only
make test-e2e          # End-to-end GUI tests

# Run tests with coverage
make test-coverage

# Run performance benchmarks
make benchmark
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Code style and standards
- Pull request process
- Issue reporting
- Development setup
- Testing requirements

### Development Setup

```bash
# Fork and clone your fork
git clone https://github.com/YOUR_USERNAME/OVS-layer-2-switch.git
cd OVS-layer-2-switch

# Create a feature branch
git checkout -b feature/your-feature-name

# Install development dependencies
make setup-dev

# Run tests before committing
make test
```

## 🐛 Troubleshooting

### Common Issues

**Permission Denied Errors**
```bash
# Ensure you have proper permissions for OVS operations
sudo usermod -aG openvswitch $USER
# Then logout and login again
```

**Port Already Exists**
```bash
# Remove existing port configuration
sudo ovs-vsctl del-port br0 eth0
```

**GUI Not Loading**
```bash
# Check if all dependencies are installed
npm run check-deps

# Clear cache and rebuild
npm run clean && npm run build
```

For more detailed troubleshooting, see our [Troubleshooting Guide](docs/troubleshooting.md).

## 📊 Performance

Typical performance characteristics:
- Bridge creation: < 100ms
- Port addition: < 50ms  
- Flow rule insertion: < 10ms
- GUI responsiveness: < 200ms for most operations
- Memory usage: ~50MB base, +10MB per bridge

## 🔒 Security Considerations

- All network operations require appropriate system permissions
- Flow rules are validated before installation
- GUI includes CSRF protection
- API endpoints use authentication tokens
- Regular security updates for dependencies

## 📈 Roadmap

- [ ] Integration with OpenStack Neutron
- [ ] Support for DPDK acceleration
- [ ] Advanced traffic shaping features
- [ ] Multi-node cluster management
- [ ] Enhanced monitoring and alerting
- [ ] Container orchestration integration

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for complete details.

## 🙏 Acknowledgments

- Open vSwitch community for the excellent switching platform
- Contributors who have helped improve this project
- Network engineering community for feedback and feature requests

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/KevinMulcahy/OVS-layer-2-switch/issues)
- **Discussions**: [GitHub Discussions](https://github.com/KevinMulcahy/OVS-layer-2-switch/discussions)
- **Documentation**: [Wiki](https://github.com/KevinMulcahy/OVS-layer-2-switch/wiki)

---

**Quick Links**: [Installation](#installation) • [Documentation](#documentation) • [Contributing](#contributing) • [License](#license)

