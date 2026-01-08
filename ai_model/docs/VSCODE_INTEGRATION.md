# VS Code Integration

## Settings

The setup generates optimized VS Code settings at `vscode/settings.json`. To use:

1. Copy to your workspace:
   ```bash
   cp vscode/settings.json .vscode/settings.json
   ```

2. Or merge with existing settings manually

### Key Optimizations

- TypeScript strict mode enforcement
- React/Redux navigation support
- Import organization
- Safer refactoring defaults
- MUI theme token awareness
- AG Grid type hints

## Extensions

Recommended extensions are listed in `vscode/extensions.json`. The setup script can optionally install them:

- **ESLint** - Code quality
- **Prettier** - Code formatting
- **TypeScript** - Enhanced TS support
- **React snippets** - Productivity
- **Path IntelliSense** - Import assistance
- **GitLens** - Git integration

### Manual Installation

To install manually:
```bash
code --install-extension <extension-id>
```

## Continue.dev Extension

Install the [Continue.dev extension](https://marketplace.visualstudio.com/items?itemName=Continue.continue) for AI coding assistance:

- `Cmd+L` - Open chat
- `Cmd+K` - Inline edits
- Automatic codebase indexing
- Tab autocomplete

See [Continue.dev Setup](CONTINUE_SETUP.md) for configuration details.

## Troubleshooting

### TypeScript/React Issues

1. **Check VS Code settings** - ensure TypeScript settings are applied
2. **Verify extensions** - ESLint, Prettier, TypeScript
3. **Check workspace** - ensure `.vscode/settings.json` is in workspace root
4. **Restart VS Code**

### Continue.dev Not Connecting

1. **Verify config exists:**
   ```bash
   cat ~/.continue/config.yaml
   ```

2. **Check YAML validity:**
   ```bash
   grep -q "models:" ~/.continue/config.yaml && echo "Config structure OK" || echo "Config may be invalid"
   ```

3. **Verify Ollama endpoint:**
   - Config should have: `apiBase: http://localhost:11434` (or `http://localhost:11435` if using proxy)
   - Test: `curl http://localhost:11434/api/tags`

4. **Restart VS Code**
