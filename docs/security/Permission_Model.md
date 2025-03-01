# SSHistorian: Permission Model

This document outlines the permission model implemented in SSHistorian, covering file system permissions, database security, and access control mechanisms.

## File System Permissions

SSHistorian follows the principle of least privilege, granting only the minimum necessary permissions for each component.

### Database Files

- **Main Database** (`data/sshistorian.db`):
  - Permissions: `0600` (user read/write only)
  - Set during initialization in `init_database()`
  - Backup files also use `0600` permissions

- **Plugin Database** (`data/plugins.db`):
  - Permissions: `0600` (user read/write only)
  - Set during initialization in `ensure_plugin_database()`

### Log Files

- **Session Logs** (`data/logs/<uuid>.log` and `data/logs/<uuid>.timing`):
  - Default Permissions: `0600` (user read/write only)
  - Configurable via the `general.log_permissions` setting
  - Set during recording in `start_session_recording()`

- **Encrypted Files** (`.enc` and `.aes.enc` files):
  - Permissions: `0600` (user read/write only)
  - Set during encryption/decryption operations

### Directories

- **Data Directory** (`data/`):
  - Created with default permissions: `0700` (user read/write/execute only)
  - Configurable via the `general.dir_permissions` setting

- **Log Directory** (`data/logs/`):
  - Created with default permissions: `0700` (user read/write/execute only) 
  - Configurable via the `general.dir_permissions` setting

### Encryption Keys

- **Private Keys**:
  - Permissions: `0600` (user read/write only)
  - Default location: `~/.config/sshistorian/keys/private.pem`
  - Set during key generation in `generate_encryption_keys()`

- **Public Keys**:
  - Permissions: `0644` (user read/write, group/others read)
  - Default location: `~/.config/sshistorian/keys/public.pem`
  - Set during key generation in `generate_encryption_keys()`

## Path Security

### Path Validation

SSHistorian employs strict path validation to prevent unauthorized file access:

1. **Path Canonicalization**:
   - All paths are normalized using `normalize_path()` 
   - Resolves symlinks and eliminates relative path components
   - Uses `readlink -f` or `realpath` when available

2. **Path Containment**:
   - `is_safe_path()` ensures operations only affect files within allowed directories
   - Prevents path traversal attacks and unauthorized file access
   - Used for all file operations, especially deletions

3. **Path Pattern Validation**:
   - Session log files must match expected UUID patterns
   - Example: `^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.log$`

Example usage in `delete_session_file`:

```bash
# Validate file has expected name format
if [[ "$path" =~ $expected_pattern ]]; then
    # Get full path and check if it's safely contained within LOG_DIR
    local full_path="${LOG_DIR}/${path}"
    local canonical_path
    canonical_path=$(normalize_path "$full_path")
    
    # Ensure file exists and is within LOG_DIR
    if [[ -f "$canonical_path" ]] && is_safe_path "$canonical_path" "$canonical_log_dir"; then
        rm -f "$canonical_path"
        log_debug "Deleted ${file_type} file: $canonical_path"
    else
        log_warning "${file_type} file not found or invalid path: $full_path"
    fi
```

## Database Security

### Parameter Binding

All SQL queries use prepared statements with parameter binding:

1. **Main Database** (`db_execute_params`):
   - Uses SQLite parameter binding
   - Named parameters (`:param_name`)
   - Special handling for NULL values

2. **Plugin Database** (`query_plugin_db_params`):
   - Similar parameter binding approach
   - Temporary script files for complex queries

Example of proper parameter binding:

```bash
db_execute_params "UPDATE sessions SET exit_code = :exit_code, duration = :duration WHERE id = :uuid;" \
    ":exit_code" "$exit_code" \
    ":duration" "$duration" \
    ":uuid" "$uuid"
```

### Transaction Support

Atomic operations are ensured through transaction support:

```bash
db_transaction "
    -- Delete tags
    DELETE FROM tags WHERE session_id = '$uuid';
    
    -- Delete encryption info
    DELETE FROM encryption_info WHERE session_id = '$uuid';
    
    -- Delete session
    DELETE FROM sessions WHERE id = '$uuid';
"
```

## Access Control Model

SSHistorian implements a single-user access model rather than role-based access control:

### Filesystem-Based Access

- Access is controlled through Unix file permissions
- Only the user running the application can access data files
- No built-in multi-user access model within the application

### Encryption-Based Access Control

For scenarios requiring shared access or additional security:

1. **Asymmetric Encryption**:
   - Session logs are encrypted using hybrid encryption (AES + RSA)
   - Only users with access to the private key can decrypt session data

2. **Multi-Recipient Support**:
   - Optional feature configurable via `encryption.multi_recipient`
   - Allows multiple public keys to be used for encryption
   - Each authorized user can decrypt with their own private key

## Temporary File Security

SSHistorian securely manages temporary files:

1. **Creation**:
   - Uses `mktemp` for secure temporary file creation
   - Random names prevent predictability

2. **Cleanup**:
   - Registers operations with `register_operation`
   - Trap handler ensures cleanup on exit, even after errors
   - `unregister_operation` for controlled cleanup

3. **Permissions**:
   - Temporary files inherit default umask
   - Sensitive temp files have explicit `0600` permissions

## Configuration Security

Configuration values are stored in the database rather than plain text files:

1. **Secure Storage**:
   - All configuration in SQLite database
   - Database has secure permissions (`0600`)
   - No plain-text config files except for encryption keys

2. **Key Paths**:
   - Only paths to encryption keys are stored, not the keys themselves
   - Keys have appropriate permissions (`0600` for private, `0644` for public)

## Conclusion

SSHistorian's permission model follows security best practices by implementing least privilege, strict path validation, secure database access, and proper file permissions. The system is designed to be run by a single user with personal access to sensitive data, with encryption providing an additional layer of security and access control when needed.