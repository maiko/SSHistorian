#!/usr/bin/env bash
#
# SSHistorian - Session Replay Module
# Functions for replaying recorded SSH sessions
#

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../../utils/constants.sh
    source "${ROOT_DIR}/src/utils/constants.sh"
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

# Source config module if not already loaded
if ! command -v get_config &>/dev/null; then
    # shellcheck source=../../config/config.sh
    source "${ROOT_DIR}/src/config/config.sh"
fi

# Source encryption module if not already loaded
if ! command -v decrypt_file &>/dev/null; then
    # shellcheck source=../encryption.sh
    source "${ROOT_DIR}/src/core/encryption.sh"
fi

# Source database models if not already loaded
if ! command -v get_session &>/dev/null; then
    # shellcheck source=../../db/models/sessions.sh
    source "${ROOT_DIR}/src/db/models/sessions.sh"
fi

# Replay a recorded SSH session
# Usage: replay_session <session_id> [--html]
replay_session() {
    local session_id="$1"
    local html_mode="${2:-}"
    
    # Validate UUID (case insensitive)
    if ! is_uuid "$session_id"; then
        handle_error "$ERR_ARGS" "Invalid session ID: $session_id"
        return $ERR_ARGS
    fi
    
    # Get session details from database
    local session_data
    session_data=$(get_session "$session_id")
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_NOT_FOUND" "Session not found: $session_id"
        return $ERR_DB_NOT_FOUND
    fi
    
    # Extract log paths from session data
    local log_path timing_path
    log_path=$(echo "$session_data" | grep "log_path" | cut -d "=" -f 2 | xargs)
    timing_path=$(echo "$session_data" | grep "timing_path" | cut -d "=" -f 2 | xargs)
    
    # Validate log paths before using them (only allow files with specific patterns)
    if ! is_valid_log_path "$log_path" || ! is_valid_timing_path "$timing_path"; then
        handle_error "$ERR_FILE_PATH" "Invalid log path format"
        return $ERR_FILE_PATH
    fi
    
    # Get the actual file paths
    local log_file timing_file
    log_file="${LOG_DIR}/${log_path}"
    timing_file="${LOG_DIR}/${timing_path}"
    
    # Validate paths are contained within LOG_DIR (path traversal protection)
    if ! is_path_secure "$log_file" || ! is_path_secure "$timing_file"; then
        handle_error "$ERR_FILE_TRAVERSAL" "Security violation: Path escapes from log directory"
        return $ERR_FILE_TRAVERSAL
    fi
    
    # Check if files are encrypted and decrypt if needed
    local is_encrypted=false
    local temp_dir=""
    
    if ! prepare_replay_files "$log_file" "$timing_file"; then
        handle_error "$ERR_FILE_GENERAL" "Failed to prepare replay files"
        return $ERR_FILE_GENERAL
    fi
    
    # Show session details
    echo -e "${BLUE}Session Details:${NC}"
    echo "$session_data"
    echo ""
    
    # Show session tags
    local tags
    tags=$(get_session_tags "$session_id")
    if [[ -n "$tags" ]]; then
        echo -e "${BLUE}Session Tags:${NC}"
        echo "$tags"
        echo ""
    fi
    
    # Check if we should generate HTML replay or use terminal replay
    if [[ "$html_mode" == "--html" ]]; then
        replay_session_html "$session_id" "$log_file" "$timing_file"
    else
        replay_session_terminal "$log_file" "$timing_file"
    fi
    
    local replay_result=$?
    
    # Clean up temporary files if they were created
    cleanup_replay_files
    
    return $replay_result
}

# Validate log file path format
# Usage: is_valid_log_path <path>
is_valid_log_path() {
    local path="$1"
    
    # Check if path matches expected UUID format for log files
    if [[ "$path" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.log$ ]]; then
        return 0
    else
        log_error "Invalid log path format: $path"
        return 1
    fi
}

# Validate timing file path format
# Usage: is_valid_timing_path <path>
is_valid_timing_path() {
    local path="$1"
    
    # Check if path matches expected UUID format for timing files
    if [[ "$path" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.timing$ ]]; then
        return 0
    else
        log_error "Invalid timing path format: $path"
        return 1
    fi
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
        log_error "Security violation: Path traversal attempt detected"
        # Path details are only logged in debug mode
        log_debug "Path traversal attempt with path: $path"
        return 1
    fi
}

