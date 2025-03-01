#!/usr/bin/env bash
#
# SSHistorian - Error Handling Module
# Provides consistent error handling across all modules

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=./constants.sh
    source "${SCRIPT_DIR}/constants.sh"
fi

# Source logging module if not already loaded
if ! command -v log_error &>/dev/null; then
    # shellcheck source=./logging.sh
    source "${SCRIPT_DIR}/logging.sh"
fi

# Error codes - central definition for consistent usage across all modules
# Range 1-9: General errors
export ERR_GENERAL=1        # General unspecified error
export ERR_ARGS=2           # Invalid arguments
export ERR_PERMISSION=3     # Permission denied
export ERR_NOT_FOUND=4      # File or resource not found
export ERR_DEPENDENCY=5     # Missing dependency
export ERR_CONFIG=6         # Configuration error
export ERR_TIMEOUT=7        # Operation timed out
export ERR_INTERRUPTED=8    # Operation interrupted
export ERR_NOT_IMPLEMENTED=9 # Feature not implemented

# Range 10-19: Database errors
export ERR_DB_GENERAL=10    # General database error
export ERR_DB_CONNECT=11    # Failed to connect to database
export ERR_DB_QUERY=12      # Failed query execution
export ERR_DB_SCHEMA=13     # Schema error
export ERR_DB_MIGRATION=14  # Migration error
export ERR_DB_INTEGRITY=15  # Data integrity error
export ERR_DB_NOT_FOUND=16  # Record not found
export ERR_DB_DUPLICATE=17  # Duplicate record

# Range 20-29: SSH related errors
export ERR_SSH_GENERAL=20   # General SSH error
export ERR_SSH_CONNECT=21   # Failed to connect to host
export ERR_SSH_AUTH=22      # Authentication failed
export ERR_SSH_EXEC=23      # Command execution failed
export ERR_SSH_RECORD=24    # Session recording failed
export ERR_SSH_REPLAY=25    # Session replay failed

# Range 30-39: Encryption errors
export ERR_CRYPT_GENERAL=30 # General encryption error
export ERR_CRYPT_KEY=31     # Key not found or invalid
export ERR_CRYPT_ENCRYPT=32 # Encryption failed
export ERR_CRYPT_DECRYPT=33 # Decryption failed

# Range 40-49: Plugin related errors
export ERR_PLUGIN_GENERAL=40 # General plugin error
export ERR_PLUGIN_LOAD=41    # Failed to load plugin
export ERR_PLUGIN_HOOK=42    # Hook execution failed
export ERR_PLUGIN_CONFIG=43  # Plugin configuration error
export ERR_PLUGIN_NOT_FOUND=44 # Plugin not found

# Range 50-59: File and path errors
export ERR_FILE_GENERAL=50  # General file error
export ERR_FILE_OPEN=51     # Failed to open file
export ERR_FILE_WRITE=52    # Failed to write to file
export ERR_FILE_READ=53     # Failed to read from file
export ERR_FILE_PERM=54     # File permission error
export ERR_FILE_PATH=55     # Invalid path
export ERR_FILE_TRAVERSAL=56 # Path traversal attempt

# Global variables to track running operations that might need cleanup on error or interrupt
# Use regular arrays for compatibility with older bash versions
declare -a CLEANUP_HANDLERS
declare -a OPERATION_IDS
declare -a OPERATION_COMMANDS

# Error handling functions

# Handle errors with consistent logging and exit codes
# Usage: handle_error <error_code> <message> [exit_on_error]
handle_error() {
    local error_code="$1"
    local message="$2"
    local exit_on_error="${3:-false}"
    
    # Log the error with code
    log_error "Error [$error_code]: $message"
    
    # Exit if requested
    if [[ "$exit_on_error" == "true" ]]; then
        # Run any registered cleanup handlers before exiting
        run_cleanup_handlers
        exit "$error_code"
    fi
    
    # Return the error code
    return "$error_code"
}

