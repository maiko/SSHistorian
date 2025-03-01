#!/usr/bin/env bash
#
# SSHistorian - Sessions Database Model
# Functions for managing session records in the database

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../../utils/constants.sh
    source "${SCRIPT_DIR}/../../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../../utils/common.sh
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Source error handling module if not already loaded
if ! command -v handle_error &>/dev/null; then
    # shellcheck source=../../utils/errors.sh
    source "${ROOT_DIR}/src/utils/errors.sh"
fi

# Source database module if not already loaded
if ! command -v init_database &>/dev/null; then
    # shellcheck source=../database.sh
    source "${ROOT_DIR}/src/db/database.sh"
fi

# Source database core if not already loaded
if ! command -v db_execute_params &>/dev/null; then
    # shellcheck source=../core/db_core.sh
    source "${ROOT_DIR}/src/db/core/db_core.sh"
fi

# Create a new session record in the database
# Usage: create_session <host> <command> [remote_user]
create_session() {
    local host="$1"
    local command="$2"
    local remote_user="${3:-}"
    local uuid timestamp created_at user log_path timing_path
    
    # Generate a UUID for the session
    uuid=$(generate_uuid)
    
    # Get current timestamp
    timestamp=$(get_iso_timestamp)
    created_at="$timestamp"
    
    # Get current user
    user=$(whoami)
    
    # Extract remote user from command if not provided
    if [[ -z "$remote_user" && "$command" =~ [[:space:]]([a-zA-Z0-9_-]+)@([a-zA-Z0-9._-]+) ]]; then
        remote_user="${BASH_REMATCH[1]}"
    fi
    
    # Construct log paths (relative to LOG_DIR)
    log_path="${uuid}.log"
    timing_path="${uuid}.timing"
    
    # Log session creation for debugging
    log_debug "Creating session: uuid=$uuid, host=$host, user=$user, remote_user=${remote_user:-NULL}"
    
    # Prepare SQL query
    local sql="INSERT INTO sessions (
    id, host, timestamp, command, user, remote_user, 
    created_at, log_path, timing_path
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
    
    # Execute the query with parameters
    if [[ -n "$remote_user" ]]; then
        # With remote user
        db_execute_params "INSERT INTO sessions (
        id, host, timestamp, command, user, remote_user, 
        created_at, log_path, timing_path
        ) VALUES (:uuid, :host, :timestamp, :command, :user, :remote_user, :created_at, :log_path, :timing_path);" \
            ":uuid" "$uuid" \
            ":host" "$host" \
            ":timestamp" "$timestamp" \
            ":command" "$command" \
            ":user" "$user" \
            ":remote_user" "$remote_user" \
            ":created_at" "$created_at" \
            ":log_path" "$log_path" \
            ":timing_path" "$timing_path"
    else
        # Use explicit NULL for empty remote_user
        db_execute_params "INSERT INTO sessions (
        id, host, timestamp, command, user, remote_user, 
        created_at, log_path, timing_path
        ) VALUES (:uuid, :host, :timestamp, :command, :user, NULL, :created_at, :log_path, :timing_path);" \
            ":uuid" "$uuid" \
            ":host" "$host" \
            ":timestamp" "$timestamp" \
            ":command" "$command" \
            ":user" "$user" \
            ":created_at" "$created_at" \
            ":log_path" "$log_path" \
            ":timing_path" "$timing_path"
    fi
    
    # Check if insert was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create session record"
        return 1
    fi
    
    # Return the UUID
    echo "$uuid"
    return 0
}