# Prepare files for replay, handling decryption if needed
# Usage: prepare_replay_files <log_file> <timing_file>
# Sets global variables log_file, timing_file, is_encrypted, and temp_dir
prepare_replay_files() {
    log_file="$1"
    timing_file="$2"
    is_encrypted=false
    temp_dir=""
    
    # Check if files exist directly or in encrypted form
    if [[ ! -f "$log_file" && -f "${log_file}.enc" ]]; then
        is_encrypted=true
        
        # Create secure temporary directory for decrypted content
        temp_dir=$(mktemp -d) || {
            log_error "Failed to create temporary directory for decrypted files"
            return 1
        }
        
        # Register for cleanup
        register_operation "replay_temp_dir" "rm -rf '$temp_dir'"
        
        # Set proper permissions immediately
        chmod 700 "$temp_dir"
        
        # Generate temporary file paths
        local temp_log="${temp_dir}/$(basename "$log_file")"
        local temp_timing="${temp_dir}/$(basename "$timing_file")"
        
        # Create empty files with secure permissions
        touch "$temp_log" "$temp_timing"
        chmod 600 "$temp_log" "$temp_timing"
        
        # Decrypt files
        log_info "Decrypting session files..."
        decrypt_file "${log_file}.enc" "$temp_log" || return 1
        decrypt_file "${timing_file}.enc" "$temp_timing" || return 1
        
        # Update paths to use temporary files
        log_file="$temp_log"
        timing_file="$temp_timing"
        
    elif [[ ! -f "$log_file" || ! -f "$timing_file" ]]; then
        log_error "Session files not found: $log_file"
        return 1
    fi
    
    return 0
}

# Clean up temporary files created for replay
# Usage: cleanup_replay_files
cleanup_replay_files() {
    if [[ "$is_encrypted" == "true" && -n "$temp_dir" && -d "$temp_dir" ]]; then
        rm -rf "$temp_dir" 2>/dev/null || true
        unregister_operation "replay_temp_dir"
    fi
    
    return 0
}

# Replay session in terminal using scriptreplay
# Usage: replay_session_terminal <log_file> <timing_file>
replay_session_terminal() {
    local log_file="$1"
    local timing_file="$2"
    
    log_info "Replaying SSH session in terminal..."
    
    # Check if scriptreplay is available
    if command -v scriptreplay &>/dev/null; then
        # Use scriptreplay with appropriate options
        scriptreplay --timing="$timing_file" "$log_file"
        return $?
    else
        log_warning "scriptreplay not found. Showing log content instead:"
        cat "$log_file"
        return 0
    fi
}

# Replay session in HTML format using TermRecord
# Usage: replay_session_html <session_id> <log_file> <timing_file>
replay_session_html() {
    local session_id="$1"
    local log_file="$2"
    local timing_file="$3"
    
    # Check if TermRecord is available
    if ! command -v TermRecord &>/dev/null; then
        handle_error "$ERR_DEPENDENCY" "TermRecord not found. Please install it with: pip3 install TermRecord"
        return $ERR_DEPENDENCY
    fi
    
    # Generate HTML replay file with path validation
    local output_basename="${session_id}_replay.html"
    local output_file="${LOG_DIR}/${output_basename}"
    
    # Validate output path for security
    if ! is_path_secure "$output_file"; then
        handle_error "$ERR_FILE_PATH" "Invalid output file path"
        return $ERR_FILE_PATH
    fi
    
    log_info "Generating HTML playback..."
    
    # Generate HTML playback file
    if TermRecord -t "$timing_file" -s "$log_file" -o "$output_file"; then
        # Set secure permissions
        chmod 600 "$output_file" || log_warning "Failed to set permissions on HTML replay file"
        
        # Get just the filename without full path for user display
        local output_basename=$(basename "$output_file")
        local output_dir=$(dirname "$output_file")
        
        log_success "HTML playback file created successfully"
        # Full path is only logged in debug mode
        log_debug "HTML playback file created at: $output_file"
        
        echo -e "${YELLOW}To replay the session, open the following file in your web browser:${NC}"
        echo "$output_file"
        return 0
    else
        handle_error "$ERR_GENERAL" "Failed to generate HTML playback with TermRecord"
        return $ERR_GENERAL
    fi
}

# Export functions
export -f replay_session
export -f is_valid_log_path
export -f is_valid_timing_path
export -f is_path_secure
export -f prepare_replay_files
export -f cleanup_replay_files
export -f replay_session_terminal
export -f replay_session_html