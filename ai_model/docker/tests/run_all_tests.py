#!/usr/bin/env python3
"""
Test runner for Docker Model Runner setup tests.

Runs all unit tests with coverage reporting.

Usage:
    python run_all_tests.py              # Run all tests
    python run_all_tests.py --coverage   # Run with coverage report
    python run_all_tests.py -v           # Verbose output
"""

import argparse
import subprocess
import sys
from pathlib import Path


def main():
    """Run tests with optional coverage."""
    parser = argparse.ArgumentParser(description="Run Docker setup tests")
    parser.add_argument(
        "--coverage", "-c",
        action="store_true",
        help="Generate coverage report"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output"
    )
    parser.add_argument(
        "--html",
        action="store_true",
        help="Generate HTML coverage report"
    )
    parser.add_argument(
        "test_pattern",
        nargs="?",
        default="",
        help="Optional test pattern to match (e.g., test_unit_hardware)"
    )
    
    args = parser.parse_args()
    
    # Change to tests directory
    tests_dir = Path(__file__).parent
    
    # Build pytest command
    cmd = ["python", "-m", "pytest"]
    
    if args.verbose:
        cmd.append("-v")
    
    if args.coverage:
        cmd.extend([
            "--cov=../lib",
            "--cov-report=term-missing",
            "--cov-fail-under=90"
        ])
        
        if args.html:
            cmd.append("--cov-report=html")
    
    # Add test pattern if specified
    if args.test_pattern:
        cmd.append(f"-k {args.test_pattern}")
    
    # Add tests directory
    cmd.append(str(tests_dir))
    
    print(f"Running: {' '.join(cmd)}")
    print("=" * 60)
    
    # Run tests
    result = subprocess.run(cmd, cwd=tests_dir.parent)
    
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