# Update session with exit code and duration
# Usage: update_session_exit <uuid> <exit_code> [duration]
update_session_exit() {
    local uuid="$1"
    local exit_code="$2"
    local duration="${3:-NULL}"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Ensure exit_code and duration are integers
    if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
        log_error "Invalid exit code: $exit_code - must be an integer"
        exit_code=1  # Default to error exit code
    fi
    
    if [[ "$duration" != "NULL" && ! "$duration" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid duration: $duration - must be an integer. Using NULL instead."
        duration="NULL"
    fi
    
    # Log the operation
    log_debug "Updating session exit: uuid=$uuid, exit_code=$exit_code, duration=$duration"
    
    # Update the session record using parameter binding to prevent SQL injection
    if [[ "$duration" == "NULL" ]]; then
        # Handle NULL specially since SQLite parameter binding doesn't handle NULL directly
        db_execute_params "UPDATE sessions SET exit_code = :exit_code, duration = NULL WHERE id = :uuid;" \
            ":exit_code" "$exit_code" \
            ":uuid" "$uuid"
    else
        db_execute_params "UPDATE sessions SET exit_code = :exit_code, duration = :duration WHERE id = :uuid;" \
            ":exit_code" "$exit_code" \
            ":duration" "$duration" \
            ":uuid" "$uuid"
    fi
    
    # Check if update was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to update session exit code"
        return 1
    fi
    
    return 0
}

# Get session details by UUID
# Usage: get_session <uuid>
get_session() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Log the operation
    log_debug "Getting session details: uuid=$uuid"
    
    # Query the database using parameter binding to prevent SQL injection
    local sql="SELECT 
    id, host, timestamp, command, user, remote_user,
    exit_code, duration, created_at, log_path, timing_path, notes
FROM sessions
WHERE id = :uuid;"
    
    db_execute_params "$sql" ":uuid" "$uuid"
    
    # Check if query was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve session: $uuid"
        return 1
    fi
    
    return 0
}

# Get all tags for a session
# Usage: get_session_tags <uuid>
get_session_tags() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Log the operation
    log_debug "Getting session tags: uuid=$uuid"
    
    # Query the database using parameter binding
    local sql="SELECT tag
FROM tags
WHERE session_id = :uuid
ORDER BY created_at;"
    
    db_execute_params "$sql" ":uuid" "$uuid" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*tag = \(.*\)$/\1/p'
    
    return 0
}

# List sessions with optional filtering
# Usage: list_sessions [--limit N] [--host name] [--tag name] [--days N] [--exit-code N]
list_sessions() {
    local limit=10
    local where_clauses=""
    local order_by="s.timestamp DESC"
    local params=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                limit="$1"
                ;;
            --host)
                shift
                local host_value="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.host = ?"
                params+=("$host_value")
                ;;
            --tag)
                shift
                local tag_value="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.id IN (
                    SELECT session_id FROM tags WHERE tag = ?
                )"
                params+=("$tag_value")
                ;;
            --days)
                shift
                where_clauses="${where_clauses:+$where_clauses AND }s.created_at >= datetime('now', '-$1 days')"
                ;;
            --exit-code)
                shift
                local exit_code_value="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.exit_code = ?"
                params+=("$exit_code_value")
                ;;
            --sort-field)
                shift
                local field="$1"
                if [[ "$field" == "created_at" || "$field" == "timestamp" || "$field" == "host" ]]; then
                    order_by="s.$field DESC"
                fi
                ;;
            *)
                log_warning "Unknown option: $1"
                ;;
        esac
        shift
    done
    
    # Construct the WHERE clause
    local where_sql=""
    if [[ -n "$where_clauses" ]]; then
        where_sql="WHERE $where_clauses"
    fi
    
    # Query the database
    local sql="SELECT 
    s.id, s.host, s.timestamp, s.command, s.user, s.remote_user,
    s.exit_code, s.duration, s.created_at,
    (SELECT GROUP_CONCAT(tag, ', ') FROM tags WHERE session_id = s.id) AS tags
