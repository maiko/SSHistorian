# SSHistorian: Input Sanitization Approach

This document details the sanitization approaches used within SSHistorian to ensure secure processing of user input, prevent common security vulnerabilities, and maintain data integrity.

## Principles of Sanitization

SSHistorian follows these core principles for sanitization:

1. **Context-Aware Sanitization**: Different types of data require different sanitization techniques
2. **Defense in Depth**: Multiple layers of validation and sanitization
3. **Least Privilege**: Restricting operations to the minimum necessary access
4. **Fail Safely**: When in doubt, reject or sanitize aggressively

## Core Sanitization Functions

### `sanitize_input` Function

The primary sanitization engine is the `sanitize_input` function in `src/utils/common.sh`, which provides context-aware sanitization:

```bash
# Sanitize user input based on context
# Usage: sanitize_input <input> [context]
sanitize_input() {
    local input="$1"
    local context="${2:-general}"
    
    case "$context" in
        sql)
            # SQL sanitization: Replace single quotes with doubled quotes
            echo "${input//\'/\'\'}"
            ;;
        cmd)
            # Command sanitization: Only allow basic chars for command execution
            echo "$input" | tr -cd 'a-zA-Z0-9 _.,:=@/\-'
            ;;
        path)
            # Path sanitization: Prevent path traversal and non-standard chars
            local result
            # Remove directory traversal attempts
            result="${input//..\/}"
            result="${result//.\.\//}"
            # Allow only safe characters
            echo "$result" | tr -cd 'a-zA-Z0-9 _.,:=@/\-'
            ;;
        *)
            # Default sanitization: Conservative approach for general text
            echo "$input" | tr -cd 'a-zA-Z0-9 _.,:=@/\-'
            ;;
    esac
}
```

## SQL Injection Prevention

### Parameterized Queries

All database interactions use parameterized queries through the `db_execute_params` function, which prevents SQL injection by properly binding parameters:

```bash
db_execute_params "INSERT INTO sessions (id, host, timestamp) VALUES (:id, :host, :timestamp);"
    ":id" "$uuid"
    ":host" "$host"
    ":timestamp" "$timestamp"
```

Key features:
- Named parameters (`:param_name`) for clarity
- Properly handles special characters and prevents injection
- Temporary script files manage parameter binding securely
- Special handling for NULL values

## Path Traversal Protection

SSHistorian prevents path traversal attacks through multiple complementary techniques:

### Path Canonicalization

The `normalize_path` function resolves paths to their canonical form:

```bash
# Normalize a path to its canonical form (resolving symlinks, etc.)
normalize_path() {
    local path="$1"
    
    # Check if readlink -f or realpath is available
    if command -v readlink >/dev/null 2>&1 && readlink -f "$path" >/dev/null 2>&1; then
        readlink -f "$path"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    else
        # Fallback implementation if readlink -f and realpath are unavailable
        local dir file
        dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd)"
        file="$(basename "$path")"
        if [[ -z "$dir" ]]; then
            echo "$path"
        else
            echo "$dir/$file"
        fi
    fi
}
```

### Path Safety Validation

The `is_safe_path` function ensures paths remain within allowed directories:

```bash
# Check if a path is safely contained within a base directory
is_safe_path() {
    local path="$1"
    local base_dir="$2"
    
    # Check if normalized path starts with normalized base dir
    [[ "$path" == "$base_dir"* ]]
}
```

This is used to ensure operations like file deletion only affect files within allowed directories:

```bash
if is_safe_path "$full_path" "$canonical_log_dir"; then
    rm -f "$full_path"
else
    log_warning "Security violation: Path is outside allowed directory"
fi
```

## Command Injection Prevention

SSHistorian prevents command injection through:

1. **Argument Escaping**:
   ```bash
   # Safe command execution with printf %q for argument escaping
   ssh_command="$(printf "%q " "$SSH_BINARY" "${ssh_options[@]}" "$target")"
   ```

2. **Input Sanitization**:
   ```bash
   # Command sanitization mode
   sanitize_input "$command" "cmd"
   ```

3. **Avoiding Shell Expansion**:
   Where possible, arguments are passed as arrays instead of strings to avoid shell expansion vulnerabilities.

## User Input Validation

In addition to sanitization, SSHistorian uses strict validation:

### UUID Validation

```bash
# Check if a string is a valid UUID
is_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}
```

### Numeric Validation

```bash
# Ensure exit_code is an integer
if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
    log_error "Invalid exit code: $exit_code - must be an integer"
    exit_code=1  # Default to error exit code
fi
```

## Conclusion

SSHistorian employs multiple defense layers to protect against common security vulnerabilities. By combining context-aware sanitization, parameterized queries, path validation, and strict input checking, the system maintains security and data integrity even when processing untrusted user input.