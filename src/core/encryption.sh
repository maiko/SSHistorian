#!/usr/bin/env bash
#
# SSHistorian - Encryption Module
# Functions for encrypting and decrypting log files using SSH keys

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ROOT_DIR:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Source database module if not already loaded
if ! command -v init_database &>/dev/null; then
    # shellcheck source=../db/database.sh
    source "${ROOT_DIR}/src/db/database.sh"
fi

# Source database core if not already loaded
if ! command -v db_execute_params &>/dev/null; then
    # shellcheck source=../db/core/db_core.sh
    source "${ROOT_DIR}/src/db/core/db_core.sh"
fi

# Check if encryption is enabled in config
is_encryption_enabled() {
    local enabled
    enabled=$(get_config "encryption.enabled" "false")
    
    log_debug "Encryption enabled setting: $enabled"
    
    if [[ "$enabled" == "true" ]]; then
        log_debug "Encryption is enabled"
        return 0
    else
        log_debug "Encryption is disabled"
        return 1
    fi
}

# Get the public key path from database config
get_public_key_path() {
    local default_key="${DEFAULT_OPENSSL_PUBLIC_KEY}"
    # Ensure keys directory exists
    mkdir -p "$(dirname "$default_key")" 2>/dev/null || true
    get_config "encryption.public_key" "$default_key"
}

# Validate a public key
validate_public_key() {
    local key_path="$1"
    
    # Check if file exists
    if [[ ! -f "$key_path" ]]; then
        log_error "Public key not found: $key_path"
        return 1
    fi
    
    # Check if it's a valid public key
    if ! openssl pkey -pubin -in "$key_path" -inform PEM -noout 2>/dev/null; then
        log_error "Invalid public key: $key_path"
        return 1
    fi
    
    return 0
}

