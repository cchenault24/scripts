# Continue.dev Setup and Usage

## Configuration

The setup script automatically generates a Continue.dev config at `~/.continue/config.yaml` with role-based model configuration.

The configuration organizes models by their roles:

### 1. Agent Plan / Chat / Edit (Primary models)
- **Used for**: Complex coding tasks, refactoring, agent planning, chat, and code editing
- **Models**: Selected from Agent Plan/Chat/Edit models based on your hardware tier
- **Temperature**: 0.7 (role-specific tuning)
- **Best for**: General development, code generation, complex refactoring

### 2. Autocomplete (Fast, lightweight models)
- **Used for**: Real-time code suggestions as you type
- **Models**: Selected from Autocomplete models (typically smaller, faster models)
- **Optimized for**: Fast response times and low latency
- **Best for**: Tab autocomplete, inline suggestions

### 3. Embed (Code indexing)
- **Used for**: Semantic code search and codebase understanding
- **Model**: nomic-embed-text (automatically installed)
- **Best for**: Code indexing, semantic search with `@Codebase` in Continue.dev

### 4. Next Edit (Predicting next edits)
- **Used for**: Predicting the next code edit
- **Models**: Selected from Next Edit models based on your hardware tier
- **Best for**: Intelligent code completion and edit prediction

## Using Continue.dev

- **Chat**: `Cmd+L` - Ask questions, get explanations
- **Inline Edit**: `Cmd+K` - Select code and request changes
- **Tab Autocomplete**: Automatic suggestions as you type (uses Autocomplete role models)
- **Context**: Continue.dev automatically indexes your workspace (uses Embed role model)
- **Codebase Search**: Use `@Codebase` in chat for semantic search across your codebase

## Model Roles

Models are automatically assigned to roles based on their capabilities. A single model can serve multiple roles (e.g., `llama3.1:8b` can be used for both Agent Plan/Chat/Edit and Autocomplete), which saves RAM and improves efficiency.

## Custom Configuration

To adjust model parameters, edit `~/.continue/config.yaml`:

```yaml
models:
  - name: Llama 3.1 8B
    provider: ollama
    model: llama3.1:8b
    apiBase: http://localhost:11434
    contextLength: 16384  # Adjust based on needs
    temperature: 0.7       # Lower = more focused
    roles:
      - chat
      - edit
      - apply
```

## Workspace-Specific Configs

Continue.dev supports workspace-specific configs. Create `.continue/config.yaml` in your workspace root to override global config.

## Local Embeddings

For better codebase understanding, you can enable local embeddings in Continue.dev config:

```yaml
embeddingsProvider:
  provider: ollama
  model: nomic-embed-text
  apiBase: http://localhost:11434
```

Note: This uses more resources but provides better semantic search. The setup script automatically configures embeddings if you select an embedding model during installation.

## Proxy Configuration

If using the optimization proxy (see [Optimization](OPTIMIZATION.md)), update the `apiBase` in your config:

```yaml
apiBase: http://localhost:11435  # Changed from 11434
```

The setup script will automatically detect and use the proxy if it's running.