# Register a function to be called on error or interrupt
# Usage: register_cleanup_handler <handler_function_name>
register_cleanup_handler() {
    local handler="$1"
    
    # Check if the function exists
    if ! declare -F "$handler" > /dev/null; then
        log_warning "Attempted to register non-existent cleanup handler: $handler"
        return 1
    fi
    
    # Add to array if not already present
    if [[ ! " ${CLEANUP_HANDLERS[*]} " =~ " ${handler} " ]]; then
        CLEANUP_HANDLERS+=("$handler")
        log_debug "Registered cleanup handler: $handler"
    fi
    
    return 0
}

# Unregister a cleanup handler
# Usage: unregister_cleanup_handler <handler_function_name>
unregister_cleanup_handler() {
    local handler="$1"
    local new_handlers=()
    
    # Rebuild array without the specified handler
    for h in "${CLEANUP_HANDLERS[@]}"; do
        if [[ "$h" != "$handler" ]]; then
            new_handlers+=("$h")
        fi
    done
    
    CLEANUP_HANDLERS=("${new_handlers[@]}")
    log_debug "Unregistered cleanup handler: $handler"
    
    return 0
}

# Execute all registered cleanup handlers
# Usage: run_cleanup_handlers
run_cleanup_handlers() {
    log_debug "Running cleanup handlers: ${#CLEANUP_HANDLERS[@]} registered"
    
    # Run handlers in reverse order (last registered, first executed)
    for ((i=${#CLEANUP_HANDLERS[@]}-1; i>=0; i--)); do
        local handler="${CLEANUP_HANDLERS[$i]}"
        log_debug "Executing cleanup handler: $handler"
        
        # Execute handler and capture any errors
        "$handler" || log_warning "Cleanup handler failed: $handler"
    done
    
    # Clear handlers after running
    CLEANUP_HANDLERS=()
    
    return 0
}

# Register an active operation that might need cleanup
# Usage: register_operation <operation_id> <cleanup_command>
register_operation() {
    local operation_id="$1"
    local cleanup_command="$2"
    
    # Add to parallel arrays
    OPERATION_IDS+=("$operation_id")
    OPERATION_COMMANDS+=("$cleanup_command")
    log_debug "Registered operation: $operation_id"
    
    return 0
}

# Unregister an operation when it completes successfully
# Usage: unregister_operation <operation_id>
unregister_operation() {
    local operation_id="$1"
    local new_ids=()
    local new_commands=()
    local i
    
    # Safety check if arrays are empty
    if [[ ${#OPERATION_IDS[@]} -eq 0 ]]; then
        return 0
    fi

    # Rebuild arrays without the specified operation
    for ((i=0; i<${#OPERATION_IDS[@]}; i++)); do
        if [[ "${OPERATION_IDS[$i]}" != "$operation_id" ]]; then
            new_ids+=("${OPERATION_IDS[$i]}")
            new_commands+=("${OPERATION_COMMANDS[$i]}")
        fi
    done
    
    # Check if new arrays are empty before assignment
    if [[ ${#new_ids[@]} -gt 0 ]]; then
        OPERATION_IDS=("${new_ids[@]}")
        OPERATION_COMMANDS=("${new_commands[@]}")
    else
        # Initialize with dummy placeholders if empty
        OPERATION_IDS=("dummy_placeholder")
        OPERATION_COMMANDS=(":")  # No-op command
    fi
    log_debug "Unregistered operation: $operation_id"
    
    return 0
}

# Clean up a specific operation
# Usage: cleanup_operation <operation_id>
cleanup_operation() {
    local operation_id="$1"
    local i
    
    # Find the operation in the array
    for ((i=0; i<${#OPERATION_IDS[@]}; i++)); do
        if [[ "${OPERATION_IDS[$i]}" == "$operation_id" ]]; then
            log_debug "Cleaning up operation: $operation_id"
            
            # Execute cleanup command
            eval "${OPERATION_COMMANDS[$i]}" || log_warning "Failed to clean up operation: $operation_id"
            
            # Remove from arrays (by recreating them without this entry)
            unregister_operation "$operation_id"
            break
        fi
    done
    
    return 0
}

# Clean up all registered operations
# Usage: cleanup_all_operations
cleanup_all_operations() {
    log_debug "Cleaning up all operations: ${#OPERATION_IDS[@]} registered"
    
    # Copy the array since we'll be modifying it while iterating
    local operations_to_clean=("${OPERATION_IDS[@]}")
    
    for operation_id in "${operations_to_clean[@]}"; do
        cleanup_operation "$operation_id"
    done
    
    return 0
}

# Set up trap to handle interrupts and cleanup
trap_with_arg() {
    local func="$1" ; shift
    for sig ; do
        # shellcheck disable=SC2064
        trap "$func $sig" "$sig"
    done
}

# Handle signals for proper cleanup
handle_signal() {
    local sig="$1"
    log_warning "Received signal: $sig"
    
    # Run all cleanup handlers
    run_cleanup_handlers
    
    # Clean up all operations
    cleanup_all_operations
    
    # Exit with signal-specific code
    case "$sig" in
        INT|SIGINT)
            exit $ERR_INTERRUPTED
            ;;
        *)
            exit $ERR_GENERAL
            ;;
    esac
}

# Set up traps for common signals
trap_with_arg handle_signal INT TERM HUP

# Error propagation for nested function calls
# Usage: propagate_error <function_name> <arg1> <arg2> ...
# Example: result=$(propagate_error my_function arg1 arg2) || return $?
propagate_error() {
    local func="$1"
    shift
    
    "$func" "$@"
    local status=$?
    
    if [[ $status -ne 0 ]]; then
        # Function failed, propagate the error code up
        return $status
    fi
    
    return 0
}

# Check if a command exists and handle error if not
# Usage: require_command <command> [error_message]
require_command() {
    local command="$1"
    local error_message="${2:-Command '$command' not found}"
    
    if ! command -v "$command" &>/dev/null; then
        handle_error "$ERR_DEPENDENCY" "$error_message"
        return "$ERR_DEPENDENCY"
    fi
    
    return 0
}

# Check if a file exists and handle error if not
# Usage: require_file <file_path> [error_message]
require_file() {
    local file_path="$1"
    local error_message="${2:-File not found: '$file_path'}"
    
    if [[ ! -f "$file_path" ]]; then
        handle_error "$ERR_NOT_FOUND" "$error_message"
        return "$ERR_NOT_FOUND"
    fi
    
    return 0
}

# Check if a directory exists and handle error if not
# Usage: require_directory <dir_path> [error_message]
require_directory() {
    local dir_path="$1"
    local error_message="${2:-Directory not found: '$dir_path'}"
    
    if [[ ! -d "$dir_path" ]]; then
        handle_error "$ERR_NOT_FOUND" "$error_message"
        return "$ERR_NOT_FOUND"
    fi
    
    return 0
}

# Check for appropriate file permissions
# Usage: check_permissions <file_path> <required_perms> [error_message]
check_permissions() {
    local file_path="$1"
    local required_perms="$2"  # e.g., "r" for read, "w" for write, "x" for execute
    local error_message="${3:-Permission denied: '$file_path'}"
    local has_error=false
    
    # Check for read permission
    if [[ "$required_perms" == *r* ]] && [[ ! -r "$file_path" ]]; then
        has_error=true
    fi
    
    # Check for write permission
    if [[ "$required_perms" == *w* ]] && [[ ! -w "$file_path" ]]; then
        has_error=true
    fi
    
    # Check for execute permission
    if [[ "$required_perms" == *x* ]] && [[ ! -x "$file_path" ]]; then
        has_error=true
    fi
    
    if [[ "$has_error" == "true" ]]; then
        handle_error "$ERR_PERMISSION" "$error_message"
        return "$ERR_PERMISSION"
    fi
    
    return 0
}

# Validate an argument matches expected format
# Usage: validate_arg <arg> <pattern> <error_message>
validate_arg() {
    local arg="$1"
    local pattern="$2"
    local error_message="$3"
    
    if ! [[ "$arg" =~ $pattern ]]; then
        handle_error "$ERR_ARGS" "$error_message"
        return "$ERR_ARGS"
    fi
    
    return 0
}

# Safely execute a SQL query with error handling using named parameters
# Usage: safe_query <db_file> <query> <param_name1> <param_value1> [<param_name2> <param_value2> ...]
safe_query() {
    local db_file="$1"
    local query="$2"
    shift 2
    local params=()
    local result
    local temp_script
    
    # Check if database file exists
    if [[ ! -f "$db_file" ]]; then
        handle_error "$ERR_DB_CONNECT" "Database file not found: $db_file"
        return "$ERR_DB_CONNECT"
    fi
    
    # Create temporary script file
    temp_script=$(mktemp)
    echo ".mode line" > "$temp_script"
    
    # Process parameters in pairs (name and value)
    while [[ $# -ge 2 ]]; do
        local param_name="$1"
        local param_value="$2"
        echo ".param set $param_name '$param_value'" >> "$temp_script"
        shift 2
    done
    
    # Add the query to the script
    echo "$query" >> "$temp_script"
    
    # Execute the query with the script
    result=$(sqlite3 "$db_file" < "$temp_script" 2>&1)
    local status=$?
    
    # Remove the temporary script
    rm -f "$temp_script"
    
    # Check for query errors
    if [[ $status -ne 0 ]]; then
        handle_error "$ERR_DB_QUERY" "SQL query failed: $result"
        return "$ERR_DB_QUERY"
    fi
    
    # Output the result
    echo "$result"
    return 0
}

# Safely execute a SQL command that modifies the database using named parameters
# Usage: safe_update <db_file> <query> <param_name1> <param_value1> [<param_name2> <param_value2> ...]
safe_update() {
    local db_file="$1"
    local query="$2"
    shift 2
    local result
    local temp_script
    
    # Check if database file exists
    if [[ ! -f "$db_file" ]]; then
        handle_error "$ERR_DB_CONNECT" "Database file not found: $db_file"
        return "$ERR_DB_CONNECT"
    fi
    
    # Create temporary script file
    temp_script=$(mktemp)
    
    # Process parameters in pairs (name and value)
    while [[ $# -ge 2 ]]; do
        local param_name="$1"
        local param_value="$2"
        echo ".param set $param_name '$param_value'" >> "$temp_script"
        shift 2
    done
    
    # Add the query to the script
    echo "$query" >> "$temp_script"
    
    # Execute the query with the script
    result=$(sqlite3 "$db_file" < "$temp_script" 2>&1)
    local status=$?
    
    # Remove the temporary script
    rm -f "$temp_script"
    
    # Check for query errors
    if [[ $status -ne 0 ]]; then
        handle_error "$ERR_DB_QUERY" "SQL update failed: $result"
        return "$ERR_DB_QUERY"
    fi
    
    return 0
}

# Safely execute a function with timeout
# Usage: with_timeout <timeout_seconds> <function_name> [args...]
with_timeout() {
    local timeout="$1"
    local func="$2"
    shift 2
    local args=("$@")
    
    # Create a temporary file to capture output
    local output_file
    output_file=$(mktemp)
    register_operation "timeout_temp_${output_file}" "rm -f ${output_file}"
    
    # Run the function with timeout
    (
        # Execute the function with its arguments
        "$func" "${args[@]}" > "$output_file" 2>&1
        echo $? > "${output_file}.exit"
    ) & local pid=$!
    
    # Wait for the process with timeout
    local wait_cmd="wait $pid"
    timeout "$timeout" bash -c "$wait_cmd"
    local timeout_status=$?
    
    # If process still exists, kill it
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        local exit_status=$ERR_TIMEOUT
        handle_error "$exit_status" "Function execution timed out after ${timeout} seconds"
    else
        # Process completed, get its exit status
        local exit_status
        if [[ -f "${output_file}.exit" ]]; then
            exit_status=$(cat "${output_file}.exit")
        else
            exit_status=$ERR_GENERAL
        fi
    fi
    
    # Output the captured output
    cat "$output_file"
    
    # Clean up
    rm -f "$output_file" "${output_file}.exit"
    unregister_operation "timeout_temp_${output_file}"
    
    return $exit_status
}

# Export functions
export -f handle_error
export -f register_cleanup_handler
export -f unregister_cleanup_handler
export -f run_cleanup_handlers
export -f register_operation
export -f unregister_operation
export -f cleanup_operation
export -f cleanup_all_operations
export -f propagate_error
export -f require_command
export -f require_file
export -f require_directory
export -f check_permissions
export -f validate_arg
export -f safe_query
export -f safe_update
export -f with_timeout