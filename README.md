# my-new-repo

OVS-layer-2-switch

![OVS L2 Switch Manager](docs/assets/images/project-banner.png)

[![Build Status](https://github.com/KevinMulcahy/my-new-repo/workflows/CI/badge.svg)](https://github.com/KevinMulcahy/my-new-repo/actions)
[![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://KevinMulcahy.github.io/my-new-repo)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

## 🌐 Features

### 🖥️ Command Line Interface (CLI)
- **Bridge Management**: Create, configure, and monitor OVS bridges
- **Port Operations**: Add, remove, and configure switch ports
- **VLAN Configuration**: Manage VLAN tagging and trunking
- **Flow Table Management**: Create and modify OpenFlow rules
- **Real-time Monitoring**: Live statistics and traffic analysis
- **Automation Support**: Scriptable operations for DevOps workflows

### 🎨 Graphical User Interface (GUI)
- **Visual Network Topology**: Interactive network diagram
- **Drag-and-Drop Configuration**: Intuitive switch setup
- **Real-time Dashboard**: Live network monitoring and statistics
- **Flow Rule Editor**: Visual OpenFlow rule creation
- **VLAN Management**: Graphical VLAN configuration
- **Multi-theme Support**: Light, dark, and high-contrast themes

## 🚀 Quick Start

### Prerequisites
- Open vSwitch 2.15+ installed and running
- Node.js 18+ (for GUI and development)
- Python 3.8+ (for CLI and tools)
- Linux system with network namespaces support

### Installation
```bash
# Clone repository
git clone https://github.com/KevinMulcahy/my-new-repo.git
cd my-new-repo

# Setup development environment
make setup-dev

# Build all components
make build

# Run tests
make test
```

## 📖 Documentation

- 📘 **[CLI Guide](docs/guides/cli-guide.md)** - Command-line interface documentation
- 🖥️ **[GUI Guide](docs/guides/gui-guide.md)** - Desktop application user guide
- 🌐 **[API Documentation](docs/guides/api-documentation.md)** - REST API reference
- 🚀 **[Deployment Guide](docs/guides/deployment-guide.md)** - Installation and deployment

## 🤝 Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## 📄 License

This project is licensed under the Apache License 2.0 - see [LICENSE](LICENSE) for details.
