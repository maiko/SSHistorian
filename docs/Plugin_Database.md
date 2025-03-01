# SSHistorian Plugin Database System

This document describes the plugin database system in SSHistorian, including the parameter binding approach, migration system, and best practices for plugin developers.

## Overview

SSHistorian uses a dedicated database (`plugins.db`) for storing plugin information, separate from the main application database. This separation ensures:

1. Better modularity and encapsulation
2. Independent plugin lifecycle management
3. Clear separation of concerns between core and plugin functionality
4. Ability to enable/disable plugins without affecting core data

## Database Structure

The plugin database consists of the following key tables:

- `plugins`: Stores plugin registration information
- `plugin_settings`: Stores plugin-specific configuration settings
- `migrations`: Tracks plugin database migrations

### Plugins Table Schema

```sql
CREATE TABLE plugins (
    id TEXT PRIMARY KEY,           -- Plugin unique identifier
    name TEXT NOT NULL,            -- Display name
    version TEXT NOT NULL,         -- Plugin version
    description TEXT,              -- Plugin description
    enabled INTEGER DEFAULT 0,     -- Whether plugin is enabled (1) or disabled (0)
    created_at TEXT NOT NULL,      -- When plugin was registered
    updated_at TEXT NOT NULL,      -- Last time plugin was updated
    has_pre_session_hook INTEGER DEFAULT 0,  -- Whether plugin has pre-session hook
    has_post_session_hook INTEGER DEFAULT 0  -- Whether plugin has post-session hook
);
```

### Plugin Settings Table Schema

```sql
CREATE TABLE plugin_settings (
    plugin_id TEXT NOT NULL,       -- References plugins.id
    key TEXT NOT NULL,             -- Setting key
    value TEXT,                    -- Setting value
    description TEXT,              -- Setting description
    updated_at TEXT NOT NULL,      -- Last updated timestamp
    PRIMARY KEY (plugin_id, key),
    FOREIGN KEY (plugin_id) REFERENCES plugins(id)
);
```

## SQLite Parameter Binding

SSHistorian uses a robust parameter binding approach when executing SQL queries to prevent SQL injection and handle special characters properly.

### Named Parameters vs. Positional Placeholders

When using the SQLite CLI, **named parameters** (`:name`) are strongly preferred over positional placeholders (`?`) because:

1. Named parameters work more reliably with the SQLite CLI
2. They make queries more readable and maintainable
3. They avoid issues with parameter ordering in complex queries
4. They are less prone to errors when parameters are reused in a query

Example of a query using named parameters:

```sql
INSERT INTO plugins (id, name, version) 
VALUES (:id, :name, :version);
```

### Parameter Binding Implementation

The `query_plugin_db_params` function in `src/plugins/plugin_db.sh` provides a secure way to execute parameterized queries:

```bash
# Execute a SQL query with parameters on the plugin database
# Usage: query_plugin_db_params "<sql_query>" [param_name1 param_value1 param_name2 param_value2 ...]
query_plugin_db_params() {
    local sql="$1"
    shift
    local params=("$@")
    
    # Build a temporary file with parameter bindings
    local temp_file=$(mktemp)
    
    # Clear any previous parameters and set output format
    echo ".mode line" > "$temp_file"
    echo ".headers on" >> "$temp_file"
    echo ".param clear" >> "$temp_file"
    
    # Process parameters in pairs: name and value
    for ((i=0; i<${#params[@]}; i+=2)); do
        if [[ $i+1 -lt ${#params[@]} ]]; then
            local param_name="${params[$i]}"
            local param_value="${params[$i+1]}"
            echo ".param set ${param_name} \"${param_value}\"" >> "$temp_file"
        fi
    done
    
    # Add the SQL query and execute
    echo "$sql" >> "$temp_file"
    sqlite3 -batch -header "$PLUGINS_DB_FILE" < "$temp_file"
    local result=$?
    
    # Clean up
    rm -f "$temp_file"
    
    return $result
}
```

## Plugin Database API

Plugins should never directly access the database. Instead, they should use the following API functions:

### Registration and Status

- `register_plugin <id> <name> <version> <description> <has_pre_session> <has_post_session>`: Register a plugin
- `set_plugin_status <id> <enabled>`: Enable or disable a plugin
- `is_plugin_enabled <id>`: Check if a plugin is enabled

### Settings Management

- `set_plugin_setting <plugin_id> <key> <value> [description]`: Set a plugin setting
- `get_plugin_setting <plugin_id> <key> [default]`: Get a plugin setting value

Example of proper plugin registration:

```bash
register_plugin "my_plugin" "My Plugin" "1.0.0" "Description of my plugin" 1 0
```

Example of setting and retrieving settings:

```bash
# Set a plugin setting
set_plugin_setting "my_plugin" "max_items" "10" "Maximum number of items to display"

# Get a plugin setting (with default fallback)
max_items=$(get_plugin_setting "my_plugin" "max_items" "5")
```

## Plugin Migration System

The plugin system includes its own migration mechanism similar to the core database migrations, but specific to plugin database schema changes.

Plugin migrations are stored in the `src/plugins/migrations` directory and follow the same naming convention:

```
NNN_description.sql
```

Existing migrations:
- `001_plugin_schema.sql`: Creates the base plugin and plugin_settings tables
- `002_plugin_migration_system.sql`: Adds plugin migration tracking

### Creating Plugin Migrations

To create a new plugin migration:

1. Create a SQL file in the `src/plugins/migrations` directory with the next available number
2. Include a header comment with the Migration ID
3. Add your SQL statements

Example:

```sql
-- SSHistorian - Custom Plugin Tables
-- Migration ID: 003_custom_plugin_tables
-- Created: 2025-03-01

CREATE TABLE custom_plugin_data (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    data TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (plugin_id) REFERENCES plugins(id)
);
```

## Best Practices for Plugin Developers

1. **Always use named parameters** (`:name`) instead of positional placeholders (`?`)
2. **Never directly access the plugin database** - use the provided API functions
3. **Sanitize and validate all user inputs** before storing in the database
4. **Use a registration function** with proper error handling
5. **Store plugin settings** using the settings API instead of global variables
6. **Follow the plugin lifecycle** for registration, initialization, and cleanup

## Troubleshooting

Common issues and solutions:

- **"NOT NULL constraint failed"**: Ensure all required parameters are provided to `register_plugin`
- **Parameter binding errors**: Use named parameters (`:name`) instead of positional placeholders (`?`)
- **Database file not found**: The plugin system initializes the database automatically, but ensure proper permissions
- **Plugin settings not persisting**: Make sure to use `set_plugin_setting` after successful registration

## Security Considerations

1. **Input validation**: Always validate and sanitize inputs before using them in database operations
2. **Parameter binding**: Always use query_plugin_db_params for parameterized queries
3. **Permissions**: Use the principle of least privilege when accessing plugin data
4. **Error handling**: Implement proper error handling for all database operations