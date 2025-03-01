#!/usr/bin/env bash
#
# SSHistorian - Configuration Management Module
# Handles application configuration storage and retrieval
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
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Source error handling module if not already loaded
if ! command -v handle_error &>/dev/null; then
    # shellcheck source=../utils/errors.sh
    source "${ROOT_DIR}/src/utils/errors.sh"
fi

# Source database core if not already loaded
if ! command -v db_execute_params &>/dev/null; then
    # shellcheck source=../db/core/db_core.sh
    source "${ROOT_DIR}/src/db/core/db_core.sh"
fi

# Get a configuration value
# Usage: get_config <key> [default]
get_config() {
    local key="$1"
    local default="${2:-}"
    local value
    
    # Make sure database exists
    ensure_database || return $?
    
    # Execute query with parameter binding
    value=$(db_execute_params -line "SELECT value FROM config WHERE key = :key LIMIT 1;" ":key" "$key" | 
           grep -v "^[[:space:]]*$" | 
           sed -n 's/^[[:space:]]*value = \(.*\)$/\1/p')
    
    # If no value found, return default if provided
    if [[ -z "$value" && -n "$default" ]]; then
        echo "$default"
        return 0
    fi
    
    echo "$value"
    return 0
}

# Set a configuration value
# Usage: set_config <key> <value>
set_config() {
    local key="$1"
    local value="$2"
    local now
    now=$(get_iso_timestamp)
    
    # Make sure database exists
    ensure_database || return $?
    
    # Check if key exists first
    local key_exists
    key_exists=$(db_execute_params -count "SELECT COUNT(*) FROM config WHERE key = :key;" ":key" "$key")
    
    if [[ "$key_exists" -eq 0 ]]; then
        log_error "Configuration key '${key}' not found (not in database)"
        return 1
    fi
    
    # Use parameter binding to update the value
    db_execute_params "UPDATE config SET value = :value, updated_at = :updated_at WHERE key = :key;" \
        ":value" "$value" \
        ":updated_at" "$now" \
        ":key" "$key"
    
    # Verify the update
    local updated_value
    updated_value=$(get_config "$key")
    
    # If the value matches what we tried to set, consider it success
    if [[ "$updated_value" == "$value" ]]; then
        log_success "Configuration updated: ${key} = ${value}"
        return 0
    else
        handle_error "$ERR_DB_GENERAL" "Failed to update configuration. Expected '${value}' but got '${updated_value}'"
        return $ERR_DB_GENERAL
    fi
}

# List all configuration values
# Usage: list_config [--category <category>]
list_config() {
    local category=""
    
    # Parse arguments
    if [[ "$1" == "--category" && -n "$2" ]]; then
        category="$2"
    fi
    
    # Make sure database exists
    ensure_database || return $?
    
    # Execute query based on whether a category is specified
    if [[ -n "$category" ]]; then
        db_execute_params -table "SELECT key, value, type, description FROM config 
            WHERE key LIKE :pattern ORDER BY key;" ":pattern" "${category}.%"
    else
        db_execute -table "SELECT key, value, type, description FROM config ORDER BY key;"
    fi
    
    return $?
}

