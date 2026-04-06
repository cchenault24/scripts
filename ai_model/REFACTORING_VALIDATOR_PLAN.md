# Refactoring Plan: validator.py `_pull_model_single_attempt()`

## Current State

**Function**: `_pull_model_single_attempt()` (lines 597-973)
- **Length**: 377 lines
- **Complexity**: Cognitive 71, Cyclomatic 45
- **Nesting**: 7 levels deep
- **Issues**: 8 debug logging blocks, regex in loops, duplicate logic

## Target State

**8 focused functions** with clear responsibilities:
1. Helper functions (pure, testable)
2. Progress handlers (isolated side effects)
3. Orchestrator (simple control flow)

## Detailed Refactoring Steps

### Phase 1: Extract Helper Functions (Pure Functions)

#### 1.1: `_remove_ansi_codes(line: str) -> str`
**Purpose**: Clean ANSI escape sequences from terminal output
**Current**: Lines 722-724, 896 (duplicated)
**Benefit**: Testable, reusable, no side effects

```python
def _remove_ansi_codes(line: str) -> str:
    """
    Remove ANSI escape sequences from terminal output.

    Args:
        line: Raw terminal output line with ANSI codes

    Returns:
        Cleaned string with ANSI codes removed
    """
    # Remove ANSI control sequences
    clean = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', line)
    # Remove OSC sequences
    clean = re.sub(r'\x1b\][0-9;]*', '', clean)
    return clean.strip()
```

#### 1.2: `_parse_ollama_progress(line: str) -> Optional[ProgressInfo]`
**Purpose**: Parse Ollama progress output into structured data
**Current**: Lines 761-855 (complex nested ifs with regex)
**Benefit**: Testable, clear contract, no side effects

```python
@dataclass
class ProgressInfo:
    """Parsed progress information from Ollama output."""
    percent: Optional[int] = None
    downloaded_bytes: Optional[int] = None
    total_bytes: Optional[int] = None
    status: str = "pulling"  # "pulling", "manifest", "complete", "error"
    message: str = ""

def _parse_ollama_progress(line: str) -> Optional[ProgressInfo]:
    """
    Parse Ollama progress line into structured data.

    Format examples:
    - "pulling manifest"
    - "pulling abc123:  45% ▕██...▏ 2.5 GB/5.5 GB"
    - "success"

    Args:
        line: Cleaned terminal output line (ANSI removed)

    Returns:
        ProgressInfo if line contains progress, None otherwise
    """
    line_lower = line.lower()

    # Check for completion
    if any(word in line_lower for word in ["success", "done", "complete"]):
        return ProgressInfo(percent=100, status="complete", message=line)

    # Check for errors
    if "error" in line_lower or "ssh:" in line_lower:
        return ProgressInfo(status="error", message=line)

    # Check for pulling with percentage
    if "pulling" in line_lower and "%" in line:
        # Extract percentage first
        percent_match = re.search(r'(\d+)%', line)
        if percent_match:
            percent = int(percent_match.group(1))

            # Extract size info if available: "X MB/Y GB"
            size_match = re.search(
                r'(\d+(?:\.\d+)?)\s*(MB|GB)\s*/\s*(\d+(?:\.\d+)?)\s*(MB|GB)',
                line
            )

            if size_match:
                downloaded = float(size_match.group(1))
                downloaded_unit = size_match.group(2)
                total = float(size_match.group(3))
                total_unit = size_match.group(4)

                # Convert to bytes
                downloaded_bytes = int(downloaded * (1024**3 if downloaded_unit == "GB" else 1024**2))
                total_bytes = int(total * (1024**3 if total_unit == "GB" else 1024**2))

                return ProgressInfo(
                    percent=percent,
                    downloaded_bytes=downloaded_bytes,
                    total_bytes=total_bytes,
                    status="pulling"
                )
            else:
                # Just percentage, no size info
                return ProgressInfo(percent=percent, status="pulling")

    # Check for manifest pulling (without percentage)
    if "pulling manifest" in line_lower:
        return ProgressInfo(status="manifest", message="Pulling manifest")

    return None
```

