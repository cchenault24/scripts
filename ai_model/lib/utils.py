"""
General utility functions.

Provides common helper functions used across modules.
"""

import hashlib
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import List, Optional, Tuple

# SSL context that skips certificate verification (equivalent to curl -k)
# Needed for work machines with corporate proxies/interception
# This is a module-level variable that's created once and reused
_UNVERIFIED_SSL_CONTEXT: ssl.SSLContext | None = None


def get_unverified_ssl_context() -> ssl.SSLContext:
    """
    Get an SSL context that skips certificate verification.
    
    This is useful for work machines with corporate proxies/interception.
    Equivalent to curl -k flag.
    
    Returns:
        SSL context with verification disabled
    """
    global _UNVERIFIED_SSL_CONTEXT
    if _UNVERIFIED_SSL_CONTEXT is None:
        try:
            _UNVERIFIED_SSL_CONTEXT = ssl._create_unverified_context()
        except Exception:
            # Fallback: create a default context and disable verification
            _UNVERIFIED_SSL_CONTEXT = ssl.create_default_context()
            _UNVERIFIED_SSL_CONTEXT.check_hostname = False
            _UNVERIFIED_SSL_CONTEXT.verify_mode = ssl.CERT_NONE
    return _UNVERIFIED_SSL_CONTEXT


def run_command(
    cmd: List[str], 
    capture: bool = True, 
    timeout: int = 300,
    clean_env: bool = False
) -> Tuple[int, str, str]:
    """
    Run a shell command and return the result.
    
    Args:
        cmd: Command to run as a list of strings (e.g., ["ollama", "list"])
        capture: Whether to capture stdout/stderr (default: True)
        timeout: Maximum time to wait in seconds (default: 300)
        clean_env: If True, remove SSH_AUTH_SOCK from environment (default: False)
                   Use this when calling Ollama to prevent Go HTTP client issues.
    
    Returns:
        Tuple of (returncode, stdout, stderr):
        - returncode: Process exit code (0 = success, -1 = error)
        - stdout: Standard output as string
        - stderr: Standard error as string
    
    Note:
        On timeout or command not found, returns (-1, "", error_message)
    """
    try:
        # Determine environment
        if clean_env:
            # Remove SSH_AUTH_SOCK to prevent Go HTTP client issues in Ollama
            env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}
        else:
            env = None  # Use current environment
        
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout,
            env=env  # Pass custom environment if clean_env=True
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)


def stream_command_output(
    cmd: List[str],
    keywords: Optional[List[str]] = None,
    show_progress: bool = True,
    timeout: Optional[int] = None,
    cwd: Optional[Path] = None
) -> Tuple[int, List[str]]:
    """
    Execute command with real-time streamed output.

    Args:
        cmd: Command and arguments as list
        keywords: Optional list of keywords to filter output (case-insensitive)
        show_progress: Whether to display filtered output to user
        timeout: Optional timeout in seconds
        cwd: Optional working directory

    Returns:
        Tuple of (return_code, output_lines)

    Example:
        >>> code, lines = stream_command_output(
        ...     ["brew", "install", "git"],
        ...     keywords=["downloading", "installing", "error"],
        ...     timeout=300
        ... )
    """
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=str(cwd) if cwd else None
        )

        output_lines = []
        start_time = time.time()

        for line in process.stdout:
            output_lines.append(line)

            # Check timeout
            if timeout and (time.time() - start_time) > timeout:
                process.kill()
                raise subprocess.TimeoutExpired(cmd, timeout)

            # Display filtered output
            if show_progress:
                if keywords is None:
                    # Show all output
                    print(f"  {line.rstrip()}")
                else:
                    # Filter by keywords (case-insensitive)
                    if any(keyword.lower() in line.lower() for keyword in keywords):
                        print(f"  {line.rstrip()}")

        process.wait()
        return process.returncode, output_lines

    except subprocess.TimeoutExpired:
        return -1, output_lines
    except Exception as e:
        return -1, [str(e)]


