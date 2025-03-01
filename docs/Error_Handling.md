# SSHistorian Error Handling Guide

This document describes the error handling system in SSHistorian, including how errors are defined, reported, and handled across the application.

## Overview

SSHistorian uses a consistent error handling approach throughout the codebase to ensure:

1. Predictable error codes across all modules
2. Clear error messages with context
3. Proper propagation of errors through the call chain
4. Graceful handling of failures
5. Cleanup of resources when operations are interrupted
6. Consistent use of named parameters for SQL operations

## Error Codes

Error codes are centrally defined in `src/utils/errors.sh` and grouped by category:

| Range | Category | Description |
|-------|----------|-------------|
| 1-9 | General | General operational errors |
| 10-19 | Database | Database connection, query, and schema errors |
| 20-29 | SSH | SSH connection and execution errors |
| 30-39 | Encryption | Encryption/decryption errors |
| 40-49 | Plugin | Plugin loading and execution errors |
| 50-59 | File | File system errors |

### Common Error Codes

Here are the most commonly used error codes:

- `ERR_GENERAL=1`: General unspecified error
- `ERR_ARGS=2`: Invalid arguments
- `ERR_PERMISSION=3`: Permission denied
- `ERR_NOT_FOUND=4`: File or resource not found
- `ERR_DB_GENERAL=10`: General database error
- `ERR_DB_QUERY=12`: Failed query execution
- `ERR_SSH_CONNECT=21`: Failed to connect to host
- `ERR_CRYPT_KEY=31`: Key not found or invalid

For a complete list, see the `src/utils/errors.sh` file.

## Error Handling Functions

The error handling module provides several helper functions:

### Core Error Handling

#### handle_error

The core error handling function:

```bash
handle_error <error_code> <message> [exit_on_error]
```

Example:
```bash
handle_error "$ERR_NOT_FOUND" "Config file not found: $config_path"
return $ERR_NOT_FOUND
```

#### propagate_error

Simplifies error propagation in nested function calls:

```bash
propagate_error <function_name> <arg1> <arg2> ...
```

Example:
```bash
result=$(propagate_error process_user_input "$user_input") || return $?
```

### Resource Management and Cleanup

#### register_cleanup_handler

Register a function to be called when cleaning up on exit or error:

```bash
register_cleanup_handler <handler_function_name>
```

Example:
```bash
cleanup_my_temp_files() {
    rm -f /tmp/my_temp_file_*.txt
}
register_cleanup_handler cleanup_my_temp_files
```

#### unregister_cleanup_handler

Remove a previously registered cleanup handler:

```bash
unregister_cleanup_handler <handler_function_name>
```

#### run_cleanup_handlers

Manually trigger all registered cleanup handlers:

```bash
run_cleanup_handlers
```

#### register_operation

Register an active operation that might need cleanup:

```bash
register_operation <operation_id> <cleanup_command>
```

Example:
```bash
register_operation "temp_file_$session_id" "rm -f /tmp/session_$session_id.dat"
```

#### unregister_operation

Unregister an operation when it completes successfully:

```bash
unregister_operation <operation_id>
```

#### cleanup_operation

Manually clean up a specific operation:

```bash
cleanup_operation <operation_id>
```

#### with_timeout

Execute a function with a timeout:

```bash
with_timeout <timeout_seconds> <function_name> [args...]
```

Example:
```bash
result=$(with_timeout 30 ssh_command "$host" "$command")
status=$?
```

### Validation Functions

#### require_command

Check if a command exists and handle error if not:

```bash
require_command <command> [error_message]
```

Example:
```bash
require_command "sqlite3" "SQLite3 is required but not installed" || return $?
```

#### require_file

Check if a file exists and handle error if not:

```bash
require_file <file_path> [error_message]
```

Example:
```bash
require_file "$key_file" "Encryption key not found: $key_file" || return $?
```

#### require_directory

Check if a directory exists and handle error if not:

```bash
require_directory <dir_path> [error_message]
```

Example:
```bash
require_directory "$log_dir" "Log directory does not exist: $log_dir" || return $?
```

#### check_permissions

Check for appropriate file permissions:

```bash
check_permissions <file_path> <required_perms> [error_message]
```

Example:
```bash
check_permissions "$db_file" "rw" "Cannot read/write to database file" || return $?
```

#### validate_arg

Validate an argument matches expected format:

```bash
validate_arg <arg> <pattern> <error_message>
```

Example:
```bash
validate_arg "$uuid" "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" "Invalid UUID format" || return $?
```

### Database Functions

#### safe_query

Safely execute a SQL query with named parameter binding:

```bash
safe_query <db_file> <query> <param_name1> <param_value1> [<param_name2> <param_value2> ...]
```

Example:
```bash
result=$(safe_query "$DB_FILE" "SELECT * FROM sessions WHERE id = :session_id" ":session_id" "$session_id")
```

#### safe_update

Safely execute a SQL command that modifies the database using named parameters:

```bash
safe_update <db_file> <query> <param_name1> <param_value1> [<param_name2> <param_value2> ...]
```

Example:
```bash
safe_update "$DB_FILE" "UPDATE sessions SET status = :status WHERE id = :id" \
  ":status" "completed" \
  ":id" "$session_id"
```

## Best Practices

