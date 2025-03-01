#!/usr/bin/env bash
#
# SSHistorian - Example CLI Extension Plugin
# Demonstrates how to add CLI commands to SSHistorian

# Source utility functions if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ROOT_DIR:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Command handler for 'hello' command
example_hello_handler() {
    local name="${1:-World}"
    echo "Hello, $name!"
    return 0
}

# Command handler for 'count' command
example_count_handler() {
    local max="${1:-5}"
    
    # Validate input
    if ! [[ "$max" =~ ^[0-9]+$ ]]; then
        log_error "Invalid number: $max"
        echo "Usage: sshistorian plugin command example count <number>"
        return 1
    fi
    
    echo "Counting to $max:"
    for ((i=1; i<=max; i++)); do
        echo "$i"
    done
    
    return 0
}

# Command handler for 'help' command
example_help_handler() {
    echo "Example Plugin Help"
    echo "=================="
    echo 
    echo "Available commands:"
    echo "  hello [name]      - Display a greeting to the specified name"
    echo "  count [number]    - Count from 1 to the specified number"
    echo "  help              - Show this help message"
    echo
    echo "Examples:"
    echo "  sshistorian plugin command example hello Alice"
    echo "  sshistorian plugin command example count 10"
    
    return 0
}

# Export functions
export -f example_hello_handler
export -f example_count_handler
export -f example_help_handler

# Register the plugin (with CLI commands enabled)
register_plugin "example" "Example Plugin" "1.0.0" "Demonstrates CLI extensions" 0 0 1

# Register CLI commands
register_cli_command "example" "hello" "Display a greeting" "example_hello_handler"
register_cli_command "example" "count" "Count to a number" "example_count_handler"
register_cli_command "example" "help" "Show help for example plugin" "example_help_handler"