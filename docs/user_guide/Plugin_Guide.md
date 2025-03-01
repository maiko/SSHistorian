# SSHistorian: Plugin System Guide

This guide provides comprehensive information about SSHistorian's plugin system, including how to use built-in plugins, configure plugin behavior, and leverage plugin functionality to extend SSHistorian.

## Understanding the Plugin System

SSHistorian features a flexible plugin architecture that allows extending the core functionality without modifying the main codebase. Plugins can:

- Add new behaviors before and after SSH sessions
- Apply automatic tagging based on custom rules
- Add new commands to the SSHistorian CLI
- Store and retrieve custom configuration
- Process session data for additional functionality

## Core Plugin Concepts

### Plugin Hooks

Plugins can register functions to be called at specific points:

1. **Pre-Session Hooks**: Run before an SSH session starts
2. **Post-Session Hooks**: Run after an SSH session completes
3. **Command Hooks**: Add new custom commands to SSHistorian

### Plugin States

Each plugin can be in one of two states:
- **Enabled**: The plugin is active and its hooks are executed
- **Disabled**: The plugin is installed but not active

### Plugin Configuration

Each plugin can have its own configuration options stored in the database, allowing users to customize plugin behavior.

## Using the Built-in Plugins

### Listing Available Plugins

To see what plugins are available:

```bash
sshistorian plugin list
```

This shows all installed plugins with their status (enabled/disabled) and description.

### Enabling and Disabling Plugins

To enable a plugin:

```bash
sshistorian plugin enable <plugin_id>
```

To disable a plugin:

```bash
sshistorian plugin disable <plugin_id>
```

### Viewing Plugin Configuration

To see a plugin's configuration options:

```bash
sshistorian plugin config <plugin_id>
```

### Setting Plugin Configuration

To set a configuration value:

```bash
sshistorian plugin config <plugin_id> <key> <value>
```

### Running Plugin Commands

Some plugins add new commands to SSHistorian:

```bash
sshistorian plugin command <plugin_id> <command> [arguments]
```

To see what commands are available:

```bash
sshistorian plugin commands
```

## The Auto Tag Plugin

The most commonly used built-in plugin is the Auto Tag plugin, which automatically adds tags to sessions based on patterns.

### Enabling Auto Tag

```bash
sshistorian plugin enable autotag
```

### Default Auto Tag Behavior

When enabled, Auto Tag automatically applies tags based on:

1. **Host-based tags**:
   - Hosts containing "prod" are tagged as "production"
   - Hosts containing "dev" are tagged as "development"
   - Hosts containing "staging" or "stage" are tagged as "staging"

2. **User-based tags**:
   - Sessions with root user are tagged as "user_root"
   - Each unique remote username gets a "user_NAME" tag

### Configuring Auto Tag

View current Auto Tag configuration:
```bash
sshistorian plugin config autotag
```

Common configuration options:

```bash
# Enable/disable tagging root users
sshistorian plugin config autotag tag_root_user true

# Set production environment patterns
sshistorian plugin config autotag prod_patterns "prod,production"

# Set development environment patterns
sshistorian plugin config autotag dev_patterns "dev,development"

# Set staging environment patterns
sshistorian plugin config autotag staging_patterns "staging,stage"

# Enable user-based tagging
sshistorian plugin config autotag tag_users true

# Enable custom tagging rules
sshistorian plugin config autotag enable_custom_rules true
```

### Custom Auto Tag Rules

You can create custom tagging rules by:

1. Creating a rules file at `~/.config/sshistorian/autotag_rules.sh`
2. Enabling custom rules:
   ```bash
   sshistorian plugin config autotag enable_custom_rules true
   ```

