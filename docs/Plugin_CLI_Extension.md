# Plugin CLI Extension System

The SSHistorian plugin system now supports CLI extensions, allowing plugins to add new commands to the CLI interface. This document explains how to create plugins that extend the CLI and how to use these commands.

## Overview

Plugins can now register custom CLI commands that integrate seamlessly with the SSHistorian command-line interface. This allows plugin developers to add new functionality that users can access through familiar command patterns.

## Plugin Development

### Registering CLI Commands

To create a plugin that extends the CLI, you need to:

1. Register your plugin with the `has_cli_commands` flag set to `1`
2. Register each CLI command using the `register_cli_command` function
3. Implement handler functions for each command

Here's a step-by-step guide:

#### 1. Plugin Registration

When registering your plugin, set the `has_cli_commands` flag:

```bash
# Register the plugin with CLI command support
register_plugin "myplugin" "My Plugin" "1.0.0" "A plugin that extends the CLI" 0 0 1
```

The parameters are:
- Plugin ID
- Plugin name
- Version
- Description
- Has pre-session hook (0/1)
- Has post-session hook (0/1)
- Has CLI commands (0/1)

#### 2. Command Registration

Register each command your plugin provides:

```bash
# Register a CLI command
register_cli_command "myplugin" "stats" "Show custom statistics" "myplugin_stats_handler"
```

The parameters are:
- Plugin ID: Must match your plugin's ID
- Command name: The name users will type (alphanumeric plus colon, underscore, or hyphen)
- Description: Short description shown in help
- Handler function: Name of the function that will handle this command

You can register multiple commands for a single plugin:

```bash
register_cli_command "myplugin" "list" "List custom items" "myplugin_list_handler"
register_cli_command "myplugin" "analyze" "Analyze something" "myplugin_analyze_handler"
```

#### 3. Implement Handler Functions

Each handler function should accept arguments and process the command:

```bash
# Handler for the stats command
myplugin_stats_handler() {
    echo "My Plugin Statistics:"
    echo "====================="
    
    # Implement your command logic here
    echo "Total items: 42"
    
    return 0
}

# Handler for the list command
myplugin_list_handler() {
    echo "My Plugin Items:"
    echo "================"
    
    # Process any arguments
    local limit=10
    if [[ "$1" == "--limit" && -n "$2" ]]; then
        limit="$2"
    fi
    
    # Implement your command logic here
    echo "Showing $limit items..."
    
    return 0
}
```

### Example Plugin with CLI Commands

Here's a complete example of a plugin that adds CLI commands:

```bash
#!/usr/bin/env bash
#
# SSHistorian - Example CLI Extension Plugin
# Demonstrates how to add CLI commands to SSHistorian

# Register the plugin (with CLI commands enabled)
register_plugin "example" "Example Plugin" "1.0.0" "Demonstrates CLI extensions" 0 0 1

# Register CLI commands
register_cli_command "example" "hello" "Display a greeting" "example_hello_handler"
register_cli_command "example" "count" "Count to a number" "example_count_handler"

# Command handler for 'hello' command
example_hello_handler() {
    local name="${1:-World}"
    echo "Hello, $name!"
    return 0
}

# Command handler for 'count' command
example_count_handler() {
    local max="${1:-5}"
    
    # Validate input
    if ! [[ "$max" =~ ^[0-9]+$ ]]; then
        log_error "Invalid number: $max"
        return 1
    fi
    
    echo "Counting to $max:"
    for ((i=1; i<=max; i++)); do
        echo "$i"
    done
    
    return 0
}
```

## Using Plugin CLI Commands

Users can access plugin CLI commands in two ways:

### 1. Using the `plugin command` syntax:

```bash
# Format: sshistorian plugin command <plugin-id> <command> [args...]
sshistorian plugin command example hello Alice
# Output: Hello, Alice!

sshistorian plugin command example count 3
# Output: 
# Counting to 3:
# 1
# 2
# 3
```

### 2. View available plugin commands:

```bash
sshistorian plugin commands
```

This will show a table of all available plugin commands from all enabled plugins:

```
Available plugin commands:

PLUGIN ID         COMMAND             DESCRIPTION
----------------  ------------------  ------------------------------------------
example           hello               Display a greeting
example           count               Count to a number
```

## Best Practices

1. **Command Naming**: Use clear, descriptive command names that don't conflict with built-in commands
2. **Error Handling**: Always validate inputs and return appropriate error codes
3. **Help and Documentation**: Provide clear help messages within your commands
4. **Output Formatting**: Use the color constants (${BLUE}, ${GREEN}, etc.) for consistent styling
5. **Performance**: Keep commands efficient; use the timeout mechanism for long-running operations
6. **Security**: Validate all user inputs to prevent command injection or other security issues

## Advanced Features

### Command Namespaces

For complex plugins, you can use colons to create command namespaces:

```bash
register_cli_command "myanalysis" "report:daily" "Generate daily report" "daily_report_handler"
register_cli_command "myanalysis" "report:weekly" "Generate weekly report" "weekly_report_handler"
```

Users would call these with:

```bash
sshistorian plugin command myanalysis report:daily
```

### Dynamic Help

You can implement a help system within your commands:

```bash
mycommand_handler() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: sshistorian plugin command myplugin mycommand [options]"
        echo "Options:"
        echo "  --format FORMAT   Output format (text, json, csv)"
        echo "  --limit N         Limit results to N items"
        return 0
    fi
    # Regular command implementation
}
```

## Troubleshooting

If your plugin commands aren't working:

1. Ensure the plugin is registered with `has_cli_commands=1`
2. Make sure the plugin is enabled (`sshistorian plugin enable <id>`)
3. Verify the command is registered correctly
4. Check that handler functions are properly defined and exported
5. Look for error messages in the logs