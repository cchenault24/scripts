# Security Fixes: SEC-7, SEC-9, SEC-10

## Summary

Implemented three critical security fixes:

1. **SEC-7**: Path validation and canonicalization to prevent path traversal attacks
2. **SEC-9**: Restrictive backup directory permissions (700)
3. **SEC-10**: Input validation for plugin registration

## SEC-7: Path Validation (lib/validation.sh)

**Vulnerability**: Path traversal allows backup/cleanup of arbitrary files (e.g., ../../../../etc/passwd)

**Fix**:
- Enhanced `validate_and_canonicalize_path()` with whitelist/blacklist approach
- Uses Python's `os.path.normpath()` for reliable path canonicalization
- Whitelist only allows safe directories:
  - `$HOME/Library/Caches/*`
  - `$HOME/Library/Logs/*`
  - `$HOME/.cache/*`
  - `/Library/Caches/*` (system cache, requires admin)
  - `/tmp/*` and `/private/tmp/*` (macOS symlink)
  - `$HOME/Downloads/*`
  - `$HOME/.Trash/*`
  - `$HOME/.mac-cleanup-backups/*`
  - `/tmp/mac-cleanup-backups/*`
- Blacklist blocks critical system directories:
  - `/System/*`, `/usr/*`, `/bin/*`, `/sbin/*`, `/etc/*`
  - `/var/db/*`, `/private/var/db/*`, `/private/etc/*`
  - `/Library/LaunchDaemons/*`, `/Library/LaunchAgents/*`

**Testing**: Manual verification shows correct blocking of path traversal attacks

## SEC-9: Backup Directory Permissions (lib/core.sh, lib/backup/storage.sh)

**Vulnerability**: Backup directories readable by all users, exposing sensitive cached data

**Fix**:
- Updated `_create_backup_dir()` to use `umask 077` before directory creation
- Enforces `chmod 700` permissions (drwx------)
- Verifies directory ownership matches current user
- Fixes insecure permissions on existing directories
- Applied to both `_create_backup_dir()` and `mc_storage_ensure_dir()`

**Testing**: All 8 tests pass (test_security_permissions.sh)
```
✓ Directory created with correct permissions: 700
✓ Directory owned by correct user
✓ Insecure permissions fixed: 755 -> 700
✓ umask correctly restored
✓ Fallback directory gets 700 permissions
```

## SEC-10: Plugin Input Validation (lib/core.sh, plugins/base.sh)

**Vulnerability**: Malicious plugin names/functions could inject code during registration

**Fix**:
- Validate plugin names: alphanumeric, spaces, hyphens, underscores only
- Validate function names: must match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- Verify functions exist using `whence -w` (zsh) or `type -t` (bash)
- Reject external commands (e.g., `ls`), only allow actual functions
- Validate category against allowed list
- Validate size function names and types
- Sanitize version strings

**Testing**: All 15 tests pass (test_security_input_validation.sh)
```
✓ Valid plugin registered successfully
✓ Correctly rejected plugin name with semicolon
✓ Correctly rejected plugin name with dollar sign
✓ Correctly rejected plugin name with backticks
✓ Correctly rejected invalid function name
✓ Correctly rejected function name with special characters
✓ Correctly rejected non-existent function
✓ Correctly rejected invalid category
✓ All valid categories accepted
✓ Correctly rejected empty function name
✓ Correctly rejected invalid size function name
✓ Valid size function accepted
✓ Invalid version rejected/sanitized
✓ Correctly rejected function name starting with number
✓ Correctly rejected external command as function
```

## Files Modified

- `lib/validation.sh`: Enhanced path validation with whitelist/blacklist
- `lib/core.sh`: Secure backup directory creation, plugin input validation
- `lib/backup/storage.sh`: Secure directory creation for backup storage
- `plugins/base.sh`: Updated register_plugin wrapper

## Test Scripts Created

- `test_security_permissions.sh`: SEC-9 tests (100% pass rate)
- `test_security_input_validation.sh`: SEC-10 tests (100% pass rate)
- `test_sec7_simple.sh`: SEC-7 manual verification tests

## Security Impact

- **HIGH**: Prevents path traversal attacks that could delete/backup system files
- **MEDIUM**: Prevents information disclosure through world-readable backups
- **MEDIUM**: Prevents code injection through malicious plugin registration
