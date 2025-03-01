# SSHistorian

A secure, database-driven tool for recording, encrypting, and playing back SSH sessions with comprehensive security features and test coverage.

SSHistorian helps security professionals, system administrators, and DevOps teams record and manage their SSH sessions by providing:

- **Secure Session Recording**: Automatically record all SSH sessions with timing information
- **Strong Encryption**: Protect sensitive session data with SSH key-based encryption
- **Flexible Playback**: Replay sessions in the terminal or as shareable HTML
- **Powerful Organization**: Add tags, search, and filter your session history
- **Plugin System**: Extend functionality with custom plugins

This project implements a robust SSH session logging system with a modular architecture, strong security controls, and thorough automated testing. It's designed for both individual use and team environments where session recording is needed for compliance, training, or security purposes.

## Features

- **Database-Driven**: Uses SQLite for reliable metadata storage and querying
- **Session Recording**: Automatically records all SSH sessions with timing information
- **UUID-Based Tracking**: Each session has a unique identifier for reliable referencing
- **Compliance-Focused**: Records all SSH activity including failed login attempts
- **Secure Playback**: Replay sessions in terminal or as HTML
- **Strong Encryption**: Optional encryption using SSH keys for maximum security
- **Session Tagging**: Add metadata tags to organize sessions
- **Interactive List View**: Browse, sort, tag, and replay sessions with an intuitive interface
- **Smart Cleanup**: Automatic compression and cleanup of old logs
- **Metadata Tracking**: Store connection information for each session
- **Secure by Default**: Proper file permissions and security controls
- **Consistent Behavior**: Clear session completion messages and statistics
- **SCP/SFTP Support**: Framework for logging file transfers
- **Comprehensive Tests**: Thorough test suite covering all components
- **Modular Design**: Code organized into reusable, testable components

## Project Structure

```
sshistorian/
├── bin/                # Executable scripts
│   └── sshistorian     # Main executable
├── src/                # Source code
│   ├── core/           # Core functionality
│   │   ├── encryption.sh # Encryption functionality
│   │   └── ssh.sh      # SSH session handling
│   ├── db/             # Database modules
│   │   ├── database.sh # Database operations
│   │   └── models/     # Data models
│   │       └── sessions.sh # Session model
│   ├── plugins/        # Plugin system
│   │   ├── plugin_manager.sh # Plugin management framework
│   │   └── autotag.sh  # Auto Tag plugin
│   ├── ui/             # User interface
│   │   └── cli.sh      # Command line interface
│   └── utils/          # Utility functions
│       ├── common.sh   # Common utilities
│       ├── constants.sh # Global constants
│       └── migration.sh # Migration utilities
├── data/               # Runtime data
│   ├── logs/           # Session recordings
│   └── sshistorian.db  # SQLite database
├── examples/           # Example configuration and plugin rules
├── tests/              # Test suite
│   ├── core/           # Core module tests
│   ├── db/             # Database tests
│   ├── ui/             # UI tests
│   ├── utils/          # Utility tests
│   ├── fixtures/       # Test data files
│   ├── helpers/        # Test helper libraries
│   ├── run_tests.sh    # Test runner script
│   └── test_helper.bash # Common test utilities
├── README.md           # Project documentation
└── CONTRIBUTING.md     # Contribution guidelines
```

## Plugin System

SSHistorian includes a flexible plugin system that allows you to extend functionality with pre-session and post-session hooks.

### Available Plugins

- **Auto Tag**: Automatically tags sessions based on hostname, remote user, and other metadata
  - Tags root user sessions as `user_root`
  - Tags environments (production, development, staging) based on hostname patterns
  - Supports custom tagging rules

### Managing Plugins

```bash
# List available plugins
sshistorian plugin list

# Enable a plugin
sshistorian plugin enable autotag

# Disable a plugin
sshistorian plugin disable autotag

# Configure a plugin setting
sshistorian plugin config autotag tag_root_user true

# Get a plugin setting
sshistorian plugin get autotag prod_patterns
```