def render_progress_bar(
    label: str,
    percent: int,
    bar_length: int = 40,
    update_in_place: bool = True
) -> None:
    """
    Render terminal progress bar.

    Args:
        label: Text label for the progress bar
        percent: Progress percentage (0-100)
        bar_length: Width of the bar in characters
        update_in_place: If True, update in place with \\r; else print new line

    Example:
        >>> for i in range(0, 101, 10):
        ...     render_progress_bar("Downloading", i)
        ...     time.sleep(0.1)
    """
    filled = int(bar_length * percent / 100)
    bar = '█' * filled + '░' * (bar_length - filled)
    prefix = "\r" if update_in_place else "\n"
    sys.stdout.write(f"{prefix}  {label} {bar} {percent}%")
    sys.stdout.flush()

    if percent >= 100 and update_in_place:
        sys.stdout.write("\n")
        sys.stdout.flush()


def create_secure_temp_dir(prefix: str = "ai_model") -> Path:
    """
    Create temporary directory with secure permissions.

    Args:
        prefix: Prefix for directory name

    Returns:
        Path to created directory

    Raises:
        SecurityError: If directory cannot be created securely

    Security:
        - Uses tempfile.mkdtemp for atomic creation
        - Sets permissions to 0700 (owner read/write/execute only)
        - Validates ownership
    """
    # Create with secure permissions atomically
    temp_dir = tempfile.mkdtemp(prefix=f"{prefix}-")
    temp_path = Path(temp_dir)

    # Verify ownership
    stat_info = temp_path.stat()
    if stat_info.st_uid != os.getuid():
        temp_path.rmdir()
        raise SecurityError("Temp directory not owned by current user")

    # Ensure only owner can access (mode 0700)
    temp_path.chmod(0o700)

    return temp_path


def create_secure_temp_file(prefix: str = "ai_model", suffix: str = "") -> Path:
    """
    Create temporary file with secure permissions.

    Args:
        prefix: Prefix for file name
        suffix: Suffix for file name (e.g., ".sh")

    Returns:
        Path to created file

    Security:
        - Uses tempfile.mkstemp for atomic creation
        - Sets permissions to 0600 (owner read/write only)
    """
    fd, temp_path_str = tempfile.mkstemp(prefix=f"{prefix}-", suffix=suffix)

    # Close the file descriptor immediately
    os.close(fd)

    # Set secure permissions (0600 - owner read/write only)
    temp_file = Path(temp_path_str)
    temp_file.chmod(0o600)

    return temp_file


def safe_rmtree(path: Path) -> None:
    """
    Remove directory tree with symlink protection.

    Args:
        path: Directory to remove

    Raises:
        SecurityError: If path contains symlinks

    Security:
        - Checks for symlinks before deletion
        - Prevents symlink attacks
    """
    if not path.exists():
        return

    if path.is_symlink():
        raise SecurityError(f"Refusing to follow symlink: {path}")

    if not path.is_dir():
        raise SecurityError(f"Path is not a directory: {path}")

    # Check all entries for symlinks before deletion
    for item in path.rglob("*"):
        if item.is_symlink():
            raise SecurityError(f"Directory contains symlink: {item}")

    # Safe to remove
    shutil.rmtree(path)


def backup_file_if_exists(path: Path, force: bool = False) -> Optional[Path]:
    """
    Create timestamped backup of existing file.

    Args:
        path: File to backup
        force: If False, only backup if file exists

    Returns:
        Backup path if created, None otherwise

    Example:
        >>> backup = backup_file_if_exists(Path("~/.opencode/bin/opencode"), force=True)
        >>> print(f"Backed up to: {backup}")
    """
    if not path.exists() or not force:
        return None

    import datetime
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = path.with_suffix(f".backup.{timestamp}")

    shutil.copy(path, backup)
    return backup