#### 1.3: `_create_rich_progress_bar() -> Progress`
**Purpose**: Create configured rich progress bar
**Current**: Lines 663-674
**Benefit**: Centralized configuration, testable

```python
def _create_rich_progress_bar() -> 'Progress':
    """
    Create pre-configured rich Progress bar for model downloading.

    Returns:
        Configured Progress instance with columns for downloading
    """
    from rich.progress import (
        Progress, SpinnerColumn, BarColumn, TextColumn,
        DownloadColumn, TransferSpeedColumn, TimeRemainingColumn
    )
    from rich.console import Console

    return Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        DownloadColumn(),
        TransferSpeedColumn(),
        TimeRemainingColumn(),
        console=Console(),
        transient=False,
        refresh_per_second=2  # Reduced from 10 (performance optimization)
    )
```

### Phase 2: Extract Progress Handlers

#### 2.1: `_monitor_rich_progress(process, model_name, progress, task) -> List[str]`
**Purpose**: Monitor subprocess with rich progress bar
**Current**: Lines 697-883 (186 lines!)
**Benefit**: Isolated side effects, testable with mocks

```python
def _monitor_rich_progress(
    process: subprocess.Popen,
    model_name: str,
    progress: 'Progress',
    task: 'TaskID'
) -> List[str]:
    """
    Monitor subprocess stderr and update rich progress bar.

    Args:
        process: Running subprocess (ollama pull)
        model_name: Model being pulled
        progress: Rich Progress instance
        task: Progress task ID

    Returns:
        List of output lines for error reporting
    """
    output_lines = []
    total_bytes = None

    if not process.stderr:
        return output_lines

    for line in process.stderr:
        # Clean ANSI codes
        clean_line = _remove_ansi_codes(line)

        # Handle edge case: "pulling manifest" appended to progress line
        if "pulling manifest" in clean_line.lower() and "%" in clean_line:
            clean_line = clean_line.split("pulling manifest")[0].strip()

        if not clean_line and "%" not in line:
            continue

        if clean_line:
            output_lines.append(clean_line)

        # Parse progress
        progress_info = _parse_ollama_progress(clean_line)
        if not progress_info:
            continue

        # Update progress bar based on parsed info
        if progress_info.status == "pulling" and progress_info.percent is not None:
            if progress_info.total_bytes:
                # Update with actual bytes
                total_bytes = progress_info.total_bytes
                progress.update(
                    task,
                    completed=progress_info.downloaded_bytes,
                    total=progress_info.total_bytes,
                    description=f"Pulling {model_name}"
                )
            else:
                # Update with percentage only
                if total_bytes is None:
                    progress.update(task, total=100, completed=progress_info.percent)
                else:
                    completed_bytes = int((progress_info.percent / 100) * total_bytes)
                    progress.update(task, completed=completed_bytes, total=total_bytes)

        elif progress_info.status == "manifest":
            progress.update(task, description=f"Pulling {model_name} (manifest)", total=None)

        elif progress_info.status == "complete":
            if total_bytes:
                progress.update(task, completed=total_bytes, total=total_bytes)
            else:
                progress.update(task, completed=100, total=100)
            print()
            ui.print_success(f"Downloaded {model_name}")

        elif progress_info.status == "error":
            print()
            ui.print_error(f"    {progress_info.message}")

    return output_lines
```

#### 2.2: `_monitor_simple_progress(process, model_name) -> List[str]`
**Purpose**: Monitor subprocess with simple text progress
**Current**: Lines 892-912
**Benefit**: Isolated fallback logic

