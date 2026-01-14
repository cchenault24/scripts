"""
UI utilities for terminal output and user interaction.

Provides colored terminal output, formatted headers, and interactive prompts.
"""

import os
import platform
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple


# ANSI color codes for terminal output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    BG_BLUE = "\033[44m"
    BG_GREEN = "\033[42m"


_LOG_FILE_PATH: Optional[Path] = None


def init_logging(log_path: Optional[Path] = None) -> Path:
    """
    Initialize file logging for corporate/debug environments.

    Logs all UI output lines to a local file for later troubleshooting.
    """
    global _LOG_FILE_PATH

    if log_path is None:
        log_path = Path.home() / "Library" / "Logs" / "llamacpp" / "setup.log"

    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"\n--- llamacpp setup started {datetime.now().isoformat(timespec='seconds')} ---\n")
        _LOG_FILE_PATH = log_path
    except Exception:
        _LOG_FILE_PATH = None
    return log_path


def _log_line(level: str, text: str) -> None:
    """Best-effort append to log file."""
    if _LOG_FILE_PATH is None:
        return
    try:
        ts = datetime.now().isoformat(timespec="seconds")
        with open(_LOG_FILE_PATH, "a", encoding="utf-8") as f:
            f.write(f"{ts} [{level}] {text}\n")
    except Exception:
        return


def colorize(text: str, color: str) -> str:
    """Apply color to text."""
    return f"{color}{text}{Colors.RESET}"


def print_header(text: str) -> None:
    """Print a styled header."""
    _log_line("HEADER", text)
    width = max(60, len(text) + 10)
    print()
    print(colorize("═" * width, Colors.CYAN))
    print(colorize(f"  {text}", Colors.CYAN + Colors.BOLD))
    print(colorize("═" * width, Colors.CYAN))
    print()


def print_subheader(text: str) -> None:
    """Print a styled subheader."""
    _log_line("SUBHEADER", text)
    print()
    print(colorize(f"▸ {text}", Colors.BLUE + Colors.BOLD))
    print(colorize("─" * 50, Colors.DIM))


def print_success(text: str) -> None:
    """Print success message."""
    _log_line("SUCCESS", text)
    print(colorize(f"✓ {text}", Colors.GREEN))


def print_error(text: str) -> None:
    """Print error message."""
    _log_line("ERROR", text)
    print(colorize(f"✗ {text}", Colors.RED))


def print_warning(text: str) -> None:
    """Print warning message."""
    _log_line("WARNING", text)
    print(colorize(f"⚠ {text}", Colors.YELLOW))


def print_info(text: str) -> None:
    """Print info message."""
    _log_line("INFO", text)
    print(colorize(f"ℹ {text}", Colors.BLUE))


def print_step(step: int, total: int, text: str) -> None:
    """Print a step indicator."""
    _log_line("STEP", text)
    print(colorize(f"[{step}/{total}] {text}", Colors.MAGENTA))


def clear_screen() -> None:
    """Clear the terminal screen."""
    os.system("cls" if platform.system() == "Windows" else "clear")


def prompt_yes_no(question: str, default: bool = True) -> bool:
    """Prompt user for yes/no answer."""
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        response = input(f"{colorize('?', Colors.CYAN)} {question} {colorize(suffix, Colors.DIM)}: ").strip().lower()
        if not response:
            return default
        if response in ("y", "yes"):
            return True
        if response in ("n", "no"):
            return False
        print_warning("Please enter 'y' or 'n'")
