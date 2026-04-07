# Preset Configurations

## Available Presets

- **developer.env** - Codestral for code generation
- **researcher.env** - Llama 70B for best quality
- **production.env** - Balanced 11B model

## Usage

```bash
./setup.sh --preset developer
```

## Creating Custom Presets

Copy a template and modify:
```bash
cp presets/developer.env presets/custom.env
# Edit custom.env
./setup.sh --preset custom
```

## Variables

- MODEL_FAMILY: llama, mistral, phi, gemma
- MODEL: Specific model name
- SETUP_CLIENTS: continue, webui, opencode, all, none
- INSTALL_EMBEDDING_MODEL: true, false
- AUTO_START: true, false
