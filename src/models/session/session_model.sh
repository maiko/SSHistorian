#!/usr/bin/env bash
#
# SSHistorian - Session Model
# Core functions for session record management

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

# Source error handling if not already loaded
if ! command -v handle_error &>/dev/null; then
    # shellcheck source=../../utils/errors.sh
    source "${ROOT_DIR}/src/utils/errors.sh"
fi

# Source database core if not already loaded
if ! command -v db_execute &>/dev/null; then
    # shellcheck source=../../db/core/db_core.sh
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
    
    # Prepare SQL query with proper parameter binding
    db_execute_params "INSERT INTO sessions (
        id, host, timestamp, command, user, remote_user, 
        created_at, log_path, timing_path
    ) VALUES (
        :id, :host, :timestamp, :command, :user, :remote_user, 
        :created_at, :log_path, :timing_path
    );" \
        ":id" "$uuid" \
        ":host" "$host" \
        ":timestamp" "$timestamp" \
        ":command" "$command" \
        ":user" "$user" \
        ":remote_user" "${remote_user:-NULL}" \
        ":created_at" "$created_at" \
        ":log_path" "$log_path" \
        ":timing_path" "$timing_path"
    
    # Check if insert was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to create session record"
        return $ERR_DB_GENERAL
    }
    
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
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    }
    
    # Ensure exit_code and duration are integers
    if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid exit code: $exit_code - must be an integer. Using 1 instead."
        exit_code=1  # Default to error exit code
    fi
    
    if [[ "$duration" != "NULL" && ! "$duration" =~ ^[0-9]+$ ]]; then
        log_warning "Invalid duration: $duration - must be an integer. Using NULL instead."
        duration="NULL"
    fi
    
    # Log the operation
    log_debug "Updating session exit: uuid=$uuid, exit_code=$exit_code, duration=$duration"
    
    # Update the session record using parameter binding
    if [[ "$duration" == "NULL" ]]; then
        # Handle NULL specially since SQLite parameter binding doesn't directly support NULL
        db_execute_params "UPDATE sessions SET exit_code = :exit_code, duration = NULL WHERE id = :id;" \
            ":exit_code" "$exit_code" \
            ":id" "$uuid"
    else
        db_execute_params "UPDATE sessions SET exit_code = :exit_code, duration = :duration WHERE id = :id;" \
            ":exit_code" "$exit_code" \
            ":duration" "$duration" \
            ":id" "$uuid"
    fi
    
    # Check if update was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to update session exit code"
        return $ERR_DB_GENERAL
    }
    
    return 0
}

# Get session details by UUID
# Usage: get_session <uuid>
get_session() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    }
    
    # Log the operation
    log_debug "Getting session details: uuid=$uuid"
    
    # Query the database using parameter binding
    local result
    result=$(db_execute_params -line "SELECT 
        id, host, timestamp, command, user, remote_user,
        exit_code, duration, created_at, log_path, timing_path, notes
    FROM sessions
    WHERE id = :id;" ":id" "$uuid")
    
    # Check if query was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_NOT_FOUND" "Failed to retrieve session: $uuid"
        return $ERR_DB_NOT_FOUND
    }
    
    # Check if any results were found
    if [[ -z "$result" ]]; then
        handle_error "$ERR_DB_NOT_FOUND" "Session not found: $uuid"
        return $ERR_DB_NOT_FOUND
    }
    
    # Output the result
    echo "$result"
    return 0
}

