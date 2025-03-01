# SSHistorian: Encryption Implementation

This document details the encryption system implemented in SSHistorian for securing SSH session logs and sensitive data.

## Encryption Overview

SSHistorian uses a hybrid encryption approach combining symmetric and asymmetric cryptography:

1. **AES-256-CBC** (symmetric) for encrypting the actual session log content
2. **RSA** (asymmetric) for encrypting the AES key

This hybrid approach provides:
- **Performance**: Fast encryption/decryption of large session logs using AES
- **Security**: Strong protection of the AES key using RSA public key cryptography
- **Flexibility**: Can support multiple recipients when needed

## Encryption Workflow

### Session Recording Encryption

When encryption is enabled and a session is recorded:

1. Session logs are written to disk:
   - `<uuid>.log`: The content of the SSH session
   - `<uuid>.timing`: Timing information for replay

2. The `encrypt_file` function is called for each file:
   - A random 256-bit AES key is generated with `openssl rand -base64 32`
   - The log file is encrypted with AES-256-CBC using this random key
   - The result is saved as `<uuid>.log.enc` or `<uuid>.timing.enc`

3. The AES key is then encrypted with the RSA public key:
   - The encrypted key is saved as `<uuid>.log.enc.aes.enc` or `<uuid>.timing.enc.aes.enc`
   - A fingerprint of the public key used is stored in the database

4. The original unencrypted files are securely deleted

### Session Replay Decryption

When a user attempts to replay an encrypted session:

1. The system detects that the log files are encrypted (`.enc` suffix)

2. The `decrypt_file` function is called for each encrypted file:
   - The user's private key (or a specified key) is used to decrypt the AES key
   - The decrypted AES key is then used to decrypt the actual log file
   - Decrypted content is written to a temporary file with secure permissions

3. The temporary decrypted files are used for replay and then securely deleted

## Key Management

### Key Generation

Keys can be generated using the `generate_encryption_keys` function:

```bash
$ sshistorian generate-keys
Generating encryption keys for SSHistorian...
Private key: /home/user/.config/sshistorian/keys/sshistorian_rsa
Public key: /home/user/.config/sshistorian/keys/sshistorian_rsa.pub
Fingerprint: 5f:e2:a0:87:eb:3a:7b:95:7d:14:77:c1:64:d5:b0:21
```

This creates:
- A 2048-bit RSA private key (permissions: `0600`)
- The corresponding RSA public key (permissions: `0644`)
- Updates the configuration to use these keys

### Key Storage

Keys are stored in the filesystem:
- Default location: `~/.config/sshistorian/keys/`
- Private key: `sshistorian_rsa` (only readable by the owner)
- Public key: `sshistorian_rsa.pub` (readable by all)

Paths to these keys are stored in the configuration database:
- `encryption.public_key`: Path to the public key
- `encryption.private_key`: Path to the private key

### Key Rotation

SSHistorian supports key rotation with the `rotate_encryption_keys` function:

1. Current keys are backed up with a timestamp
2. New keys are generated
3. All encrypted files are:
   - Decrypted with the old private key
   - Re-encrypted with the new public key
4. Configuration is updated to point to the new keys

## Encryption Database Integration

Encryption information is tracked in the `encryption_info` table:

| Column | Description |
|--------|-------------|
| session_id | The UUID of the encrypted session |
| public_key_fingerprint | Fingerprint of the public key used |
| encrypted_at | Timestamp when encryption occurred |

This allows verifying which key was used to encrypt each session, important for key rotation and auditing.

## Encryption Configuration

Encryption is configurable through the database-stored configuration:

| Setting | Default | Description |
|---------|---------|-------------|
| encryption.enabled | false | Toggle encryption on/off |
| encryption.method | asymmetric | Encryption method (asymmetric only for now) |
| encryption.public_key | ${KEYS_DIR}/public.pem | Path to public key file |
| encryption.private_key | ${KEYS_DIR}/private.pem | Path to private key file |
| encryption.multi_recipient | false | Enable multi-recipient encryption |
| encryption.additional_keys | | Comma-separated list of additional recipients |

## Security Measures

### Path Validation

Before encryption/decryption operations:
- Files are validated to have the expected extensions (`.log`, `.timing`, `.enc`)
- Paths are canonicalized using `normalize_path`
- `is_safe_path` ensures files are within the allowed directory

### Permissions

- All encrypted files get `0600` permissions (read/write only for the owner)
- Decrypted temporary files also get `0600` permissions
- Private keys have `0600` permissions; public keys have `0644`

### Securely Handling Decrypted Data

When working with decrypted data:
- Temporary files are created with `mktemp`
- Clean-up occurs automatically through trap handlers
- Decrypted content is kept in memory only when needed

## Implementation Details

### Encryption Functions

The core encryption functionality resides in `src/core/encryption.sh`:

- `encrypt_file`: Encrypts a file using hybrid encryption
- `decrypt_file`: Decrypts a previously encrypted file
- `generate_encryption_keys`: Creates new RSA key pair
- `rotate_encryption_keys`: Handles key rotation
- `is_encryption_enabled`: Checks if encryption is enabled
- `get_key_fingerprint`: Gets the fingerprint of a public key
- `store_encryption_info`: Records encryption metadata in the database

### Encryption Algorithms

- **Session Content**: AES-256-CBC with a random key and salt
- **AES Key Protection**: RSA encryption (2048-bit keys by default)
- **Key Fingerprinting**: MD5 hash of the public key (for identification only)

### OpenSSL Commands

The implementation relies on OpenSSL for cryptographic operations:

```bash
# For AES encryption
echo "$aes_key" | openssl enc -aes-256-cbc -salt -in "$input_file" -out "$output_file" -pass stdin

# For RSA encryption of the AES key
echo "$aes_key" | openssl rsautl -encrypt -pubin -inkey "$pub_key" -out "$encrypted_key"

# For RSA decryption of the AES key
aes_key=$(openssl rsautl -decrypt -inkey "$private_key" -in "$encrypted_key")

# For AES decryption
echo "$aes_key" | openssl enc -d -aes-256-cbc -in "$encrypted_file" -out "$output_file" -pass stdin
```

## Test Mode Support

For testing purposes, the encryption system includes special handling:
- Test-specific keys can be generated in a test directory
- Simplified encryption for test environments
- Mock encryption when OpenSSL isn't available in the test environment

## Conclusion

SSHistorian's encryption implementation provides a robust security layer for sensitive session logs. By combining the performance of symmetric encryption with the security of asymmetric cryptography, it achieves both efficiency and strong protection. The key management system, database integration, and security measures ensure that encrypted data remains secure while still being accessible to authorized users.