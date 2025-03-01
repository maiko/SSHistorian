#!/usr/bin/env bash
#
# SSHistorian - Database Schema Module
# Functions for managing database schema and migrations
#

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

# Get all migration files from migrations directory
# Returns a list of migration files sorted by version number
get_migration_files() {
    local migrations_dir="${SCRIPT_DIR}/migrations"
    local file_pattern="*.sql"
    
    # Ensure the directory exists
    if [[ ! -d "$migrations_dir" ]]; then
        log_warning "Migrations directory not found: $migrations_dir"
        return 1
    fi
    
    # Find all migration files and sort them
    find "$migrations_dir" -type f -name "$file_pattern" | sort
}

# Check if a migration has been applied
# Usage: has_migration_been_applied <migration_id>
has_migration_been_applied() {
    local migration_id="$1"
    local count
    
    # Check if the migrations table exists
    local table_exists
    table_exists=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='migrations';" 2>/dev/null || echo "0")
    
    # If the table doesn't exist, no migrations have been applied
    if [[ "$table_exists" -eq 0 ]]; then
        return 1
    fi
    
    # Create temporary file for parameter binding with secure permissions
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"  # Set secure permissions (0600: only owner can read/write)
    
    # Add parameter binding command
    echo ".param set 1 \"$migration_id\"" > "$temp_file"
    # Add SQL query
    echo "SELECT count(*) FROM migrations WHERE migration_id = ?;" >> "$temp_file"
    
    # Execute query with parameter binding
    count=$(sqlite3 "$DB_FILE" < "$temp_file" 2>/dev/null || echo "0")
    
    # Clean up
    rm -f "$temp_file"
    
    # Return true if found, false otherwise
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Initialize migrations tracking table if it doesn't exist
init_migrations_table() {
    local table_exists
    table_exists=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='migrations';" 2>/dev/null || echo "0")
    
    # If the table already exists, we're done
    if [[ "$table_exists" -eq 1 ]]; then
        log_debug "Migrations table already exists"
        return 0
    fi
    
    log_info "Creating migrations tracking table"
    
    # Create the migrations table
    sqlite3 "$DB_FILE" <<SQL
CREATE TABLE migrations (
    migration_id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    description TEXT
);
SQL
    
    # Check if the table was created successfully
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create migrations table"
        return 1
    fi
    
    log_success "Migrations table created successfully"
    return 0
}

# Initialize schema_info table to track version
init_schema_info_table() {
    local table_exists
    table_exists=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='schema_info';" 2>/dev/null || echo "0")
    
    # If the table already exists, we're done
    if [[ "$table_exists" -eq 1 ]]; then
        log_debug "Schema info table already exists"
        return 0
    fi
    
    log_info "Creating schema_info table"
    
    # Create schema_info table to track version
    sqlite3 "$DB_FILE" <<SQL
-- Version tracking
CREATE TABLE schema_info (
    version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Insert schema version
INSERT INTO schema_info (version, created_at, updated_at) 
VALUES ('${DB_VERSION}', datetime('now'), datetime('now'));
SQL
    
    # Check if the table was created successfully
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create schema_info table"
        return 1
    fi
    
    log_success "Schema info table created with version: ${DB_VERSION}"
    return 0
}

# Apply a specific migration file
# Usage: apply_migration <migration_file>
apply_migration() {
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
    if has_migration_been_applied "$migration_id"; then
        log_debug "Migration already applied: $migration_id"
        return 0
    fi
    
    log_info "Applying migration: $migration_id - $description"
    
    # Run everything in a single transaction for atomicity
    {
        # Start transaction and apply migration
        echo "BEGIN TRANSACTION;"
        cat "$migration_file"
        
        # Record the migration in the migrations table
        local now
        now=$(get_iso_timestamp)
        echo "INSERT INTO migrations (migration_id, applied_at, description) VALUES ('$migration_id', '$now', '$description');"
        
        # Commit transaction
        echo "COMMIT;"
    } | sqlite3 "$DB_FILE"
    
    local result=$?
    
    # Check if the transaction succeeded
    if [[ $result -ne 0 ]]; then
        log_error "Migration failed: $migration_id"
        return 1
    fi
    
    log_success "Migration applied successfully: $migration_id"
    return 0
}

# Run all pending migrations
# This is called during database initialization
run_migrations() {
    log_info "Checking for pending migrations"
    
    # Ensure migrations table exists
    init_migrations_table || return 1
    
    # Get all migration files
    local migration_files
    migration_files=$(get_migration_files)
    
    # Apply each migration that hasn't been applied yet
    local file
    for file in $migration_files; do
        apply_migration "$file" || {
            log_error "Migration failed, aborting migration process"
            return 1
        }
    done
    
    # Update schema_info table with current version
    sqlite3 "$DB_FILE" "UPDATE schema_info SET version = ?, updated_at = datetime('now');" "$DB_VERSION"
    
    log_success "All migrations applied successfully"
    return 0
}

# Check if database migration is needed
check_migration_needed() {
    local current_version
    
    # Get current schema version - no parameter binding needed for this basic query
    current_version=$(sqlite3 "$DB_FILE" "SELECT version FROM schema_info LIMIT 1;" 2>/dev/null)
    
    # If query failed or no version found, database might be corrupted
    if [[ $? -ne 0 || -z "$current_version" ]]; then
        log_error "Failed to retrieve schema version. Database might be corrupted."
        return 1
    fi
    
    # Compare versions and migrate if needed
    if [[ "$current_version" != "$DB_VERSION" ]]; then
        log_info "Database needs migration from v${current_version} to v${DB_VERSION}"
        
        # Run migrations
        run_migrations
        return $?
    fi
    
    log_debug "Database schema is up-to-date (v${DB_VERSION})"
    return 0
}

# Export functions
export -f get_migration_files
export -f has_migration_been_applied
export -f init_migrations_table
export -f init_schema_info_table
export -f apply_migration
export -f run_migrations
export -f check_migration_needed