# List sessions with optional filtering
# Usage: list_sessions [--limit N] [--host name] [--tag name] [--days N] [--exit-code N]
list_sessions() {
    local limit=10
    local where_clauses=""
    local order_by="s.timestamp DESC"
    local params=()
    local param_values=()
    
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
                where_clauses="${where_clauses:+$where_clauses AND }s.host = :host"
                params+=("host")
                param_values+=("$host_value")
                ;;
            --tag)
                shift
                local tag_value="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.id IN (
                    SELECT session_id FROM tags WHERE tag = :tag
                )"
                params+=("tag")
                param_values+=("$tag_value")
                ;;
            --days)
                shift
                where_clauses="${where_clauses:+$where_clauses AND }s.created_at >= datetime('now', '-$1 days')"
                ;;
            --exit-code)
                shift
                local exit_code_value="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.exit_code = :exit_code"
                params+=("exit_code")
                param_values+=("$exit_code_value")
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
    
    # Construct the SQL query
    local sql="SELECT 
        s.id, s.host, s.timestamp, s.command, s.user, s.remote_user,
        s.exit_code, s.duration, s.created_at,
        (SELECT GROUP_CONCAT(tag, ', ') FROM tags WHERE session_id = s.id) AS tags
    FROM sessions s
    $where_sql
    ORDER BY $order_by
    LIMIT $limit;"
    
    # Build parameter bindings for the query
    local param_args=()
    for i in "${!params[@]}"; do
        param_args+=(":${params[$i]}" "${param_values[$i]}")
    done
    
    # Execute the query with parameters
    if [[ ${#param_args[@]} -gt 0 ]]; then
        db_execute_params -line "$sql" "${param_args[@]}"
    else
        db_execute -line "$sql"
    fi
    
    return $?
}

# Delete a session and its associated data
# Usage: delete_session <uuid>
delete_session() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    }
    
    # Log the operation
    log_debug "Deleting session: uuid=$uuid"
    
    # Get the log paths before deleting
    local log_path timing_path
    read -r log_path timing_path < <(db_execute_params -line "SELECT log_path, timing_path FROM sessions WHERE id = :uuid;" \
        ":uuid" "$uuid" | grep -E "log_path|timing_path" | sed -e 's/^[[:space:]]*log_path = \(.*\)$/\1/' -e 's/^[[:space:]]*timing_path = \(.*\)$/\1/')
    
    # Use parameterized query to delete each component
    # Delete tags
    db_execute_params "DELETE FROM tags WHERE session_id = :uuid;" ":uuid" "$uuid"
    
    # Delete encryption info
    db_execute_params "DELETE FROM encryption_info WHERE session_id = :uuid;" ":uuid" "$uuid"
    
    # Delete session
    db_execute_params "DELETE FROM sessions WHERE id = :uuid;" ":uuid" "$uuid"
    
    # Check if transaction was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to delete session database records: $uuid"
        return $ERR_DB_GENERAL
    }
    
    # Delete log files if they exist
    if [[ -n "$log_path" ]]; then
        delete_session_file "$log_path" "log"
    fi
    
    if [[ -n "$timing_path" ]]; then
        delete_session_file "$timing_path" "timing"
    fi
    
    log_success "Session deleted: $uuid"
    return 0
}

# Helper for safely deleting session files
# Usage: delete_session_file <file_path> <file_type>
delete_session_file() {
    local path="$1"
    local file_type="$2"
    local expected_pattern=""
    
    # Set expected pattern based on file type
    case "$file_type" in
        "log")
            expected_pattern="^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.log$"
            ;;
        "timing")
            expected_pattern="^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.timing$"
            ;;
        *)
            log_warning "Invalid file type for deletion: $file_type"
            return 1
            ;;
    esac
    
    # Skip if path is empty
    if [[ -z "$path" ]]; then
        return 0
    fi
    
    # Validate file has expected name format
    if [[ "$path" =~ $expected_pattern ]]; then
        # Get full path and check if it's safely contained within LOG_DIR
        local full_path="${LOG_DIR}/${path}"
        
        # Validate path for security
        if is_path_secure "$full_path"; then
            if [[ -f "$full_path" ]]; then
                rm -f "$full_path"
                log_debug "Deleted ${file_type} file: $full_path"
            else
                log_debug "${file_type} file not found: $full_path"
            fi
            
            # Check for encrypted version
            local encrypted_path="${full_path}.enc"
            if [[ -f "$encrypted_path" ]]; then
                rm -f "$encrypted_path"
                log_debug "Deleted encrypted ${file_type} file: $encrypted_path"
            fi
        else
            log_warning "Security violation: Path traversal attempt when deleting ${file_type} file: $full_path"
        fi
    else
        log_warning "Invalid ${file_type} filename pattern: $path"
    fi
    
    return 0
}

# Validate that a path is securely contained within the log directory
# Usage: is_path_secure <path>
is_path_secure() {
    local path="$1"
    
    # Canonicalize both paths for comparison
    local canonical_path canonical_log_dir
    canonical_path=$(normalize_path "$path")
    canonical_log_dir=$(normalize_path "$LOG_DIR")
    
    # Check if the normalized path starts with the normalized log directory
    if [[ "$canonical_path" == "$canonical_log_dir"* ]]; then
        return 0
    else
        return 1
    fi
}

# Export functions
export -f create_session
export -f update_session_exit
export -f get_session
export -f list_sessions
export -f delete_session
export -f delete_session_file
export -f is_path_secure