Example rules file:
```bash
#!/usr/bin/env bash
# Custom auto-tagging rules for SSHistorian

# Tag sessions by hostname type
if [[ "$host" =~ db|database ]]; then
    add_tag "database-server"
fi

if [[ "$host" =~ web|www ]]; then
    add_tag "web-server"
fi

# Tag by connection type
if [[ "$command" =~ -X ]]; then
    add_tag "x11-forwarding"
fi

# Tag by session duration
if [[ "$duration" -gt 300 ]]; then
    add_tag "long-session"
fi

# Tag by exit code
if [[ "$exit_code" -ne 0 ]]; then
    add_tag "failed-session"
fi
```

In custom rules, you have access to these variables:
- `$host`: The hostname of the SSH connection
- `$command`: The full SSH command used
- `$user`: Local username running SSHistorian
- `$remote_user`: Username on the remote server
- `$exit_code`: Exit code of the SSH session
- `$duration`: Duration of the session in seconds
- `$uuid`: The session's unique identifier

And these functions:
- `add_tag <tag>`: Add a tag to the session
- `has_tag <tag>`: Check if a tag already exists on the session

## CLI Extension Plugins

Some plugins add new commands to SSHistorian. The Example CLI plugin demonstrates this functionality.

### Enabling the Example CLI Plugin

```bash
sshistorian plugin enable example
```

### Using Plugin Commands

List available plugin commands:
```bash
sshistorian plugin commands
```

Run a plugin command:
```bash
sshistorian plugin command example hello World
```

## Using Plugins Effectively

### Plugin Combinations

Plugins can work together. For example:
- Auto Tag creates tags based on patterns
- Another plugin could use those tags to apply specific processing

### When to Use Plugins

Consider using plugins when:
1. You want consistent, automatic behavior
2. You need to apply the same actions to multiple sessions
3. You want to extend SSHistorian without modifying core code

### Performance Considerations

Plugins run additional code before and after sessions, which might add some overhead. For most use cases, this is negligible, but it's something to consider for performance-sensitive environments.

## Troubleshooting Plugins

### Plugin Not Working

If a plugin isn't working as expected:

1. **Check if it's enabled**:
   ```bash
   sshistorian plugin list
   ```

2. **Check configuration**:
   ```bash
   sshistorian plugin config <plugin_id>
   ```

3. **Enable debugging**:
   ```bash
   DEBUG=true sshistorian <command>
   ```
   This will show detailed plugin execution information.

### Configuration Issues

If plugin configuration isn't being applied:

1. **Verify the configuration key**:
   ```bash
   sshistorian plugin config <plugin_id>
   ```
   Check that you're using the exact key name shown.

2. **Check value format**:
   Some configuration values need specific formats (true/false for booleans, comma-separated for lists).

### Plugin Database Reset

In rare cases, you might need to reset the plugin database:

```bash
sshistorian plugin reset
```

**Warning**: This will delete all plugin configurations and reset plugins to their default state.

## Advanced Plugin Topics

### Plugin Database

Plugins store their configuration in a separate SQLite database (`data/plugins.db`). This separation prevents plugin issues from affecting the main application data.

### Plugin Lifecycle

When you enable a plugin:
1. SSHistorian checks if the plugin is valid
2. The plugin's registration function is called
3. Default configuration is applied
4. The plugin's status is updated in the database

When a session starts:
1. SSHistorian loads all enabled plugins
2. Pre-session hooks are executed in registration order
3. The SSH session runs
4. Post-session hooks are executed in registration order

### Managing Multiple Plugins

If you're using multiple plugins, consider:
1. **Execution Order**: Plugins run in the order they were registered
2. **Interactions**: One plugin's output might affect another's behavior
3. **Configuration Conflicts**: Make sure plugin configurations don't conflict

## Conclusion

SSHistorian's plugin system provides a flexible way to extend functionality without modifying core code. Whether you're using the built-in Auto Tag plugin or creating custom extensions, plugins allow you to tailor SSHistorian to your specific needs.

For developers interested in creating new plugins, see the [Developer Extension Guidelines](../Developer_Extension_Guidelines.md) document for detailed information on the plugin API.