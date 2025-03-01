# SSHistorian User Guide

Welcome to the SSHistorian User Guide. This document provides comprehensive information about how to use SSHistorian effectively.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Basic Usage](#basic-usage)
4. [Managing Sessions](#managing-sessions)
5. [Session Replay](#session-replay)
6. [Tagging Sessions](#tagging-sessions)
7. [Encryption](#encryption)
8. [Configuration](#configuration)
9. [Plugin System](#plugin-system)
10. [Troubleshooting](#troubleshooting)
11. [Command Reference](#command-reference)

## Introduction

SSHistorian is a secure, database-driven tool for recording, encrypting, and playing back SSH sessions. It provides robust functionality for organizations that need to log SSH sessions for compliance, security, or training purposes.

With SSHistorian, you can:
- Record all SSH sessions with timing information
- Replay sessions in the terminal or as HTML
- Encrypt sensitive sessions for security
- Tag and organize sessions with metadata
- Manage and search your session history
- Extend functionality with plugins

## Installation

### Prerequisites

Before installing SSHistorian, ensure you have the following:

- Bash 4.0 or later
- SQLite 3
- OpenSSL (for encryption)
- `script` and `scriptreplay` commands
- Python 3 and pipx (for HTML playback)

### Installation Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/maiko/sshistorian.git
   cd sshistorian
   ```

2. Install runtime dependencies:
   ```bash
   pipx install TermRecord  # For HTML playback support
   ```

3. Set up the command in your PATH:
   ```bash
   chmod +x bin/sshistorian
   ```

   **Option 1 (Recommended)**: Create as a separate command
   ```bash
   sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/sshistorian
   ```

   **Option 2**: Replace the system SSH (use with caution)
   ```bash
   sudo ln -s "$(pwd)/bin/sshistorian" /usr/local/bin/ssh
   ```

### Platform-specific Notes

#### macOS

macOS users need additional tools:
```bash
brew install util-linux  # For scriptreplay support
```

Note: On macOS, terminal replay has limited timing accuracy. For the best experience, use the HTML replay option.

#### Linux

Most Linux distributions have the required tools installed by default. Ensure you have:
```bash
sudo apt-get install util-linux sqlite3 openssl  # For Debian/Ubuntu
# or
sudo yum install util-linux sqlite openssl  # For RHEL/CentOS
```

## Basic Usage

### Recording SSH Sessions

To record an SSH session, simply use SSHistorian as you would use the regular SSH command:

```bash
sshistorian user@hostname
```

This will:
1. Start a new SSH session
2. Record all terminal activity
3. Store session information in the database
4. Save session logs for later replay

### SSH Options

You can pass any standard SSH options to SSHistorian:

```bash
sshistorian -p 2222 user@hostname               # Connect on port 2222
sshistorian -i ~/.ssh/custom_key user@hostname  # Use a specific key file
sshistorian -A user@hostname                    # Forward SSH agent
```

### Running Remote Commands

You can run commands directly:

```bash
sshistorian user@hostname "ls -la"  # Run command and exit
```

### Session Completion

After each session, SSHistorian displays a completion message with:
- Session UUID (for later reference)
- Duration of the session
- Exit code
- Command used

## Managing Sessions

### Listing Sessions

To list your recorded sessions:

```bash
sshistorian sessions
```

This shows an interactive list where you can:
- See session details (host, date, duration, tags)
- Replay sessions
- Add tags
- Filter the list

#### Filtering Sessions

You can filter the session list:

```bash
sshistorian sessions --limit 20                # Show 20 most recent sessions
sshistorian sessions --host production-server  # Filter by hostname
sshistorian sessions --tag important           # Filter by tag
sshistorian sessions --days 7                  # Show last 7 days
sshistorian sessions --exit-code 1             # Show failed sessions
```

### Viewing Session Details

To see detailed information about a specific session:

```bash
sshistorian sessions
```

Then select a session and press `i <num>` to see detailed information, or use:

```bash
sshistorian info <uuid>
```

### Deleting Sessions

To delete a session:

```bash
sshistorian delete <uuid>
```

This removes the session from the database and deletes associated log files.

## Session Replay

There are two ways to replay sessions:

### Terminal Replay

To replay a session in the terminal:

```bash
sshistorian replay <uuid>
```

Or from the sessions list, press `r <num>`.

### HTML Replay

For a shareable HTML replay:

```bash
sshistorian replay <uuid> --html
```

Or from the sessions list, press `h <num>`.

This creates an HTML file with a self-contained playback that can be viewed in any browser.

## Tagging Sessions

Tags help organize and find sessions later.

### Adding Tags

To add a tag to a session:

```bash
sshistorian tag <uuid> "important"
```

Or from the sessions list, press `t <num> "tag"`.

### Removing Tags

To remove a tag:

```bash
sshistorian untag <uuid> "important"
```

Or from the sessions list, press `u <num> "tag"`.

### Finding Sessions by Tag

```bash
sshistorian sessions --tag "important"
```

### Automatic Tagging

The Auto Tag plugin can automatically tag sessions based on patterns:

```bash
sshistorian plugin enable autotag
```

See the [Plugin System](#plugin-system) section for more details.

## Encryption

SSHistorian supports encryption to protect sensitive session data.

### Enabling Encryption

1. Generate encryption keys:
   ```bash
   sshistorian generate-keys
   ```

2. Or enable manually:
   ```bash
   sshistorian config set encryption.enabled true
   sshistorian config set encryption.method asymmetric
   sshistorian config set encryption.public_key /path/to/key.pub
   ```

### How Encryption Works

1. Session logs are encrypted with AES-256-CBC
2. The AES key is encrypted with your public key
3. When replaying, you'll need your private key to decrypt

### Decrypting Sessions

When replaying an encrypted session:
1. SSHistorian detects the session is encrypted
2. You'll be prompted for your private key location (if not configured)
3. The session is decrypted temporarily for replay

## Configuration

SSHistorian uses a database-driven configuration system.

### Viewing Configuration

```bash
sshistorian config
```

### Setting Configuration Values

```bash
sshistorian config set <key> <value>
```

For example:
```bash
sshistorian config set general.log_permissions 0600
sshistorian config set general.session_retention_days 30
```

### Important Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `general.log_permissions` | File permissions for logs | `0600` |
| `general.dir_permissions` | Directory permissions | `0700` |
| `general.session_retention_days` | Days to keep sessions | `7` |
| `general.auto_cleanup` | Automatically clean old logs | `true` |
| `encryption.enabled` | Enable encryption | `false` |
| `encryption.method` | Encryption method | `asymmetric` |
| `encryption.public_key` | Path to public key | - |
| `encryption.private_key` | Path to private key | - |
| `ui.color_enabled` | Enable colors in output | `true` |

## Plugin System

SSHistorian includes a plugin system to extend functionality.

### Managing Plugins

List available plugins:
```bash
sshistorian plugin list
```

Enable a plugin:
```bash
sshistorian plugin enable <plugin_id>
```

Disable a plugin:
```bash
sshistorian plugin disable <plugin_id>
```

Configure a plugin:
```bash
sshistorian plugin config <plugin_id> <key> <value>
```

### Auto Tag Plugin

The Auto Tag plugin automatically tags sessions based on patterns:

```bash
sshistorian plugin enable autotag
```

It applies tags based on:
- Hostname patterns (prod, dev, staging)
- Remote user (root, admin)
- Custom rules

#### Custom Auto Tag Rules

Create custom tagging rules:

1. Create a file at `~/.config/sshistorian/autotag_rules.sh`
2. Enable custom rules:
   ```bash
   sshistorian plugin config autotag enable_custom_rules true
   ```

Example rule file:
```bash
# Custom auto-tagging rules

# Tag database servers
if [[ "$host" =~ db|database ]]; then
    add_tag "database"
fi

# Tag sessions with longer duration
if [[ "$duration" -gt 300 ]]; then
    add_tag "long_session"
fi
```

### CLI Extension Plugins

Plugins can add new commands to SSHistorian. To use a plugin command:

```bash
sshistorian plugin command <plugin_id> <command> [args]
```

To list available plugin commands:
```bash
sshistorian plugin commands
```

## Troubleshooting

### Common Issues

#### Session Replay Not Working

- Check if `scriptreplay` is installed
- On macOS, install with `brew install util-linux`
- Try HTML replay instead

#### Permissions Issues

- Ensure the data directory is writable
- Check file permissions with `ls -la data/`
- Default permissions: `0600` for files, `0700` for directories

#### Encryption Issues

- Verify encryption keys exist and are readable
- Check permissions on key files
- Make sure the public key is valid with `openssl pkey -pubin -in key.pub -text`

### Logs and Debugging

Enable debug mode to see detailed logs:

```bash
DEBUG=true sshistorian command
```

Log files are stored in `data/logs/`.

## Command Reference

Here's a quick reference of all SSHistorian commands:

| Command | Description | Example |
|---------|-------------|---------|
| `sshistorian [options] [user@]hostname [command]` | Connect to SSH and log session | `sshistorian user@host` |
| `sshistorian sessions [options]` | List recorded sessions | `sshistorian sessions --limit 10` |
| `sshistorian replay <uuid> [--html]` | Replay a session | `sshistorian replay abc-123` |
| `sshistorian tag <uuid> <tag>` | Add a tag to a session | `sshistorian tag abc-123 important` |
| `sshistorian untag <uuid> <tag>` | Remove a tag | `sshistorian untag abc-123 important` |
| `sshistorian delete <uuid>` | Delete a session | `sshistorian delete abc-123` |
| `sshistorian generate-keys` | Generate encryption keys | `sshistorian generate-keys` |
| `sshistorian config` | Show configuration | `sshistorian config` |
| `sshistorian config set <key> <value>` | Set configuration | `sshistorian config set encryption.enabled true` |
| `sshistorian plugin list` | List available plugins | `sshistorian plugin list` |
| `sshistorian plugin enable <id>` | Enable a plugin | `sshistorian plugin enable autotag` |
| `sshistorian plugin disable <id>` | Disable a plugin | `sshistorian plugin disable autotag` |
| `sshistorian plugin config <id> <key> <value>` | Configure a plugin | `sshistorian plugin config autotag tag_root true` |
| `sshistorian plugin commands` | List plugin commands | `sshistorian plugin commands` |
| `sshistorian stats` | Show statistics | `sshistorian stats` |
| `sshistorian help` | Show help information | `sshistorian help` |
| `sshistorian version` | Show version information | `sshistorian version` |