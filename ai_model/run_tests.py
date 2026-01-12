#!/usr/bin/env python3
"""
Convenient test runner for ai_model tests.

Automatically handles virtual environment setup and dependency installation.
Supports running tests for ollama, docker, or both backends.

Usage:
    python3 run_tests.py                    # Run all tests (both backends)
    python3 run_tests.py --ollama           # Run tests for ollama backend
    python3 run_tests.py --docker           # Run tests for docker backend
    python3 run_tests.py --ollama --docker  # Run both (same as default)
    python3 run_tests.py --unit             # Run only unit tests
    python3 run_tests.py --cov              # Run with coverage
    python3 run_tests.py -v                 # Verbose output
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


# Script directory
SCRIPT_DIR = Path(__file__).parent
VENV_DIR = SCRIPT_DIR / ".venv"
VENV_PYTHON = VENV_DIR / "bin" / "python3"
VENV_PIP = VENV_DIR / "bin" / "pip"
REQUIREMENTS = SCRIPT_DIR / "tests" / "requirements.txt"


def check_venv():
    """Check if virtual environment exists and is valid."""
    return VENV_DIR.exists() and VENV_PYTHON.exists()


def create_venv():
    """Create virtual environment."""
    print("Creating virtual environment...")
    result = subprocess.run(
        [sys.executable, "-m", "venv", str(VENV_DIR)],
        cwd=SCRIPT_DIR,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Error creating virtual environment: {result.stderr}")
        return False
    print("✓ Virtual environment created")
    return True


def install_dependencies():
    """Install test dependencies in virtual environment."""
    if not REQUIREMENTS.exists():
        print(f"Warning: {REQUIREMENTS} not found")
        return True
    
    print("Installing test dependencies...")
    result = subprocess.run(
        [str(VENV_PIP), "install", "-q", "-r", str(REQUIREMENTS)],
        cwd=SCRIPT_DIR,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Error installing dependencies: {result.stderr}")
        return False
    print("✓ Dependencies installed")
    return True


def setup_environment():
    """Ensure virtual environment and dependencies are set up."""
    if not check_venv():
        if not create_venv():
            return False
        if not install_dependencies():
            return False
    else:
        # Check if pytest is installed
        result = subprocess.run(
            [str(VENV_PYTHON), "-m", "pytest", "--version"],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print("Dependencies missing, installing...")
            if not install_dependencies():
                return False
    
    return True


def run_tests(backend=None, unit_only=False, integration_only=False, 
              e2e_only=False, coverage=False, verbose=False, 
              quick=False, filter_expr=None, failfast=False, html_cov=False):
    """Run tests with specified options."""
    
    # Set backend environment variable first
    if backend:
        os.environ['TEST_BACKEND'] = backend
    elif 'TEST_BACKEND' in os.environ:
        del os.environ['TEST_BACKEND']
    
    # Set PYTHONPATH to ensure correct backend is imported
    # This must happen before pytest imports any modules
    if backend == "ollama":
        backend_path = str(SCRIPT_DIR / "ollama")
        docker_path = str(SCRIPT_DIR / "docker")
        # Create PYTHONPATH with parent directory first (for test imports), then backend
        pythonpath_parts = [str(SCRIPT_DIR), backend_path]
        # Add current PYTHONPATH if it exists and doesn't conflict
        existing = os.environ.get('PYTHONPATH', '')
        if existing:
            for p in existing.split(':'):
                if p and docker_path not in p and backend_path not in p and str(SCRIPT_DIR) not in p:
                    pythonpath_parts.append(p)
        os.environ['PYTHONPATH'] = ':'.join(pythonpath_parts)
    elif backend == "docker":
        backend_path = str(SCRIPT_DIR / "docker")
        ollama_path = str(SCRIPT_DIR / "ollama")
        # Create PYTHONPATH with parent directory first (for test imports), then backend
        pythonpath_parts = [str(SCRIPT_DIR), backend_path]
        # Add current PYTHONPATH if it exists and doesn't conflict
        existing = os.environ.get('PYTHONPATH', '')
        if existing:
            for p in existing.split(':'):
                if p and ollama_path not in p and backend_path not in p and str(SCRIPT_DIR) not in p:
                    pythonpath_parts.append(p)
        os.environ['PYTHONPATH'] = ':'.join(pythonpath_parts)
    else:
        # Both backends - don't set PYTHONPATH, let conftest handle it
        if 'PYTHONPATH' in os.environ:
            # Remove backend-specific paths
            pythonpath_parts = []
            ollama_path = str(SCRIPT_DIR / "ollama")
            docker_path = str(SCRIPT_DIR / "docker")
            for p in os.environ['PYTHONPATH'].split(':'):
                if p and ollama_path not in p and docker_path not in p:
                    pythonpath_parts.append(p)
            if pythonpath_parts:
                os.environ['PYTHONPATH'] = ':'.join(pythonpath_parts)
            else:
                del os.environ['PYTHONPATH']
    
    # Build pytest command
    # Use importlib mode to avoid module name conflicts between tests/ and ollama/tests/
    cmd = [str(VENV_PYTHON), "-m", "pytest", "--import-mode=importlib"]
    
    # Test paths
    test_paths = []
    shared_tests = SCRIPT_DIR / "tests"
    ollama_tests = SCRIPT_DIR / "ollama" / "tests"
    docker_tests = SCRIPT_DIR / "docker" / "tests"
    
    # Determine which tests to run
    if backend == "ollama":
        # Shared tests + ollama-specific
        if shared_tests.exists():
            if integration_only:
                test_paths.append(str(shared_tests / "test_integration.py"))
            else:
                # For unit_only or all, pass directory and let pytest filter
                test_paths.append(str(shared_tests))
        
        # Ignore docker tests to avoid conftest conflicts
        cmd.append("--ignore=docker/tests")
        
        if ollama_tests.exists():
            # Pass directory and let pytest discover tests
            # Use -k filter to select specific test types
            test_paths.append(str(ollama_tests))
    elif backend == "docker":
        # Shared tests + docker-specific
        if shared_tests.exists():
            if integration_only:
                test_paths.append(str(shared_tests / "test_integration.py"))
            else:
                test_paths.append(str(shared_tests))
        
        # Ignore ollama tests to avoid conftest conflicts
        cmd.append("--ignore=ollama/tests")
        
        if docker_tests.exists():
            # Pass directory and let pytest discover tests
            # Use -k filter to select specific test types
            test_paths.append(str(docker_tests))
    else:
        # Both backends - just shared tests
        if shared_tests.exists():
            if integration_only:
                test_paths.append(str(shared_tests / "test_integration.py"))
            else:
                test_paths.append(str(shared_tests))
        
        # Ignore backend-specific test dirs when running shared tests
        cmd.extend(["--ignore=ollama/tests", "--ignore=docker/tests"])
    
    if not test_paths:
        print("Error: No test directories found")
        return 1
    
    cmd.extend(test_paths)
    
    # Add test type filtering as pytest arguments
    if unit_only:
        cmd.append("-k")
        cmd.append("test_unit_")
    elif e2e_only:
        cmd.append("-k")
        cmd.append("test_e2e or extended")
    
    # Verbosity
    if verbose:
        cmd.extend(["-v", "--tb=short"])
    else:
        cmd.append("-q")
    
    # Coverage
    if coverage:
        cmd.extend([
            "--cov=ollama/lib",
            "--cov=docker/lib",
            "--cov-report=term-missing",
        ])
        if html_cov:
            cmd.append("--cov-report=html")
    
    # Quick mode
    if quick:
        cmd.extend(["-m", "not slow"])
    
    # Filter
    if filter_expr:
        cmd.extend(["-k", filter_expr])
    
    # Fail fast
    if failfast:
        cmd.append("-x")
    
    # Color output
    cmd.append("--color=yes")
    
    # Ignore collection errors for backend-specific tests if running shared tests
    # This allows shared tests to run even if backend-specific tests have issues
    if backend and shared_tests.exists():
        cmd.append("--continue-on-collection-errors")
    
    # Print header
    print("=" * 70)
    print("ai_model Test Suite")
    print("=" * 70)
    print()
    
    if backend:
        print(f"Backend: {backend}")
    else:
        print("Backend: Both (ollama and docker)")
    
    if unit_only:
        print("Type: Unit tests only")
    elif integration_only:
        print("Type: Integration tests only")
    elif e2e_only:
        print("Type: E2E tests only")
    else:
        print("Type: All tests")
    
    if coverage:
        print("Coverage: Enabled")
    
    print()
    print("-" * 70)
    print()
    
    # Run tests
    result = subprocess.run(cmd, cwd=SCRIPT_DIR)
    
    # Print summary
    print()
    print("-" * 70)
    
    if result.returncode == 0:
        print("✅ All tests passed!")
    else:
        print("❌ Some tests failed")
    
    if coverage and html_cov:
        print()
        print("HTML coverage report: htmlcov/index.html")
    
    return result.returncode


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Run ai_model tests with automatic dependency management",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 run_tests.py --ollama           # Run ollama tests
  python3 run_tests.py --docker           # Run docker tests
  python3 run_tests.py --ollama --unit    # Run ollama unit tests only
  python3 run_tests.py --cov -v           # Run with coverage and verbose
  python3 run_tests.py -k "config"        # Run tests matching "config"
        """
    )
    
    # Backend selection
    parser.add_argument(
        "--ollama",
        action="store_true",
        help="Run tests for ollama backend"
    )
    parser.add_argument(
        "--docker",
        action="store_true",
        help="Run tests for docker backend"
    )
    
    # Test type selection
    parser.add_argument(
        "--unit",
        action="store_true",
        help="Run only unit tests"
    )
    parser.add_argument(
        "--integration",
        action="store_true",
        help="Run only integration tests"
    )
    parser.add_argument(
        "--e2e",
        action="store_true",
        help="Run only E2E tests"
    )
    
    # Other options
    parser.add_argument(
        "--cov", "--coverage",
        action="store_true",
        help="Enable coverage reporting"
    )
    parser.add_argument(
        "--html",
        action="store_true",
        help="Generate HTML coverage report"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output"
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Quick mode (skip slow tests)"
    )
    parser.add_argument(
        "-k", "--filter",
        type=str,
        help="Filter tests by keyword expression"
    )
    parser.add_argument(
        "-x", "--failfast",
        action="store_true",
        help="Stop on first failure"
    )
    
    args = parser.parse_args()
    
    # Determine backend
    backend = None
    if args.ollama and args.docker:
        backend = None  # Both
    elif args.ollama:
        backend = "ollama"
    elif args.docker:
        backend = "docker"
    # else: None (both)
    
    # Setup environment
    print("Setting up test environment...")
    if not setup_environment():
        print("Failed to set up test environment")
        return 1
    print()
    
    # Run tests
    return run_tests(
        backend=backend,
        unit_only=args.unit,
        integration_only=args.integration,
        e2e_only=args.e2e,
        coverage=args.cov,
        verbose=args.verbose,
        quick=args.quick,
        filter_expr=args.filter,
        failfast=args.failfast,
        html_cov=args.html
    )


if __name__ == "__main__":
    sys.exit(main())
