# Contributing to SSHistorian

Thank you for your interest in contributing to the SSHistorian project! This document outlines the guidelines for contributing to the project, including coding standards, testing procedures, and project structure information.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/sshistorian.git` (replace "yourusername" with your GitHub username)
   - Original repository: https://github.com/maiko/sshistorian
3. Set up your development environment following the README instructions
4. Install the development dependencies: `brew install bats-core shellcheck`
5. Install the test helpers: `./tests/install_submodules.sh`

Before submitting a pull request, please ensure your code passes all tests and follows the coding standards outlined below.

## Commands
- **Run Tests**: 
  - All tests: `./tests/run_tests.sh`
  - Single test: `bats tests/path/to/test_file.bats`
  - Install test helpers: `./tests/install_submodules.sh` (using Git submodules)
- **Syntax Check**: 
  - Main script: `bash -n bin/sshistorian`
  - All modules: `for f in src/**/*.sh; do bash -n "$f"; done`
- **Lint**: 
  - Main script: `shellcheck bin/sshistorian`
  - All modules: `shellcheck src/**/*.sh`
- **Install Dependencies**: 
  - Runtime: `pipx install TermRecord`
  - Testing: `brew install bats-core shellcheck`
- **Run**: 
  - Create symlink: `ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/sshistorian`
  - Or replace system SSH: `sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/ssh`
- **Usage**: `sshistorian [options] [user@]hostname` to log a session
- **Commands**:
  - **List Sessions**: `sshistorian list [--limit N] [--days N] [--mod-time]`
  - **Replay Session**: `sshistorian replay <session-id> [--html]`
  - **Tag Session**: `sshistorian tag <session-id> "tag message"`
  - **Clean Logs**: `sshistorian clean [--force]`
  - **Generate Keys**: `sshistorian generate-keys` (for asymmetric encryption)
  - **View Config**: `sshistorian config`
  - **Edit Config**: `sshistorian config edit`
  - **Show Stats**: `sshistorian stats`
  - **Show Version**: `sshistorian version`

## Project Structure
```
SSHistorian/
├── bin/
│   └── sshistorian        # Main executable script
├── src/
│   ├── config/            # Configuration files
│   │   └── defaults.sh    # Default configuration values
│   ├── core/              # Core functionality
│   │   ├── encryption.sh  # Encryption and decryption
│   │   └── ssh.sh         # SSH session handling
│   ├── db/                # Database management
│   │   ├── database.sh    # SQLite operations
│   │   ├── migrations/    # Database schema migrations
│   │   └── models/        # Data models
│   │       └── sessions.sh # Session management
│   ├── ui/                # User interface components
│   │   ├── cli.sh         # Command line interface
│   │   └── tui/           # Terminal user interface components
│   └── utils/             # Utility functions
│       └── common.sh      # Common logging and utilities
├── data/                  # Runtime data
│   ├── logs/              # Session log files
│   └── sshistorian.db     # SQLite database
└── tests/                 # Test infrastructure
    ├── core/              # Tests for core modules
    ├── db/                # Tests for database modules
    ├── ui/                # Tests for UI modules
    ├── utils/             # Tests for utility functions
    ├── run_tests.sh       # Test runner
    └── test_helper.bash   # Common test utilities
```

## Session Behavior
- All SSH sessions are logged, including failed login attempts
- The "SSH Session Completed" message is displayed after every session
- Statistics are shown after successful completion
- For compliance reasons, all sessions are treated equally from a logging perspective

## Interactive Options
In the session list view:
- **r <num>** - Replay a session
- **h <num>** - View HTML playback of a session
- **t <num> "tag"** - Add a tag to a session
- **o** - Toggle sort order between original creation date and last modified date
- **q** - Quit the list view

## Code Style
- **Formatting**: 4-space indentation, 80-column limit
- **Naming**: snake_case for variables and functions
- **Function Style**: All functionality should be in functions with clear descriptions
- **Error Handling**: Use `set -euo pipefail`, with specific error messages
- **Comments**: Each function should have a descriptive comment
- **Output**: Use color constants for terminal output
- **Logging**: Use log_message/log_error functions for consistent formatting
- **Constants**: Define configuration variables at the top or in config files
- **Security**: Sanitize user input, especially when used in commands
- **Modularity**: Group related functions in separate files
- **Exports**: Export functions that need to be available across modules

## File Organization
- Logs stored in `$HOME/sshistorian_logs` by default (configurable via LOG_BASE_DIR)
- Config stored in `$HOME/.config/sshistorian/config`
- Each session creates .log, .timing, and .meta files
- Files can be compressed with gzip/xz and optionally encrypted

## Features
- Session recording and playback
- HTML playback with TermRecord
- Session tagging for organization
- Log file compression and encryption (symmetric or asymmetric)
- Automatic cleanup of old logs
- Support for SCP/SFTP (partial)
- Configuration management and validation
- Enhanced command-line interface
- Modular, maintainable code structure

## Encryption
- Two encryption methods available:
  1. **Symmetric**: Uses AES-256-CBC with random keys stored alongside encrypted files
  2. **Asymmetric**: Uses RSA public key for encryption, private key required for decryption
- Generate keys with `sshistorian generate-keys`
- Configure in ~/.config/sshistorian/config by setting:
  ```
  ENABLE_ENCRYPTION=true
  ENCRYPTION_METHOD="asymmetric"  # or "symmetric"
  ```

## Testing Guidelines
- **CRITICAL**: Always run tests after making code changes: `./tests/run_tests.sh`
- When adding new features, add corresponding tests
- Test categories should match the module structure (utils, db, core, ui)
- Each test should run in isolation with a clean environment
- Mock external commands and dependencies when testing
- Use assert functions from bats-assert for clear test expectations
- Tests should have clear descriptions that explain what they're testing
- Use setup/teardown functions to initialize and clean test environment
- Remember to check both success and failure conditions

## Test Development Process
1. Create a new test file in the appropriate directory (e.g., `tests/core/new_feature_test.bats`)
2. Use existing tests as templates for structure and style
3. Write tests before or alongside feature implementation (TDD approach)
4. Ensure tests are independent and don't rely on global state
5. For complex functionality, test edge cases thoroughly
6. Update the test suite when refactoring or changing behavior

## Development Guidelines
- Always run syntax check before committing: `bash -n file.sh`
- Use shellcheck for linting: `shellcheck file.sh`
- When adding new features:
  1. Update both CLAUDE.md and README.md
  2. Add appropriate tests in the tests directory
  3. Run tests to verify functionality
- Test with various combinations of symlinks (ssh, ssh-log)
- Verify file permissions are set correctly for security-sensitive files
- Check for cross-platform compatibility (Linux vs macOS differences)
- Follow database migration patterns when changing schema
- Maintain backward compatibility with existing session data
- Use the database abstraction layer for all data operations