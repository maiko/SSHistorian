#!/usr/bin/env bash
#
# SSHistorian - Database Core Module
# Low-level functions for database operations
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

# Initialize the database if it doesn't exist
# Creates database file and initializes core tables
init_database() {
    # Check if database already exists
    if [[ -f "$DB_FILE" ]]; then
        log_debug "Database already exists at $DB_FILE"
        
        # Verify schema version and migrate if needed
        if command -v check_migration_needed &>/dev/null; then
            check_migration_needed
        fi
        return 0
    fi
    
    # Create data directory if it doesn't exist
    mkdir -p "$(dirname "$DB_FILE")" || {
        handle_error "$ERR_FILE_GENERAL" "Failed to create database directory"
        # Full path is only logged in debug mode
        log_debug "Failed to create database directory: $(dirname "$DB_FILE")"
        return $ERR_FILE_GENERAL
    }
    
    log_info "Creating new database"
    # Full path is only logged in debug mode
    log_debug "Database location: $DB_FILE"
    
    # Create empty database first
    sqlite3 "$DB_FILE" ""
    
    # Check if database was created successfully
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to create database file"
        return $ERR_DB_GENERAL
    fi
    
    # Set secure permissions for database file
    chmod 600 "$DB_FILE" || {
        log_warning "Failed to set secure permissions on database file"
    }
    
    # Initialize schema_info table if available
    if command -v init_schema_info_table &>/dev/null; then
        init_schema_info_table || {
            handle_error "$ERR_DB_SCHEMA" "Failed to initialize schema_info table"
            return $ERR_DB_SCHEMA
        }
    fi
    
    # Run migrations if available
    if command -v run_migrations &>/dev/null; then
        run_migrations || {
            handle_error "$ERR_DB_MIGRATION" "Failed to run migrations"
            return $ERR_DB_MIGRATION
        }
    fi
    
    # Insert default config if available
    if command -v insert_default_config &>/dev/null; then
        insert_default_config || {
            handle_error "$ERR_DB_GENERAL" "Failed to insert default configuration"
            return $ERR_DB_GENERAL
        }
    fi
    
    log_success "Database initialized successfully (v${DB_VERSION})"
    return 0
}

# Helper function to ensure database exists
# Usage: ensure_database
ensure_database() {
    if [[ ! -f "$DB_FILE" ]]; then
        init_database || return $?
    fi
    return 0
}

# Execute a SQL query and return results
# Usage: db_execute [-line|-table|-csv|-json|-count] <sql>
db_execute() {
    local output_format="-line"
    local sql=""
    
    # Parse arguments (safely check if arguments exist)
    if [[ $# -gt 0 && ("$1" == "-line" || "$1" == "-table" || "$1" == "-csv" || "$1" == "-json" || "$1" == "-count") ]]; then
        output_format="$1"
        shift
    fi
    
    # Safely get SQL parameter if it exists
    if [[ $# -gt 0 ]]; then
        sql="$1"
    else
        handle_error "$ERR_ARGS" "Missing SQL query"
        return $ERR_ARGS
    fi
    
    # Make sure database exists
    ensure_database || return $?
    
    # Choose SQLite output format
    local sqlite_args=""
    case "$output_format" in
        "-line")
            sqlite_args="-line"
            ;;
        "-table")
            sqlite_args="-column -header"
            ;;
        "-csv")
            sqlite_args="-csv -header"
            ;;
        "-json")
            sqlite_args="-json"
            ;;
        "-count")
            # Special case for just returning a count value
            local result
            result=$(sqlite3 "$DB_FILE" "$sql")
            echo "$result"
            return $?
            ;;
    esac
    
    # Execute the query
    sqlite3 $sqlite_args "$DB_FILE" "$sql"
    local status=$?
    
    # Handle errors 
    if [[ $status -ne 0 ]]; then
        handle_error "$ERR_DB_QUERY" "SQL query failed (check logs for details)"
        # Full query is logged only in debug mode
        log_debug "Failed SQL query was: $sql"
        return $ERR_DB_QUERY
    fi
    
    return 0
}

