# Client Setup Guide

Complete guide for using local LLM models through three different client interfaces: Continue.dev (IDE), Open WebUI (Browser), and OpenCode CLI (Terminal).

## Overview

Your local Ollama server provides AI models through three distinct clients, each optimized for different workflows:

| Client | Best For | Interface | Installation |
|--------|----------|-----------|--------------|
| **Continue.dev** | Daily coding, autocomplete, inline edits | JetBrains/VS Code | Plugin |
| **Open WebUI** | Testing models, demos, non-developers | Browser (localhost:38080) | Docker |
| **OpenCode CLI** | Automation, scripts, CI/CD pipelines | Terminal | npm/bun |

**Key Point:** All three clients connect to the same local Ollama server (localhost:11434), so you can use different models in different clients or switch between them seamlessly.

---

## 1. Continue.dev (JetBrains/VS Code)

Continue.dev is the primary interface for software development, providing AI-powered autocomplete and chat directly in your IDE.

### Installation

#### JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.)
1. Open your JetBrains IDE
2. Go to **Settings/Preferences** → **Plugins**
3. Search for "**Continue**"
4. Click **Install** and restart the IDE

#### VS Code
1. Open VS Code
2. Go to **Extensions** (⌘+Shift+X on Mac)
3. Search for "**Continue**"
4. Click **Install**

### Configuration

Continue.dev stores its configuration at `~/.continue/config.json`. The setup script auto-generates this file, but you can customize it manually.

#### Location
```
~/.continue/config.json
```

#### Basic Configuration
```json
{
  "models": [
    {
      "title": "Llama 3.3 70B",
      "provider": "ollama",
      "model": "llama3.3:70b-instruct-q4_K_M",
      "apiBase": "http://localhost:11434"
    },
    {
      "title": "Codestral 22B",
      "provider": "ollama",
      "model": "codestral:22b-v0.1-q8_0",
      "apiBase": "http://localhost:11434"
    },
    {
      "title": "Gemma4 31B",
      "provider": "ollama",
      "model": "gemma4:31b-it-q8_0",
      "apiBase": "http://localhost:11434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Fast Autocomplete",
    "provider": "ollama",
    "model": "llama3.2:3b-instruct-q8_0",
    "apiBase": "http://localhost:11434"
  }
}
```

#### Adding New Models
To add a new model:
1. Pull the model: `ollama pull <model-name>`
2. Edit `~/.continue/config.json`
3. Add a new entry to the `models` array:
```json
{
  "title": "My Custom Model",
  "provider": "ollama",
  "model": "model-name:tag",
  "apiBase": "http://localhost:11434"
}
```
4. Restart your IDE or reload Continue.dev

#### Switching Between Models in IDE
- **JetBrains:** Click the Continue icon in the sidebar → Model dropdown at top
- **VS Code:** Open Continue panel → Click model name at top → Select from list

#### Autocomplete Configuration
For faster autocomplete, use a smaller model (3B-7B parameters):
```json
"tabAutocompleteModel": {
  "title": "Fast Autocomplete",
  "provider": "ollama",
  "model": "llama3.2:3b-instruct-q8_0",
  "apiBase": "http://localhost:11434"
}
```

Recommended autocomplete models:
- `llama3.2:3b-instruct-q8_0` (3GB, fastest)
- `phi3.5:3.8b-mini-instruct-q8_0` (4GB, fast)
- `gemma4:e2b-it-q4_K_M` (7.2GB, balanced)

### Usage

#### Keyboard Shortcuts
- **Open Chat:** `⌘+L` (Mac) / `Ctrl+L` (Windows/Linux)
- **Inline Edit:** `⌘+I` (Mac) / `Ctrl+I` (Windows/Linux)
- **Accept Suggestion:** `Tab`
- **Reject Suggestion:** `Esc`

#### Chat Panel
1. Open the Continue panel (sidebar or `⌘+L`)
2. Type your question or request
3. Get AI-powered responses with code examples
4. Click code blocks to insert into your editor

