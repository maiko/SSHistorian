#!/usr/bin/env bash
#
# SSHistorian - Common Utilities
# Shared functions used across the application

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=./constants.sh
    source "${SCRIPT_DIR}/constants.sh"
fi

# Logging functions
# Usage: log_debug "Debug message"
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        if [[ "$USE_COLORS" == "true" ]]; then
            echo -e "${GRAY}[${timestamp}][DEBUG]${NC} $*" >&2
        else
            echo "[${timestamp}][DEBUG] $*" >&2
        fi
    fi
}

# Usage: log_info "Info message"
log_info() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [[ "$USE_COLORS" == "true" ]]; then
        echo -e "${BLUE}[${timestamp}][INFO]${NC} $*"
    else
        echo "[${timestamp}][INFO] $*"
    fi
}

# Usage: log_warning "Warning message"
log_warning() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [[ "$USE_COLORS" == "true" ]]; then
        echo -e "${YELLOW}[${timestamp}][WARNING]${NC} $*" >&2
    else
        echo "[${timestamp}][WARNING] $*" >&2
    fi
}

# Usage: log_error "Error message"
log_error() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [[ "$USE_COLORS" == "true" ]]; then
        echo -e "${RED}[${timestamp}][ERROR]${NC} $*" >&2
    else
        echo "[${timestamp}][ERROR] $*" >&2
    fi
}

# Usage: log_success "Success message"
log_success() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [[ "$USE_COLORS" == "true" ]]; then
        echo -e "${GREEN}[${timestamp}][SUCCESS]${NC} $*"
    else
        echo "[${timestamp}][SUCCESS] $*"
    fi
}

# Generate a UUID
# Usage: generate_uuid
generate_uuid() {
    # Use system uuid generator if available
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr -d '[:space:]'
        return
    fi
    
    # If python is available, use that
    if command -v python3 &>/dev/null; then
        python3 -c 'import uuid; print(uuid.uuid4())'
        return
    elif command -v python &>/dev/null; then
        python -c 'import uuid; print(uuid.uuid4())'
        return
    fi
    
    # If neither uuid nor python are available, generate a UUID using bash
    # This is less secure but should work in most cases
    local uuid
    uuid="$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}')"
    echo "${uuid:0:36}"
}

