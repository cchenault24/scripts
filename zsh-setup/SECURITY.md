# Security Policy

## Security Considerations

This document outlines the security measures implemented in zsh-setup and best practices for secure usage.

## Input Validation

### Plugin Name Sanitization
All plugin names are sanitized before use to prevent command injection attacks:

```bash
# Sanitize function removes all non-safe characters
zsh_setup::utils::filesystem::sanitize_name "$plugin_name"

# Allowed characters: alphanumeric, dash (-), underscore (_), dot (.)
# Removed: semicolons, pipes, backticks, $(), slashes, etc.
```

**Examples:**
- `test-plugin_123` → `test-plugin_123` ✓
- `plugin;rm -rf /` → `pluginrm-rf` ✓ (injection attempt blocked)
- `../../../etc/passwd` → `......etcpasswd` ✓ (path traversal blocked)
- `` `whoami` `` → `whoami` ✓ (command substitution blocked)

### URL Validation
Git URLs are validated before cloning:
- Must be valid git repository URLs
- Network connectivity verified
- Authentication handled securely

## File Security

### Permissions

All files and directories are created with secure permissions:

| Resource | Permissions | Purpose |
|----------|-------------|---------|
| State directory | `700` (rwx------) | Owner-only access to prevent information disclosure |
| State files | `600` (rw-------) | Owner-only read/write to protect sensitive data |
| Worker scripts | `700` (rwx------) | Owner-only execute to prevent tampering |
| Backup files | `644` (rw-r--r--) | Standard backup permissions |

### State File Location

State files are stored in XDG-compliant locations:
- Primary: `$XDG_STATE_HOME/zsh-setup/`
- Fallback: `~/.local/state/zsh-setup/`

**Benefits:**
- Survives system reboots (not in /tmp)
- Proper user-specific permissions
- Follows modern Linux/macOS standards
- Easy to backup and restore

### Temporary Files

Temporary files follow security best practices:
- Created with `mktemp` using random suffixes
- Immediate permission restriction to `700`
- Cleanup traps ensure removal on exit/interrupt
- No predictable filenames

```bash
# Secure temporary file creation
local worker_script=$(mktemp -t zsh_setup_worker.XXXXXX.sh)
chmod 700 "$worker_script"
trap 'rm -f "$worker_script"' EXIT INT TERM
```

## Command Injection Prevention

### Shell Command Safety
- No direct `eval` of user-provided input
- All variables properly quoted in commands
- Plugin names sanitized before use in:
  - File paths
  - Log file names
  - Command arguments
  - Worker script parameters

### Git Operations
Git commands are executed with validated inputs:
```bash
# Safe git operations
git clone "$plugin_url" "$plugin_path"  # Both validated
git pull --quiet                         # No user input
```

## Privilege Handling

### Sudo Usage
- Explicit `--no-privileges` flag available
- Graceful degradation when sudo unavailable
- Clear messages about privilege requirements
- No automatic privilege escalation

### Package Manager Safety
- Detection before installation attempts
- User notification of required permissions
- Fallback behavior without sudo
- No forced installations

## Data Privacy

### What Gets Stored
- Plugin names and versions (public data)
- Installation timestamps (local only)
- Git commit hashes (public data)
- No personal information collected

### Log Files
- Created in `/tmp` with unique names
- Removed after successful operations
- Retained only on failure for debugging
- Sanitized paths prevent information disclosure

## Testing

Security features are validated with comprehensive tests:

```bash
# Run security test suite
./tests/test_security.sh
```

**Test Coverage:**
- Input sanitization (8 tests)
- File permissions (3 tests)
- Temporary file security (1 test)

All tests must pass before merging security-related changes.

## Reporting Security Issues

If you discover a security vulnerability, please:

1. **Do NOT** open a public GitHub issue
2. Email the maintainers privately (check repository for contact)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and work with you to address the issue.

## Security Checklist for Contributors

When contributing code that handles user input or file operations:

- [ ] Input is sanitized before use in commands
- [ ] File paths are constructed safely (no user input in critical paths)
- [ ] Temporary files have secure permissions
- [ ] Cleanup traps are in place for temp files
- [ ] No use of `eval` with user input
- [ ] All shell variables are properly quoted
- [ ] Error messages don't leak sensitive information
- [ ] Tests validate security properties

## Dependencies

### External Tools
- git: Used for plugin installation (system-provided)
- jq: Optional for JSON parsing (graceful fallback)
- npm: Optional for npm-based plugins

All external tools are invoked with validated inputs.

### No External Libraries
This project uses only bash built-ins and standard Unix tools to minimize supply chain risks.

## Security Updates

Security-related changes are documented in CHANGELOG.md with a `[SECURITY]` prefix. Update zsh-setup regularly to get the latest security fixes:

```bash
cd zsh-setup
git pull origin main
```

## Threat Model

### In Scope
- Command injection via plugin names
- Path traversal attacks
- Information disclosure through logs
- Privilege escalation attempts
- Temporary file race conditions

### Out of Scope
- Physical access to the machine
- Compromised user account
- Malicious plugins from trusted sources
- Supply chain attacks on git/npm

## Best Practices for Users

1. **Review plugins before installation**: Check the source code
2. **Use trusted sources**: Install plugins from reputable repositories
3. **Keep software updated**: Regular `git pull` for security fixes
4. **Check permissions**: Verify file permissions after installation
5. **Use `--dry-run`**: Test installations before applying changes

## Secure Configuration

Example secure configuration:

```bash
# ~/.zshrc
# Set restrictive umask
umask 077

# Source zsh-setup with proper error handling
if [[ -f /path/to/zsh-setup/lib/core/bootstrap.sh ]]; then
    source /path/to/zsh-setup/lib/core/bootstrap.sh
fi
```

## Audit Trail

Security-related changes are tracked in git with detailed commit messages. Use `git log --grep="security"` to see security improvements over time.

## Compliance

This project follows:
- OWASP Top 10 guidelines for shell scripts
- CIS Security Benchmarks for Unix systems
- Principle of least privilege
- Defense in depth

## Additional Resources

- [Shell Script Security](https://mywiki.wooledge.org/BashPitfalls)
- [OWASP Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
- [CWE-78: OS Command Injection](https://cwe.mitre.org/data/definitions/78.html)