#### Inline Code Generation
1. Highlight code you want to modify
2. Press `⌘+I` (Mac) or `Ctrl+I` (Windows/Linux)
3. Type your instruction (e.g., "add error handling")
4. Review and accept changes

#### Code Explanation
1. Highlight code
2. Open Continue chat (`⌘+L`)
3. Type "explain this code"
4. Get detailed explanation

#### Common Workflows
- **Refactoring:** Highlight code → `⌘+I` → "refactor this to use async/await"
- **Bug Fixing:** Highlight code → `⌘+I` → "fix the null pointer bug"
- **Documentation:** Highlight function → `⌘+I` → "add JSDoc comments"
- **Testing:** Highlight function → `⌘+L` → "write unit tests for this"

### Troubleshooting

#### Connection Issues
**Problem:** "Could not connect to Ollama"

**Solutions:**
1. Check if Ollama is running:
   ```bash
   curl http://localhost:11434/api/tags
   ```
2. Verify the server is running:
   ```bash
   pgrep -f ollama
   ```
3. Start/restart Ollama:
   ```bash
   ollama serve &
   ```
4. Check Continue config has correct URL: `http://localhost:11434`

#### Model Not Responding
**Problem:** Model takes forever or doesn't respond

**Solutions:**
1. Check if model is pulled:
   ```bash
   ollama list
   ```
2. Pull the model if missing:
   ```bash
   ollama pull llama3.3:70b-instruct-q4_K_M
   ```
3. Switch to a smaller model if RAM is insufficient (check `MODEL_GUIDE.md`)
4. Restart IDE and Ollama server

#### Autocomplete Not Working
**Problem:** Tab autocomplete doesn't trigger

**Solutions:**
1. Ensure `tabAutocompleteModel` is configured in `~/.continue/config.json`
2. Use a smaller/faster model (3B-7B)
3. Check IDE settings haven't disabled Continue autocomplete
4. Restart IDE

---

## 2. Open WebUI (Browser)

Open WebUI provides a ChatGPT-like web interface for interacting with local models, ideal for testing, demos, and non-developers.

### Access

#### URL
```
http://localhost:38080
```

#### First-Time Setup
1. Open browser and navigate to `http://localhost:38080`
2. Create an admin account (first user becomes admin)
3. Login with your credentials
4. The UI will automatically connect to your local Ollama server

### Features

#### Chat Interface
- **Clean ChatGPT-style UI** with conversation history
- **Markdown rendering** for code blocks and formatting
- **Syntax highlighting** for code snippets
- **Multi-turn conversations** with context retention

#### Model Selection
- **Dropdown menu** at top of chat interface
- **Real-time switching** between models mid-conversation
- **Model info** showing size and family
- All models from Ollama automatically available

#### Conversation History
- **Persistent storage** of all conversations
- **Search** through past chats
- **Export** conversations as JSON/Markdown
- **Share** conversations via URL (requires setup)

#### Settings & Customization
- **System prompts:** Customize model behavior
- **Temperature:** Control randomness (0.0-1.0)
- **Max tokens:** Limit response length
- **Context window:** Adjust memory size
- **Model parameters:** Advanced tuning

### Usage Tips

#### Best Use Cases
- **Model testing:** Try different models before integrating into code
- **Demos:** Show AI capabilities to stakeholders
- **Non-developers:** Team members without IDE access
- **Long conversations:** Extended back-and-forth discussions
- **Markdown output:** When you need formatted documentation

#### How to Share Conversations
1. Click the conversation in sidebar
2. Click "**Share**" icon
3. Enable "**Share publicly**"
4. Copy the generated URL
5. Recipients can view (read-only by default)

#### Customizing System Prompts
1. Click "**Settings**" (gear icon)
2. Go to "**System Prompt**" section
3. Enter custom prompt, e.g.:
   ```
   You are a senior Python developer specializing in FastAPI.
   Always include error handling and type hints.
   ```
4. Save and start new conversation

#### Model Comparison
Use multiple browser tabs to compare models side-by-side:
1. Open two tabs: `http://localhost:38080`
2. Select different model in each tab
3. Ask same question to both
4. Compare responses

