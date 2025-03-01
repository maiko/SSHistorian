# SSHistorian: Encryption Guide

This guide provides detailed information about SSHistorian's encryption capabilities, how to set up encryption, and best practices for managing encrypted session data.

## Understanding SSHistorian's Encryption

SSHistorian uses a hybrid encryption approach that combines the speed of symmetric encryption with the security of asymmetric encryption:

1. **Symmetric Encryption (AES-256-CBC)**: Used to encrypt the actual session log content
2. **Asymmetric Encryption (RSA)**: Used to encrypt the AES key

This approach provides:
- **Performance**: Fast encryption/decryption of large session logs
- **Security**: Strong protection of the encryption key
- **Convenience**: Automatic encryption without password prompts

## How Encryption Works in SSHistorian

When encryption is enabled:

1. **During Recording**:
   - SSHistorian records the session normally
   - A random AES-256 key is generated
   - The log files are encrypted with AES
   - The AES key is encrypted with your public key
   - Original unencrypted files are securely deleted

2. **During Playback**:
   - SSHistorian detects encrypted log files
   - Your private key is used to decrypt the AES key
   - The AES key decrypts the session logs
   - Decrypted content is used for playback
   - Temporary decrypted files are securely deleted

3. **Encrypted Files**:
   For each session, encryption creates:
   - `<uuid>.log.enc` - The encrypted log file
   - `<uuid>.log.enc.aes.enc` - The encrypted AES key
   - `<uuid>.timing.enc` - The encrypted timing file
   - `<uuid>.timing.enc.aes.enc` - The encrypted AES key for timing

## Setting Up Encryption

### Method 1: Automatic Key Generation (Recommended)

The simplest way to enable encryption is to use the built-in key generation:

```bash
sshistorian generate-keys
```

This command:
1. Creates a 2048-bit RSA key pair in `~/.config/sshistorian/keys/`
2. Sets permissions correctly (private key: 0600, public key: 0644)
3. Updates the configuration to enable encryption
4. Displays the key fingerprint for verification

### Method 2: Manual Configuration

If you want to use existing keys or customize the setup:

1. **Set key paths**:
   ```bash
   sshistorian config set encryption.public_key /path/to/your/public/key.pub
   sshistorian config set encryption.private_key /path/to/your/private/key
   ```

2. **Enable encryption**:
   ```bash
   sshistorian config set encryption.enabled true
   sshistorian config set encryption.method asymmetric
   ```

### Verifying Encryption Setup

To verify your encryption setup:
```bash
sshistorian config get encryption.enabled
sshistorian config get encryption.public_key
sshistorian config get encryption.private_key
```

## Advanced Encryption Features

### Key Rotation

It's a good security practice to periodically rotate encryption keys. SSHistorian supports key rotation:

1. Generate new keys:
   ```bash
   sshistorian generate-keys --rotate
   ```

2. This will:
   - Back up your old keys
   - Generate new keys
   - Re-encrypt all existing sessions with the new keys
   - Update the configuration

### Multi-Recipient Encryption

You can configure SSHistorian to encrypt sessions for multiple recipients, allowing multiple users to decrypt sessions:

1. Enable multi-recipient mode:
   ```bash
   sshistorian config set encryption.multi_recipient true
   ```

2. Add additional public keys:
   ```bash
   sshistorian config set encryption.additional_keys "/path/to/user1.pub,/path/to/user2.pub"
   ```

With this configuration, each session will be encrypted multiple times, once for each public key, allowing any of the corresponding private keys to decrypt the session.

## Best Practices for Encrypted Sessions

### Key Management

1. **Private Key Security**: 
   - Store private keys securely
   - Consider using a hardware security module for key storage
   - Set restrictive permissions (0600) on private keys
   - Never share private keys

2. **Backup Keys**: 
   - Back up encryption keys securely
   - Store backups in a secure, separate location
   - Document key fingerprints for verification

3. **Key Rotation**:
   - Rotate keys periodically (e.g., annually)
   - Rotate keys immediately if compromise is suspected
   - Ensure successful re-encryption of all important sessions

### Operational Considerations

1. **Performance**:
   - Encryption adds processing overhead
   - For very large sessions, this might be noticeable
   - Consider enabling encryption only for sensitive sessions if performance is a concern

2. **Disk Space**:
   - Encrypted files are slightly larger than unencrypted ones
   - Each session requires additional files for the encrypted AES keys
   - Plan disk space accordingly

3. **Access Control**:
   - Encryption doesn't replace proper file permissions
   - Keep using the principle of least privilege
   - Regularly review who has access to encryption keys

## Troubleshooting Encryption

### Common Issues

#### Can't Decrypt Session

If you're having trouble decrypting a session:

1. **Check Key Location**:
   ```bash
   sshistorian config get encryption.private_key
   ```
   Ensure the private key exists at the specified location.

2. **Check Key Permissions**:
   ```bash
   ls -la $(sshistorian config get encryption.private_key)
   ```
   The private key should have 0600 permissions.

3. **Verify Key Compatibility**:
   Make sure you're using the correct private key that corresponds to the public key used for encryption.

4. **Check Fingerprint**:
   ```bash
   sshistorian encryption info <uuid>
   ```
   This shows which public key was used to encrypt the session.

#### Encryption Not Working

If newly recorded sessions aren't being encrypted:

1. **Check Encryption Status**:
   ```bash
   sshistorian config get encryption.enabled
   ```
   Should return "true".

2. **Verify Public Key**:
   ```bash
   sshistorian config get encryption.public_key
   openssl pkey -pubin -in $(sshistorian config get encryption.public_key) -text
   ```
   This verifies the public key is valid.

3. **Check for Error Messages**:
   Run with debug to see detailed errors:
   ```bash
   DEBUG=true sshistorian user@host
   ```

## Advanced Topics

### Manual Decryption

In rare cases, you might need to manually decrypt a session:

```bash
sshistorian decrypt <uuid> --output /path/to/output
```

This decrypts the session files to the specified location without playing them back.

### Encryption Algorithms and Security

SSHistorian uses:
- AES-256-CBC for symmetric encryption
- 2048-bit RSA keys for asymmetric encryption

These algorithms are industry-standard and provide strong security when used correctly.

### Security Considerations

While encryption provides strong protection for your data:

1. It doesn't protect against malware on your system
2. If your private key is compromised, all sessions can be decrypted
3. It doesn't protect active sessions, only stored recordings

Use additional security measures like system hardening, regular updates, and endpoint protection for comprehensive security.

## Conclusion

Encryption provides an essential layer of security for sensitive SSH session recordings. By properly configuring and managing SSHistorian's encryption capabilities, you can ensure your session data is protected even if the underlying storage is compromised.

Remember to follow key management best practices and regularly test your ability to decrypt sessions to ensure continued access to your important data.