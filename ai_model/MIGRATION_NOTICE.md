# Port Migration Notice

**Date:** $(date +%Y-%m-%d)
**Action:** Migrated from custom port 31434 to default port 11434

## What Changed

- **Ollama Server:** Now runs on default port `11434` (was `31434`)
- **All Configuration Files:** Updated to use default port
- **Continue.dev:** Uses auto-discovery (no custom `apiBase` needed)
- **OpenCode:** Uses default Ollama connection
- **Documentation:** All examples updated

## Why This Change

Using the default port (11434) provides:
- ✅ Auto-discovery by all Ollama-aware tools
- ✅ Simpler configuration (no custom ports)
- ✅ Better compatibility with third-party tools
- ✅ Standard across all environments

## Archived Files

The following temporary troubleshooting scripts were archived:
- `rebuild-configs.sh` - No longer needed
- `fix-continue-port.sh` - No longer needed
- `fix-continue-jetbrains.sh` - No longer needed
- `test-continue-connection.sh` - Diagnostic script
- `diagnose-config.sh` - Redundant with diagnose.sh
- `CONFIGURATION_SUMMARY.md` - Outdated

These files are available in the `archive/` directory if needed.

## Current Configuration

All scripts now use port `11434` by default. No environment variables needed.

**Test your setup:**
```bash
curl http://localhost:11434/api/tags
ollama list
```

## Rollback (if needed)

All modified files have backups with `.backup.pre-cleanup` extension.

To rollback:
```bash
cd ai_model
find . -name "*.backup.pre-cleanup" | while read f; do
    mv "$f" "${f%.backup.pre-cleanup}"
done
```
