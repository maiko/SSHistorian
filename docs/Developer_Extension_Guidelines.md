# SSHistorian Developer Extension Guidelines

This guide provides detailed information for developers who want to extend SSHistorian's functionality.

## How to Add New Commands

There are two ways to add new commands to SSHistorian:

1. **Core Commands**: Adding commands directly to the main CLI interface
2. **Plugin Commands**: Adding commands through the plugin system

### Adding Core Commands

To add a new command directly to SSHistorian's core CLI:

1. Update the `show_help()` function in `src/ui/cli.sh` to add your command to the help output
2. Add a case statement in the `process_arguments()` function to handle your command
3. Implement the command handler function in an appropriate module
4. Update documentation to reflect the new command

Example:

```bash
# In src/ui/cli.sh, add to show_help():
echo "  mycommand <arg>                   Description of my command"

# In the process_arguments() function, add:
case "$1" in
    # ...existing cases...
    mycommand)
        shift
        my_command_handler "$@"
        ;;
    # ...more cases...
esac

# Implement the handler in an appropriate module:
my_command_handler() {
    # Command implementation
}
```

### Adding Commands via Plugins

The recommended way to add new commands is through the plugin system, which provides better modularity and separation of concerns.

SSHistorian supports adding CLI commands through plugins. See the detailed documentation in [Plugin_CLI_Extension.md](Plugin_CLI_Extension.md).

Basic steps:

1. Create a plugin file in `src/plugins/`
2. Register your plugin with CLI support enabled
3. Register your commands
4. Implement command handlers

Example:

```bash
# Register plugin with CLI support
register_plugin "myplugin" "My Plugin" "1.0.0" "Plugin description" 0 0 1

# Register commands
register_cli_command "myplugin" "mycommand" "Command description" "my_command_handler"

# Implement handler
my_command_handler() {
    # Command implementation
    return 0
}

# Export the handler
export -f my_command_handler
```

Users can then run your command with:

```bash
sshistorian plugin command myplugin mycommand [args...]
```

## How to Extend Database Schema

When extending the database schema, follow these guidelines to ensure compatibility and maintainability:

1. **Create Migrations**: Always create proper migrations for schema changes
2. **Use Parameter Binding**: Always use parameter binding for all SQL queries
3. **Follow Naming Conventions**: Use consistent naming conventions for tables and columns

### Creating a Migration

1. Create a numbered migration file in `src/db/migrations/` (for core database) or `src/plugins/migrations/` (for plugin database)
2. Follow the incremental numbering scheme (e.g., `003_your_migration.sql`)
3. Include SQL statements for both creating new structures and upgrading existing ones
4. Test both clean install and upgrade paths

Example migration:

```sql
-- Migration: Add new_table to store additional data
CREATE TABLE IF NOT EXISTS new_table (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    value TEXT,
    created_at TEXT NOT NULL
);

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_new_table_name ON new_table(name);

-- Update version
PRAGMA user_version = X; -- Replace X with the appropriate version number
```

### Creating Model Functions

After extending the schema, create model functions to interact with your new tables:

1. Create or update model files in `src/db/models/` or `src/models/`
2. Implement CRUD functions using parameter binding
3. Add proper error handling and validation

Example model function:

```bash
# Add a new item
add_new_item() {
    local name="$1"
    local value="$2"
    local id uuid created_at
    
    # Generate UUID
    id=$(generate_uuid)
    created_at=$(get_iso_timestamp)
    
    # Insert using parameter binding
    db_execute_params "INSERT INTO new_table (id, name, value, created_at) 
                      VALUES (:id, :name, :value, :created_at);" \
        ":id" "$id" \
        ":name" "$name" \
        ":value" "$value" \
        ":created_at" "$created_at"
    
    return $?
}
```

## Best Practices for Security

Security is a critical aspect of SSHistorian. Follow these best practices:

1. **Input Validation**: Always validate and sanitize user input
2. **Parameter Binding**: Use parameter binding for all SQL queries to prevent SQL injection
3. **Path Traversal Prevention**: Validate file paths and prevent directory traversal
4. **Least Privilege**: Follow the principle of least privilege
5. **Error Messages**: Avoid revealing sensitive information in error messages
6. **Temporary Files**: Use secure methods for creating temporary files
7. **Command Injection**: Prevent command injection in shell commands

Examples:

```bash
# Good: Using parameter binding for SQL
db_execute_params "SELECT * FROM sessions WHERE host = :host;" ":host" "$user_input"

# Good: Path traversal prevention
if [[ "$user_path" != "${user_path//..}" ]]; then
    log_error "Path traversal attempt detected"
    return 1
fi

# Good: Secure temporary file creation
temp_file=$(mktemp) || {
    log_error "Failed to create temporary file"
    return 1
}
```

## Modular Architecture Overview

SSHistorian follows a modular architecture to ensure maintainability and extensibility:

1. **Core**: Core functionality for SSH session handling
2. **Database**: Database management and data models
3. **UI**: User interface components (CLI)
4. **Utilities**: Common utilities and helper functions
5. **Plugins**: Extension system for additional functionality

When extending SSHistorian, place your code in the appropriate module and maintain separation of concerns:

- **src/core/**: SSH session handling, encryption, etc.
- **src/db/**: Database operations and migrations
- **src/models/**: Data models and business logic
- **src/ui/**: User interface components
- **src/utils/**: Utility functions
- **src/plugins/**: Plugin system and extensions

## Plugin System Documentation

For detailed information about the plugin system, see:

- [Plugin_Architecture.md](Plugin_Architecture.md): Overview of the plugin architecture
- [Plugin_Database.md](Plugin_Database.md): Plugin database schema and operations
- [Plugin_CLI_Extension.md](Plugin_CLI_Extension.md): Extending the CLI via plugins