# Check if a command exists
# Usage: command_exists "sqlite3"
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if required commands are available
check_dependencies() {
    local missing=false
    
    # Check for sqlite3
    if ! command_exists sqlite3; then
        log_error "SQLite3 is required but not found. Please install sqlite3."
        missing=true
    fi
    
    # Check for standard utilities
    for cmd in ssh openssl date basename dirname; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            missing=true
        fi
    done
    
    # Optional commands (will use alternatives)
    if ! command_exists uuidgen && ! command_exists python3 && ! command_exists python; then
        log_warning "Neither uuidgen nor python found. Will use a less secure method to generate UUIDs."
    fi
    
    # Fail if any required dependency is missing
    if [[ "$missing" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# Get a fingerprint of a public key
# Usage: get_key_fingerprint "/path/to/key.pub"
get_key_fingerprint() {
    local key_path="$1"
    
    # Check if the key exists
    if [[ ! -f "$key_path" ]]; then
        log_error "Public key not found: $key_path"
        return 1
    fi
    
    # Generate fingerprint using OpenSSL
    local fingerprint
    fingerprint=$(openssl pkey -pubin -in "$key_path" -inform PEM -outform DER 2>/dev/null | 
                 openssl dgst -sha256 -binary | 
                 openssl enc -base64 | 
                 tr -d '=\n')
    
    # Check if fingerprint generation was successful
    if [[ $? -ne 0 || -z "$fingerprint" ]]; then
        log_error "Failed to generate fingerprint for key: $key_path"
        return 1
    fi
    
    echo "$fingerprint"
    return 0
}

# Format a timestamp in a cross-platform way
# Usage: format_timestamp "2023-01-01T12:34:56Z" [format]
format_timestamp() {
    local timestamp="$1"
    local format="${2:-%Y-%m-%d %H:%M:%S}"
    
    # Use date to convert and format the timestamp
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        # ISO 8601 format - handle differently for macOS and Linux
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS version uses -j and -f options
            date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+$format" 2>/dev/null || echo "$timestamp"
        else
            # Linux version uses -d option
            date -u -d "$timestamp" "+$format" 2>/dev/null || echo "$timestamp"
        fi
    else
        # Assume timestamp is already in desired format
        echo "$timestamp"
    fi
}

# Get current timestamp in ISO 8601 format
# Usage: get_iso_timestamp
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Basic log message function (used in tests)
# Usage: log_message "INFO" "Message"
log_message() {
    local level="$1"
    local message="$2"
    
    echo "[$level] $message"
}

# Check if a string is a valid UUID
# Usage: is_uuid "123e4567-e89b-12d3-a456-426614174000"
is_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

# Get a formatted timestamp (YYYYMMDD_HHMMSS)
# Usage: get_timestamp
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Normalize a path to its canonical form
# Usage: normalize_path "/path/to/file"
normalize_path() {
    local path="$1"
    
    # Use realpath if available (Linux)
    if command -v realpath &>/dev/null; then
        realpath -s "$path" 2>/dev/null || echo "$path"
        return
    fi
    
    # Use readlink -f on macOS/BSD
    if command -v readlink &>/dev/null; then
        # Not all readlink versions support -f, especially on macOS
        readlink -f "$path" 2>/dev/null || echo "$path"
        return
    fi
    
    # Pure bash fallback for canonicalization
    local result
    # For absolute paths
    if [[ "$path" = /* ]]; then
        # Try to resolve via cd if it's a directory
        if [[ -d "$path" ]]; then
            result="$(cd "$path" 2>/dev/null && pwd)" || result="$path"
        else
            # For files, resolve the directory part and append filename
            local dir file
            dir="$(dirname "$path")"
            file="$(basename "$path")"
            if [[ -d "$dir" ]]; then
                result="$(cd "$dir" 2>/dev/null && pwd)/$file" || result="$path"
            else
                result="$path"
            fi
        fi
    else
        # For relative paths, prepend current dir
        if [[ -d "$path" ]]; then
            result="$(cd "$path" 2>/dev/null && pwd)" || result="$path"
        else
            local dir file
            dir="$(dirname "$path")"
            file="$(basename "$path")"
            if [[ -d "$dir" ]]; then
                result="$(cd "$dir" 2>/dev/null && pwd)/$file" || result="$path"
            else
                result="$PWD/$path"
            fi
        fi
    fi
    
    echo "$result"
}

# Check if a path is safely contained within a base directory
# Usage: is_safe_path "/path/to/check" "/base/directory"
is_safe_path() {
    local path="$1"
    local base_dir="$2"
    
    # Canonicalize both paths
    local canonical_path canonical_base
    canonical_path=$(normalize_path "$path")
    canonical_base=$(normalize_path "$base_dir")
    
    # Check if path is contained within base_dir
    [[ "$canonical_path" == "$canonical_base"* ]]
}

# Sanitize input to prevent command injection and SQL injection
# Usage: sanitize_input "user input" [context]
# Context can be 'sql', 'cmd', or 'path' to handle different types of input
sanitize_input() {
    local input="$1"
    local context="${2:-sql}" # Default context is SQL
    
    case "$context" in
        sql)
            # For SQL contexts, replace single quotes with doubled quotes 
            # (the proper way to escape quotes in SQLite)
            echo "$input" | sed "s/'/''/g"
            ;;
        cmd)
            # For command-line contexts, only allow specific characters
            # and remove anything potentially dangerous
            echo "$input" | LC_ALL=C tr -cd 'A-Za-z0-9_.,=:/@\-+ '
            ;;
        path)
            # For file paths, enhanced protection against path traversal
            # Strict restriction to alphanumeric, periods, hyphens, underscores and forward slashes
            # Explicitly removes any ../ sequences (but keep real characters)
            local filtered
            filtered=$(echo "$input" | tr -cd 'A-Za-z0-9_.,/:@\-+ ')
            
            # Remove all variations of directory traversal patterns
            # (handles multiple dots, slashes, etc.)
            filtered=$(echo "$filtered" | sed -E 's|(\.+/+)+||g' | sed -E 's|/+|/|g')
            echo "$filtered"
            ;;
        *)
            # Default fallback - very strict
            echo "$input" | LC_ALL=C tr -cd 'A-Za-z0-9_.,=:/@\-+ '
            ;;
    esac
}

# Confirm an action with a prompt
# Usage: confirm_action "Are you sure?"
confirm_action() {
    local prompt="$1"
    local response
    
    echo -n "$prompt [y/N] "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Export functions
export -f log_debug
export -f log_info
export -f log_warning
export -f log_error
export -f log_success
export -f log_message
export -f generate_uuid
export -f command_exists
export -f check_dependencies
export -f get_key_fingerprint
export -f format_timestamp
export -f get_iso_timestamp
export -f is_uuid
export -f get_timestamp
export -f normalize_path
export -f is_safe_path
export -f sanitize_input
export -f confirm_action