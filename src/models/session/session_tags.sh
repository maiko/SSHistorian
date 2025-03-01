#!/usr/bin/env bash
#
# SSHistorian - Session Tags Module
# Functions for managing session tags
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

# Source session model if not already loaded
if ! command -v get_session &>/dev/null; then
    # shellcheck source=./session_model.sh
    source "${SCRIPT_DIR}/session_model.sh"
fi

# Get all tags for a session
# Usage: get_session_tags <uuid>
get_session_tags() {
    local uuid="$1"
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    fi
    
    # Log the operation
    log_debug "Getting session tags: uuid=$uuid"
    
    # Query the database using parameter binding
    local tags
    tags=$(db_execute_params -line "SELECT tag FROM tags WHERE session_id = :uuid ORDER BY created_at;" \
        ":uuid" "$uuid" | grep -v "^[[:space:]]*$" | sed -n 's/^[[:space:]]*tag = \(.*\)$/\1/p')
    
    # Output the tags, one per line (even if empty)
    echo "$tags"
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
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    fi
    
    # Validate tag
    if [[ -z "$tag" ]]; then
        handle_error "$ERR_ARGS" "Tag cannot be empty"
        return $ERR_ARGS
    fi
    
    # Sanitize the tag (allowing only alphanumeric characters, dots, underscores, and hyphens)
    # This prevents SQL injection and ensures consistent tag format
    tag=$(echo "$tag" | tr -c '[:alnum:]._-' '_')
    
    # Make sure the session exists
    if ! get_session "$uuid" &>/dev/null; then
        handle_error "$ERR_DB_NOT_FOUND" "Session not found: $uuid"
        return $ERR_DB_NOT_FOUND
    }
    
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
        handle_error "$ERR_DB_GENERAL" "Failed to add tag to session"
        return $ERR_DB_GENERAL
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
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    fi
    
    # Validate tag
    if [[ -z "$tag" ]]; then
        handle_error "$ERR_ARGS" "Tag cannot be empty"
        return $ERR_ARGS
    fi
    
    # Sanitize the tag
    tag=$(sanitize_input "$tag")
    
    # Log the operation
    log_debug "Removing tag from session: uuid=$uuid, tag=$tag"
    
    # Delete the tag using parameter binding to prevent SQL injection
    db_execute_params "DELETE FROM tags WHERE session_id = :session_id AND tag = :tag;" \
        ":session_id" "$uuid" \
        ":tag" "$tag"
    
    # Check if delete was successful
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to remove tag from session"
        return $ERR_DB_GENERAL
    fi
    
    log_success "Tag removed from session: $tag"
    return 0
}

# List all available tags in the system with counts
# Usage: list_all_tags
list_all_tags() {
    # Query the database for tags with counts
    db_execute -table "SELECT tag, COUNT(*) as session_count 
        FROM tags 
        GROUP BY tag 
        ORDER BY session_count DESC, tag ASC;"
    
    return $?
}

# Find sessions with specific tag
# Usage: find_sessions_by_tag <tag> [--limit <limit>]
find_sessions_by_tag() {
    local tag="$1"
    local limit=10
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                limit="$1"
                ;;
            *)
                log_warning "Unknown option: $1"
                ;;
        esac
        shift
    done
    
    # Validate tag
    if [[ -z "$tag" ]]; then
        handle_error "$ERR_ARGS" "Tag cannot be empty"
        return $ERR_ARGS
    fi
    
    # Sanitize the tag
    tag=$(sanitize_input "$tag")
    
    # Query the database using parameter binding
    db_execute_params -line "SELECT 
        s.id, s.host, s.timestamp, s.command, s.user, s.remote_user,
        s.exit_code, s.duration, s.created_at,
        (SELECT GROUP_CONCAT(t.tag, ', ') FROM tags t WHERE t.session_id = s.id) AS tags
        FROM sessions s
        JOIN tags t ON s.id = t.session_id
        WHERE t.tag = :tag
        GROUP BY s.id
        ORDER BY s.timestamp DESC
        LIMIT :limit;" \
        ":tag" "$tag" \
        ":limit" "$limit"
    
    return $?
}

# Auto-tag a session based on patterns
# Usage: auto_tag_session <uuid> <patterns_file>
auto_tag_session() {
    local uuid="$1"
    local patterns_file="$2"
    local added_tags=0
    
    # Validate UUID
    if ! is_uuid "$uuid"; then
        handle_error "$ERR_ARGS" "Invalid UUID format: $uuid"
        return $ERR_ARGS
    fi
    
    # Validate patterns file
    if [[ ! -f "$patterns_file" || ! -r "$patterns_file" ]]; then
        handle_error "$ERR_FILE_GENERAL" "Patterns file not found or not readable: $patterns_file"
        return $ERR_FILE_GENERAL
    }
    
    # Get session details
    local session_data
    session_data=$(get_session "$uuid")
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_NOT_FOUND" "Session not found: $uuid"
        return $ERR_DB_NOT_FOUND
    }
    
    # Extract host and command for pattern matching
    local host command
    host=$(echo "$session_data" | grep "host" | cut -d "=" -f 2 | xargs)
    command=$(echo "$session_data" | grep "command" | cut -d "=" -f 2 | xargs)
    
    # Read patterns file and apply tags
    while IFS=':' read -r pattern tag || [[ -n "$pattern" ]]; do
        # Skip comments and empty lines
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        
        # Trim whitespace from pattern and tag
        pattern=$(echo "$pattern" | xargs)
        tag=$(echo "$tag" | xargs)
        
        # Skip if pattern or tag is empty
        [[ -z "$pattern" || -z "$tag" ]] && continue
        
        # Check if host or command matches the pattern
        if [[ "$host" =~ $pattern || "$command" =~ $pattern ]]; then
            # Add the tag
            if add_session_tag "$uuid" "$tag" &>/dev/null; then
                log_debug "Auto-tagged session $uuid with '$tag' (matched pattern: $pattern)"
                ((added_tags++))
            fi
        fi
    done < "$patterns_file"
    
    log_info "Added $added_tags tags to session $uuid based on patterns"
    return 0
}

# Export functions
export -f get_session_tags
export -f add_session_tag
export -f remove_session_tag
export -f list_all_tags
export -f find_sessions_by_tag
export -f auto_tag_session