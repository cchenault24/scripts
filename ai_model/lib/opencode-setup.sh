#!/bin/bash
#
# OpenCode installation and configuration
#

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_opencode() {
    print_header "Installing OpenCode"

    # Remove Homebrew version if exists
    if brew list opencode &>/dev/null; then
        print_warning "Removing Homebrew version of OpenCode..."
        brew uninstall opencode
    fi

    if [ "$BUILD_OPENCODE_FROM_SOURCE" = "true" ]; then
        print_info "Building OpenCode from source (BUILD_OPENCODE_FROM_SOURCE=true)"

        # Check if custom build marker exists
        CUSTOM_BUILD_MARKER="$HOME/.opencode/bin/.custom-build-dev"

        if [ -f "$CUSTOM_BUILD_MARKER" ]; then
            print_status "OpenCode custom build already installed"
            "$HOME/.opencode/bin/opencode" --version
            print_info "To rebuild, remove: $CUSTOM_BUILD_MARKER"
        else
            # Install base OpenCode first if not present
            if [ ! -d "$HOME/.opencode" ]; then
                print_info "Installing base OpenCode first..."
                curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh
                bash /tmp/opencode-install.sh
            fi

            if [ -d "$OPENCODE_BUILD_DIR" ]; then
                print_warning "Removing existing build directory: $OPENCODE_BUILD_DIR"
                rm -rf "$OPENCODE_BUILD_DIR"
            fi

            print_info "Cloning latest OpenCode from dev branch..."
            print_info "This includes the newest features and fixes"
            git clone --depth 1 --branch dev https://github.com/anomalyco/opencode.git "$OPENCODE_BUILD_DIR" || {
                print_error "Failed to clone OpenCode repository (dev branch)"
                exit 1
            }
            cd "$OPENCODE_BUILD_DIR"

            # Show the latest commit info
            LATEST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%ar)" 2>/dev/null || echo "unknown")
            print_info "Latest commit: $LATEST_COMMIT"

            print_info "Installing dependencies and building..."
            bun install || {
                print_error "Failed to install dependencies"
                exit 1
            }
            cd packages/opencode || {
                print_error "packages/opencode directory not found"
                exit 1
            }
            print_info "Building OpenCode binary with production optimizations..."
            print_info "Enabling: minification, tree-shaking, production mode"
            bun run build -- --single --skip-install --production || {
                print_error "Failed to build OpenCode"
                exit 1
            }

            # Backup original if it exists and isn't already backed up
            if [ -f "$HOME/.opencode/bin/opencode" ] && [ ! -f "$HOME/.opencode/bin/opencode.backup" ]; then
                print_info "Backing up original OpenCode binary..."
                cp "$HOME/.opencode/bin/opencode" "$HOME/.opencode/bin/opencode.backup"
            fi

            print_info "Installing custom build..."

            # Check if build output exists
            if [ ! -f "dist/opencode-darwin-arm64/bin/opencode" ]; then
                print_error "Build output not found: dist/opencode-darwin-arm64/bin/opencode"
                print_info "Available files:"
                find dist -name "opencode" 2>/dev/null || echo "No opencode binary found"
                exit 1
            fi

            mkdir -p "$HOME/.opencode/bin"
            cp dist/opencode-darwin-arm64/bin/opencode "$HOME/.opencode/bin/opencode" || {
                print_error "Failed to copy OpenCode binary"
                exit 1
            }
            chmod +x "$HOME/.opencode/bin/opencode"

            # Create marker file to indicate custom build
            touch "$CUSTOM_BUILD_MARKER"

            print_status "OpenCode custom build installed from source"
            "$HOME/.opencode/bin/opencode" --version
        fi
    else
        print_info "Using official OpenCode release (recommended)"
        print_info "This version gets automatic updates via 'opencode update'"

        # Check if OpenCode binary exists (not just the directory)
        if [ ! -f "$HOME/.opencode/bin/opencode" ]; then
            # Check if we have a backup to restore
            if [ -f "$HOME/.opencode/bin/opencode.backup" ]; then
                print_info "Restoring OpenCode from backup..."
                cp "$HOME/.opencode/bin/opencode.backup" "$HOME/.opencode/bin/opencode"
                chmod +x "$HOME/.opencode/bin/opencode"
                print_status "Restored from backup"
            else
                print_info "Installing OpenCode..."
                curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh
                bash /tmp/opencode-install.sh
            fi
        else
            print_status "OpenCode already installed"

            # Check if update is available
            if "$HOME/.opencode/bin/opencode" --version 2>&1 | grep -q "update available"; then
                print_info "Update available - run 'opencode update' to update"
            fi
        fi

        # Verify installation succeeded
        if [ -f "$HOME/.opencode/bin/opencode" ]; then
            print_status "OpenCode installed at: $(which opencode || echo "$HOME/.opencode/bin/opencode")"
            "$HOME/.opencode/bin/opencode" --version
        else
            print_error "OpenCode installation failed"
            exit 1
        fi
    fi

    echo ""
}

