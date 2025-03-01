#!/usr/bin/env bash
#
# SSHistorian - Plugin Manager
# Handles plugin registration, configuration and lifecycle management

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${SCRIPT_DIR}/../utils/common.sh"
fi

# Source database module if not already loaded
if ! command -v init_database &>/dev/null; then
    # shellcheck source=../db/database.sh
    source "${SCRIPT_DIR}/../db/database.sh"
fi

# Source plugin database module if not already loaded
if ! command -v ensure_plugin_database &>/dev/null; then
    # shellcheck source=./plugin_db.sh
    source "${SCRIPT_DIR}/plugin_db.sh"
fi

# Source plugin hooks module if not already loaded
if ! command -v register_pre_session_hook &>/dev/null; then
    # shellcheck source=./plugin_hooks.sh
    source "${SCRIPT_DIR}/plugin_hooks.sh"
fi

# Array to store registered plugins
declare -a REGISTERED_PLUGINS=()

# Initialize plugins database schema
initialize_plugin_schema() {
    log_debug "Initializing plugin database schema"
    
    # First ensure database file and core tables exist
    ensure_plugin_database
    
    # Now run migrations to add actual schema
    log_debug "Running plugin migrations"
    run_plugin_migrations || {
        log_error "Failed to run plugin migrations"
        return 1
    }
    
    # Verify plugins table exists after migrations
    if ! plugin_table_exists "plugins"; then
        log_error "Plugin schema initialization failed - 'plugins' table not found"
        return 1
    fi
    
    log_success "Plugin database schema initialized successfully"
    return 0
}

