# Advanced TUI Features

## Overview
Complete TUI overhaul with modern, professional interface elements.

## New Features

### 1. **Animated Spinners** ⣾
Real-time feedback during long operations using Unicode braille patterns.

```bash
start_spinner "Downloading model..."
# Your long operation here
stop_spinner
```

**What users see:**
```
  ⣾ Downloading model...
```
The spinner animates automatically while waiting.

### 2. **Progress Bars**
Visual progress indicators with percentages.

```bash
draw_progress_bar 45 100  # 45% complete
```

**What users see:**
```
  [██████████████████░░░░░░░░░░░░░░░░░░░░]  45%
```

### 3. **Download Progress with ETA**
Sophisticated progress display with speed and time estimates.

```bash
draw_download_progress 250 500 5.2  # 250MB of 500MB at 5.2MB/s
```

**What users see:**
```
  [████████████████████░░░░░░░░░░░░░░░░░░░░]  50%  250.0MB/500.0MB  5.2MB/s  ETA: 8m 2s
```

### 4. **Box Drawing**
Professional-looking boxes for important information.

```bash
draw_info_box "Title" "Line 1" "Line 2" "Line 3"
```

**What users see:**
```
┌───────────────────────────────────────────────────────────┐
│ Title                                                     │
├───────────────────────────────────────────────────────────┤
│ Line 1                                                    │
│ Line 2                                                    │
│ Line 3                                                    │
└───────────────────────────────────────────────────────────┘
```

### 5. **Error Boxes with Actions**
Beautiful error display with actionable choices.

```bash
draw_error_box \
    "Model Download Failed" \
    "Description of the error..." \
    "Retry|Check disk space|View logs|Skip"
```

**What users see:**
```
╔═══════════════════════════════════════════════════════════╗
║ ❌ Model Download Failed                                  ║
╠═══════════════════════════════════════════════════════════╣
║ Description of the error...                               ║
╠═══════════════════════════════════════════════════════════╣
║ [1] Retry                                                 ║
║ [2] Check disk space                                      ║
║ [3] View logs                                             ║
║ [4] Skip                                                  ║
╚═══════════════════════════════════════════════════════════╝
```

### 6. **Tree Display**
Hierarchical display of operations.

```bash
echo "[1/3] Installing Components"
tree_node 0 0 "✓" "Ollama v0.20.4 found"
tree_node 0 0 "⣾" "Checking for updates..."
tree_node 0 1 "✓" "Up to date"
```

**What users see:**
```
[1/3] Installing Components
├─ ✓ Ollama v0.20.4 found
├─ ⣾ Checking for updates...
└─ ✓ Up to date
```

### 7. **Configuration Preview**
Preview all settings before execution.

```bash
show_config_preview \
    "M4" "48" "10" \
    "gemma4:31b" "19" \
    "codegemma:7b" "5.0" \
    "OpenCode + JetBrains"
```

**What users see:**
```
╔═══════════════════════════════════════════════════════════╗
║                  Configuration Preview                    ║
╠═══════════════════════════════════════════════════════════╣
║  Hardware:  M4 • 48GB RAM • 10 cores                      ║
║                                                           ║
║  Will Download:                                           ║
║    → gemma4:31b         19GB   ⏱️  ~18 min                ║
║    → codegemma:7b       5.0GB  ⏱️  ~4 min                 ║
║                         ─────   ─────────                 ║
║                         24GB    ~22 min                   ║
║                                                           ║
║  Will Configure:                                          ║
║    ✓ IDE Tools: OpenCode + JetBrains                      ║
║    ✓ Local Ollama provider                                ║
║    ✓ LaunchAgent for auto-start                           ║
╠═══════════════════════════════════════════════════════════╣
║  [C]ontinue  [E]dit Configuration  [Q]uit                 ║
╚═══════════════════════════════════════════════════════════╝
```

### 8. **Interactive Final Menu**
Post-installation menu with quick actions.

```bash
show_final_menu "gemma4-optimized-31b-32k" "OpenCode + JetBrains"
```