configure_opencode() {
    local model_name="$1"
    local context_size="$2"

    print_header "Creating OpenCode configuration for Ollama"

    CONFIG_DIR="$HOME/.config/opencode"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/prompts"

    print_info "Creating opencode.jsonc..."

    cat > "$CONFIG_DIR/opencode.jsonc" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://127.0.0.1:3456/v1",
        "timeout": 600000,
        "chunkTimeout": 60000,
        "toolParser": [
          { "type": "raw-function-call" },
          { "type": "json" }
        ]
      },
      "models": {
        "$model_name": {
          "name": "Gemma 4 ($model_name)",
          "tool_call": true,
          "limit": {
            "context": $context_size,
            "output": 16384
          },
          "options": {
            "temperature": 0.7,
            "top_p": 0.95,
            "top_k": 64,
            "repeat_penalty": 1.1,
            "num_predict": 16384
          }
        }
      }
    }
  },
  "model": "ollama/$model_name",
  "agent": {
    "build": {
      "prompt": "{file:./prompts/build.txt}",
      "steps": 100,
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "allow",
        "task": "allow"
      }
    },
    "review": {
      "prompt": "{file:./prompts/review.txt}",
      "steps": 50,
      "permission": {
        "edit": "deny",
        "bash": "allow",
        "webfetch": "allow",
        "task": "allow"
      }
    },
    "refactor": {
      "prompt": "{file:./prompts/refactor.txt}",
      "steps": 100,
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "deny",
        "task": "allow"
      }
    }
  }
}
EOF

    print_status "Created: $CONFIG_DIR/opencode.jsonc"

    print_info "Creating AGENTS.md..."
    cat > "$CONFIG_DIR/AGENTS.md" <<'EOF'
# OpenCode Agent Instructions

You are a coding assistant with direct access to the user's file system.

## CRITICAL: When user mentions a file
If the user asks about a file or provides a file path:
1. IMMEDIATELY use the 'read' tool to read it
2. Do NOT ask them to paste the content
3. Do NOT say you don't have access
4. Just read the file and answer

## Available Tools

### read
Read a file from the file system.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `offset` (number, optional): Line number to start from
- `limit` (number, optional): Max lines to read

Example: `{"filePath": "/Users/web/project/hello.txt"}`

Best practices:
- ALWAYS read files before editing them
- Use for specific files you know about
- For large files, use offset/limit to read sections

### edit
Modify an existing file by replacing text.
Parameters:
- `filePath` (string, REQUIRED): Absolute path to the file
- `oldString` (string, REQUIRED): The exact text to find and replace
- `newString` (string, REQUIRED): The replacement text
- `replaceAll` (boolean, optional): Replace all occurrences

Example: `{"filePath": "/path/to/file.ts", "oldString": "foo", "newString": "bar"}`

Best practices:
- MUST read the file first
- Make oldString unique enough to match once
- Preserve indentation and formatting

### write
Create or overwrite a file.
Parameters (ALL required):
- `filePath` (string, REQUIRED): Absolute path to the file
- `content` (string, REQUIRED): The content to write

Example: `{"filePath": "/Users/web/project/hello.txt", "content": "Hello world"}`

Best practices:
- Use only for NEW files
- Prefer 'edit' for existing files
- Include complete file content

### bash
Execute shell commands.
Parameters (ALL required unless noted):
- `command` (string, REQUIRED): The shell command to run
- `description` (string, REQUIRED): Short description of what the command does (5-10 words)
- `timeout` (number, optional): Timeout in milliseconds
- `workdir` (string, optional): Working directory