### Troubleshooting

#### Can't Connect to Ollama
**Problem:** "Connection failed" or "No models available"

**Solutions:**
1. Verify Ollama is running:
   ```bash
   curl http://localhost:11434/api/tags
   ```
2. Check Docker container is running:
   ```bash
   docker ps | grep open-webui
   ```
3. Restart Open WebUI container:
   ```bash
   docker restart open-webui
   ```
4. Check environment variable in container:
   ```bash
   docker exec open-webui env | grep OLLAMA
   ```
   Should show: `OLLAMA_BASE_URL=http://host.docker.internal:11434`

#### Docker Container Not Running
**Problem:** Page doesn't load at localhost:38080

**Solutions:**
1. Check if container exists:
   ```bash
   docker ps -a | grep open-webui
   ```
2. Start container if stopped:
   ```bash
   docker start open-webui
   ```
3. Re-run setup if container missing:
   ```bash
   docker run -d \
     --name open-webui \
     -p 8080:8080 \
     -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
     -v open-webui:/app/backend/data \
     ghcr.io/open-webui/open-webui:main
   ```

#### Slow Response Times
**Problem:** Responses take very long

**Solutions:**
1. Switch to a smaller model (use model dropdown)
2. Reduce "Max Tokens" in settings (try 2048 or 4096)
3. Close other applications to free RAM
4. Check if model fits in RAM (see `MODEL_GUIDE.md`)

---

## 3. OpenCode CLI (Terminal)

OpenCode CLI provides terminal-based AI assistance for automation, scripts, and CI/CD pipelines.

### Installation

The setup script automatically installs OpenCode. For manual installation:

#### Via Bun (Recommended)
```bash
bun install -g opencode
```

#### Via NPM
```bash
npm install -g opencode
```

#### Verify Installation
```bash
opencode --version
```

### Configuration

OpenCode stores its configuration at `~/.config/opencode/opencode.jsonc`.

#### Location
```
~/.config/opencode/opencode.jsonc
```

#### Basic Configuration
```jsonc
{
  "model": "llama3.3:70b-instruct-q4_K_M",
  "baseUrl": "http://localhost:11434",
  "temperature": 0.7,
  "num_predict": 4096,
  "repeat_penalty": 1.1,
  "agents": {
    "build": {
      "model": "codestral:22b-v0.1-q8_0",
      "systemPrompt": "You are a code generation expert. Write clean, efficient code."
    },
    "review": {
      "model": "llama3.3:70b-instruct-q4_K_M",
      "systemPrompt": "You are a code reviewer. Focus on bugs, security, and best practices."
    },
    "refactor": {
      "model": "gemma4:31b-it-q8_0",
      "systemPrompt": "You are a refactoring expert. Improve code structure and performance."
    }
  }
}
```

#### Multi-Agent Setup
Configure specialized agents for different tasks:
- **build:** Code generation (fast model)
- **review:** Code review (reasoning model)
- **refactor:** Performance optimization (balanced model)
- **explain:** Documentation (general model)

### Basic Commands

#### Simple Query
```bash
opencode "write a function to parse JSON safely"
```

#### Using Specific Agent
```bash
opencode --agent build "create a REST API handler"
opencode --agent review "check this code for bugs"
opencode --agent refactor "optimize this for performance"
```

#### File Input
```bash
opencode "explain this code" < script.py
cat main.go | opencode "add error handling"
```

#### File Output
```bash
opencode "write a quicksort implementation" > quicksort.py
opencode --agent build "create a Dockerfile" > Dockerfile
```

#### Interactive Mode
```bash
opencode -i
> write a function to hash passwords
> now add rate limiting
> exit
```

#### Piping and Chaining
```bash
# Generate code and review it
opencode --agent build "create user model" | opencode --agent review

# Refactor existing file
cat legacy.js | opencode --agent refactor "modernize to ES6" > modern.js

# Generate test and code together
opencode "write tests for authentication" > auth.test.js && \
opencode --agent build "implement authentication" > auth.js
```

### Configuration Tips