# Insert default configuration values
# This is used during database initialization
insert_default_config() {
    local now
    now=$(get_iso_timestamp)
    
    log_info "Setting up default configuration"
    
    # Use individual statements without transaction wrapper
    # On older SQLite versions, transactions can get confused with multiple statements
    
    # General settings
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.log_dir', '${LOG_DIR}', 'Directory where session logs are stored', 'path', '${LOG_DIR}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.session_retention_days', '${DEFAULT_MAX_LOG_AGE_DAYS}', 'Number of days to keep session logs', 'integer', '${DEFAULT_MAX_LOG_AGE_DAYS}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.auto_cleanup', '${DEFAULT_ASYNC_CLEANUP}', 'Automatically clean up old session logs', 'boolean', '${DEFAULT_ASYNC_CLEANUP}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.keys_dir', '${KEYS_DIR}', 'Directory for encryption keys', 'path', '${KEYS_DIR}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.log_base_dir', '${DEFAULT_LOG_BASE_DIR}', 'Base directory for logs', 'path', '${DEFAULT_LOG_BASE_DIR}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.log_permissions', '${DEFAULT_LOG_PERMISSIONS}', 'File permissions for log files (in octal)', 'string', '${DEFAULT_LOG_PERMISSIONS}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.dir_permissions', '${DEFAULT_DIR_PERMISSIONS}', 'Directory permissions for log directories (in octal)', 'string', '${DEFAULT_DIR_PERMISSIONS}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('general.version', '${VERSION}', 'SSHistorian version', 'string', '${VERSION}', '${now}');"
    
    # SSH settings
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ssh.binary', '${DEFAULT_SSH_BINARY}', 'Path to SSH binary', 'path', '${DEFAULT_SSH_BINARY}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ssh.default_options', '', 'Default SSH options to apply to all connections', 'string', '', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ssh.scp_binary', '${DEFAULT_SCP_BINARY}', 'Path to SCP binary', 'path', '${DEFAULT_SCP_BINARY}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ssh.sftp_binary', '${DEFAULT_SFTP_BINARY}', 'Path to SFTP binary', 'path', '${DEFAULT_SFTP_BINARY}', '${now}');"
    
    # Encryption settings
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.enabled', '${DEFAULT_ENABLE_ENCRYPTION}', 'Enable encryption of session logs', 'boolean', '${DEFAULT_ENABLE_ENCRYPTION}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.method', '${DEFAULT_ENCRYPTION_METHOD}', 'Encryption method (symmetric or asymmetric)', 'string', '${DEFAULT_ENCRYPTION_METHOD}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.public_key', '${DEFAULT_OPENSSL_PUBLIC_KEY}', 'Path to public key for encryption', 'path', '${DEFAULT_OPENSSL_PUBLIC_KEY}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.private_key', '${DEFAULT_OPENSSL_PRIVATE_KEY}', 'Path to private key for decryption', 'path', '${DEFAULT_OPENSSL_PRIVATE_KEY}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.multi_recipient', 'false', 'Enable multi-recipient encryption', 'boolean', 'false', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('encryption.additional_keys', '', 'Comma-separated list of additional public keys', 'string', '', '${now}');"
    
    # Compression settings
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('compression.tool', '${DEFAULT_COMPRESSION_TOOL}', 'Compression tool (gzip or xz)', 'string', '${DEFAULT_COMPRESSION_TOOL}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('compression.level', '${DEFAULT_COMPRESSION_LEVEL}', 'Compression level (1-9)', 'integer', '${DEFAULT_COMPRESSION_LEVEL}', '${now}');"
    
    # UI settings
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ui.timestamp_format', '${DEFAULT_TIMESTAMP_FORMAT}', 'Format string for displaying timestamps', 'string', '${DEFAULT_TIMESTAMP_FORMAT}', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ui.show_command_in_list', 'true', 'Show the full command in session list', 'boolean', 'true', '${now}');"
    
    db_execute "INSERT INTO config (key, value, description, type, default_value, updated_at) VALUES 
    ('ui.color_enabled', '${USE_COLORS}', 'Enable colorized output', 'boolean', '${USE_COLORS}', '${now}');"
    
    # No COMMIT needed since we're not using transaction

    if [[ $? -ne 0 ]]; then
        handle_error "$ERR_DB_GENERAL" "Failed to insert default configuration"
        return $ERR_DB_GENERAL
    fi
    
    return 0
}

# Migrate user configuration from file to database
# This is a one-time migration for users upgrading from older versions
migrate_config_to_database() {
    local old_config_file="${HOME}/.config/sshistorian/config"
    
    # Check if old config file exists
    if [[ ! -f "$old_config_file" ]]; then
        log_debug "No old configuration file found, no migration needed"
        return 0
    fi
    
    log_info "Migrating configuration from file to database..."
    
    # Read old config file and extract settings
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue
        
        # Extract key-value pairs
        if [[ "$line" =~ ^([A-Za-z0-9_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Convert old-style keys to new format
            local db_key
            case "$key" in
                LOG_BASE_DIR)
                    db_key="general.log_base_dir"
                    ;;
                MAX_LOG_AGE_DAYS)
                    db_key="general.session_retention_days"
                    ;;
                LOG_PERMISSIONS)
                    db_key="general.log_permissions"
                    ;;
                ENABLE_ENCRYPTION)
                    db_key="encryption.enabled"
                    ;;
                ENCRYPTION_METHOD)
                    db_key="encryption.method"
                    ;;
                COMPRESSION_TOOL)
                    db_key="compression.tool"
                    ;;
                COMPRESSION_LEVEL)
                    db_key="compression.level"
                    ;;
                ASYNC_CLEANUP)
                    db_key="general.auto_cleanup"
                    ;;
                *)
                    # Ignore unknown settings
                    log_warning "Unknown configuration key: $key (skipping)"
                    continue
                    ;;
            esac
            
            # Update database with the value (if key exists)
            if set_config "$db_key" "$value"; then
                log_debug "Migrated setting: $key → $db_key = $value"
            else
                log_warning "Failed to migrate setting: $key"
            fi
        fi
    done < "$old_config_file"
    
    # Backup the old config file
    local backup_file="${old_config_file}.bak.$(date +%Y%m%d%H%M%S)"
    if mv "$old_config_file" "$backup_file"; then
        log_success "Configuration migrated successfully. Old config backed up to $backup_file"
    else
        log_warning "Configuration migrated but failed to backup old config file"
    fi
    
    # Check for old encryption keys and migrate if needed
    local old_key_dir="${HOME}/.config/sshistorian"
    
    # If the old public key exists, update the database to point to it
    if [[ -f "${old_key_dir}/public.pem" ]]; then
        set_config "encryption.public_key" "${old_key_dir}/public.pem"
        log_info "Using existing encryption key at ${old_key_dir}/public.pem"
    fi
    
    # If the old private key exists, update the database to point to it
    if [[ -f "${old_key_dir}/private.pem" ]]; then
        set_config "encryption.private_key" "${old_key_dir}/private.pem"
    fi
    
    return 0
}

# Export functions
export -f get_config
export -f set_config
export -f list_config
export -f insert_default_config
export -f migrate_config_to_database