Example: `{"command": "ls -la", "description": "List files in current directory"}`

Best practices:
- Use for git, tests, builds, package management
- ALWAYS provide description
- Check exit codes for errors

### glob
Find files by pattern.
Parameters:
- `pattern` (string, REQUIRED): Glob pattern like `**/*.ts`
- `path` (string, optional): Directory to search in

Example: `{"pattern": "**/*.test.ts"}`

Best practices:
- Use for finding files by name pattern
- Good for: "Find all test files", "Find component files"
- NOT for content search (use grep or task)

### grep
Search file contents.
Parameters:
- `pattern` (string, REQUIRED): Regex pattern to search for
- `path` (string, optional): Directory to search in
- `include` (string, optional): File pattern filter like `*.js`

Example: `{"pattern": "function.*auth", "include": "*.ts"}`

Best practices:
- Use for specific content searches
- Good for: Known function/class names, specific strings
- For open-ended searches, use 'task' tool with Explore agent

### task
Launch specialized agents for complex tasks.
Parameters:
- `subagent_type` (string, REQUIRED): Agent type (e.g., "Explore")
- `prompt` (string, REQUIRED): Task description for the agent

Example: `{"subagent_type": "Explore", "prompt": "Find all error handling code in the authentication system"}`

Best practices for LARGE CODEBASES (10,000+ files):
- Use 'task' with subagent_type=Explore for open-ended searches
- Good for: "Where is X handled?", "How does Y work?", "Find all Z"
- Much faster and more thorough than manual grep/glob
- The Explore agent can search multiple files efficiently

### question
Ask the user for clarification.
Parameters:
- `question` (string, REQUIRED): The question to ask

Best practices:
- Use when requirements are unclear
- Ask before making large changes
- Get approval for refactoring plans

### webfetch
Fetch content from external URLs.
Parameters:
- `url` (string, REQUIRED): URL to fetch
- `prompt` (string, REQUIRED): What to extract from the content

Best practices:
- Use for documentation, API references
- NOT for authenticated content

### todowrite
Track tasks and progress. The `todos` parameter MUST be a JSON array of objects, NOT a string.
Parameters:
- `todos` (array of objects, REQUIRED): Each object has:
  - `content` (string, REQUIRED): Brief description of the task
  - `status` (string, REQUIRED): One of: `pending`, `in_progress`, `completed`, `cancelled`
  - `priority` (string, REQUIRED): One of: `high`, `medium`, `low`

Example: `{"todos": [{"content": "Add game over screen", "status": "in_progress", "priority": "high"}, {"content": "Add sound effects", "status": "pending", "priority": "low"}]}`

IMPORTANT: `todos` MUST be an array `[...]`, NOT a string `"[...]"`. Never stringify the array.

## WORKFLOW FOR LARGE CODEBASES

When working with large codebases (10,000+ files):

1. **Exploration Phase**
   - Use 'task' tool with Explore agent for broad searches
   - Use 'glob' for finding specific file names
   - Use 'grep' for known patterns

2. **Reading Phase**
   - Use 'read' only for files directly relevant to the task
   - Don't read files "just in case" - be targeted

3. **Modification Phase**
   - ALWAYS read files before editing
   - Make changes incrementally
   - Test after each logical change

4. **Verification Phase**
   - Use 'bash' to run tests
   - Check that changes work as expected

## IMPORTANT REMINDERS

**Parameter Format:**
- Use camelCase: `filePath` not `file_path`
- Provide all required parameters
- Use correct types (string, number, boolean, array)

**Common Mistakes to Avoid:**
- ❌ Calling non-existent tools (google:search, web_search)
- ❌ Using snake_case parameters
- ❌ Making changes without reading files first
- ❌ Using grep/glob for open-ended searches (use task tool)
- ❌ Stringifying array parameters

## DO NOT
- Call tools that don't exist (like google:search, web_search, etc.)
- Ask user to paste file contents when you can read them
- Use snake_case parameters (use camelCase: filePath not file_path)
- Edit files without reading them first
- Make large changes (3+ files) without asking user first
EOF

    print_status "Created: $CONFIG_DIR/AGENTS.md"

    print_info "Creating build.txt prompt..."
    cat > "$CONFIG_DIR/prompts/build.txt" <<'EOF'