```python
def _monitor_simple_progress(process: subprocess.Popen, model_name: str) -> List[str]:
    """
    Monitor subprocess stderr with simple text output (no rich).

    Args:
        process: Running subprocess (ollama pull)
        model_name: Model being pulled

    Returns:
        List of output lines for error reporting
    """
    output_lines = []

    if not process.stderr:
        return output_lines

    for line in process.stderr:
        clean_line = _remove_ansi_codes(line)
        if not clean_line:
            continue

        output_lines.append(clean_line)

        # Simple progress output
        line_lower = clean_line.lower()
        if "pulling" in line_lower or "%" in clean_line:
            print(f"    {clean_line}", end="\r", flush=True)
        elif any(word in line_lower for word in ["success", "done"]):
            print()
            ui.print_success(f"    {clean_line}")
        elif "error" in line_lower or "ssh:" in line_lower:
            print()
            ui.print_error(f"    {clean_line}")

    return output_lines
```

### Phase 3: Extract Transport Methods

#### 3.1: `_pull_via_cli_with_progress(model_name) -> Tuple[bool, str]`
**Purpose**: Pull model via CLI with progress display
**Current**: Lines 632-938 (combined)
**Benefit**: Clear separation of transport vs display

```python
def _pull_via_cli_with_progress(model_name: str) -> Tuple[bool, str]:
    """
    Pull model via Ollama CLI with progress display.

    Uses rich progress bar if available, falls back to simple output.

    Args:
        model_name: Model to pull (e.g., "gpt-oss:20b")

    Returns:
        Tuple of (success, error_message)
    """
    # Check if rich is available
    try:
        from rich.progress import Progress
        use_rich = True
    except ImportError:
        use_rich = False

    # Create clean environment (remove SSH_AUTH_SOCK for VPN resilience)
    clean_env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}

    # Start subprocess
    process = subprocess.Popen(
        ["ollama", "pull", model_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=clean_env
    )

    try:
        # Monitor progress based on available UI
        if use_rich:
            with _create_rich_progress_bar() as progress:
                task = progress.add_task(f"Pulling {model_name}", total=100)
                output_lines = _monitor_rich_progress(process, model_name, progress, task)
        else:
            output_lines = _monitor_simple_progress(process, model_name)

        # Wait for completion
        if process.poll() is None:
            process.wait(timeout=MODEL_PULL_TIMEOUT)

        # Check result
        if process.returncode == 0:
            return True, ""
        else:
            # Find error in output
            error_msg = ""
            for line in output_lines:
                if any(word in line.lower() for word in ["error", "failed", "ssh:"]):
                    error_msg = line
                    break
            return False, error_msg or "Unknown error during pull"

    except subprocess.TimeoutExpired:
        process.kill()
        try:
            process.wait(timeout=PROCESS_KILL_TIMEOUT)
        except subprocess.TimeoutExpired:
            pass
        return False, f"Timeout after {MODEL_PULL_TIMEOUT}s"

    finally:
        # Cleanup
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=PROCESS_KILL_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
```

#### 3.2: `_pull_via_cli_silent(model_name) -> Tuple[bool, str]`
**Purpose**: Pull model via CLI without progress
**Current**: Lines 940-950
**Benefit**: Separate concern, testable

```python
def _pull_via_cli_silent(model_name: str) -> Tuple[bool, str]:
    """
    Pull model via Ollama CLI without progress display.

    Args:
        model_name: Model to pull

    Returns:
        Tuple of (success, error_message)
    """
    code, stdout, stderr = utils.run_command(
        ["ollama", "pull", model_name],
        timeout=MODEL_PULL_TIMEOUT,
        clean_env=True
    )

    if code == 0:
        return True, ""
    else:
        error_msg = stderr.strip() if stderr else stdout.strip()
        return False, error_msg or "Unknown error during pull"
```

### Phase 4: Simplify Main Function

#### 4.1: New `_pull_model_single_attempt()` (Orchestrator)
**Purpose**: Coordinate pull strategies
**Current**: 377 lines
**Target**: ~40 lines