def verify_file_checksum(file_path: Path, expected_sha256: str) -> bool:
    """
    Verify file SHA-256 checksum.

    Args:
        file_path: File to verify
        expected_sha256: Expected SHA-256 hash (hex string)

    Returns:
        True if checksum matches, False otherwise

    Example:
        >>> if verify_file_checksum(model_file, "abc123..."):
        ...     print("Checksum verified!")
    """
    sha256 = hashlib.sha256()

    with open(file_path, 'rb') as f:
        # Read in chunks to handle large files
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)

    actual = sha256.hexdigest()
    return actual.lower() == expected_sha256.lower()


def safely_add_to_path(bin_dir: Path) -> bool:
    """
    Safely add directory to PATH with security validation.

    Args:
        bin_dir: Directory to add to PATH

    Returns:
        True if added successfully, False if validation failed

    Security:
        - Validates directory ownership
        - Checks permissions (rejects world-writable)
        - Prevents duplicates

    Example:
        >>> if safely_add_to_path(Path.home() / ".bun" / "bin"):
        ...     print("Added to PATH safely")
    """
    # Verify directory exists
    if not bin_dir.exists():
        return False

    # Verify ownership (must be current user or root)
    stat_info = bin_dir.stat()
    current_uid = os.getuid()

    if stat_info.st_uid not in [current_uid, 0]:
        from . import ui
        ui.print_error(f"Security: {bin_dir} is owned by UID {stat_info.st_uid}, not you ({current_uid})")
        return False

    # Verify permissions (must not be world-writable)
    mode = stat_info.st_mode
    if mode & 0o002:  # World-writable bit
        from . import ui
        ui.print_error(f"Security: {bin_dir} is world-writable (mode {oct(mode)})")
        return False

    # Check if already in PATH (avoid duplicates)
    current_path = os.environ.get("PATH", "")
    if str(bin_dir) in current_path.split(":"):
        return True  # Already present

    # Safe to add
    os.environ["PATH"] = f"{bin_dir}:{current_path}"
    return True


def validate_repo_id(repo_id: str) -> bool:
    """
    Validate HuggingFace repository ID format.

    Args:
        repo_id: Repository ID (e.g., "ggml-org/gemma-4-26B-it-GGUF")

    Returns:
        True if valid format, False otherwise

    Security:
        - Prevents command injection via malformed repo IDs
        - Enforces org/repo-name format
    """
    pattern = r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$'
    return bool(re.match(pattern, repo_id))


def validate_filename(filename: str) -> bool:
    """
    Validate filename for security.

    Args:
        filename: Filename to validate

    Returns:
        True if safe filename, False otherwise

    Security:
        - Prevents path traversal (../, /)
        - Rejects special characters
        - Enforces whitelist pattern
    """
    # Check for path traversal
    if any(char in filename for char in ['/', '\\', '\0']):
        return False

    if filename.startswith('.') or '..' in filename:
        return False

    # Whitelist approach for GGUF files
    pattern = r'^[a-zA-Z0-9_.-]+\.gguf$'
    return bool(re.match(pattern, filename))


def retry_with_backoff(
    func,
    max_retries: int = 3,
    initial_delay: float = 1.0,
    backoff_factor: float = 2.0,
    exceptions: Tuple = (Exception,)
):
    """
    Retry function with exponential backoff.

    Args:
        func: Function to retry
        max_retries: Maximum number of retry attempts
        initial_delay: Initial delay in seconds
        backoff_factor: Multiplier for delay after each retry
        exceptions: Tuple of exceptions to catch and retry

    Returns:
        Result of successful function call

    Raises:
        Last exception if all retries fail

    Example:
        >>> result = retry_with_backoff(
        ...     lambda: download_file(url),
        ...     max_retries=3,
        ...     exceptions=(IOError, TimeoutError)
        ... )
    """
    delay = initial_delay
    last_exception = None

    for attempt in range(max_retries):
        try:
            return func()
        except exceptions as e:
            last_exception = e
            if attempt < max_retries - 1:
                time.sleep(delay)
                delay *= backoff_factor

    # All retries failed
    raise last_exception


class SecurityError(Exception):
    """Raised when security validation fails."""
    pass
