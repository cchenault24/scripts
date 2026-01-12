#!/usr/bin/env python3
"""
Comprehensive test runner for shared ai_model tests.

Runs all unit, integration, and E2E tests with coverage reporting.
Supports both ollama and docker backends via parametrization.

Usage:
    python tests/run_all_tests.py           # Run all tests for both backends
    python tests/run_all_tests.py -v        # Verbose mode
    python tests/run_all_tests.py --cov     # With coverage
    python tests/run_all_tests.py --backend ollama  # Run only ollama tests
    python tests/run_all_tests.py --backend docker  # Run only docker tests
    python tests/run_all_tests.py --quick   # Quick mode (skip slow tests)
"""

import argparse
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))


def main():
    """Run the test suite."""
    parser = argparse.ArgumentParser(
        description="Run shared ai_model test suite"
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Verbose output'
    )
    parser.add_argument(
        '--cov', '--coverage',
        action='store_true',
        help='Enable coverage reporting'
    )
    parser.add_argument(
        '--html',
        action='store_true',
        help='Generate HTML coverage report'
    )
    parser.add_argument(
        '--quick',
        action='store_true',
        help='Quick mode (skip slow tests)'
    )
    parser.add_argument(
        '--unit',
        action='store_true',
        help='Run only unit tests'
    )
    parser.add_argument(
        '--integration',
        action='store_true',
        help='Run only integration tests'
    )
    parser.add_argument(
        '--backend',
        choices=['ollama', 'docker'],
        help='Run tests for specific backend only'
    )
    parser.add_argument(
        '-k', '--filter',
        type=str,
        help='Filter tests by keyword expression'
    )
    parser.add_argument(
        '--failfast', '-x',
        action='store_true',
        help='Stop on first failure'
    )
    
    args = parser.parse_args()
    
    # Try to import pytest
    try:
        import pytest
    except ImportError:
        print("Error: pytest is required to run tests")
        print("Install with: pip install pytest pytest-cov")
        return 1
    
    # Build pytest arguments
    pytest_args = []
    
    # Test directory
    test_dir = Path(__file__).parent
    
    # Determine which tests to run
    if args.unit:
        pytest_args.append(str(test_dir / "test_unit_*.py"))
    elif args.integration:
        pytest_args.append(str(test_dir / "test_integration.py"))
    else:
        pytest_args.append(str(test_dir))
    
    # Backend filtering
    if args.backend:
        pytest_args.extend(['-k', f'backend_type == "{args.backend}" or not backend_type'])
    else:
        # Run both backends (default behavior with parametrization)
        pass
    
    # Verbosity
    if args.verbose:
        pytest_args.extend(['-v', '--tb=short'])
    else:
        pytest_args.append('-q')
    
    # Coverage
    if args.cov:
        # Coverage for both backends
        pytest_args.extend([
            '--cov=../ollama/lib',
            '--cov=../docker/lib',
            '--cov-report=term-missing',
        ])
        if args.html:
            pytest_args.append('--cov-report=html')
    
    # Quick mode
    if args.quick:
        pytest_args.extend(['-m', 'not slow'])
    
    # Filter
    if args.filter:
        pytest_args.extend(['-k', args.filter])
    
    # Fail fast
    if args.failfast:
        pytest_args.append('-x')
    
    # Color output
    pytest_args.append('--color=yes')
    
    # Print header
    print("=" * 60)
    print("Shared ai_model Test Suite")
    print("=" * 60)
    print()
    
    if args.unit:
        print("Running: Unit tests only")
    elif args.integration:
        print("Running: Integration tests only")
    else:
        print("Running: All tests")
    
    if args.backend:
        print(f"Backend: {args.backend} only")
    else:
        print("Backend: Both (ollama and docker)")
    
    if args.cov:
        print("Coverage: Enabled")
    
    print()
    print("-" * 60)
    print()
    
    # Run pytest
    result = pytest.main(pytest_args)
    
    # Print summary
    print()
    print("-" * 60)
    
    if result == 0:
        print("✅ All tests passed!")
    else:
        print("❌ Some tests failed")
    
    if args.cov and args.html:
        print()
        print("HTML coverage report generated in: htmlcov/index.html")
    
    return result


if __name__ == '__main__':
    sys.exit(main())
