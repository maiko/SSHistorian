#!/usr/bin/env bash
#
# SSHistorian - Session Recorder Module
# Functions for recording SSH/terminal sessions
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
if ! command -v encrypt_file &>/dev/null; then
    # shellcheck source=../encryption.sh
    source "${ROOT_DIR}/src/core/encryption.sh"
fi

# Source database models if not already loaded
if ! command -v update_session_exit &>/dev/null; then
    # shellcheck source=../../db/models/sessions.sh
    source "${ROOT_DIR}/src/db/models/sessions.sh"
fi

# Start recording a session
# Usage: start_session_recording <session_id> <ssh_binary> [ssh_args...]
start_session_recording() {
    local session_id="$1"
    local ssh_binary="$2"
    shift 2
    local ssh_args=("$@")
    
    # Prepare log files
    local log_file="${LOG_DIR}/${session_id}.log"
    local timing_file="${LOG_DIR}/${session_id}.timing"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$log_file")" || {
        handle_error "$ERR_FILE_GENERAL" "Failed to create log directory"
        # Full path is only logged in debug mode
        log_debug "Failed to create log directory: $(dirname "$log_file")"
        return $ERR_FILE_GENERAL
    }
    
    # Get file permissions from config
    local log_permissions
    log_permissions=$(get_config "general.log_permissions" "0600")
    
    # Register operation for cleanup in case of error
    register_operation "session_recording_$session_id" "clean_up_recording_files '$log_file' '$timing_file'"
    
    # Get start time for timing
    local start_time
    start_time=$(date +%s)
    
    # Use script to record the session in a cross-platform way
    local ssh_exit
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version of script (older BSD version)
        log_debug "Using macOS (BSD) version of script"
        
        # Check if we have a newer version of script that supports timing (-t option)
        if script -h 2>&1 | grep -q -- "-t"; then
            # Newer version with timing support
            log_debug "Using script with timing support"
            script -q -t "$timing_file" "$log_file" "$ssh_binary" "${ssh_args[@]}"
            ssh_exit=$?
        else
            # Older version without timing support
            log_debug "Using script without timing support"
            script -q "$log_file" "$ssh_binary" "${ssh_args[@]}"
            ssh_exit=$?
            
            # Create a basic timing file for macOS (not as accurate)
            log_debug "Creating basic timing file for macOS"
            local file_size
            file_size=$(stat -f%z "$log_file" 2>/dev/null || echo "0")
            echo "0.000000 $file_size" > "$timing_file"
        fi
    else
        # Linux version with timing file support
        log_debug "Using Linux version of script with timing support"
        # Safely escape arguments to prevent command injection
        # Using older bash compatible approach (printf %q) which works on all versions
        script -q -c "$(printf '%q ' "$ssh_binary" "${ssh_args[@]}")" -T "$timing_file" "$log_file"
        ssh_exit=$?
    fi
    
    # Calculate session duration
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Set proper permissions for log files
    chmod "$log_permissions" "$log_file" "$timing_file" || {
        log_warning "Failed to set permissions on log files"
    }
    
    # Update session record with exit code and duration
    update_session_exit "$session_id" "$ssh_exit" "$duration" || {
        log_warning "Failed to update session record with exit code and duration"
    }
    
    # Check if encryption is enabled
    local encryption_enabled
    encryption_enabled=$(get_config "encryption.enabled" "false")
    
    # Encrypt files if encryption is enabled
    if [[ "$encryption_enabled" == "true" ]]; then
        log_info "Encrypting session logs..."
        
        # Encrypt the log and timing files
        encrypt_file "$log_file" "$session_id" || log_warning "Failed to encrypt log file"
        encrypt_file "$timing_file" "$session_id" || log_warning "Failed to encrypt timing file"
    else
        log_debug "Encryption is disabled"
    fi
    
    # Check if plugin system is available and run post-session hooks
    if command -v run_post_session_hooks &>/dev/null; then
        log_debug "Running plugin post-session hooks"
        run_post_session_hooks "$session_id" "$ssh_exit" "$duration"
    else
        log_debug "Plugin system not available, skipping post-session hooks"
    fi
    
    # Unregister cleanup operation as we're done
    unregister_operation "session_recording_$session_id"
    
    log_success "SSH session completed (Duration: ${duration}s, Exit: $ssh_exit)"
    
    return $ssh_exit
}

# Clean up recording files in case of error
# Usage: clean_up_recording_files <log_file> <timing_file>
clean_up_recording_files() {
    local log_file="$1"
    local timing_file="$2"
    
    log_warning "Cleaning up session recording files due to error or interrupt"
    
    # Remove the files if they exist
    [[ -f "$log_file" ]] && rm -f "$log_file"
    [[ -f "$timing_file" ]] && rm -f "$timing_file"
    
    # Also check for encrypted versions
    [[ -f "${log_file}.enc" ]] && rm -f "${log_file}.enc"
    [[ -f "${timing_file}.enc" ]] && rm -f "${timing_file}.enc"
    
    return 0
}

# Export functions
export -f start_session_recording
export -f clean_up_recording_files