FROM sessions s
$where_sql
ORDER BY $order_by
LIMIT $limit;"
    
    # Execute the query with parameters
    if [[ ${#params[@]} -gt 0 ]]; then
        db_execute_params "$sql" "${params[@]}"
    else
        db_execute "$sql"
    fi
    
    return 0
}

# Delete a session and its associated data
# Usage: delete_session <uuid>
delete_session() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Log the operation
    log_debug "Deleting session: uuid=$uuid"
    
    # Get the log paths before deleting
    local log_path timing_path
    local result
    result=$(db_execute_params -line "SELECT log_path, timing_path FROM sessions WHERE id = :uuid;" \
        ":uuid" "$uuid")
    log_path=$(echo "$result" | grep "log_path" | cut -d "=" -f 2 | xargs)
    timing_path=$(echo "$result" | grep "timing_path" | cut -d "=" -f 2 | xargs)
    
    # Use a transaction with parameterized queries
    # Begin transaction
    db_execute "BEGIN TRANSACTION;"
    
    # Delete tags with parameterized query
    db_execute_params "DELETE FROM tags WHERE session_id = :uuid;" ":uuid" "$uuid"
    
    # Delete encryption info with parameterized query
    db_execute_params "DELETE FROM encryption_info WHERE session_id = :uuid;" ":uuid" "$uuid"
    
    # Delete session with parameterized query
    db_execute_params "DELETE FROM sessions WHERE id = :uuid;" ":uuid" "$uuid"
    
    # Commit transaction
    db_execute "COMMIT;"
    
    # Check if transaction was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to delete session: $uuid"
        return $ERR_DB_GENERAL
    fi
    
    # Enhanced path security validation using canonical paths
    # Only allow operations on files that are within LOG_DIR and match expected patterns
    
    # Canonicalize LOG_DIR for path containment checks 
    local canonical_log_dir
    canonical_log_dir=$(normalize_path "$LOG_DIR")
    
    # Helper function to safely delete a file with proper validation
    # Usage: safely_delete_file <file_path> <file_type> <expected_pattern>
    safely_delete_file() {
        local path="$1"
        local file_type="$2"
        local expected_pattern="$3"
        
        # Skip if path is empty
        if [[ -z "$path" ]]; then
            return 0
        fi
        
        # Validate file has expected name format
        if [[ "$path" =~ $expected_pattern ]]; then
            # Get full path and check if it's safely contained within LOG_DIR
            local full_path="${LOG_DIR}/${path}"
            local canonical_path
            canonical_path=$(normalize_path "$full_path")
            
            # Ensure file exists and is within LOG_DIR
            if [[ -f "$canonical_path" ]] && is_safe_path "$canonical_path" "$canonical_log_dir"; then
                rm -f "$canonical_path"
                log_debug "Deleted ${file_type} file: $canonical_path"
            else
                log_warning "${file_type} file not found or invalid path: $full_path"
            fi
            
            # Check for encrypted version
            local encrypted_path="${canonical_path}.enc"
            if [[ -f "$encrypted_path" ]] && is_safe_path "$encrypted_path" "$canonical_log_dir"; then
                rm -f "$encrypted_path"
                log_debug "Deleted encrypted ${file_type} file: $encrypted_path"
            fi
        else
            log_warning "Invalid ${file_type} filename pattern: $path"
        fi
        
        return 0
    }
    
    # Delete log and timing files with strict path validation
    safely_delete_file "$log_path" "log" "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.log$"
    safely_delete_file "$timing_path" "timing" "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.timing$"
    
    log_success "Session deleted: $uuid"
    return 0
}

# Add a tag to a session
# Usage: add_session_tag <uuid> <tag>
add_session_tag() {
    local uuid="$1"
    local tag="$2"
    local created_at
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Sanitize the tag (allowing only alphanumeric characters, dots, underscores, and hyphens)
    tag=$(echo "$tag" | tr -c '[:alnum:]._-' '_')
    
    # Make sure the session exists
    local session_exists
    session_exists=$(db_execute_params -count "SELECT COUNT(*) FROM sessions WHERE id = :uuid;" \
        ":uuid" "$uuid")
    if [[ "$session_exists" -eq 0 ]]; then
        log_error "Session not found: $uuid"
        return 1
    fi
    
    # Get current timestamp
    created_at=$(get_iso_timestamp)
    
    # Log the tag operation
    log_debug "Adding tag to session: uuid=$uuid, tag=$tag"
    
    # Insert the tag using parameter binding to prevent SQL injection
    db_execute_params "INSERT OR REPLACE INTO tags (session_id, tag, created_at)
VALUES (:session_id, :tag, :created_at);" \
        ":session_id" "$uuid" \
        ":tag" "$tag" \
        ":created_at" "$created_at"
    
    # Check if insert was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to add tag to session"
        return 1
    fi
    
    log_success "Tag added to session: $tag"
    return 0
}

# Remove a tag from a session
# Usage: remove_session_tag <uuid> <tag>
remove_session_tag() {
    local uuid="$1"
    local tag="$2"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        log_error "Invalid UUID format: $uuid"
        return 1
    fi
    
    # Sanitize the tag
    tag=$(sanitize_input "$tag")
    
    # Log the operation
    log_debug "Removing tag from session: uuid=$uuid, tag=$tag"
    
    # Delete the tag using parameter binding to prevent SQL injection
    db_execute_params "DELETE FROM tags
WHERE session_id = :session_id AND tag = :tag;" \
        ":session_id" "$uuid" \
        ":tag" "$tag"
    
    # Check if delete was successful
    if [[ $? -ne 0 ]]; then
        log_error "Failed to remove tag from session"
        return 1
    fi
    
    log_success "Tag removed from session: $tag"
    return 0
}

# Export functions
export -f create_session
export -f update_session_exit
export -f get_session
export -f get_session_tags
export -f list_sessions
export -f delete_session
export -f add_session_tag
export -f remove_session_tag