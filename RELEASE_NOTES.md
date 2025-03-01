# SSHistorian 2025.03.RC1 Release Notes

We're excited to announce the first public release candidate of SSHistorian, a secure, database-driven tool for recording, encrypting, and playing back SSH sessions. This release represents several months of development and testing, focusing on security, modularity, and extensibility.

## Overview

SSHistorian is designed to help security professionals, system administrators, and DevOps teams securely record and manage their SSH sessions with features like encryption, tagging, and flexible playback options.

## Key Features

### Secure Session Recording

- **Automatic Recording**: Records all SSH sessions with timing information
- **UUID-Based Tracking**: Each session has a unique identifier for reliable referencing
- **Secure File Handling**: Proper file permissions and secure cleanup of sensitive data

### Strong Security Controls

- **Database-Driven**: SQLite for reliable metadata storage with parameterized queries
- **Hybrid Encryption**: AES-256-CBC for content + RSA for key protection
- **Path Traversal Protection**: Comprehensive validation of all file paths
- **Input Sanitization**: Context-aware sanitization for all user inputs

### Session Management

- **Session Tagging**: Add metadata tags to organize sessions
- **Interactive List View**: Browse, sort, tag, and replay sessions
- **Filtering Options**: Filter by host, tag, date, or other criteria

### Flexible Playback

- **Terminal Replay**: Accurate playback in the terminal with timing
- **HTML Export**: Generate shareable HTML replays with timing
- **Encrypted Storage**: Decrypt sessions on-demand for playback

### Extensible Plugin System

- **Plugin Architecture**: Extend functionality with custom plugins
- **CLI Extensions**: Add new commands via plugins
- **Automatic Tagging**: Tag sessions based on patterns

## Installation

SSHistorian can be installed using the included installation script:

```bash
git clone https://github.com/maiko/sshistorian.git
cd sshistorian
./install.sh
```

For detailed installation instructions, see the [Installation Guide](docs/user_guide/README.md).

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[User Guide](docs/user_guide/README.md)**: Complete usage instructions and examples
- **[Encryption Guide](docs/user_guide/Encryption_Guide.md)**: Detailed information on encryption features
- **[Plugin Guide](docs/user_guide/Plugin_Guide.md)**: How to use and create plugins
- **[Security Documentation](docs/security/README.md)**: Security model details

## Changes in this Release

This is the first public release, including:

- Complete modular architecture with separation of concerns
- Robust plugin system with CLI extension support
- Comprehensive error handling and security controls
- Full test coverage for all components
- Detailed documentation for users and developers

## Known Issues

- macOS scriptreplay has limited timing accuracy - use HTML replay for accurate playback
- TermRecord needs to be installed separately for HTML playback

## Acknowledgements

- Special thanks to Claude (Anthropic) for assistance with development and documentation

## License

SSHistorian is licensed under the GNU General Public License v3.0.