# Encrypt a file using hybrid encryption (AES + RSA)
# This creates two files:
# 1. <output_file> - The file encrypted with random AES key
# 2. <output_file>.aes.enc - The AES key encrypted with RSA public key
# Usage: encrypt_file <input_file> <output_file> [session_id]
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local session_id="${3:-}"
    local pub_key encrypted_key
    
    log_debug "encrypt_file called for $input_file → $output_file (session $session_id)"
    
    # For tests: if we're in test mode and session_id is empty, skip validation
    local in_test_mode="${SSHISTORIAN_TEST_MODE:-false}"
    
    # Check if encryption is enabled (skip check in test mode)
    if ! is_encryption_enabled && [[ "$in_test_mode" != "true" ]]; then
        log_debug "Encryption is disabled, skipping encryption for $input_file"
        return 0
    fi
    
    # Canonicalize input and output paths for security
    local canonical_input canonical_output canonical_log_dir
    canonical_input=$(normalize_path "$input_file")
    canonical_output=$(normalize_path "$output_file")
    canonical_log_dir=$(normalize_path "$LOG_DIR")
    
    log_debug "Proceeding with encryption of $canonical_input"
    
    # Verify file extension for input file
    if [[ ! "$canonical_input" =~ \.(log|timing)$ && "$in_test_mode" != "true" ]]; then
        log_error "Invalid file extension for encryption: $canonical_input (must be .log or .timing)"
        return 1
    fi
    
    # Verify output file extension and location
    if [[ ! "$canonical_output" =~ \.(log|timing)\.enc$ && "$in_test_mode" != "true" ]]; then
        log_error "Invalid output file extension: $canonical_output (must end with .log.enc or .timing.enc)"
        return 1
    fi
    
    # Ensure output file is within LOG_DIR if not in test mode
    if [[ "$in_test_mode" != "true" ]]; then
        if ! is_safe_path "$canonical_output" "$canonical_log_dir"; then
            log_error "Security violation: Output file must be within log directory: $canonical_output"
            return 1
        fi
    fi
    
    # Check if input file exists
    if [[ ! -f "$canonical_input" ]]; then
        log_error "File not found for encryption: $canonical_input"
        return 1
    fi
    
    # Define encrypted key path
    encrypted_key="${canonical_output}.aes.enc"
    
    # For test mode, we'll use a simple symmetric encryption
    if [[ "$in_test_mode" == "true" ]]; then
        log_debug "Test mode: Using simplified encryption"
        
        # Use test keys if available, otherwise default
        local test_key_dir="${SSHISTORIAN_CONFIG_DIR:-${KEYS_DIR}/test}"
        if [[ -f "${test_key_dir}/sshistorian_rsa.pub" ]]; then
            pub_key="${test_key_dir}/sshistorian_rsa.pub"
        else
            # For tests, create a test key if needed
            if [[ ! -d "${test_key_dir}" ]]; then
                mkdir -p "${test_key_dir}"
            fi
            
            # Either generate keys or use fallback method
            if command -v openssl &>/dev/null; then
                if [[ ! -f "${test_key_dir}/sshistorian_rsa" ]]; then
                    openssl genrsa -out "${test_key_dir}/sshistorian_rsa" 2048 >/dev/null 2>&1
                    openssl rsa -in "${test_key_dir}/sshistorian_rsa" -pubout -out "${test_key_dir}/sshistorian_rsa.pub" >/dev/null 2>&1
                fi
                pub_key="${test_key_dir}/sshistorian_rsa.pub"
            else
                # Mock encryption for tests without OpenSSL
                cat "$canonical_input" > "$canonical_output"
                echo "TEST_KEY" > "$encrypted_key"
                chmod 600 "$canonical_output" "$encrypted_key"
                return 0
            fi
        fi
    else
        # Get public key
        pub_key=$(get_public_key_path)
        if ! validate_public_key "$pub_key"; then
            log_error "Failed to validate public key for encryption"
            return 1
        fi
    fi
    
    # Get fingerprint of public key
    local fingerprint=""
    if [[ -n "$session_id" ]]; then
        fingerprint=$(get_key_fingerprint "$pub_key")
        if [[ $? -ne 0 ]]; then
            log_error "Failed to get fingerprint for public key: $pub_key"
            return 1
        fi
    fi
    
    # Generate random AES key
    local aes_key
    aes_key=$(openssl rand -base64 32)
    
    # Encrypt file with AES key
    echo "$aes_key" | openssl enc -aes-256-cbc -salt -in "$canonical_input" -out "$canonical_output" -pass stdin
    if [[ $? -ne 0 ]]; then
        log_error "Failed to encrypt file with AES: $canonical_input"
        return 1
    fi
    
    # Encrypt AES key with public key
    echo "$aes_key" | openssl rsautl -encrypt -pubin -inkey "$pub_key" -out "$encrypted_key"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to encrypt AES key with RSA: $pub_key"
        rm -f "$canonical_output"
        return 1
    fi
    
    # Store encryption info in database if we have a session_id
    if [[ -n "$session_id" ]]; then
        store_encryption_info "$session_id" "$fingerprint"
    fi
    
    # Set secure permissions
    chmod 600 "$canonical_output" "$encrypted_key"
    
    # If successful and not in test mode, remove original file
    if [[ "${SSHISTORIAN_TEST_MODE:-false}" != "true" ]]; then
        rm -f "$canonical_input"
    fi
    
    log_debug "File encrypted successfully: $canonical_input → $canonical_output"
    return 0
}