You are an expert coding assistant with direct file system access.

## File Access
When the user mentions a file path or asks about code:
1. IMMEDIATELY use 'read' tool to read it
2. Do NOT ask them to paste content
3. Do NOT say you lack access
4. Read it and answer

## Code Exploration (Large Codebases)
For open-ended searches like "where is X handled" or "how does Y work":
- Use 'task' tool with subagent_type=Explore for multi-file searches
- This is faster and more thorough than manual grep/glob
- Example: "Find all error handling code" → use task tool

For specific searches:
- Known file: use 'read' directly
- Specific pattern: use 'grep' or 'glob'
- Class/function name: use 'glob' for "**/*ClassName*"

## Context Management (Large Codebases)
When working with large codebases (10,000+ files):
- Read ONLY files directly relevant to the current task
- Use 'task' tool for exploration, not manual file reads
- Prioritize targeted searches over broad scans
- When context grows large, summarize findings before continuing
- For changes spanning 3+ files, present plan to user first
- Break large tasks into smaller, focused subtasks

## Code Modifications
Small changes (1-2 files):
- Read the file first (ALWAYS)
- Use 'edit' for precise changes
- Use 'write' for new files only
- Test after changes
- Verify the change worked

Large refactors (3+ files):
- Present a plan to the user first
- Get approval before making changes
- Make changes incrementally
- Test after each logical step
- Document what changed and why

## Commands
- Use 'bash' for git, tests, builds
- Always provide 'description' parameter
- Run tests after significant changes
- Check exit codes and handle errors

## Good Examples
User: "Fix the bug in auth.ts"
✅ CORRECT: Read auth.ts first, understand the bug, make targeted fix, test

User: "Where is error handling?"
✅ CORRECT: Use task tool with Explore agent for multi-file search

User: "Update the API endpoint to support pagination"
✅ CORRECT: Read endpoint file, read tests, update both, run tests

## Bad Examples
❌ WRONG: Making changes without reading the file first
❌ WRONG: Using grep/glob for open-ended searches (use task tool)
❌ WRONG: Creating new files when editing existing ones would work
❌ WRONG: Making 5+ file changes without asking user first
❌ WRONG: Calling non-existent tools like google:search

## Available Tools
- read: {filePath} - Read any file
- write: {filePath, content} - Create new files
- edit: {filePath, oldString, newString} - Modify files
- bash: {command, description} - Run commands (BOTH required)
- glob: {pattern} - Find files by pattern
- grep: {pattern} - Search file contents
- task: Use for complex multi-file exploration
- webfetch: Fetch external content
- todowrite: Track tasks
- question: Ask user for clarification
- skill: Invoke specialized skills

## DO NOT
- Invent tools (no google:search, web_search, etc.)
- Ask for file content you can read
- Use snake_case params (use camelCase)
- Make large changes without asking first
- Skip reading files before editing them
- Use manual grep/glob for open-ended searches
EOF

    print_status "Created: $CONFIG_DIR/prompts/build.txt"

    print_info "Creating review.txt prompt..."
    cat > "$CONFIG_DIR/prompts/review.txt" <<'EOF'
You are a code review expert focusing on quality, security, and best practices.

## Review Approach
Your role is to review code changes, NOT to make edits directly.
Focus on: correctness, security, performance, maintainability, testing.

## Review Process
1. Read all changed files thoroughly
2. Understand the context and purpose
3. Check for common issues:
   - Security vulnerabilities (injection, XSS, auth bypass)
   - Logic errors and edge cases
   - Performance issues
   - Code smell and maintainability
   - Missing tests or documentation
   - Breaking changes
4. Provide constructive feedback with specific examples
5. Suggest improvements with code snippets

## Review Categories
**CRITICAL** - Must fix (security, bugs, breaking changes)
**IMPORTANT** - Should fix (performance, best practices)
**SUGGESTION** - Consider (refactoring, style improvements)

## Security Checklist
- [ ] Input validation and sanitization
- [ ] Authentication and authorization
- [ ] SQL injection prevention
- [ ] XSS prevention
- [ ] CSRF protection
- [ ] Sensitive data handling
- [ ] Dependency vulnerabilities