**What users see:**
```
╔═══════════════════════════════════════════════════════════╗
║            ✨ Setup Complete! ✨                           ║
╠═══════════════════════════════════════════════════════════╣
║  Quick Actions:                                           ║
║    [1] 🚀 Launch OpenCode                                 ║
║    [2] 🧪 Test Gemma4 model                               ║
║    [3] 📋 View JetBrains setup guide                      ║
║    [4] 📊 Check system resources                          ║
║    [5] 📝 View configuration files                        ║
║    [H] 📚 View help & documentation                       ║
║    [Q] Quit                                               ║
╠═══════════════════════════════════════════════════════════╣
║  Tip: Run './setup-gemma4-opencode.sh -v' for verbose    ║
╚═══════════════════════════════════════════════════════════╝
```

### 9. **System Resources Monitor**
Live system resource display.

```bash
show_system_resources
```

**What users see:**
```
┌─ System Resources ─────────────────────────────────────┐
│ CPU:  ████████░░░░░░░░░░ 45%  (4.5 / 10 cores)         │
│ RAM:  ████████████████░░ 68%  (32.6GB / 48GB)          │
│ Disk: ██░░░░░░░░░░░░░░░░ 12%  (121GB free)             │
└────────────────────────────────────────────────────────┘
```

### 10. **Arrow Key Navigation** (Optional)
Interactive menu navigation with arrow keys.

```bash
result=$(show_menu "Select Model" "gemma4:e2b|gemma4:latest|gemma4:31b")
```

**What users see:**
```
Select Model

   gemma4:e2b     7GB   128K
   gemma4:latest  10GB  128K
 → gemma4:31b     19GB  256K  ★ Recommended

Use ↑↓ arrows to move, Enter to select
```

## Integration with Existing Code

### Verbosity Levels
All new features respect verbosity settings:

- **Quiet (`-q`)**: Minimal output, no fancy UI
- **Normal (default)**: Spinners, progress bars, clean boxes
- **Verbose (`-v`)**: Tree structures, detailed info

### Automatic Fallback
- Detects terminal capabilities
- Falls back to simpler UI if Unicode not supported
- Works in all environments

## Usage Examples

### During Download
```bash
# Normal mode: spinner
start_spinner "Downloading gemma4:31b..."
ollama pull gemma4:31b > /dev/null 2>&1
stop_spinner
print_status "gemma4:31b downloaded"

# Verbose mode: show full output with tree
tree_node 0 0 "⣾" "Pulling manifest..."
tree_node 0 0 "⣾" "Downloading layers..."
tree_node 0 1 "✓" "Verification complete"
```

### Error Handling
```bash
if ! ollama pull "$MODEL"; then
    draw_error_box \
        "Download Failed" \
        "Failed to download $MODEL.
        
Possible causes:
  • Network issues
  • Disk full
  • Invalid model name" \
        "Retry|Check disk space|Cancel"
    
    read -p "Select [1-3]: " choice
    case $choice in
        1) retry_download ;;
        2) df -h && exit 1 ;;
        *) exit 1 ;;
    esac
fi
```

## Testing

Run the test script to see all features:
```bash
./test_advanced_tui.sh
```

## File Structure

```
lib/
├── common.sh             # Basic print functions
├── tui-advanced.sh       # Advanced TUI features (NEW)
├── interactive.sh        # User input handling
└── ...
```

## Benefits

### User Experience
- ✅ **Professional appearance** - Rivals GUI installers
- ✅ **Clear feedback** - Users know what's happening
- ✅ **Confidence** - Preview before execution
- ✅ **Actionable errors** - Clear next steps on failure
- ✅ **Time estimates** - Users know how long to wait

### Technical
- ✅ **Pure Bash** - No external dependencies
- ✅ **Lightweight** - Unicode characters only
- ✅ **Portable** - Works on all macOS systems
- ✅ **Respects verbosity** - Adapts to user preference
- ✅ **Graceful degradation** - Falls back when needed

## Unicode Characters Used

| Symbol | Purpose |
|--------|---------|
| ⣾⣽⣻⢿⡿⣟⣯⣷ | Spinner (braille patterns) |
| █ | Progress bar filled |
| ░ | Progress bar empty |
| ╔═╗╠═╣╚═╝ | Double-line boxes |
| ┌─┐├─┤└─┘ | Single-line boxes |
| ├─└─ | Tree branches |
| ✓✗ | Success/failure |
| ⏱️⣾ | Time/waiting |
| →↑↓ | Navigation |
| 🚀🧪📋📊📝📚 | Action icons |

## Version
Script version: 2.2.0 (with advanced TUI)

## Future Enhancements

Potential additions:
- Real-time download progress parsing
- Multi-column layouts
- Color themes
- More interactive elements
- Live logs with filtering
