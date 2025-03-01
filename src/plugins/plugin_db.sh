#!/usr/bin/env bash
#
# SSHistorian - Plugin Database Module
# Functions for plugin database operations
#

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ROOT_DIR:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Initialize the plugin database if it doesn't exist
ensure_plugin_database() {
    # Check if database file exists
    if [[ ! -f "$PLUGINS_DB_FILE" ]]; then
        log_info "Plugin database file not found, initializing..."
        
        # Create the plugin database directory if it doesn't exist
        mkdir -p "$(dirname "$PLUGINS_DB_FILE")" || {
            log_error "Failed to create plugin database directory"
            return 1
        }
        
        # Create an empty database file
        touch "$PLUGINS_DB_FILE" || {
            log_error "Failed to create plugin database file"
            return 1
        }
        
        # Set secure permissions
        chmod 600 "$PLUGINS_DB_FILE" || {
            log_warning "Failed to set permissions on plugin database file"
        }
        
        log_success "Plugin database file created successfully"
    fi
    
    # Ensure we have write permissions
    if [[ ! -w "$PLUGINS_DB_FILE" ]]; then
        log_error "Plugin database file is not writable: $PLUGINS_DB_FILE"
        return 1
    fi
    
    # Create schema_info table if needed - don't use query_plugin_db function to avoid recursion
    local schema_exists
    schema_exists=$(sqlite3 "$PLUGINS_DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='schema_info';" 2>/dev/null || echo "0")
    
    # Create schema_info table if it doesn't exist
    if [[ "$schema_exists" != "1" ]]; then
        log_info "Creating schema_info table for plugin database"
        sqlite3 "$PLUGINS_DB_FILE" <<SQL
-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_info (
    version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Insert initial schema version
INSERT INTO schema_info (version, created_at, updated_at)
VALUES ('1', datetime('now'), datetime('now'));
SQL
    fi
    
    # Create migrations table if it doesn't exist - don't use init_plugins_migrations_table to avoid recursion
    local migrations_exists
    migrations_exists=$(sqlite3 "$PLUGINS_DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='migrations';" 2>/dev/null || echo "0")
    
    if [[ "$migrations_exists" != "1" ]]; then
        log_info "Creating plugins migrations tracking table"
        sqlite3 "$PLUGINS_DB_FILE" <<SQL
CREATE TABLE IF NOT EXISTS migrations (
    migration_id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    description TEXT
);
SQL
        log_success "Plugins migrations table created successfully"
    fi
    
    return 0
}


# Initialize plugins tracking table
init_plugins_migrations_table() {
    log_debug "Checking for plugins migrations tracking table"
    
    # Check if migrations table already exists
    local migrations_exists
    migrations_exists=$(query_plugin_db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='migrations';" 2>/dev/null || echo "0")
    
    # Skip if table already exists
    if [[ "$migrations_exists" == *"1"* ]]; then
        log_debug "Plugins migrations table already exists"
        return 0
    fi
    
    log_info "Creating plugins migrations tracking table"
    
    # Create the migrations table for plugins
    query_plugin_db <<SQL
CREATE TABLE IF NOT EXISTS migrations (
    migration_id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    description TEXT
);
SQL
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create plugins migrations table"
        return 1
    fi
    
    log_success "Plugins migrations table created successfully"
    return 0
}

# Get all plugin migration files from migrations directory
# Returns a list of migration files sorted by version number
get_plugin_migration_files() {
    local migrations_dir="${PLUGINS_DIR}/migrations"
    local file_pattern="*.sql"
    
    # Ensure the directory exists
    if [[ ! -d "$migrations_dir" ]]; then
        log_warning "Plugin migrations directory not found: $migrations_dir"
        return 1
    fi
    
    # Find all migration files and sort them
    find "$migrations_dir" -type f -name "$file_pattern" | sort
}

# Check if a plugin migration has been applied
# Usage: has_plugin_migration_been_applied <migration_id>
has_plugin_migration_been_applied() {
    local migration_id="$1"
    local count
    
    # Check if the migrations table exists
    if ! plugin_table_exists "migrations"; then
        return 1
    fi
    
    # Check if this specific migration has been applied
    count=$(query_plugin_db_params "SELECT count(*) FROM migrations WHERE migration_id = :migration_id;" \
        ":migration_id" "$migration_id" | sed -n 's/^count(\*) = \(.*\)$/\1/p')
    
    # Return true if found, false otherwise
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Apply a specific plugin migration file
# Usage: apply_plugin_migration <migration_file>
apply_plugin_migration() {
    local migration_file="$1"
    local migration_id description
    
    # Extract migration ID and description from filename and header
    migration_id=$(basename "$migration_file" .sql)
    description=$(grep -m 1 -- "-- Migration ID:" "$migration_file" | cut -d ":" -f 2- | tr -d ' ' || echo "$migration_id")
    
    # If description is empty, use the migration ID
    if [[ -z "$description" ]]; then
        description="$migration_id"
    fi
    
    # Check if migration has already been applied
    if has_plugin_migration_been_applied "$migration_id"; then
        log_debug "Plugin migration already applied: $migration_id"
        return 0
    fi
    
    log_info "Applying plugin migration: $migration_id - $description"
    
    # First, directly apply the migration SQL to prevent syntax errors
    sqlite3 "$PLUGINS_DB_FILE" < "$migration_file"
    local sql_result=$?
    
    if [[ $sql_result -ne 0 ]]; then
        log_error "Failed to apply SQL for migration: $migration_id"
        return 1
    fi
    
    # Now record that the migration has been applied
    local now
    now=$(get_iso_timestamp)
    query_plugin_db_params "INSERT INTO migrations (migration_id, applied_at, description) VALUES (:migration_id, :applied_at, :description);" \
        ":migration_id" "$migration_id" \
        ":applied_at" "$now" \
        ":description" "$description"
    local record_result=$?
    
    if [[ $record_result -ne 0 ]]; then
        log_warning "Migration SQL was applied but failed to record it in migrations table: $migration_id"
        return 1
    fi
    
    log_success "Plugin migration applied successfully: $migration_id"
    return 0
}

# Run all pending plugin migrations
# This is called during plugin database initialization
run_plugin_migrations() {
    log_info "Checking for pending plugin migrations"
    
    # Ensure migrations table exists
    init_plugins_migrations_table || return 1
    
    # Get all migration files
    local migration_files
    migration_files=$(get_plugin_migration_files)
    
    # If no migration files found, we're done
    if [[ -z "$migration_files" ]]; then
        log_debug "No plugin migration files found"
        return 0
    fi
    
    # Validate all migration files first before applying
    local file
    for file in $migration_files; do
        local migration_id
        migration_id=$(basename "$file" .sql)
        
        # Skip if migration has already been applied
        if has_plugin_migration_been_applied "$migration_id"; then
            log_debug "Skipping already applied migration: $migration_id"
            continue
        fi
        
        # Check if file exists and is readable
        if [[ ! -f "$file" || ! -r "$file" ]]; then
            log_error "Migration file not found or not readable: $file"
            return 1
        fi
        
        # Check if migration file contains SQL
        if [[ ! -s "$file" ]]; then
            log_warning "Migration file is empty: $file"
        fi
    done
    
    # Now apply each migration
    local success_count=0
    local error_count=0
    for file in $migration_files; do
        local migration_id
        migration_id=$(basename "$file" .sql)
        
        # Skip if migration has already been applied
        if has_plugin_migration_been_applied "$migration_id"; then
            continue
        fi
        
        # Apply the migration - continue even on failure to try to apply as many as possible
        if ! apply_plugin_migration "$file"; then
            log_error "Failed to apply migration: $migration_id"
            error_count=$((error_count + 1))
        else
            success_count=$((success_count + 1))
        fi
    done
    
    # Report results
    if [[ $error_count -gt 0 ]]; then
        log_warning "Plugin migrations completed with errors: $success_count succeeded, $error_count failed"
        if [[ $success_count -eq 0 ]]; then
            # If no migrations succeeded, return failure
            return 1
        fi
    else
        if [[ $success_count -gt 0 ]]; then
            log_success "All plugin migrations applied successfully ($success_count total)"
        else
            log_info "No new plugin migrations to apply"
        fi
    fi
    
    return 0
}

# Execute a SQL query directly on the plugin database
# Usage: query_plugin_db "<sql_query>"
query_plugin_db() {
    # Check if database file exists, but don't call ensure_plugin_database to avoid recursion
    if [[ ! -f "$PLUGINS_DB_FILE" ]]; then
        log_error "Plugin database file not found. Run ensure_plugin_database first."
        return 1
    fi
    
    # Execute the query using heredoc
    sqlite3 -batch -header "$PLUGINS_DB_FILE" "$@"
    return $?
}

# Execute a SQL query with parameters on the plugin database
# Usage: query_plugin_db_params "<sql_query>" [param_name1 param_value1 param_name2 param_value2 ...]
query_plugin_db_params() {
    local sql="$1"
    shift
    local params=("$@")
    
    # Check if database file exists, but don't call ensure_plugin_database to avoid recursion
    if [[ ! -f "$PLUGINS_DB_FILE" ]]; then
        log_error "Plugin database file not found. Run ensure_plugin_database first."
        return 1
    fi
    
    # Build a heredoc with parameter binding and secure permissions
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"  # Set secure permissions (0600: only owner can read/write)
    
    # Add debug mode and headers
    echo ".mode line" > "$temp_file"
    echo ".headers on" >> "$temp_file"
    echo ".param clear" >> "$temp_file"  # Clear any previous parameters
    
    # Generate the parameter binding commands
    # Parameters must come in pairs: param_name param_value
    for ((i=0; i<${#params[@]}; i+=2)); do
        if [[ $i+1 -lt ${#params[@]} ]]; then
            local param_name="${params[$i]}"
            local param_value="${params[$i+1]}"
            
            # Add the parameter binding command using named parameters
            echo ".param set ${param_name} \"${param_value}\"" >> "$temp_file"
        fi
    done
    
    # Add the SQL query
    echo "$sql" >> "$temp_file"
    
    # Execute the query with proper parameter binding
    sqlite3 -batch -header "$PLUGINS_DB_FILE" < "$temp_file"
    local result=$?
    
    # Clean up
    rm -f "$temp_file"
    
    return $result
}

# Check if a table exists in the plugin database
# Usage: plugin_table_exists <table_name>
plugin_table_exists() {
    local table_name="$1"
    local count
    
    # Check if database file exists, but don't call ensure_plugin_database to avoid recursion
    if [[ ! -f "$PLUGINS_DB_FILE" ]]; then
        log_error "Plugin database file not found. Run ensure_plugin_database first."
        return 1
    fi
    
    # Check if table exists using named parameters
    local sql="SELECT count(*) FROM sqlite_master WHERE type='table' AND name=:table_name;"
    count=$(query_plugin_db_params "$sql" ":table_name" "$table_name" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*count(\*) = \(.*\)$/\1/p')
    
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Export functions
export -f ensure_plugin_database
export -f init_plugins_migrations_table
export -f query_plugin_db
export -f query_plugin_db_params
export -f plugin_table_exists
export -f get_plugin_migration_files
export -f has_plugin_migration_been_applied
export -f apply_plugin_migration
export -f run_plugin_migrations