1. **Return error codes**: Always return an appropriate error code when a function fails
2. **Propagate errors**: Check return codes from called functions and propagate them upward
3. **Use the error handling functions**: Leverage the provided functions rather than ad-hoc error handling
4. **Be specific**: Use the most specific error code that applies to the situation
5. **Provide context**: Include relevant details in error messages (file paths, variable values, etc.)
6. **Log first**: Use the error handling functions to log the error before returning
7. **Register cleanup handlers**: Use cleanup handlers to ensure resources are properly released on exit or error
8. **Use named parameters**: Always use named parameters (`:param_name`) instead of positional placeholders (`?`) for SQLite queries
9. **Track operations**: Register long-running operations to ensure they can be cleaned up if interrupted
10. **Handle interrupts**: Ensure your functions can handle graceful interruption via signals

## Examples

### Basic Error Handling Example

Here's a complete example of proper error handling:

```bash
process_file() {
    local file_path="$1"
    local output_dir="$2"
    
    # Check arguments
    if [[ -z "$file_path" || -z "$output_dir" ]]; then
        handle_error "$ERR_ARGS" "Missing required arguments"
        return $ERR_ARGS
    fi
    
    # Check if file exists
    require_file "$file_path" "Input file does not exist: $file_path" || return $?
    
    # Check if output directory exists
    require_directory "$output_dir" "Output directory does not exist: $output_dir" || return $?
    
    # Check file permissions
    check_permissions "$file_path" "r" "Cannot read input file: $file_path" || return $?
    check_permissions "$output_dir" "w" "Cannot write to output directory: $output_dir" || return $?
    
    # Process the file (and check for errors from called functions)
    local result
    result=$(propagate_error process_file_content "$file_path") || return $?
    
    # Write the result
    echo "$result" > "$output_dir/$(basename "$file_path").processed"
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_FILE_WRITE" "Failed to write output file"
        return $ERR_FILE_WRITE
    fi
    
    return 0
}
```

### Advanced Example with Resource Cleanup

Here's an example that utilizes cleanup handlers and operation tracking:

```bash
process_large_file() {
    local input_file="$1"
    local output_path="$2"
    
    # Validate arguments
    require_file "$input_file" "Input file not found" || return $?
    
    # Create a temporary working directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Register cleanup handler for the temporary directory
    cleanup_temp_dir() {
        [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
    }
    register_cleanup_handler cleanup_temp_dir
    
    # Create a temporary file for intermediate results
    local temp_file="$temp_dir/intermediate.dat"
    register_operation "temp_file_$temp_file" "rm -f $temp_file"
    
    log_message "Processing file: $input_file"
    
    # Extract data to temporary file
    extract_data "$input_file" > "$temp_file"
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_FILE_GENERAL" "Failed to extract data from $input_file"
        return $ERR_FILE_GENERAL
    fi
    
    # Process with timeout (30 seconds max)
    local result
    result=$(with_timeout 30 transform_data "$temp_file")
    local status=$?
    
    if [[ $status -eq $ERR_TIMEOUT ]]; then
        handle_error "$ERR_TIMEOUT" "Data transformation timed out"
        return $ERR_TIMEOUT
    elif [[ $status -ne 0 ]]; then
        handle_error "$status" "Failed to transform data"
        return $status
    fi
    
    # Write final output
    echo "$result" > "$output_path"
    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_FILE_WRITE" "Failed to write output file: $output_path"
        return $ERR_FILE_WRITE
    fi
    
    # Cleanup operations (these will be automatically cleaned up on exit too)
    unregister_operation "temp_file_$temp_file"
    unregister_cleanup_handler cleanup_temp_dir
    cleanup_temp_dir
    
    log_success "Successfully processed file: $input_file"
    return 0
}
```

### Database Operation Example

Here's an example using the new named parameter approach for database operations:

```bash
update_session_status() {
    local session_id="$1"
    local new_status="$2"
    
    # Validate arguments
    validate_arg "$session_id" "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" \
        "Invalid session ID format" || return $?
    
    validate_arg "$new_status" "^(active|paused|completed|failed)$" \
        "Invalid status value: $new_status" || return $?
    
    # Check if session exists
    local session_exists
    session_exists=$(safe_query "$DB_FILE" \
        "SELECT COUNT(*) as count FROM sessions WHERE id = :session_id" \
        ":session_id" "$session_id")
    
    if [[ -z "$session_exists" ]] || [[ "$(echo "$session_exists" | grep -oP 'count = \K\d+')" == "0" ]]; then
        handle_error "$ERR_DB_NOT_FOUND" "Session not found: $session_id"
        return $ERR_DB_NOT_FOUND
    fi
    
    # Update session status
    safe_update "$DB_FILE" \
        "UPDATE sessions SET status = :status, updated_at = datetime('now') WHERE id = :session_id" \
        ":status" "$new_status" \
        ":session_id" "$session_id" || return $?
    
    log_success "Updated session $session_id status to $new_status"
    return 0
}
```

## Error Handling in Plugins

Plugin developers should follow the same error handling patterns:

1. Source the errors.sh module in your plugin
2. Use the error handling functions provided
3. Return appropriate error codes from your hook functions

Example:
```bash
my_plugin_pre_session_hook() {
    local session_id="$1"
    
    # Validate input
    validate_arg "$session_id" "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" "Invalid session ID" || return $?
    
    # Do plugin work...
    
    return 0
}
```