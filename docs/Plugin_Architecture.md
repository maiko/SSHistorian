# SSHistorian Plugin Architecture

This document describes the plugin architecture of SSHistorian, focusing on the separation of concerns and overall design principles.

## Architecture Overview

The plugin system is designed with clean separation of concerns, following modular design principles:

1. **Plugin Manager**: Handles plugin registration, lifecycle, and configuration
2. **Plugin Database**: Manages plugin-specific database operations
3. **Plugin Hooks**: Implements the hook system for event-driven plugin execution

This separation ensures each component has a single responsibility, making the code more maintainable and easier to extend.

## Core Components

### Plugin Manager (`plugin_manager.sh`)

The Plugin Manager is responsible for:

- Plugin registration and initialization
- Plugin lifecycle management (enable/disable)
- Plugin configuration storage and retrieval
- Loading plugin files
- Plugin discovery and enumeration

It provides a high-level API for other parts of the system to interact with plugins.

### Plugin Database (`plugin_db.sh`)

The Plugin Database module focuses on:

- Database initialization and schema management
- Migration handling for database changes
- Low-level database operations specific to plugins
- Database query execution with parameter binding

This module encapsulates all database operations, providing a clean API for the plugin manager.

### Plugin Hooks (`plugin_hooks.sh`)

The Plugin Hooks module handles:

- Hook registration for different event types
- Hook execution with proper timing and error handling
- Managing plugin execution order
- Timeout handling for long-running operations
- Cleanup for interrupted operations

By separating hook execution from plugin management, we achieve cleaner code and better testability.

## Plugin Lifecycle

1. **Registration**: Plugins register themselves with the Plugin Manager
2. **Initialization**: The Plugin Manager initializes the plugin database if needed
3. **Hook Registration**: Plugins register hooks for various events
4. **Configuration**: Default or user settings are stored in the plugin database
5. **Execution**: Hooks are triggered by system events
6. **Cleanup**: Resources are properly released after plugin execution

## Hooks System

SSHistorian implements an event-driven architecture for plugins using hooks. Hooks are registered for specific events:

- **Pre-Session Hooks**: Executed before an SSH session starts
- **Post-Session Hooks**: Executed after an SSH session completes

### Hook Registration

Plugins register hooks by specifying their capabilities during registration:

```bash
register_plugin "autotag" "Auto Tag" "1.0.0" "Automatically tag sessions based on patterns" 0 1
```

Hook registration creates an association between the plugin ID and the event.

### Hook Execution

When an event occurs, SSHistorian:

1. Identifies all plugins registered for that event
2. Checks if each plugin is enabled
3. Executes each plugin's hook function with appropriate parameters
4. Handles timeouts to prevent long-running hooks from blocking
5. Propagates results while ensuring proper error handling

## Plugin Configuration

Each plugin can store and retrieve configuration settings using:

```bash
set_plugin_setting "plugin_id" "setting_key" "setting_value" "Description"
get_plugin_setting "plugin_id" "setting_key" "default_value"
```

These settings are stored in the plugin database, allowing persistent configuration without requiring separate files.

## Plugin Development

To create a new plugin:

1. Create a new `.sh` file in the `src/plugins/` directory
2. Source necessary dependencies
3. Register the plugin with capabilities
4. Implement hook functions
5. Store default configuration
6. Ensure proper error handling

Example:

```bash
#!/usr/bin/env bash
# My Custom Plugin

# Register the plugin (id, name, version, description, pre_hook, post_hook)
register_plugin "myplugin" "My Plugin" "1.0.0" "Plugin description" 1 1

# Set default configuration
set_plugin_setting "myplugin" "enabled_by_default" "true" "Enable this plugin by default"

# Implement pre-session hook
myplugin_pre_session_hook() {
    local session_id="$1"
    local host="$2"
    local command="$3"
    local remote_user="$4"
    
    # Plugin logic here
    
    return 0
}

# Implement post-session hook
myplugin_post_session_hook() {
    local session_id="$1"
    local exit_code="$2"
    local duration="$3"
    
    # Plugin logic here
    
    return 0
}
```