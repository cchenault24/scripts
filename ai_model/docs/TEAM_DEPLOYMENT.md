# Team Deployment Guide

Enterprise deployment guide for rolling out the AI Model Development Environment across teams.

## 1. Prerequisites

### Hardware Requirements
- **Apple Silicon Mac** (M1 or later)
- **Minimum 16GB RAM** (32GB+ recommended for larger models)
- **50GB+ free disk space** (varies by model selection)

### Software Requirements
- **macOS 13.0 or later**
- **Xcode Command Line Tools**
- **Admin access** (required for Homebrew installation)

### Network Requirements
- **Internet connection** for initial model downloads
- **No special firewall rules needed** (all services run locally)

## 2. Unattended Installation

### Basic Installation
```bash
./setup.sh --unattended
```

### Installation with Preset
```bash
./setup.sh --preset developer --unattended
```

### Installation with Specific Model
```bash
OLLAMA_MODEL=llama3.3:70b-instruct-q4_K_M ./setup.sh --unattended
```

### Logging
- **All output saved** to `installation.log` in the current directory
- **Errors highlighted** with clear messaging
- **Post-install report** generated with system status

## 3. Preset Configurations

### Available Presets

**`developer`** - Optimized for software development
- Codestral + Llama 3.2 11B
- Best for code completion and debugging

**`researcher`** - Optimized for analysis and research
- Llama 3.3 70B + Gemma 31B
- Best for complex reasoning tasks

**`production`** - Balanced configuration for team use
- Balanced performance and resource usage
- Suitable for general-purpose deployment

### Creating Custom Presets

1. Copy template from `presets/` directory
2. Modify configuration:
   - `MODEL_FAMILY` - Base model family
   - `MODEL` - Specific model variant
   - `SETUP_CLIENTS` - Which clients to install
3. Use with `--preset custom`

Example custom preset:
```bash
# presets/custom.sh
MODEL_FAMILY="llama"
MODEL="llama3.3:70b-instruct-q4_K_M"
SETUP_CLIENTS="continue openwebui"
```

## 4. Multi-User Setup

### Shared Machines
- **Each user runs own Ollama instance** on different ports
- **Separate configs per user** in home directories
- **Model files can be shared** using symlinks to save disk space

### Configuration Management
- **Use version control** for `presets/` directory
- **Document team standards** for model selection
- **Create model recommendation matrix** by role:
  - Developers: Codestral, Llama 3.2
  - Researchers: Llama 3.3 70B, Gemma 31B
  - General users: Llama 3.2 11B

## 5. CI/CD Integration

### Health Checks
```bash
./llama-control.sh health
exit $?  # Use exit code in CI pipeline
```

Exit codes:
- `0` - All services healthy
- `1` - One or more services down

### Automated Testing
```bash
./tests/integration-test.sh
```

Validates:
- Ollama service responsiveness
- Model availability
- Client configurations

### Metrics Collection
```bash
./llama-control.sh metrics --json > metrics.json
```

Captures:
- Model performance statistics
- Resource utilization
- Response times

## 6. Update Procedures

### Updating Ollama
```bash
# Remove cached build
rm -rf /tmp/ollama-build

# Rebuild from latest source
./setup.sh
```

This rebuilds Ollama from the latest upstream source.

### Updating Models
```bash
# Re-download latest version of a model
ollama pull <model-name>
```

Example:
```bash
ollama pull llama3.3:70b-instruct-q4_K_M
```

### Updating Clients

**Continue.dev:**
- Update via IDE plugin manager (VS Code/JetBrains)

**Open WebUI:**
```bash
docker pull ghcr.io/open-webui/open-webui:main
docker restart open-webui
```

**OpenCode:**
```bash
npm update -g opencode
```

## 7. Backup and Recovery

### What to Backup

**Essential:**
- Config files:
  - `~/.continue/config.json`
  - `~/.config/opencode/config.json`
- Custom presets:
  - `ai_model/presets/`

**Optional:**
- Model files (can be re-downloaded, but large)
  - `~/.ollama/models/`

### Recovery Procedure

```bash
# 1. Reinstall system
./setup.sh

# 2. Restore configs
cp backup/continue-config.json ~/.continue/config.json
cp backup/opencode-config.json ~/.config/opencode/config.json

# 3. Verify
./llama-control.sh health
```

### Backup Script Example
```bash
#!/bin/bash
BACKUP_DIR="backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup configs
cp ~/.continue/config.json "$BACKUP_DIR/continue-config.json"
cp ~/.config/opencode/config.json "$BACKUP_DIR/opencode-config.json"

# Backup custom presets
cp -r ai_model/presets/ "$BACKUP_DIR/presets/"

echo "Backup completed: $BACKUP_DIR"
```

## 8. Security Considerations

### Model Source Verification
- **Only use approved models:**
  - Llama (Meta)
  - Mistral (Mistral AI)
  - Phi (Microsoft)
  - Gemma (Google)
- **Blocked sources enforced** by setup script
- **Verify model checksums** when downloading manually

### Network Security
- **Ollama binds to localhost only** by default
- **No external access** without explicit configuration
- **Add firewall rules** if network access is required:
  ```bash
  # Example: Allow only local network
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/ollama
  ```

### Data Privacy
- **All data stays local** - no cloud communication
- **No telemetry sent** to external servers
- **Model conversations not logged** by default
- **Sensitive data never leaves** the local machine

### Best Practices
1. **Restrict admin access** to setup scripts
2. **Audit model usage** periodically
3. **Use approved model list** for team deployments
4. **Document data handling policies** for users
5. **Regular security updates** via update procedures

## 9. Troubleshooting

### Common Issues

**Installation fails with "command not found":**
- Ensure Xcode Command Line Tools are installed
- Run: `xcode-select --install`

**Model download slow or fails:**
- Check internet connection
- Verify disk space availability
- Try smaller model variant first

**Ollama service won't start:**
- Check port availability: `lsof -i :11434`
- Review logs: `./llama-control.sh logs`
- Restart: `./llama-control.sh restart`

### Getting Help
- Check logs in `installation.log`
- Use `./llama-control.sh health` for diagnostics
- Review documentation in `docs/` directory

## 10. Support and Maintenance

### Regular Maintenance Schedule
- **Weekly:** Check service health
- **Monthly:** Update models and clients
- **Quarterly:** Review and update presets

### Monitoring
```bash
# Check system status
./llama-control.sh status

# View resource usage
./llama-control.sh metrics

# Test model response
./llama-control.sh test
```

### Documentation
- Keep this guide updated with team-specific procedures
- Document custom presets and their use cases
- Maintain a changelog of configuration changes