# Execute a parameterized SQL query with proper binding
# Usage: db_execute_params [-line|-table|-csv|-json|-count] <sql> [param_name1 param_value1 param_name2 param_value2 ...]
db_execute_params() {
    local output_format="-line"
    local sql=""
    
    # Parse arguments (safely check if arguments exist)
    if [[ $# -gt 0 && ("$1" == "-line" || "$1" == "-table" || "$1" == "-csv" || "$1" == "-json" || "$1" == "-count") ]]; then
        output_format="$1"
        shift
    fi
    
    # Safely get SQL parameter if it exists
    if [[ $# -gt 0 ]]; then
        sql="$1"
        shift
    else
        handle_error "$ERR_ARGS" "Missing SQL query"
        return $ERR_ARGS
    fi
    
    # We need at least the SQL query
    if [[ -z "$sql" ]]; then
        handle_error "$ERR_ARGS" "Missing SQL query for db_execute_params"
        return $ERR_ARGS
    fi
    
    # Make sure database exists
    ensure_database || return $?
    
    # Create temporary file for parameter binding with secure permissions
    local temp_script
    temp_script=$(mktemp)
    chmod 600 "$temp_script"  # Set secure permissions (0600: only owner can read/write)
    register_operation "db_temp_script" "rm -f ${temp_script}"
    
    # Choose SQLite output format
    case "$output_format" in
        "-line")
            echo ".mode line" > "$temp_script"
            ;;
        "-table")
            echo ".mode column" > "$temp_script"
            echo ".headers on" >> "$temp_script"
            ;;
        "-csv")
            echo ".mode csv" > "$temp_script"
            echo ".headers on" >> "$temp_script"
            ;;
        "-json")
            echo ".mode json" > "$temp_script"
            ;;
        "-count")
            # No special mode needed for count
            ;;
    esac
    
    # Process parameters in pairs (name and value)
    while [[ $# -ge 2 ]]; do
        local param_name="$1"
        local param_value="$2"
        
        # Add parameter binding with proper escaping
        echo ".param set ${param_name} \"${param_value}\"" >> "$temp_script"
        shift 2
    done
    
    # Add the SQL query
    echo "$sql" >> "$temp_script"
    
    # Execute the query with correct parameter binding
    sqlite3 "$DB_FILE" < "$temp_script"
    local status=$?
    
    # Remove the temporary script
    rm -f "$temp_script"
    unregister_operation "db_temp_script"
    
    # Handle errors
    if [[ $status -ne 0 ]]; then
        handle_error "$ERR_DB_QUERY" "SQL query failed with parameters (check logs for details)"
        # Full query is logged only in debug mode
        log_debug "Failed parameterized SQL query was: $sql"
        return $ERR_DB_QUERY
    fi
    
    return 0
}

# Execute a transaction with multiple SQL statements
# Usage: db_transaction <sql_statements>
db_transaction() {
    local sql_statements="$1"
    
    # Make sure database exists
    ensure_database || return $?
    
    # Create a temporary script file with secure permissions
    local temp_script
    temp_script=$(mktemp)
    chmod 600 "$temp_script"  # Set secure permissions (0600: only owner can read/write)
    register_operation "db_temp_transaction" "rm -f ${temp_script}"
    
    # Add transaction wrapping
    echo "BEGIN TRANSACTION;" > "$temp_script"
    echo "$sql_statements" >> "$temp_script"
    echo "COMMIT;" >> "$temp_script"
    
    # Execute the transaction
    sqlite3 "$DB_FILE" < "$temp_script"
    local status=$?
    
    # Remove the temporary script
    rm -f "$temp_script"
    unregister_operation "db_temp_transaction"
    
    # Handle errors
    if [[ $status -ne 0 ]]; then
        handle_error "$ERR_DB_QUERY" "Database transaction failed"
        return $ERR_DB_QUERY
    fi
    
    return 0
}

# Check if a table exists in the database
# Usage: table_exists <table_name>
table_exists() {
    local table_name="$1"
    local count
    
    # Make sure database exists
    if [[ ! -f "$DB_FILE" ]]; then
        return 1
    fi
    
    # Execute query with parameter binding
    count=$(db_execute_params -count "SELECT count(*) FROM sqlite_master WHERE type='table' AND name = :table_name;" \
        ":table_name" "$table_name")
    
    # Return true if found, false otherwise
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Create backup of the database
# Usage: backup_database [suffix]
backup_database() {
    local suffix="${1:-$(date +%Y%m%d%H%M%S)}"
    local backup_file="${DB_FILE}.backup.${suffix}"
    
    # Make sure database exists
    if [[ ! -f "$DB_FILE" ]]; then
        handle_error "$ERR_FILE_GENERAL" "Database file does not exist, cannot create backup"
        return $ERR_FILE_GENERAL
    fi
    
    log_info "Creating database backup: $backup_file"
    
    # Create the backup
    sqlite3 "$DB_FILE" ".backup '$backup_file'"
    
    # Check if backup was successful
    if [[ $? -ne 0 || ! -f "$backup_file" ]]; then
        handle_error "$ERR_FILE_GENERAL" "Failed to create database backup"
        return $ERR_FILE_GENERAL
    fi
    
    # Set secure permissions for backup file
    chmod 600 "$backup_file" || {
        log_warning "Failed to set secure permissions on backup file"
    }
    
    log_success "Database backup created successfully: $backup_file"
    return 0
}

# Get the schema version from the database
# Usage: get_schema_version
get_schema_version() {
    local version
    
    # Make sure database exists
    if [[ ! -f "$DB_FILE" ]]; then
        echo "$DB_VERSION"  # Default to current version if DB doesn't exist yet
        return 0
    fi
    
    # Query the schema version
    version=$(db_execute -count "SELECT version FROM schema_info LIMIT 1;" 2>/dev/null)
    
    # If query failed or no version found, use default
    if [[ $? -ne 0 || -z "$version" ]]; then
        echo "$DB_VERSION"
        return 1
    fi
    
    echo "$version"
    return 0
}

# Export functions
export -f init_database
export -f ensure_database
export -f db_execute
export -f db_execute_params
export -f db_transaction
export -f table_exists
export -f backup_database
export -f get_schema_version