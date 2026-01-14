"""
General utility functions.

Provides common helper functions used across modules.
"""

import hashlib
import os
import ssl
import subprocess
from pathlib import Path
from typing import List, Optional, Tuple

try:
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False


def ensure_rich_installed() -> bool:
    """
    Ensure Rich is installed, installing it if necessary.
    
    Returns:
        True if Rich is available (either was already installed or just installed)
    """
    global RICH_AVAILABLE
    
    if RICH_AVAILABLE:
        return True
    
    # Try to install Rich
    try:
        import subprocess
        import sys
        
        code, _, stderr = run_command(
            [sys.executable, "-m", "pip", "install", "rich>=13.0.0"],
            timeout=120
        )
        
        if code == 0:
            # Try importing again
            try:
                from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn
                RICH_AVAILABLE = True
                return True
            except ImportError:
                return False
        else:
            return False
    except Exception:
        return False


def ensure_huggingface_hub_installed() -> bool:
    """
    Ensure huggingface_hub is installed, installing it if necessary.
    
    Returns:
        True if huggingface_hub is available (either was already installed or just installed)
    """
    try:
        import huggingface_hub
        return True
    except ImportError:
        try:
            import subprocess
            import sys
            
            from . import ui
            ui.print_info("Installing huggingface_hub...")
            
            code, stdout, stderr = run_command(
                [sys.executable, "-m", "pip", "install", "huggingface_hub>=0.20.0", "--quiet"],
                timeout=120
            )
            
            if code == 0:
                try:
                    import huggingface_hub
                    ui.print_success("huggingface_hub installed")
                    return True
                except ImportError:
                    ui.print_warning("huggingface_hub installed but import failed")
                    return False
            else:
                ui.print_warning(f"Failed to install huggingface_hub: {stderr}")
                return False
        except Exception as e:
            ui.print_warning(f"Error installing huggingface_hub: {e}")
            return False


# SSL context that skips certificate verification (equivalent to curl -k)
_UNVERIFIED_SSL_CONTEXT: Optional[ssl.SSLContext] = None


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
            _UNVERIFIED_SSL_CONTEXT = ssl.create_default_context()
            _UNVERIFIED_SSL_CONTEXT.check_hostname = False
            _UNVERIFIED_SSL_CONTEXT.verify_mode = ssl.CERT_NONE
    return _UNVERIFIED_SSL_CONTEXT


def run_command(
    cmd: List[str], 
    capture: bool = True, 
    timeout: int = 300,
    clean_env: bool = False,
    cwd: Optional[str] = None,
    show_progress: bool = False
) -> Tuple[int, str, str]:
    """
    Run a shell command and return the result.
    
    Args:
        cmd: Command to run as a list of strings
        capture: Whether to capture stdout/stderr (default: True)
        timeout: Maximum time to wait in seconds (default: 300)
        clean_env: If True, remove SSH_AUTH_SOCK from environment
        cwd: Working directory for command (default: None)
        show_progress: If True, show real-time output (default: False)
    
    Returns:
        Tuple of (returncode, stdout, stderr)
    """
    try:
        if clean_env:
            env = {k: v for k, v in os.environ.items() if k != 'SSH_AUTH_SOCK'}
        else:
            env = None
        
        if show_progress:
            # Ensure Rich is available
            ensure_rich_installed()
            
            # Show progress with Rich if available, otherwise show real-time output
            if RICH_AVAILABLE:
                import re
                
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    env=env,
                    cwd=cwd,
                    bufsize=1
                )
                
                stdout_lines = []
                with Progress(
                    SpinnerColumn(),
                    TextColumn("[progress.description]{task.description}"),
                    BarColumn(),
                    TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                    TimeElapsedColumn(),
                    transient=True,
                ) as progress:
                    task = progress.add_task("Building...", total=100)
                    
                    for line in process.stdout:
                        line = line.rstrip()
                        if line:
                            # Extract percentage from CMake output (e.g., "[ 31%] Building...")
                            percent_match = re.search(r'\[\s*(\d+)%\]', line)
                            if percent_match:
                                percent = int(percent_match.group(1))
                                progress.update(task, completed=percent)
                            
                            # Update description with current build step (truncate long lines)
                            if len(line) > 60:
                                description = line[:57] + "..."
                            else:
                                description = line
                            progress.update(task, description=description)
                            
                            stdout_lines.append(line)
                    
                    process.wait()
                    progress.update(task, completed=100)
                
                stdout = "\n".join(stdout_lines)
                return process.returncode, stdout, ""
            else:
                # Fallback to simple real-time output
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    env=env,
                    cwd=cwd,
                    bufsize=1
                )
                
                stdout_lines = []
                for line in process.stdout:
                    line = line.rstrip()
                    if line:
                        print(f"  {line}")
                        stdout_lines.append(line)
                
                process.wait()
                stdout = "\n".join(stdout_lines)
                return process.returncode, stdout, ""
        else:
            result = subprocess.run(
                cmd,
                capture_output=capture,
                text=True,
                timeout=timeout,
                env=env,
                cwd=cwd
            )
            return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)


def calculate_sha256(file_path: Path) -> str:
    """
    Calculate SHA256 hash of a file.
    
    Args:
        file_path: Path to the file
    
    Returns:
        SHA256 hash as hexadecimal string
    """
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def format_bytes(bytes_count: int) -> str:
    """
    Format bytes to human-readable string.
    
    Args:
        bytes_count: Number of bytes
    
    Returns:
        Formatted string (e.g., "1.5 GB")
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_count < 1024.0:
            return f"{bytes_count:.2f} {unit}"
        bytes_count /= 1024.0
    return f"{bytes_count:.2f} PB"


def ensure_directory(path: Path) -> None:
    """
    Ensure a directory exists, creating it if necessary.
    
    Args:
        path: Path to the directory
    """
    path.mkdir(parents=True, exist_ok=True)
