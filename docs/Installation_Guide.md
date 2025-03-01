# SSHistorian Installation Guide

This guide provides detailed instructions for installing SSHistorian on different platforms.

## Requirements

SSHistorian requires the following dependencies:

- Bash 4.0 or later
- SQLite 3
- OpenSSL
- util-linux package (for scriptreplay)
- Python 3 with TermRecord (optional, for HTML playback)

## Quick Installation

For most users, the simplest way to install SSHistorian is using the included installation script:

```bash
git clone https://github.com/maiko/sshistorian.git
cd sshistorian
./install.sh
```

This script will:
- Detect your operating system
- Install necessary dependencies
- Set up directories with correct permissions
- Create a symlink in your PATH
- Offer to generate encryption keys

## Manual Installation

If you prefer to install manually or the automatic script doesn't work for your system, follow these steps:

### 1. Clone the Repository

```bash
git clone https://github.com/maiko/sshistorian.git
cd sshistorian
```

### 2. Install Dependencies

#### Debian/Ubuntu Linux

```bash
sudo apt-get update
sudo apt-get install sqlite3 util-linux openssl

# For HTML playback (optional)
pip3 install TermRecord
```

#### Red Hat/CentOS/Fedora Linux

```bash
sudo yum install sqlite util-linux openssl

# For HTML playback (optional)
pip3 install TermRecord
```

#### macOS

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install sqlite util-linux openssl

# For HTML playback (optional)
pip3 install TermRecord
```

### 3. Set Up Directories

```bash
# Create data directories with secure permissions
mkdir -p data/logs
chmod 700 data data/logs

# Create encryption keys directory
mkdir -p ~/.config/sshistorian/keys
chmod 700 ~/.config/sshistorian/keys
```

### 4. Make Executable and Create Symlink

```bash
# Make the main script executable
chmod +x bin/sshistorian

# Create a symlink in your PATH
sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/sshistorian
```

### 5. Generate Encryption Keys (Optional)

```bash
sshistorian generate-keys
```

## Verifying Installation

To verify your installation:

```bash
# Check version
sshistorian version

# Show help
sshistorian help
```

## Upgrading

To upgrade SSHistorian:

1. Pull the latest changes:
   ```bash
   cd /path/to/sshistorian
   git pull
   ```

2. Run the install script to update dependencies:
   ```bash
   ./install.sh
   ```

## Troubleshooting

### Common Issues

#### "Command not found" Error

If you receive "command not found" when trying to run SSHistorian, check:
- The symlink was created correctly: `ls -l /usr/local/bin/sshistorian`
- Your PATH includes /usr/local/bin: `echo $PATH`

#### Permission Errors

If you encounter permission errors:
- Check the permissions on the `data` directory: `ls -la data`
- Ensure the main script is executable: `chmod +x bin/sshistorian`

#### HTML Playback Not Working

- Verify TermRecord is installed: `pip3 list | grep TermRecord`
- Install if missing: `pip3 install TermRecord`

### Debugging

If you're experiencing issues, run SSHistorian with debug output:

```bash
DEBUG=true sshistorian <command>
```

## Platform-Specific Notes

### macOS

- scriptreplay functionality has limited timing accuracy on macOS
- For the best experience, use the HTML playback option with `--html` flag

### Linux

- On some minimal distributions, you might need to install additional packages like `bash-completion`

## Next Steps

After installation:

1. Read the [User Guide](user_guide/README.md) for basic usage
2. Explore the [Encryption Guide](user_guide/Encryption_Guide.md) for security features
3. Check out the [Plugin Guide](user_guide/Plugin_Guide.md) for extending functionality