### Custom Auto Tag Rules

You can create a custom rules file at `~/.config/sshistorian/autotag_rules.sh` to implement your own tagging logic. Enable custom rules with:

```bash
sshistorian plugin config autotag enable_custom_rules true
```

See the `examples/autotag_rules.sh` file for a sample implementation.

## Installation

### Quick Install

1. Clone this repository:
```bash
git clone https://github.com/maiko/sshistorian.git
cd sshistorian
```

2. Run the installation script:
```bash
./install.sh
```
This will install SSHistorian system-wide and set up all dependencies.

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/maiko/sshistorian.git
cd sshistorian
```

2. Install runtime dependencies:
```bash
# For Debian/Ubuntu
sudo apt-get install sqlite3 util-linux openssl

# For macOS
brew install sqlite util-linux openssl

# For HTML playback support (optional)
pip3 install TermRecord || pip install TermRecord
```

3. Create a symlink for the main script in your PATH:
```bash
chmod +x bin/sshistorian
# Either create as a separate command (recommended)
sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/sshistorian
# Or create as 'ssh' (replacing the system ssh - use with caution)
# sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/ssh
```

4. Install test dependencies (optional, for development):
```bash
# For Debian/Ubuntu
sudo apt-get install bats shellcheck

# For macOS
brew install bats-core shellcheck

