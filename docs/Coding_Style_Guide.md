# SSHistorian Coding Style Guide

This document outlines the coding style and best practices for the SSHistorian project.

## File Structure

Each file should:
1. Start with a shebang if executable (`#!/usr/bin/env bash`)
2. Include a comment header with file description
3. Source required dependencies
4. Define functions
5. Export functions that need to be accessible to other modules

Example:

```bash
#!/usr/bin/env bash
#
# SSHistorian - Module Name
# Brief description of what this module does
#

# First source dependencies, then define and export functions
# ...
```

## Module Imports

The proper way to import dependencies is to use absolute paths based on the `ROOT_DIR` variable:

```bash
# At the beginning of each file - always start with constants.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ROOT_DIR:-}" ]]; then
    source "${SCRIPT_DIR}/path/to/constants.sh"
fi

# Then use ROOT_DIR for importing other modules
if ! command -v log_debug &>/dev/null; then
    source "${ROOT_DIR}/src/utils/common.sh"
fi
```

Avoid using relative paths like `../utils/common.sh`. Instead, use absolute paths based on `ROOT_DIR`.

## Function Definitions

Functions should:
1. Have a descriptive comment explaining purpose, parameters, and return value
2. Use local variables to avoid polluting the global namespace
3. Follow snake_case naming convention
4. Return appropriate exit codes

Example:

```bash
# Process a user input and return a sanitized value
# Args:
#   $1: Input string to sanitize
# Returns:
#   0 on success, non-zero on error
#   Outputs sanitized string to stdout
sanitize_input() {
    local input="$1"
    local sanitized
    
    # Input validation
    if [[ -z "$input" ]]; then
        log_error "Empty input"
        return 1
    fi
    
    # Process input
    sanitized="${input//[^a-zA-Z0-9_-]/}"
    
    # Return result
    echo "$sanitized"
    return 0
}
```

## Error Handling

Always use proper error handling:

```bash
# Use set -e in scripts that should exit on error
set -euo pipefail

# Use conditional checks and explicit returns in functions
if [[ ! -f "$file" ]]; then
    log_error "File not found: $file"
    return 1
fi

# For operations that might fail, use proper checks
temp_file=$(mktemp) || {
    log_error "Failed to create temporary file"
    return 1
}
```

## SQL Queries

Always use parameter binding for SQL queries:

```bash
# Good - using parameter binding
db_execute_params "SELECT * FROM sessions WHERE host = :host;" ":host" "$user_input"

# Bad - vulnerable to SQL injection
db_execute "SELECT * FROM sessions WHERE host = '$user_input';"
```

## Code Organization

- Group related functions in the same file
- Place modules in appropriate directories:
  - `src/core/`: Core SSH functionality
  - `src/db/`: Database operations
  - `src/utils/`: Utility functions
  - `src/plugins/`: Plugin system
  - `src/ui/`: User interface components

## Documentation

- Each file should have a comment header
- Each function should have a comment explaining its purpose
- Complex logic should have inline comments
- Update documentation when changing behavior

## Variable Naming

- Use lowercase with underscores (snake_case) for variables and functions
- Use uppercase with underscores for constants
- Use descriptive names that explain the purpose

```bash
# Good variable names
local user_input="$1"
local temp_file
local host_count

# Good constant names
readonly MAX_RETRIES=3
readonly LOG_DIR="/var/log/sshistorian"
```

## Consistent Indentation

Use 4 spaces for indentation, not tabs:

```bash
if [[ -n "$var" ]]; then
    # 4 spaces indentation
    echo "Variable is set"
    
    if [[ "$var" == "value" ]]; then
        # 8 spaces (nested)
        echo "Variable equals value"
    fi
fi
```

## Line Length

Keep line length to a maximum of 120 characters. Break long commands using backslashes:

```bash
# Long command broken into multiple lines
long_command_with_many_arguments \
    --first-option="$first_value" \
    --second-option="$second_value" \
    --third-option="$third_value"
```