#### Model Optimizations
For faster responses in CLI (where speed matters):
```jsonc
{
  "num_predict": 2048,        // Limit output length
  "repeat_penalty": 1.1,      // Reduce repetition
  "top_k": 40,                // Constrain sampling
  "top_p": 0.9,               // Nucleus sampling
  "temperature": 0.7          // Balance creativity/consistency
}
```

#### Custom Prompts
Add task-specific agents:
```jsonc
"agents": {
  "test": {
    "model": "codestral:22b-v0.1-q8_0",
    "systemPrompt": "Write comprehensive unit tests with edge cases. Use pytest."
  },
  "docs": {
    "model": "llama3.3:70b-instruct-q4_K_M",
    "systemPrompt": "Generate clear documentation with examples."
  },
  "security": {
    "model": "llama3.3:70b-instruct-q4_K_M",
    "systemPrompt": "Analyze code for security vulnerabilities and suggest fixes."
  }
}
```

### Usage Tips

#### Best Use Cases
- **Automation:** Generate code in build scripts
- **CI/CD:** Automated code review in pipelines
- **Batch processing:** Process multiple files
- **Git hooks:** Pre-commit code analysis
- **Scripts:** Quick one-off code generation

#### Working with Large Codebases
```bash
# Analyze entire directory
find src/ -name "*.py" | xargs -I {} sh -c 'echo "=== {} ===" && cat {} | opencode --agent review'

# Generate documentation for all files
for file in src/*.js; do
  cat "$file" | opencode "document this code" > "docs/$(basename $file .js).md"
done

# Security audit
grep -r "password\|token\|secret" src/ | opencode --agent security "identify security issues"
```

#### CI/CD Integration Example
```yaml
# .github/workflows/ai-review.yml
name: AI Code Review
on: [pull_request]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install OpenCode
        run: npm install -g opencode
      - name: AI Review
        run: |
          git diff origin/main...HEAD | \
          opencode --agent review "review these changes" > review.md
      - name: Post Comment
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const review = fs.readFileSync('review.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: review
            });
```

### Troubleshooting

#### Command Not Found
**Problem:** `zsh: command not found: opencode`

**Solutions:**
1. Check if OpenCode is installed:
   ```bash
   which opencode
   ```
2. Install via bun:
   ```bash
   bun install -g opencode
   ```
3. Ensure bun bin is in PATH:
   ```bash
   echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

#### Agent Errors
**Problem:** "Agent 'xyz' not found"

**Solutions:**
1. Check config file exists:
   ```bash
   cat ~/.config/opencode/opencode.jsonc
   ```
2. Verify agent is defined in config
3. Use default model if no agents:
   ```bash
   opencode "your query"  # Without --agent flag
   ```

#### Connection Failed
**Problem:** "Could not connect to model server"

**Solutions:**
1. Verify Ollama is running:
   ```bash
   curl http://localhost:11434/api/tags
   ```
2. Check baseUrl in config:
   ```bash
   grep baseUrl ~/.config/opencode/opencode.jsonc
   ```
3. Start Ollama if needed:
   ```bash
   ollama serve &
   ```

---

## 4. Switching Between Clients

All three clients connect to the same local Ollama server, allowing seamless model switching and flexible workflows.

### Using the Same Model Across Clients

All clients can use the same model simultaneously:
1. Pull a model once: `ollama pull llama3.3:70b-instruct-q4_K_M`
2. It's immediately available in:
   - Continue.dev (IDE dropdown)
   - Open WebUI (model selector)
   - OpenCode CLI (config file)

### Using Different Models in Different Clients

Each client can use a different model:
- **Continue.dev:** Use fast model for autocomplete (`llama3.2:3b`)
- **Open WebUI:** Use reasoning model for chat (`llama3.3:70b`)
- **OpenCode CLI:** Use code-specialized model (`codestral:22b`)

Example workflow:
1. **Coding:** Use Continue.dev with `codestral:22b` for code generation
2. **Review:** Copy code to Open WebUI with `llama3.3:70b` for detailed analysis
3. **Automate:** Use OpenCode CLI with `llama3.2:11b` in scripts

### Automated Config Updates with `switch-model.sh`

The `switch-model.sh` script (if available) updates all client configs at once:

```bash
# Switch all clients to use Codestral
./switch-model.sh codestral:22b-v0.1-q8_0

