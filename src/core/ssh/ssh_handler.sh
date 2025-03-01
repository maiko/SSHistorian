#!/usr/bin/env bash
#
# SSHistorian - SSH Handler Module
# Core functions for SSH command execution and setup
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

# Handle SSH session
# Records a session and manages logging
# Usage: handle_ssh [ssh_args...]
handle_ssh() {
    # Check if any arguments are provided
    if [[ $# -eq 0 ]]; then
        handle_error "$ERR_ARGS" "No SSH target specified"
        echo "Usage: $(basename "$0") [options] [user@]hostname [command]"
        return $ERR_ARGS
    fi
    
    # Get SSH binary from config
    local ssh_binary
    ssh_binary=$(get_config "ssh.binary" "/usr/bin/ssh")
    
    # Validate that SSH binary exists
    if [[ ! -x "$ssh_binary" ]]; then
        handle_error "$ERR_DEPENDENCY" "SSH binary not found or not executable: $ssh_binary"
        return $ERR_DEPENDENCY
    fi
    
    # Parse the target hostname and user from arguments
    local host remote_user original_command
    original_command="$ssh_binary $*"
    
    # Extract hostname and remote user from arguments
    remote_user="" # Initialize as empty
    host=""
    
    # Parse the first non-option argument
    for arg in "$@"; do
        # Skip options that start with -
        if [[ "$arg" == -* ]]; then
            continue
        fi
        
        # This should be the hostname or user@hostname
        if [[ "$arg" == *@* ]]; then
            remote_user="${arg%%@*}"
            host="${arg#*@}"
        else
            host="$arg"
        fi
        
        # Once we find a hostname, break
        break
    done
    
    # Validate hostname
    if [[ -z "$host" ]]; then
        handle_error "$ERR_ARGS" "Could not determine hostname from SSH arguments"
        return $ERR_ARGS
    fi
    
    # Create database record for the session
    local session_id
    session_id=$(create_session "$host" "$original_command" "$remote_user")
    if [[ $? -ne 0 || -z "$session_id" ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to create session record in database"
        return $ERR_DB_GENERAL
    fi
    
    log_info "Starting SSH session logging for $host (Session ID: $session_id)"
    
    # Check if plugin system is available and run pre-session hooks
    if command -v run_pre_session_hooks &>/dev/null; then
        log_debug "Running plugin pre-session hooks"
        run_pre_session_hooks "$session_id" "$host" "$original_command" "$remote_user"
    else
        log_debug "Plugin system not available, skipping pre-session hooks"
    fi
    
    # Start session recording
    start_session_recording "$session_id" "$ssh_binary" "$@"
    
    return $?
}

# Export functions
export -f handle_ssh