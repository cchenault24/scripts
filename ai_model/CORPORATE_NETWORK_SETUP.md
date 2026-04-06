# Corporate Network Setup Guide

This guide addresses common issues when running the llama.cpp setup script in corporate environments with SSL interception, proxies, or authentication requirements.

---

## Issue 1: SSL Certificate Errors

### Symptoms
```
SSLError: [SSL: CERTIFICATE_VERIFY_FAILED]
```

### Root Cause
Corporate networks often use SSL interception (man-in-the-middle proxies) for security. Python's default certificate bundle doesn't include corporate CA certificates.

### Solution

The setup script **automatically handles this** by injecting `pip-system-certs` into the HuggingFace CLI:

```bash
# This happens automatically during setup
pipx inject huggingface-hub pip-system-certs
```

**Manual Fix** (if needed):
```bash
pipx inject huggingface-hub pip-system-certs
```

This makes the HuggingFace CLI use your system's certificate store, which includes corporate CA certificates.

---

## Issue 2: HuggingFace Authentication Token

### Symptoms
```
HTTP 401: Unauthorized
HTTP 403: Forbidden
```

### Root Cause
Some HuggingFace models (including certain Gemma 4 variants) require authentication to download.

### Solution

#### Option 1: Set Environment Variable (Recommended)

**Temporary** (current session):
```bash
export HF_TOKEN=hf_your_token_here
python3 setup-llamacpp.py
```

**Permanent** (add to `~/.zshrc` or `~/.bashrc`):
```bash
echo 'export HF_TOKEN=hf_your_token_here' >> ~/.zshrc
source ~/.zshrc
```

#### Option 2: Interactive Prompt

The setup script will prompt you for a token if `HF_TOKEN` is not found:
```
⚠ HuggingFace token not found in environment (HF_TOKEN)

Some models require authentication to download.
You can:
  1. Set environment variable: export HF_TOKEN=hf_...
  2. Enter token now (will not be saved)
  3. Skip (may fail for gated models)
```

#### Getting Your Token

1. Go to https://huggingface.co/settings/tokens
2. Create a new token with **Read** access
3. Copy the token (starts with `hf_...`)

⚠️ **Security Note:** Never commit tokens to git or share them publicly. If exposed, regenerate immediately.

---

## Issue 3: Proxy Configuration

### Symptoms
```
ConnectionError: Failed to establish connection
Timeout errors
```

### Solution

Set proxy environment variables **before** running the setup:

```bash
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1

python3 setup-llamacpp.py
```

For authenticated proxies:
```bash
export HTTP_PROXY=http://username:password@proxy.company.com:8080
export HTTPS_PROXY=http://username:password@proxy.company.com:8080
```

---

## Issue 4: Homebrew Behind Proxy

### Symptoms
```
curl: (7) Failed to connect to raw.githubusercontent.com
```

### Solution

Configure Homebrew to use your proxy:

```bash
# Add to ~/.zshrc or ~/.bashrc
export ALL_PROXY=http://proxy.company.com:8080

# Or for authenticated proxies
export ALL_PROXY=http://username:password@proxy.company.com:8080
```

---

## Quick Setup for Corporate Networks

### Full Script

```bash
#!/bin/bash
# Save as: setup-corporate.sh

# SSL Certificate Support
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt  # Linux
# OR
export REQUESTS_CA_BUNDLE=/etc/ssl/cert.pem                    # macOS

# Proxy Configuration (adjust to your proxy)
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export ALL_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1

# HuggingFace Token (get from https://huggingface.co/settings/tokens)
export HF_TOKEN=hf_your_token_here

# Run setup
python3 setup-llamacpp.py
```

Make executable and run:
```bash
chmod +x setup-corporate.sh
./setup-corporate.sh
```

---

## Troubleshooting

### Test HuggingFace CLI Connection

```bash
# Check if token is set
echo $HF_TOKEN

# Test connection
hf whoami

# Test download (small file)
hf download facebook/bart-large README.md
```

### Test SSL Certificates

```bash
python3 -c "import ssl; import certifi; print(certifi.where())"
```

Should print path to certificate bundle.

### Verify pip-system-certs Installation

```bash
pipx list | grep huggingface-hub -A 5
```

Should show `pip-system-certs` in the injected packages list.

---

## What the Setup Script Does Automatically

✅ **Injects pip-system-certs** into HuggingFace CLI (fixes SSL)
✅ **Prompts for HF_TOKEN** if not found in environment
✅ **Respects proxy environment variables** (HTTP_PROXY, HTTPS_PROXY)
✅ **Validates all downloads** with checksums (optional)
✅ **Provides helpful error messages** for network issues

---

## Common Error Messages & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `SSL: CERTIFICATE_VERIFY_FAILED` | Corporate SSL interception | Automatic (pip-system-certs) |
| `HTTP 401: Unauthorized` | Missing HF token | Set HF_TOKEN environment variable |
| `HTTP 403: Forbidden` | Invalid/expired token | Regenerate token on HuggingFace |
| `Connection timeout` | Firewall/proxy blocking | Configure HTTP_PROXY/HTTPS_PROXY |
| `Connection refused` | Proxy misconfiguration | Verify proxy URL and port |

---

## Security Best Practices

1. **Never commit HF_TOKEN to git**
   ```bash
   # Add to .gitignore
   echo '.env' >> .gitignore
   echo 'HF_TOKEN' >> .gitignore
   ```

2. **Use environment files**
   ```bash
   # Create .env file
   cat > .env <<EOF
   HF_TOKEN=hf_your_token_here
   EOF

   # Load in script
   source .env
   python3 setup-llamacpp.py
   ```

3. **Rotate tokens regularly**
   - Regenerate tokens every 90 days
   - Revoke old tokens on HuggingFace

4. **Use Read-only tokens**
   - Only grant **Read** access, never **Write**

---

## Contact IT Support

If you continue to experience issues after following this guide:

1. **Collect diagnostics:**
   ```bash
   echo "Proxy: $HTTP_PROXY"
   echo "HF Token: ${HF_TOKEN:0:8}..."  # First 8 chars only
   curl -I https://huggingface.co
   hf whoami
   ```

2. **Share with IT:**
   - Proxy configuration needed
   - Firewall rules for `huggingface.co`, `githubusercontent.com`
   - SSL inspection exemption for HuggingFace (optional)

---

## Additional Resources

- HuggingFace Documentation: https://huggingface.co/docs/hub/security-tokens
- pip-system-certs: https://pypi.org/project/pip-system-certs/
- pipx Documentation: https://pipx.pypa.io/

---

**Last Updated:** April 6, 2026
**Applies To:** setup-llamacpp.py v2.0+
