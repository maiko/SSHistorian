#!/usr/bin/env bash
#
# SSHistorian - Logging Utilities
# Functions for logging messages, errors, and warnings

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=./constants.sh
    source "${SCRIPT_DIR}/constants.sh"
fi

# Function to log informational messages
# Usage: log_message "Your message here"
log_message() {
    local timestamp msg level
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    msg="$1"
    level="${2:-INFO}"
    
    # Format the output based on log level
    case "$level" in
        INFO)
            echo -e "${BLUE}[${timestamp}]${NC} ${msg}"
            ;;
        DEBUG)
            # Only show debug messages if DEBUG is enabled
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${GRAY}[${timestamp}] [DEBUG]${NC} ${msg}"
            fi
            ;;
        *)
            echo -e "${BLUE}[${timestamp}]${NC} ${msg}"
            ;;
    esac
    
    # Optionally log to file if LOG_FILE is defined
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[${timestamp}] [${level}] ${msg}" >> "$LOG_FILE"
    fi
}

# Function to log error messages
# Usage: log_error "Error message here"
log_error() {
    local timestamp msg
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    msg="$1"
    
    echo -e "${RED}[ERROR]${NC} ${msg}" >&2
    
    # Optionally log to file if LOG_FILE is defined
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[${timestamp}] [ERROR] ${msg}" >> "$LOG_FILE"
    fi
}

# Function to log warning messages
# Usage: log_warning "Warning message here"
log_warning() {
    local timestamp msg
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    msg="$1"
    
    echo -e "${YELLOW}[WARNING]${NC} ${msg}" >&2
    
    # Optionally log to file if LOG_FILE is defined
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[${timestamp}] [WARNING] ${msg}" >> "$LOG_FILE"
    fi
}

# Function to log success messages
# Usage: log_success "Success message here"
log_success() {
    local timestamp msg
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    msg="$1"
    
    echo -e "${GREEN}[SUCCESS]${NC} ${msg}"
    
    # Optionally log to file if LOG_FILE is defined
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[${timestamp}] [SUCCESS] ${msg}" >> "$LOG_FILE"
    fi
}

# Function to log a command execution
# Usage: log_command "Command description" "command to execute"
log_command() {
    local description="$1"
    local command="$2"
    local hide_output="${3:-false}"
    local exit_code
    
    log_message "Running: $description"
    
    if [[ "$hide_output" == "true" ]]; then
        eval "$command" &>/dev/null
        exit_code=$?
    else
        eval "$command"
        exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_message "Command completed successfully."
    else
        log_error "Command failed with exit code: $exit_code"
    fi
    
    return $exit_code
}

# Set up error handling
# Function to handle errors
handle_error() {
    local line_no="$1"
    local command="$2"
    local exit_code="$3"
    
    log_error "Error in line ${line_no}: Command '${command}' exited with status ${exit_code}"
    
    # We log the error but don't exit the script - this allows the caller to handle the error
    return $exit_code
}

# Function to log debug messages
# Usage: log_debug "Debug message here"
log_debug() {
    local msg="$1"
    
    # Only log if DEBUG is enabled
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_message "$msg" "DEBUG"
    fi
    
    return 0
}

# Export functions and variables
export RED GREEN YELLOW BLUE CYAN MAGENTA GRAY BOLD NC
export -f log_message
export -f log_error
export -f log_warning
export -f log_success
export -f log_command
export -f log_debug
export -f handle_error