# Install test submodules
./tests/install_submodules.sh
```

### macOS-specific setup

macOS users may need additional tools for full functionality:

```bash
# For scriptreplay support (terminal replay)
brew install util-linux
```

Note: On macOS, terminal replay has limited timing accuracy due to platform limitations. For the best experience, use the HTML replay option with `--html` flag.

## Usage

### Basic SSH Session Recording

```bash
sshistorian user@hostname
```

This will establish an SSH connection and automatically record the session. All sessions are logged with a consistent "SSH Session Completed" message at the end, including failed login attempts (for compliance requirements).

### Interactive Session Management

List recorded sessions with interactive options:
```bash
sshistorian sessions [--limit N] [--days N] [--host hostname] [--tag tagname]
```

In the interactive session list, you can:
- Press **r <num>** - Replay a session
- Press **h <num>** - View HTML playback of a session
- Press **t <num> "tag"** - Add a tag to a session
- Press **f** - Filter sessions
- Press **s** - Change sort order
- Press **q** - Quit the list view

### Command-line Session Management

Replay a session:
```bash
sshistorian replay <uuid>
```

Generate HTML playback:
```bash
sshistorian replay <uuid> --html
```

Tag a session:
```bash
sshistorian tag <uuid> "Important debug session"
```

View statistics about session logs:
```bash
sshistorian stats
```

Check the configuration:
```bash
sshistorian config
```

Edit the configuration:
```bash
sshistorian config edit
```

### Comprehensive User Guide

For a complete guide with detailed instructions and examples, see the [User Guide](docs/user_guide/README.md).

Additional guides are available for specific features:
- [Encryption Guide](docs/user_guide/Encryption_Guide.md)
- [Plugin System Guide](docs/user_guide/Plugin_Guide.md)
- [Security Documentation](docs/security/README.md)

### Encryption

SSHistorian supports two encryption methods:

1. **Generate Dedicated Keys (Recommended)**:
   ```bash
   sshistorian generate-keys
   ```
   This will create a dedicated RSA key pair for encryption in `~/.config/sshistorian/` and automatically update your configuration.

2. **Configure Manually**:
   ```bash
   sshistorian config edit
   ```

   ```bash
   # Enable encryption
   encryption.enabled=true
   # Choose encryption method: "symmetric" or "asymmetric"
   encryption.method=asymmetric
   # Set path to public key (for asymmetric encryption)
   encryption.key_path=/path/to/your/public_key.pub
   ```

With asymmetric encryption:
- Your sessions are automatically encrypted with your public key
- When replaying, you'll be prompted for your private key location
- This approach provides strong security without interactive password prompts

## Configuration

SSHistorian creates a configuration file at `~/.config/sshistorian/config` on first run. You can customize the behavior by editing this file directly or using `sshistorian config edit`. 

A comprehensive example configuration can be found in the `sshistorian.conf.example` file with detailed comments explaining each option.

## Security

SSHistorian takes security seriously:
- All log files have 0600 permissions by default
- Log directories have 0700 permissions
- Strong encryption is available (AES-256-CBC)
- With asymmetric encryption, decryption requires your private key
- SSH credentials are never logged
- SQL injection protections via parameter binding
- Command injection prevention using array-based execution
- Context-aware input sanitization for all user inputs
- Secure temporary file handling with proper permissions
- Path validation to prevent directory traversal attacks

## Development and Testing

The project follows a modular architecture with comprehensive automated testing.

### Architecture

- **Database-Driven**: SQLite database for metadata storage and retrieval
- **Model-View Separation**: Clear separation between data models and UI components
- **Core Modules**: Functionality divided into logical, single-purpose modules
- **Utility Layer**: Common functions abstracted for reuse across the codebase

### Testing Infrastructure

The project includes a comprehensive test suite built with Bats (Bash Automated Testing System):

- **Test Categories**: Tests organized by module (utils, db, core, ui)
- **Isolated Testing**: Each test runs in its own environment
- **Mocking Support**: System for mocking external commands and dependencies
- **Test Helpers**: Common functions for test setup and assertions
- **Test Runner**: Script to run all tests and generate a report

To run the tests:

```bash
./tests/run_tests.sh
```

To run a specific test:

```bash
bats tests/path/to/test_file.bats
```

### Key Improvements

1. **Database Integration**: Replaced file-based metadata with SQLite database
2. **UUID-Based Identification**: Reliable session identification with UUIDs
3. **Modular Structure**: Code organized into logical, focused modules
4. **Enhanced Security**: SSH key-based encryption for maximum security
5. **Comprehensive Testing**: Thorough test coverage of all components
6. **Improved Error Handling**: Robust error checking throughout
7. **Configuration Management**: Advanced configuration with database backend
8. **Enhanced CLI**: Intuitive commands for all operations
9. **Documentation**: Thorough documentation of code and architecture
10. **Cross-Platform Compatibility**: Consistent behavior across operating systems

## Implementation Details

- Uses `script` command for session recording with timing data
- Terminal replay through `scriptreplay` for accurate session playback
- HTML playback via `TermRecord` for shareable recordings
- Session data stored in SQLite database with UUIDs as primary keys
- Session recordings stored in `data/logs/` with UUID-based filenames
- Each session produces `.log` and `.timing` files
- Encryption uses SSH keys (asymmetric) or AES-256 (symmetric)
- Database migrations handle schema evolution
- Comprehensive error handling throughout
- Testing with Bats framework for reliable quality assurance

## Test Suite Architecture

The test suite is organized into several components:

- **Test Helper**: Common functions for all tests (`test_helper.bash`)
- **Test Categories**: Tests grouped by module (utils, db, core, ui)
- **Test Fixtures**: Sample data for testing
- **Mock System**: Framework for mocking external commands
- **Test Runner**: Script to run all tests with reporting
- **Helper Libraries**:
  - bats-support: Core test helpers
  - bats-assert: Test assertions
  - bats-file: File-related test helpers

Each test follows this structure:
1. Setup test environment with isolated directories and database
2. Source the relevant module(s)
3. Run tests with detailed assertions
4. Clean up the test environment

This approach ensures tests are:
- Isolated: No test affects another
- Repeatable: Same results every time
- Fast: Quick to run the entire suite
- Descriptive: Clear failure messages

## License

[GNU General Public License v3.0](LICENSE)

## Authors and Contributors

- **Maiko BOSSUYT** - *Initial work* - [maiko](https://github.com/maiko)
- **Claude** - *Code improvements and documentation* - [Anthropic](https://www.anthropic.com)