# This updates:
# - ~/.continue/config.json
# - Open WebUI default model
# - ~/.config/opencode/opencode.jsonc
```

#### Manual Model Switching

**Continue.dev:**
1. Edit `~/.continue/config.json`
2. Change model in `models` array or `tabAutocompleteModel`
3. Restart IDE

**Open WebUI:**
1. Open web interface
2. Click model dropdown at top
3. Select new model (instant switch)

**OpenCode CLI:**
1. Edit `~/.config/opencode/opencode.jsonc`
2. Change `model` field or agent model
3. No restart needed (takes effect immediately)

### Workflow Recommendations

#### For Daily Development
1. **Continue.dev (Primary):** Fast autocomplete + inline edits
   - Autocomplete: `llama3.2:3b-instruct-q8_0` (3GB)
   - Chat: `codestral:22b-v0.1-q8_0` (25GB)

2. **Open WebUI (Secondary):** Complex questions, exploration
   - Model: `llama3.3:70b-instruct-q4_K_M` (42GB)

3. **OpenCode CLI (Automation):** Git hooks, scripts
   - Model: `llama3.2:11b-instruct-q8_0` (12GB)

#### For Teams with Limited RAM (16GB)
- **Continue.dev:** `phi3.5:3.8b-mini-instruct-q8_0` (4GB)
- **Open WebUI:** `gemma4:e4b-it-q8_0` (12GB)
- **OpenCode CLI:** `phi3.5:3.8b-mini-instruct-q8_0` (4GB)

#### For High-Performance Workstations (48GB+)
- **Continue.dev:** `codestral:22b-v0.1-q8_0` (25GB) for coding
- **Open WebUI:** `gemma4:31b-it-q8_0` (34GB) for reasoning
- **OpenCode CLI:** `codestral:22b-v0.1-q8_0` (25GB) for automation

### Resource Management

**Check What's Running:**
```bash
# Active models
curl http://localhost:11434/api/ps

# Server status
curl http://localhost:11434/api/tags
```

**Unload Models to Free RAM:**
```bash
# Unload all models
curl -X POST http://localhost:11434/api/generate -d '{"model":"", "keep_alive":0}'
```

**Monitor Resource Usage:**
```bash
# Check RAM usage
htop

# Check model memory
ollama ps
```

---

## Quick Reference

### Continue.dev
- **Install:** IDE Plugins → Search "Continue"
- **Config:** `~/.continue/config.json`
- **Shortcuts:** `⌘+L` (chat), `⌘+I` (inline edit)
- **Best for:** Daily coding, autocomplete

### Open WebUI
- **URL:** http://localhost:38080
- **Docker:** `docker ps | grep open-webui`
- **Best for:** Testing, demos, non-developers

### OpenCode CLI
- **Install:** `bun install -g opencode`
- **Config:** `~/.config/opencode/opencode.jsonc`
- **Usage:** `opencode "your query"`
- **Best for:** Automation, CI/CD, scripts

### Ollama Server
- **Check status:** `curl http://localhost:11434/api/tags`
- **List models:** `ollama list`
- **Pull model:** `ollama pull <model>`
- **Remove model:** `ollama rm <model>`

---

## Additional Resources

- **Model Selection Guide:** See `MODEL_GUIDE.md` for choosing the right model
- **Troubleshooting:** See `TROUBLESHOOTING.md` for common issues
- **Team Deployment:** See `TEAM_DEPLOYMENT.md` for enterprise setup
- **Ollama Docs:** https://ollama.ai/docs
- **Continue.dev Docs:** https://continue.dev/docs
- **Open WebUI Docs:** https://docs.openwebui.com
- **OpenCode Docs:** https://github.com/karanpratapsingh/opencode

---

**Generated by:** AI Model Setup Scripts
**Last Updated:** 2026-04-07
