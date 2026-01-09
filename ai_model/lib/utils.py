"""
General utility functions.

Provides common helper functions used across modules.
"""

import ssl
import subprocess
from typing import List, Tuple

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


def run_command(cmd: List[str], capture: bool = True, timeout: int = 300) -> Tuple[int, str, str]:
    """
    Run a shell command and return the result.
    
    Args:
        cmd: Command to run as a list of strings (e.g., ["docker", "version"])
        capture: Whether to capture stdout/stderr (default: True)
        timeout: Maximum time to wait in seconds (default: 300)
    
    Returns:
        Tuple of (returncode, stdout, stderr):
        - returncode: Process exit code (0 = success, -1 = error)
        - stdout: Standard output as string
        - stderr: Standard error as string
    
    Note:
        On timeout or command not found, returns (-1, "", error_message)
    """
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -1, "", f"Command not found: {cmd[0]}"
    except Exception as e:
        return -1, "", str(e)
