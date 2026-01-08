# Security and Privacy

## Local-First

- **No cloud APIs**: All inference is local
- **No telemetry**: Continue.dev telemetry disabled
- **No external calls**: Only initial installs and model downloads require internet
- **Offline capable**: Works fully offline after setup

## Enterprise-Safe

- **No data leaves your machine**: Code never sent to external services
- **Auditable**: All code is open-source and inspectable
- **Restricted environments**: Works in air-gapped networks (after initial setup)
- **Clearance-friendly**: No external dependencies during operation

## Data Storage

- **Models**: Stored in `~/.ollama/models/`
- **Config**: `~/.continue/config.yaml`
- **State**: `~/.local-llm-setup/`
- **Logs**: `~/.local-llm-setup/*.log`

All data stays on your local machine.
