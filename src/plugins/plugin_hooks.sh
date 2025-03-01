#!/usr/bin/env bash
#
# SSHistorian - Plugin Hooks Manager
# Handles plugin hook registration and execution
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

# Source error handling module if not already loaded
if ! command -v run_cleanup_handlers &>/dev/null; then
    # shellcheck source=../utils/errors.sh
    source "${SCRIPT_DIR}/../utils/errors.sh"
fi

# Arrays to store registered hooks (initialized with dummy values for compatibility)
REGISTERED_PRE_SESSION_HOOKS=("dummy_placeholder")
REGISTERED_POST_SESSION_HOOKS=("dummy_placeholder")
REGISTERED_CLI_COMMANDS=("dummy_placeholder")

# Maximum time (in seconds) a plugin hook is allowed to run before timing out
PLUGIN_HOOK_TIMEOUT=${PLUGIN_HOOK_TIMEOUT:-10}

# Register a hook for pre-session execution
# Usage: register_pre_session_hook <plugin_id>
register_pre_session_hook() {
    local plugin_id="$1"
    
    # Validate plugin ID
    if ! [[ "$plugin_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $plugin_id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Check if hook is already registered (compatible with bash 3.2)
    local hook_registered=false
    for registered_hook in "${REGISTERED_PRE_SESSION_HOOKS[@]}"; do
        if [[ "$registered_hook" == "$plugin_id" ]]; then
            hook_registered=true
            break
        fi
    done
    
    if [[ "$hook_registered" == "true" ]]; then
        log_debug "Pre-session hook already registered: $plugin_id"
        return 0
    fi
    
    # Register the hook
    if [[ "${#REGISTERED_PRE_SESSION_HOOKS[@]}" -eq 1 && "${REGISTERED_PRE_SESSION_HOOKS[0]}" == "dummy_placeholder" ]]; then
        # Replace dummy placeholder with actual value
        REGISTERED_PRE_SESSION_HOOKS[0]="$plugin_id"
    else
        # Add to array
        REGISTERED_PRE_SESSION_HOOKS+=("$plugin_id")
    fi
    log_debug "Registered pre-session hook: $plugin_id"
    
    return 0
}

# Register a hook for post-session execution
# Usage: register_post_session_hook <plugin_id>
register_post_session_hook() {
    local plugin_id="$1"
    
    # Validate plugin ID
    if ! [[ "$plugin_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $plugin_id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Check if hook is already registered (compatible with bash 3.2)
    local hook_registered=false
    for registered_hook in "${REGISTERED_POST_SESSION_HOOKS[@]}"; do
        if [[ "$registered_hook" == "$plugin_id" ]]; then
            hook_registered=true
            break
        fi
    done
    
    if [[ "$hook_registered" == "true" ]]; then
        log_debug "Post-session hook already registered: $plugin_id"
        return 0
    fi
    
    # Register the hook
    if [[ "${#REGISTERED_POST_SESSION_HOOKS[@]}" -eq 1 && "${REGISTERED_POST_SESSION_HOOKS[0]}" == "dummy_placeholder" ]]; then
        # Replace dummy placeholder with actual value
        REGISTERED_POST_SESSION_HOOKS[0]="$plugin_id"
    else
        # Add to array
        REGISTERED_POST_SESSION_HOOKS+=("$plugin_id")
    fi
    log_debug "Registered post-session hook: $plugin_id"
    
    return 0
}

# Run a plugin hook with timeout
# Usage: run_plugin_hook_with_timeout <function_name> <timeout> [args...]
run_plugin_hook_with_timeout() {
    local function_name="$1"
    local timeout="$2"
    shift 2
    local args=("$@")
    
    # Use the new with_timeout function from errors.sh
    result=$(with_timeout "$timeout" "$function_name" "${args[@]}")
    local status=$?
    
    # Output the result
    echo "$result"
    
    # Return the status code
    return $status
}

# Run pre-session hooks for all enabled plugins
# Usage: run_pre_session_hooks <session_id> <host> <command> <remote_user>
run_pre_session_hooks() {
    local session_id="$1"
    local host="$2"
    local command="$3"
    local remote_user="${4:-}"
    local plugin_id plugin_function result=0
    
    log_debug "Running pre-session hooks (${#REGISTERED_PRE_SESSION_HOOKS[@]} registered)"
    
    # Loop through registered pre-session hooks
    for plugin_id in "${REGISTERED_PRE_SESSION_HOOKS[@]}"; do
        # Skip dummy placeholder
        if [[ "$plugin_id" == "dummy_placeholder" ]]; then
            continue
        fi
        
        # Check if plugin is enabled
        if is_plugin_enabled "$plugin_id"; then
            # Construct function name for the hook
            plugin_function="${plugin_id}_pre_session_hook"
            
            # Check if function exists
            if command -v "$plugin_function" &>/dev/null; then
                log_debug "Running pre-session hook for plugin: $plugin_id"
                
                # Register the operation for cleanup
                register_operation "pre_session_hook_${plugin_id}" "log_warning 'Pre-session hook for ${plugin_id} was interrupted'"
                
                # Call the hook function with timeout and capture return code
                run_plugin_hook_with_timeout "$plugin_function" "$PLUGIN_HOOK_TIMEOUT" \
                    "$session_id" "$host" "$command" "$remote_user"
                local hook_result=$?
                
                # Clean up the operation
                unregister_operation "pre_session_hook_${plugin_id}"
                
                # If hook returns non-zero, record error but continue with other hooks
                if [[ $hook_result -eq $ERR_TIMEOUT ]]; then
                    log_error "Pre-session hook for $plugin_id timed out after ${PLUGIN_HOOK_TIMEOUT} seconds"
                    result=1
                elif [[ $hook_result -ne 0 ]]; then
                    log_warning "Pre-session hook for $plugin_id failed with code $hook_result"
                    result=1
                fi
            else
                log_warning "Plugin $plugin_id registered pre-session hook but function $plugin_function not found"
            fi
        fi
    done
    
    return $result
}

# Run post-session hooks for all enabled plugins
# Usage: run_post_session_hooks <session_id> <exit_code> <duration>
run_post_session_hooks() {
    local session_id="$1"
    local exit_code="$2"
    local duration="$3"
    local plugin_id plugin_function result=0
    
    log_debug "Running post-session hooks (${#REGISTERED_POST_SESSION_HOOKS[@]} registered)"
    
    # Loop through registered post-session hooks
    for plugin_id in "${REGISTERED_POST_SESSION_HOOKS[@]}"; do
        # Skip dummy placeholder
        if [[ "$plugin_id" == "dummy_placeholder" ]]; then
            continue
        fi
        
        # Check if plugin is enabled
        if is_plugin_enabled "$plugin_id"; then
            # Construct function name for the hook
            plugin_function="${plugin_id}_post_session_hook"
            
            # Check if function exists
            if command -v "$plugin_function" &>/dev/null; then
                log_debug "Running post-session hook for plugin: $plugin_id"
                
                # Register the operation for cleanup
                register_operation "post_session_hook_${plugin_id}" "log_warning 'Post-session hook for ${plugin_id} was interrupted'"
                
                # Call the hook function with timeout and capture return code
                run_plugin_hook_with_timeout "$plugin_function" "$PLUGIN_HOOK_TIMEOUT" \
                    "$session_id" "$exit_code" "$duration"
                local hook_result=$?
                
                # Clean up the operation
                unregister_operation "post_session_hook_${plugin_id}"
                
                # If hook returns non-zero, record error but continue with other hooks
                if [[ $hook_result -eq $ERR_TIMEOUT ]]; then
                    log_error "Post-session hook for $plugin_id timed out after ${PLUGIN_HOOK_TIMEOUT} seconds"
                    result=1
                elif [[ $hook_result -ne 0 ]]; then
                    log_warning "Post-session hook for $plugin_id failed with code $hook_result"
                    result=1
                fi
            else
                log_warning "Plugin $plugin_id registered post-session hook but function $plugin_function not found"
            fi
        fi
    done
    
    return $result
}

# Register a CLI command extension
# Usage: register_cli_command <plugin_id> <command> <description> <handler_function>
register_cli_command() {
    local plugin_id="$1"
    local command="$2"
    local description="$3"
    local handler_function="$4"
    
    # Validate plugin ID
    if ! [[ "$plugin_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid plugin ID format: $plugin_id (must be alphanumeric, underscore, or hyphen)"
        return 1
    fi
    
    # Validate command (alphanumeric plus colon for subcommands and hyphen/underscore)
    if ! [[ "$command" =~ ^[a-zA-Z0-9_:-]+$ ]]; then
        log_error "Invalid command format: $command (must be alphanumeric, colon, underscore, or hyphen)"
        return 1
    fi
    
    # Validate handler function exists
    if ! command -v "$handler_function" &>/dev/null; then
        log_error "Handler function does not exist: $handler_function"
        return 1
    fi
    
    # Construct the command registration entry
    local cmd_entry="${plugin_id}:${command}:${description}:${handler_function}"
    
    # Check if command is already registered (compatible with bash 3.2)
    local cmd_registered=false
    for registered_cmd in "${REGISTERED_CLI_COMMANDS[@]}"; do
        local reg_plugin_id reg_command
        reg_plugin_id=$(echo "$registered_cmd" | cut -d':' -f1)
        reg_command=$(echo "$registered_cmd" | cut -d':' -f2)
        
        if [[ "$reg_plugin_id" == "$plugin_id" && "$reg_command" == "$command" ]]; then
            cmd_registered=true
            break
        fi
    done
    
    if [[ "$cmd_registered" == "true" ]]; then
        log_debug "CLI command already registered: $plugin_id:$command"
        return 0
    fi
    
    # Register the command
    if [[ "${#REGISTERED_CLI_COMMANDS[@]}" -eq 1 && "${REGISTERED_CLI_COMMANDS[0]}" == "dummy_placeholder" ]]; then
        # Replace dummy placeholder with actual value
        REGISTERED_CLI_COMMANDS[0]="$cmd_entry"
    else
        # Add to array
        REGISTERED_CLI_COMMANDS+=("$cmd_entry")
    fi
    log_debug "Registered CLI command: $plugin_id:$command"
    
    return 0
}

# Get all registered CLI commands
# Usage: get_registered_cli_commands
get_registered_cli_commands() {
    # Skip dummy placeholder
    local cmds=()
    for cmd in "${REGISTERED_CLI_COMMANDS[@]}"; do
        if [[ "$cmd" != "dummy_placeholder" ]]; then
            cmds+=("$cmd")
        fi
    done
    
    # Return the commands as newline-separated string
    if [[ ${#cmds[@]} -gt 0 ]]; then
        printf "%s\n" "${cmds[@]}"
    fi
}

# Run a CLI command handler
# Usage: run_cli_command_handler <plugin_id> <command> [args...]
run_cli_command_handler() {
    local plugin_id="$1"
    local command="$2"
    shift 2
    local args=("$@")
    
    # Look for a matching handler
    local handler=""
    for cmd_entry in "${REGISTERED_CLI_COMMANDS[@]}"; do
        # Skip dummy placeholder
        if [[ "$cmd_entry" == "dummy_placeholder" ]]; then
            continue
        fi
        
        local reg_plugin_id reg_command reg_handler
        reg_plugin_id=$(echo "$cmd_entry" | cut -d':' -f1)
        reg_command=$(echo "$cmd_entry" | cut -d':' -f2)
        reg_handler=$(echo "$cmd_entry" | cut -d':' -f4)
        
        if [[ "$reg_plugin_id" == "$plugin_id" && "$reg_command" == "$command" ]]; then
            handler="$reg_handler"
            break
        fi
    done
    
    # If no handler found, return error
    if [[ -z "$handler" ]]; then
        log_error "No handler found for command: $plugin_id:$command"
        return 1
    fi
    
    # Check if plugin is enabled
    if ! is_plugin_enabled "$plugin_id"; then
        log_error "Plugin $plugin_id is disabled"
        return 1
    fi
    
    # Run the handler with timeout and arguments
    run_plugin_hook_with_timeout "$handler" "$PLUGIN_HOOK_TIMEOUT" "${args[@]}"
    return $?
}

# Export functions
export -f register_pre_session_hook
export -f register_post_session_hook
export -f register_cli_command
export -f get_registered_cli_commands
export -f run_cli_command_handler
export -f run_plugin_hook_with_timeout
export -f run_pre_session_hooks
export -f run_post_session_hooks