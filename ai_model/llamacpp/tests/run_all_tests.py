#!/usr/bin/env python3
"""
Run all tests for llama.cpp server setup.

Usage:
    python run_all_tests.py
    python run_all_tests.py --coverage
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest

if __name__ == "__main__":
    # Check for coverage flag
    coverage = "--coverage" in sys.argv or "-c" in sys.argv
    
    if coverage:
        # Run with coverage
        pytest_args = [
            "--cov=lib",
            "--cov-report=html",
            "--cov-report=term-missing",
            "--cov-report=xml",
            "-v",
            "."
        ]
    else:
        pytest_args = ["-v", "."]
    
    exit_code = pytest.main(pytest_args)
    sys.exit(exit_code)