```python
def _pull_model_single_attempt(
    model_name: str,
    show_progress: bool = True,
    use_api: bool = True
) -> Tuple[bool, str]:
    """
    Execute a single Ollama pull attempt without retries.

    Strategy:
    1. Try API method first (clean JSON progress)
    2. Fall back to CLI with progress display
    3. Or use silent CLI if progress disabled

    Args:
        model_name: Model to pull (e.g., "gpt-oss:20b")
        show_progress: Whether to display progress
        use_api: Whether to try API method first

    Returns:
        Tuple of (success, error_message):
        - success: True if pull succeeded
        - error_message: Error details if failed, empty if successful
    """
    # Try API first (preferred: clean JSON progress)
    if use_api:
        try:
            return _pull_model_via_api(model_name, show_progress)
        except Exception as e:
            if show_progress:
                ui.print_warning(f"API pull failed, falling back to CLI: {e}")

    # Fall back to CLI method
    try:
        if show_progress:
            return _pull_via_cli_with_progress(model_name)
        else:
            return _pull_via_cli_silent(model_name)

    except FileNotFoundError:
        return False, "Ollama command not found - is Ollama installed?"
    except (OSError, IOError, subprocess.SubprocessError) as e:
        return False, f"Process error: {type(e).__name__}: {e}"
```

## Metrics

### Before Refactoring
- **Lines**: 377
- **Functions**: 1
- **Complexity**: Cognitive 71, Cyclomatic 45
- **Nesting**: 7 levels
- **Debug logging**: 8 blocks (~120 lines)
- **Testability**: Low (monolithic, side effects throughout)

### After Refactoring
- **Lines**: ~280 (net -97 lines, -26%)
- **Functions**: 8 (clear responsibilities)
- **Complexity**: Max 8 per function (avg 5)
- **Nesting**: Max 3 levels
- **Debug logging**: 0 (removed per recommendation)
- **Testability**: High (pure functions, mocked I/O)

### Benefits
1. **Reduced complexity**: 71 → <8 per function (-89%)
2. **Better testability**: Each function testable in isolation
3. **Clearer structure**: Single Responsibility Principle
4. **Performance**: -16s debug logging overhead removed
5. **Maintainability**: Easy to understand and modify

## Implementation Order

1. ✅ Create refactoring plan (this document)
2. Create helper functions (`_remove_ansi_codes`, `_parse_ollama_progress`, `_create_rich_progress_bar`)
3. Create progress monitors (`_monitor_rich_progress`, `_monitor_simple_progress`)
4. Create transport methods (`_pull_via_cli_with_progress`, `_pull_via_cli_silent`)
5. Simplify main function (`_pull_model_single_attempt`)
6. Run tests to verify functionality
7. Commit with detailed message

## Testing Strategy

**Unit Tests (New):**
- `test_remove_ansi_codes()` - Test ANSI cleaning
- `test_parse_ollama_progress()` - Test progress parsing with fixtures
- `test_parse_ollama_progress_edge_cases()` - Manifest, errors, completion

**Integration Tests (Existing):**
- Verify end-to-end model pulling still works
- Test progress display (manual verification)
- Test error handling paths

**Verification:**
```bash
# Run existing tests
python3 run_tests.py -k "validator"

# Manual test
python3 -c "from lib.validator import _pull_model_single_attempt; print(_pull_model_single_attempt('all-minilm:latest', show_progress=True))"
```

## Risks & Mitigation

**Risk 1**: Breaking existing functionality
- **Mitigation**: Comprehensive tests, careful extraction

**Risk 2**: Performance regression
- **Mitigation**: Removed debug logging actually *improves* performance

**Risk 3**: Missing edge cases
- **Mitigation**: Preserve all existing logic, just reorganized

## Success Criteria

- [  ] All 8 functions implemented
- [  ] Main function < 50 lines
- [  ] No function > complexity 10
- [  ] All debug logging removed
- [  ] Tests passing
- [  ] Manual verification works

---

**Status**: Ready for implementation
**Estimated effort**: 2-3 hours
**Expected benefit**: -89% complexity, +300% testability