# Decrypt a file that was encrypted with hybrid encryption
# Usage: decrypt_file <encrypted_file> <output_file> [private_key_path]
decrypt_file() {
    local encrypted_file="$1"
    local output_file="$2"
    local private_key="${3:-}"
    local encrypted_key aes_key
    
    # Canonicalize paths for security
    local canonical_encrypted_file canonical_output_file canonical_log_dir
    canonical_encrypted_file=$(normalize_path "$encrypted_file")
    canonical_output_file=$(normalize_path "$output_file")
    canonical_log_dir=$(normalize_path "$LOG_DIR")
    
    # Verify file extensions
    local in_test_mode="${SSHISTORIAN_TEST_MODE:-false}"
    if [[ "$in_test_mode" != "true" ]]; then
        # Validate encrypted file extension
        if [[ ! "$canonical_encrypted_file" =~ \.(log|timing)\.enc$ ]]; then
            log_error "Invalid encrypted file extension: $canonical_encrypted_file (must end with .log.enc or .timing.enc)"
            return 1
        fi
        
        # Validate output file is in a safe location
        if [[ "$canonical_output_file" != /tmp/* && ! "$canonical_output_file" =~ /temp_decrypted\.* ]]; then
            # If not a temporary file, ensure it's within LOG_DIR and has proper extension
            if ! is_safe_path "$canonical_output_file" "$canonical_log_dir"; then
                log_error "Security violation: Output file must be within log directory: $canonical_output_file"
                return 1
            fi
            
            if [[ ! "$canonical_output_file" =~ \.(log|timing)$ ]]; then
                log_error "Invalid output file extension: $canonical_output_file (must end with .log or .timing)"
                return 1
            fi
        fi
    fi
    
    # Check if encrypted file exists
    if [[ ! -f "$canonical_encrypted_file" ]]; then
        log_error "Encrypted file not found: $canonical_encrypted_file"
        return 1
    fi
    
    # Check if encrypted key exists - directly use the .aes.enc extension
    encrypted_key="${canonical_encrypted_file}.aes.enc"
    if [[ ! -f "$encrypted_key" ]]; then
        # For backward compatibility, try the old format too
        encrypted_key="${canonical_encrypted_file%.enc}.aes.enc"
        if [[ ! -f "$encrypted_key" ]]; then
            log_error "Encrypted key not found: $encrypted_key"
            return 1
        fi
    fi
    
    # Ensure the encrypted key is in a safe location
    if [[ "$in_test_mode" != "true" ]]; then
        local canonical_encrypted_key
        canonical_encrypted_key=$(normalize_path "$encrypted_key")
        if ! is_safe_path "$canonical_encrypted_key" "$canonical_log_dir"; then
            log_error "Security violation: Encrypted key must be within log directory: $canonical_encrypted_key"
            return 1
        fi
    fi
    
    # For tests: if we're in test mode, use test keys
    if [[ "$in_test_mode" == "true" ]]; then
        log_debug "Test mode: Using test private key"
        
        # Check if it's a test key
        if grep -q "TEST_KEY" "$encrypted_key" 2>/dev/null; then
            log_debug "Test mode: Using mock decryption"
            cp "$canonical_encrypted_file" "$canonical_output_file"
            chmod 600 "$canonical_output_file"
            return 0
        fi
        
        # Use test key if available
        local test_key_dir="${SSHISTORIAN_CONFIG_DIR:-${KEYS_DIR}/test}"
        if [[ -f "${test_key_dir}/sshistorian_rsa" ]]; then
            private_key="${test_key_dir}/sshistorian_rsa"
        else
            log_error "Test key not found: ${test_key_dir}/sshistorian_rsa"
            return 1
        fi
    elif [[ -n "$PRIVATE_KEY" ]]; then
        # Use the explicitly provided private key (useful for key rotation)
        private_key="$PRIVATE_KEY"
    elif [[ -z "$private_key" ]]; then
        # If private key not provided, get from database or use default
        private_key=$(get_config "encryption.private_key" "${DEFAULT_OPENSSL_PRIVATE_KEY}")
        
        # Prompt user if key doesn't exist
        if [[ ! -f "$private_key" ]]; then
            log_warning "Private key not found: $private_key"
            read -r -p "Enter path to private key: " private_key
            
            if [[ ! -f "$private_key" ]]; then
                log_error "Invalid private key path: $private_key"
                return 1
            fi
        fi
    fi
    
    # Canonicalize private key path
    local canonical_private_key
    canonical_private_key=$(normalize_path "$private_key")
    
    # Decrypt the AES key with private key
    aes_key=$(openssl rsautl -decrypt -inkey "$canonical_private_key" -in "$encrypted_key" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to decrypt AES key with private key: $canonical_private_key"
        return 1
    fi
    
    # Decrypt the file with AES key
    echo "$aes_key" | openssl enc -d -aes-256-cbc -in "$canonical_encrypted_file" -out "$canonical_output_file" -pass stdin
    if [[ $? -ne 0 ]]; then
        log_error "Failed to decrypt file with AES key: $canonical_encrypted_file"
        return 1
    fi
    
    # Set secure permissions on output file
    chmod 600 "$canonical_output_file"
    
    log_debug "File decrypted successfully: $canonical_output_file"
    return 0
}

# Store encryption information in the database
# Usage: store_encryption_info <session_id> <fingerprint>
store_encryption_info() {
    local session_id="$1"
    local fingerprint="$2"
    local encrypted_at
    
    # Get current timestamp
    encrypted_at=$(get_iso_timestamp)
    
    # Insert into database using parameter binding
    db_execute_params "INSERT OR REPLACE INTO encryption_info (
    session_id, public_key_fingerprint, encrypted_at
) VALUES (
    :session_id, :fingerprint, :encrypted_at
);" \
        ":session_id" "$session_id" \
        ":fingerprint" "$fingerprint" \
        ":encrypted_at" "$encrypted_at"
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to store encryption info in database"
        return 1
    fi
    
    return 0
}

# Get encryption information for a session
# Usage: get_encryption_info <session_id>
get_encryption_info() {
    local session_id="$1"
    
    db_execute_params -line "SELECT 
    session_id, public_key_fingerprint, encrypted_at
FROM encryption_info
WHERE session_id = :session_id;" \
        ":session_id" "$session_id"
    
    return 0
}

# Get the fingerprint of a public key
get_key_fingerprint() {
    local key_path="$1"
    
    # Check if file exists
    if [[ ! -f "$key_path" ]]; then
        log_error "Public key not found: $key_path"
        return 1
    fi
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(openssl pkey -pubin -in "$key_path" -inform PEM -outform DER | openssl md5 -c | awk '{print $2}')
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get fingerprint for key: $key_path"
        return 1
    fi
    
    echo "$fingerprint"
    return 0
}

# Generate a random encryption key
# Returns a 256-bit (64 hex character) random key
generate_random_key() {
    openssl rand -hex 32
    return $?
}

# Check if a file is encrypted
# Usage: is_file_encrypted <file_path>
is_file_encrypted() {
    local file_path="$1"
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi
    
    # Check for signature/magic bytes that indicate encryption
    # OpenSSL encrypted files typically start with "Salted__"
    if head -c 8 "$file_path" | grep -q "Salted__"; then
        return 0  # File is encrypted
    fi
    
    # Also check filename pattern (.enc suffix)
    if [[ "$file_path" == *.enc ]]; then
        return 0  # File is encrypted
    fi
    
    return 1  # File is not encrypted
}

# Generate encryption keys for SSHistorian
# Creates a dedicated RSA key pair for encrypting log files
# Usage: generate_encryption_keys
generate_encryption_keys() {
    # Define key paths - use test directory if in test mode or keys directory otherwise
    local keys_dir="${SSHISTORIAN_CONFIG_DIR:-${KEYS_DIR}}"
    local private_key="${keys_dir}/sshistorian_rsa"
    local public_key="${keys_dir}/sshistorian_rsa.pub"
    
    log_info "Generating encryption keys for SSHistorian..."
    
    # Ensure keys directory exists with secure permissions
    mkdir -p "$keys_dir"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create keys directory: $keys_dir"
        return 1
    fi
    
    # Set secure permissions for keys directory (0700: only owner can read/write/execute)
    chmod 700 "$keys_dir"
    if [[ $? -ne 0 ]]; then
        log_warning "Failed to set secure permissions on keys directory: $keys_dir"
    }
    
    # Check if keys already exist
    if [[ -f "$private_key" || -f "$public_key" ]]; then
        # In test mode, always overwrite without prompting
        if [[ "${SSHISTORIAN_TEST_MODE:-false}" != "true" ]]; then
            local overwrite
            log_warning "Encryption keys already exist. Overwrite? (y/n)"
            read -r overwrite
            
            if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
                log_info "Key generation canceled."
                return 0
            fi
        else
            log_debug "Test mode: Overwriting existing keys without prompt"
        fi
    fi
    
    # Generate RSA private key (2048 bits)
    openssl genrsa -out "$private_key" 2048
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate private key"
        return 1
    fi
    
    # Extract public key
    openssl rsa -in "$private_key" -pubout -out "$public_key"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to extract public key"
        rm -f "$private_key"  # Clean up private key if public key extraction fails
        return 1
    fi
    
    # Set correct permissions
    chmod 600 "$private_key"
    chmod 644 "$public_key"
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(get_key_fingerprint "$public_key")
    
    # Update configuration to use the new keys if we're not in test mode
    if [[ "${SSHISTORIAN_TEST_MODE:-false}" != "true" ]]; then
        if command -v set_config &>/dev/null; then
            set_config "encryption.public_key" "$public_key"
            set_config "encryption.private_key" "$private_key"
            set_config "encryption.enabled" "true"
            set_config "encryption.method" "asymmetric"
        else
            log_warning "set_config function not available, skipping configuration update"
        fi
        
        log_success "Encryption keys generated successfully!"
        echo "Private key: $private_key"
        echo "Public key: $public_key"
        echo "Fingerprint: $fingerprint"
        echo ""
        echo "Configuration updated to use the new keys."
        echo "Your session logs will now be encrypted with these keys."
    else
        log_debug "Test mode: Keys generated at $private_key and $public_key"
    fi
    
    return 0
}

# Rotate encryption keys and re-encrypt files
# This function generates new keys and re-encrypts all files in the provided list
# Usage: rotate_encryption_keys <file_list_path>
rotate_encryption_keys() {
    local file_list_path="$1"
    local old_private_key old_public_key new_private_key new_public_key
    
    # Use test config directory if in test mode
    local in_test_mode="${SSHISTORIAN_TEST_MODE:-false}"
    local config_dir
    if [[ "$in_test_mode" == "true" ]]; then
        config_dir="${SSHISTORIAN_CONFIG_DIR}"
    else
        config_dir="${HOME}/.config/sshistorian"
    fi
    
    old_private_key="${config_dir}/sshistorian_rsa"
    old_public_key="${config_dir}/sshistorian_rsa.pub"
    
    # Check if current keys exist
    if [[ ! -f "$old_private_key" || ! -f "$old_public_key" ]]; then
        log_error "Current encryption keys not found - cannot rotate"
        return 1
    fi
    
    # Create backup of old keys
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_dir="${config_dir}/key_backup_${timestamp}"
    mkdir -p "$backup_dir"
    
    # Copy old keys to backup
    cp "$old_private_key" "${backup_dir}/sshistorian_rsa.old"
    cp "$old_public_key" "${backup_dir}/sshistorian_rsa.pub.old"
    
    log_info "Current keys backed up to ${backup_dir}"
    
    # Generate new keys
    log_info "Generating new encryption keys..."
    
    # Temporarily rename old keys
    mv "$old_private_key" "${old_private_key}.old"
    mv "$old_public_key" "${old_public_key}.old"
    
    # Generate new keys
    generate_encryption_keys
    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate new keys"
        
        # Restore old keys
        mv "${old_private_key}.old" "$old_private_key"
        mv "${old_public_key}.old" "$old_public_key"
        
        return 1
    fi
    
    # New keys have been generated, now re-encrypt files
    log_info "Re-encrypting files with new keys..."
    
    # Check if file list exists
    if [[ ! -f "$file_list_path" ]]; then
        log_error "File list not found: $file_list_path"
        return 1
    fi
    
    # Read file list and re-encrypt each file
    local success=true
    while IFS= read -r file; do
        # Skip empty lines
        [[ -z "$file" ]] && continue
        
        # Skip files that don't exist
        [[ ! -f "$file" ]] && {
            log_warning "File not found, skipping: $file"
            continue
        }
        
        log_debug "Re-encrypting file: $file"
        
        # Decrypt with old key
        local temp_file="${TEMP_DIR:-/tmp}/temp_decrypted.$(date +%N)"
        
        # Use the old key for decryption
        export PRIVATE_KEY="${old_private_key}.old"
        if ! decrypt_file "$file" "$temp_file"; then
            log_error "Failed to decrypt file with old key: $file"
            success=false
            continue
        fi
        
        # Encrypt with new key
        export PRIVATE_KEY=""  # Clear the override
        if ! encrypt_file "$temp_file" "$file" "rotation"; then
            log_error "Failed to re-encrypt file with new key: $file"
            success=false
        fi
        
        # Clean up temp file
        rm -f "$temp_file"
    done < "$file_list_path"
    
    # Clean up old keys if re-encryption was successful
    if [[ "$success" == "true" ]]; then
        log_info "Key rotation completed successfully"
        # Leave old keys in backup directory, but remove the temporary files
        rm -f "${old_private_key}.old" "${old_public_key}.old"
    else
        log_warning "Key rotation had some failures"
    fi
    
    return 0
}

# Export functions
export -f is_encryption_enabled
export -f get_public_key_path
export -f validate_public_key
export -f encrypt_file
export -f decrypt_file
export -f store_encryption_info
export -f get_encryption_info
export -f get_key_fingerprint
export -f generate_random_key
export -f is_file_encrypted
export -f generate_encryption_keys
export -f rotate_encryption_keys