# Register a plugin with the system
# Usage: register_plugin <id> <name> <version> <description> <has_pre_session> <has_post_session> <has_cli_commands>
register_plugin() {
    local id="$1"
    local name="$2"
    local version="$3"
    local description="$4"
    local has_pre_session="${5:-0}"
    local has_post_session="${6:-0}"
    local has_cli_commands="${7:-0}"
    local now
    
    # Debug logging of parameters
    log_debug "Registering plugin with ID: '$id', Name: '$name', Version: '$version'"
    
    # Validate inputs - all required fields must be provided
    if [[ -z "$id" || -z "$name" || -z "$version" ]]; then
        log_error "Missing required parameters for plugin registration"
        log_error "ID: '$id', Name: '$name', Version: '$version'"
        return 1
    fi
    
    # Validate plugin ID (alphanumeric plus underscore and hyphen)
    if ! [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Get current timestamp
    now=$(get_iso_timestamp)
    
    # Check if plugin is already registered using named parameters
    local select_sql="SELECT COUNT(*) FROM plugins WHERE id = :plugin_id;"
    local exists
    exists=$(query_plugin_db_params "$select_sql" ":plugin_id" "$id" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*COUNT(\*) = \(.*\)$/\1/p')
    
    # Insert or update plugin record
    if [[ "$exists" -eq 0 ]]; then
        # Insert new plugin using named parameters
        local insert_sql="INSERT INTO plugins (id, name, version, description, enabled, created_at, updated_at, has_pre_session_hook, has_post_session_hook, has_cli_commands) 
        VALUES (:id, :name, :version, :description, 0, :created_at, :updated_at, :has_pre_session, :has_post_session, :has_cli_commands);"
        
        # Execute the query with named parameters
        query_plugin_db_params "$insert_sql" \
            ":id" "$id" \
            ":name" "$name" \
            ":version" "$version" \
            ":description" "$description" \
            ":created_at" "$now" \
            ":updated_at" "$now" \
            ":has_pre_session" "$has_pre_session" \
            ":has_post_session" "$has_post_session" \
            ":has_cli_commands" "$has_cli_commands" > /dev/null
        local insert_result=$?
        
        if [[ $insert_result -ne 0 ]]; then
            log_error "Failed to register plugin: $id"
            return 1
        fi
        
        log_success "Plugin registered: $name (ID: $id)"
    else
        # Update existing plugin using named parameters
        local update_sql="UPDATE plugins SET 
            name = :name, 
            version = :version, 
            description = :description, 
            updated_at = :updated_at, 
            has_pre_session_hook = :has_pre_session, 
            has_post_session_hook = :has_post_session,
            has_cli_commands = :has_cli_commands
        WHERE id = :id;"
        
        # Execute the query with named parameters
        query_plugin_db_params "$update_sql" \
            ":name" "$name" \
            ":version" "$version" \
            ":description" "$description" \
            ":updated_at" "$now" \
            ":has_pre_session" "$has_pre_session" \
            ":has_post_session" "$has_post_session" \
            ":has_cli_commands" "$has_cli_commands" \
            ":id" "$id" > /dev/null
        local update_result=$?
        
        if [[ $update_result -ne 0 ]]; then
            log_error "Failed to update plugin registration: $id"
            return 1
        fi
        
        log_success "Plugin registration updated: $name (ID: $id)"
    fi
    
    # Add to in-memory registry
    REGISTERED_PLUGINS+=("$id")
    
    # Register hooks if applicable using the plugin_hooks module
    if [[ "$has_pre_session" -eq 1 ]]; then
        register_pre_session_hook "$id"
    fi
    
    if [[ "$has_post_session" -eq 1 ]]; then
        register_post_session_hook "$id"
    fi
    
    # For has_cli_commands, we don't register anything here
    # CLI commands are registered by the plugin itself using register_cli_command
    
    return 0
}

# Enable or disable a plugin
# Usage: set_plugin_status <id> <enabled>
set_plugin_status() {
    local id="$1"
    local enabled="$2"  # 1 for enabled, 0 for disabled
    local now
    
    # Validate plugin ID
    if ! [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Validate enabled status
    if [[ "$enabled" != "0" && "$enabled" != "1" ]]; then
        log_error "Invalid enabled status: $enabled (must be 0 or 1)"
        return 1
    fi
    
    # Get current timestamp
    now=$(get_iso_timestamp)
    
    # Check if plugin exists using named parameters
    local sql="SELECT COUNT(*) FROM plugins WHERE id = :plugin_id;"
    local exists
    exists=$(query_plugin_db_params "$sql" ":plugin_id" "$id" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*COUNT(\*) = \(.*\)$/\1/p')
    
    if [[ "$exists" -eq 0 ]]; then
        log_error "Plugin not found: $id"
        return 1
    fi
    
    # Update plugin status using named parameters
    local update_sql="UPDATE plugins SET enabled = :enabled, updated_at = :updated_at WHERE id = :plugin_id;"
    query_plugin_db_params "$update_sql" ":enabled" "$enabled" ":updated_at" "$now" ":plugin_id" "$id" > /dev/null
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to update plugin status: $id"
        return 1
    fi
    
    if [[ "$enabled" -eq 1 ]]; then
        log_success "Plugin enabled: $id"
    else
        log_success "Plugin disabled: $id"
    fi
    
    return 0
}

# Check if a plugin is enabled
# Usage: is_plugin_enabled <id>
is_plugin_enabled() {
    local id="$1"
    local enabled
    
    # Validate plugin ID
    if ! [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Query the database using plugin_db functions with named parameters
    local sql="SELECT enabled FROM plugins WHERE id = :plugin_id;"
    enabled=$(query_plugin_db_params "$sql" ":plugin_id" "$id" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*enabled = \(.*\)$/\1/p')
    
    # Check if query returned a value
    if [[ -z "$enabled" ]]; then
        # Plugin not found
        log_debug "Plugin not found or not enabled: $id"
        return 1
    fi
    
    # Check if plugin is enabled
    if [[ "$enabled" -eq 0 ]]; then
        log_debug "Plugin is disabled: $id"
        return 1
    fi
    
    return 0
}

# Set a plugin setting
# Usage: set_plugin_setting <plugin_id> <key> <value> [description]
set_plugin_setting() {
    local plugin_id="$1"
    local key="$2"
    local value="$3"
    local description="${4:-}"
    local now
    
    # Validate plugin ID and key
    if ! [[ "$plugin_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $plugin_id"
        return 1
    fi
    
    if ! [[ "$key" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid setting key format: $key"
        return 1
    fi
    
    # Check if plugin exists using named parameters
    local plugin_exists_sql="SELECT COUNT(*) FROM plugins WHERE id = :plugin_id;"
    local exists
    exists=$(query_plugin_db_params "$plugin_exists_sql" ":plugin_id" "$plugin_id" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*COUNT(\*) = \(.*\)$/\1/p')
    
    if [[ "$exists" -eq 0 ]]; then
        log_error "Plugin not found: $plugin_id"
        return 1
    fi
    
    # Get current timestamp
    now=$(get_iso_timestamp)
    
    # Check if setting already exists using named parameters
    local setting_exists_sql="SELECT COUNT(*) FROM plugin_settings WHERE plugin_id = :plugin_id AND key = :key;"
    local setting_exists
    setting_exists=$(query_plugin_db_params "$setting_exists_sql" ":plugin_id" "$plugin_id" ":key" "$key" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*COUNT(\*) = \(.*\)$/\1/p')
    
    # Insert or update setting using named parameters
    if [[ "$setting_exists" -eq 0 ]]; then
        # Insert new setting
        local insert_sql="INSERT INTO plugin_settings (plugin_id, key, value, description, updated_at) 
            VALUES (:plugin_id, :key, :value, :description, :updated_at);"
        query_plugin_db_params "$insert_sql" \
            ":plugin_id" "$plugin_id" \
            ":key" "$key" \
            ":value" "$value" \
            ":description" "$description" \
            ":updated_at" "$now" > /dev/null
    else
        # Update existing setting
        local update_sql="UPDATE plugin_settings 
            SET value = :value, description = :description, updated_at = :updated_at 
            WHERE plugin_id = :plugin_id AND key = :key;"
        query_plugin_db_params "$update_sql" \
            ":value" "$value" \
            ":description" "$description" \
            ":updated_at" "$now" \
            ":plugin_id" "$plugin_id" \
            ":key" "$key" > /dev/null
    fi
    
    local result=$?
    
    if [[ $result -ne 0 ]]; then
        log_error "Failed to set plugin setting: $plugin_id.$key"
        return 1
    fi
    
    log_debug "Plugin setting updated: $plugin_id.$key = $value"
    return 0
}

# Get a plugin setting
# Usage: get_plugin_setting <plugin_id> <key> [default]
get_plugin_setting() {
    local plugin_id="$1"
    local key="$2"
    local default="${3:-}"
    local value
    
    # Query the database using named parameters
    local sql="SELECT value FROM plugin_settings WHERE plugin_id = :plugin_id AND key = :key;"
    value=$(query_plugin_db_params "$sql" ":plugin_id" "$plugin_id" ":key" "$key" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*value = \(.*\)$/\1/p')
    
    # If no value found, return default
    if [[ -z "$value" && -n "$default" ]]; then
        echo "$default"
        return 0
    fi
    
    echo "$value"
    return 0
}

# Use plugin hooks module for hooks related functions
# The implementation of these functions has been moved to plugin_hooks.sh

# Load all plugins from the plugins directory
load_plugins() {
    # Use ROOT_DIR and PLUGINS_DIR from constants for consistent path resolution
    local plugin_dir
    if [[ -n "${PLUGINS_DIR:-}" ]]; then
        # If PLUGINS_DIR is defined, use it directly
        plugin_dir="${PLUGINS_DIR}"
    elif [[ -n "${ROOT_DIR:-}" ]]; then
        # If ROOT_DIR is defined, use it to build absolute path
        plugin_dir="${ROOT_DIR}/src/plugins"
    else
        # Fallback to script directory
        plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    
    log_info "Loading plugins from: $plugin_dir"
    
    # Initialize plugin schema if needed
    initialize_plugin_schema
    
    # Skip plugin loading if initialization failed
    # This prevents trying to load plugins when the database isn't ready
    if ! plugin_table_exists "plugins"; then
        log_warning "Plugin database not initialized properly, skipping plugin loading"
        return 1
    fi
    
    # Find all plugin files (excluding system plugin files)
    # Using find to handle all edge cases with filenames
    while IFS= read -r plugin_file; do
        # Skip empty lines and system plugin files
        if [[ -z "$plugin_file" || 
              "$plugin_file" == *"plugin_manager.sh" || 
              "$plugin_file" == *"plugin_db.sh" || 
              "$plugin_file" == *"plugin_hooks.sh" ]]; then
            continue
        fi
        
        # Verify file exists and is readable
        if [[ ! -f "$plugin_file" || ! -r "$plugin_file" ]]; then
            log_warning "Plugin file not found or not readable: $plugin_file"
            continue
        fi
        
        # Source the plugin file with error handling
        log_debug "Loading plugin file: $plugin_file"
        
        # Use a subshell to source the plugin to contain potential failures
        (
            # shellcheck disable=SC1090
            source "$plugin_file"
        )
        
        # Check for errors sourcing the plugin
        if [[ $? -ne 0 ]]; then
            log_error "Failed to load plugin file: $plugin_file"
        fi
    done < <(find "$plugin_dir" -maxdepth 1 -type f -name "*.sh" | sort)
    
    log_info "Loaded ${#REGISTERED_PLUGINS[@]} plugins"
    return 0
}

# List all registered plugins
list_plugins() {
    # Execute query using query_plugin_db (no parameters needed here)
    local sql="SELECT id, name, version, description, enabled, 
    has_pre_session_hook, has_post_session_hook, created_at, updated_at 
    FROM plugins ORDER BY name;"
    
    # Execute using query_plugin_db (direct query is fine with no parameters)
    query_plugin_db "$sql"
    return $?
}

# Export functions
export -f initialize_plugin_schema
export -f register_plugin
export -f set_plugin_status
export -f is_plugin_enabled
export -f set_plugin_setting
export -f get_plugin_setting
export -f load_plugins
export -f list_plugins