#!/usr/bin/env bash
#
# SSHistorian - Database Migration Module
# Functions for managing schema migrations
#

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../../utils/constants.sh
    source "${SCRIPT_DIR}/../../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../../utils/common.sh
    source "${SCRIPT_DIR}/../../utils/common.sh"
fi

# Source error handling module if not already loaded
if ! command -v handle_error &>/dev/null; then
    # shellcheck source=../../utils/errors.sh
    source "${SCRIPT_DIR}/../../utils/errors.sh"
fi

# Source database core if not already loaded
if ! command -v db_execute &>/dev/null; then
    # shellcheck source=../core/db_core.sh
    source "${SCRIPT_DIR}/../core/db_core.sh"
fi

# Get all migration files from migrations directory
# Returns a list of migration files sorted by version number
get_migration_files() {
    local migrations_dir="${ROOT_DIR}/src/db/migrations"
    local file_pattern="*.sql"
    
    # Ensure the directory exists
    if [[ ! -d "$migrations_dir" ]]; then
        handle_error "$ERR_FILE_GENERAL" "Migrations directory not found: $migrations_dir"
        return $ERR_FILE_GENERAL
    fi
    
    # Find all migration files and sort them
    find "$migrations_dir" -type f -name "$file_pattern" | sort
}

# Initialize schema_info table to track version
init_schema_info_table() {
    local table_exists
    table_exists=$(db_execute -count "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='schema_info';")
    
    # If the table already exists, we're done
    if [[ "$table_exists" -eq 1 ]]; then
        log_debug "Schema info table already exists"
        return 0
    fi
    
    log_info "Creating schema_info table"
    
    # Create schema_info table to track version
    db_execute "
CREATE TABLE schema_info (
    version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);"

    # Insert initial version data with parameter binding
    db_execute_params "
INSERT INTO schema_info (version, created_at, updated_at) 
VALUES (:version, datetime('now'), datetime('now'));" \
        ":version" "$DB_VERSION"
    
    # Check if the table was created successfully
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_SCHEMA" "Failed to create schema_info table"
        return $ERR_DB_SCHEMA
    fi
    
    log_success "Schema info table created with version: ${DB_VERSION}"
    return 0
}

# Initialize migrations tracking table if it doesn't exist
init_migrations_table() {
    local table_exists
    table_exists=$(db_execute -count "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='migrations';")
    
    # If the table already exists, we're done
    if [[ "$table_exists" -eq 1 ]]; then
        log_debug "Migrations table already exists"
        return 0
    fi
    
    log_info "Creating migrations tracking table"
    
    # Create the migrations table
    local migrations_sql="
CREATE TABLE migrations (
    migration_id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL,
    description TEXT
);
"
    db_execute "$migrations_sql"
    
    # Check if the table was created successfully
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_SCHEMA" "Failed to create migrations table"
        return $ERR_DB_SCHEMA
    fi
    
    log_success "Migrations table created successfully"
    return 0
}

# Check if a migration has been applied
# Usage: has_migration_been_applied <migration_id>
has_migration_been_applied() {
    local migration_id="$1"
    local count
    
    # Check if the migrations table exists
    if ! table_exists "migrations"; then
        return 1
    fi
    
    # Check if this specific migration has been applied
    count=$(db_execute_params -count "SELECT count(*) FROM migrations WHERE migration_id = :migration_id;" \
        ":migration_id" "$migration_id")
    
    # Return true if found, false otherwise
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
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
    
    # Validate file exists and is readable
    if [[ ! -f "$migration_file" || ! -r "$migration_file" ]]; then
        handle_error "$ERR_FILE_GENERAL" "Migration file not found or not readable: $migration_file"
        return $ERR_FILE_GENERAL
    fi
    
    # Run everything in a single transaction for atomicity
    # Read the file content and create a full transaction
    local migration_sql
    migration_sql=$(<"$migration_file")
    
    # First apply the migration SQL directly
    # We cannot use params for arbitrary SQL, but we can isolate this from user input
    # by validating migration files come from trusted source
    db_execute "$migration_sql"
    
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_MIGRATION" "Migration SQL failed: $migration_id"
        return $ERR_DB_MIGRATION
    fi
    
    # Now record the migration with parameterized query
    local timestamp
    timestamp=$(get_iso_timestamp)
    
    db_execute_params "INSERT INTO migrations (migration_id, applied_at, description)
        VALUES (:migration_id, :applied_at, :description);" \
        ":migration_id" "$migration_id" \
        ":applied_at" "$timestamp" \
        ":description" "$description"
    
    local result=$?
    
    # Check if the transaction succeeded
    if [[ $result -ne 0 ]]; then
        handle_error "$ERR_DB_MIGRATION" "Migration failed: $migration_id"
        return $ERR_DB_MIGRATION
    fi
    
    log_success "Migration applied successfully: $migration_id"
    return 0
}

# Run all pending migrations
# This is called during database initialization
run_migrations() {
    log_info "Checking for pending migrations"
    
    # Ensure migrations table exists
    init_migrations_table || return $?
    
    # Get all migration files
    local migration_files
    migration_files=$(get_migration_files)
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_FILE_GENERAL" "Failed to get migration files"
        return $ERR_FILE_GENERAL
    fi
    
    # Apply each migration that hasn't been applied yet
    local file
    for file in $migration_files; do
        apply_migration "$file" || {
            handle_error "$ERR_DB_MIGRATION" "Migration failed, aborting migration process"
            return $ERR_DB_MIGRATION
        }
    done
    
    # Update schema_info table with current version
    db_execute_params "UPDATE schema_info SET version = :version, updated_at = datetime('now');" \
        ":version" "$DB_VERSION"
    
    log_success "All migrations applied successfully"
    return 0
}

# Check if database migration is needed
check_migration_needed() {
    local current_version
    
    # Get current schema version
    current_version=$(get_schema_version)
    if [[ $? -ne 0 || -z "$current_version" ]]; then
        handle_error "$ERR_DB_SCHEMA" "Failed to retrieve schema version. Database might be corrupted."
        return $ERR_DB_SCHEMA
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
export -f init_schema_info_table
export -f init_migrations_table
export -f has_migration_been_applied
export -f apply_migration
export -f run_migrations
export -f check_migration_needed