## Output Format
For each issue found:
```
[CATEGORY] Issue in file.ts:123
Description of the issue
Why it matters
Suggested fix with code example
```

## DO NOT
- Make direct edits (edit permission is denied)
- Approve code without thorough review
- Ignore security issues
- Be overly critical about style preferences
EOF

    print_status "Created: $CONFIG_DIR/prompts/review.txt"

    print_info "Creating refactor.txt prompt..."
    cat > "$CONFIG_DIR/prompts/refactor.txt" <<'EOF'
You are a refactoring expert focused on improving code quality without changing behavior.

## Refactoring Principles
1. Preserve existing functionality (behavior stays the same)
2. Improve code structure, readability, and maintainability
3. Make changes incrementally and test frequently
4. Follow existing code patterns and conventions

## Before Refactoring
1. Read all relevant files to understand current structure
2. Identify code smells and improvement opportunities
3. Present refactoring plan to user for approval
4. Get explicit approval before making changes

## Common Refactoring Patterns
- Extract repeated code into functions/classes
- Rename variables/functions for clarity
- Simplify complex conditionals
- Remove dead code
- Consolidate duplicate logic
- Improve error handling
- Add type safety

## Refactoring Process
1. **Analyze**: Read code, identify issues, understand dependencies
2. **Plan**: Present structured refactoring plan to user
3. **Approve**: Wait for user approval before changes
4. **Execute**: Make changes incrementally
5. **Test**: Run tests after each logical change
6. **Verify**: Confirm behavior unchanged

## Safety First
- ALWAYS run existing tests after changes
- Make one logical change at a time
- Commit working changes frequently
- If tests fail, revert and reassess
- Keep refactoring separate from new features

## Context Management
For large refactorings:
- Break into smaller phases (3-5 files per phase)
- Get approval for each phase
- Test and commit between phases
- Document what changed and why

## Available Tools
- read: Read files to understand structure
- edit: Make precise refactoring changes
- bash: Run tests, git commands
- task: Explore codebase for patterns
- question: Ask user for clarification or approval

## DO NOT
- Change behavior or add features (that's not refactoring)
- Make large changes without user approval
- Skip running tests
- Refactor and add features in same change
- Use external APIs (webfetch is denied)
EOF

    print_status "Created: $CONFIG_DIR/prompts/refactor.txt"

    print_info "Creating performance environment variables..."
    cat > "$CONFIG_DIR/opencode-env.sh" <<'EOF'
#!/bin/bash
#
# OpenCode Performance Environment Variables
# Source this file before running opencode for optimal performance:
#   source ~/.config/opencode/opencode-env.sh && opencode
#
# Or add to your ~/.zshrc or ~/.bashrc:
#   [ -f ~/.config/opencode/opencode-env.sh ] && source ~/.config/opencode/opencode-env.sh
#

# Disable file time checks (10-20% faster file operations)
export OPENCODE_DISABLE_FILETIME_CHECK=true

# Increase bash tool timeout for long-running operations (10 minutes)
export OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS=600000

# Skip models.dev fetch on startup (2-5s faster startup)
export OPENCODE_DISABLE_MODELS_FETCH=true

# Disable terminal title updates (minor overhead reduction)
export OPENCODE_DISABLE_TERMINAL_TITLE=true

# Enable experimental file watcher (more efficient file change detection)
export OPENCODE_EXPERIMENTAL_FILEWATCHER=true
EOF

    chmod +x "$CONFIG_DIR/opencode-env.sh"
    print_status "Created: $CONFIG_DIR/opencode-env.sh"

    echo ""

    # Update OpenCode config with optimized model if it differs from base model
    CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Updating OpenCode config to use optimized model..."
        # Update the model references in the config
        BASE_MODEL="${model_name%-*}"
        sed -i.bak "s|\"${BASE_MODEL}\":|\"$model_name\":|g" "$CONFIG_FILE"
        sed -i.bak "s|ollama/${BASE_MODEL}\"|ollama/$model_name\"|g" "$CONFIG_FILE"
        rm -f "$CONFIG_FILE.bak"
        print_status "Config updated to use: $model_name"
    fi

    echo ""
}
