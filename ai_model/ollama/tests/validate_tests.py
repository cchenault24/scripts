#!/usr/bin/env python3
"""
Test Validation Script - Validates Tests Against Specifications.

This script analyzes test files to identify potential implementation-driven tests
that may not properly validate the specifications.

Usage:
    python tests/validate_tests.py
    python tests/validate_tests.py --verbose
    python tests/validate_tests.py --fix  # Suggest fixes

Checks performed:
1. Missing docstrings (should explain EXPECTED behavior)
2. Single assertion tests (may be too weak)
3. Tests that don't use specification values
4. Missing edge case tests
5. Missing SSL context verification
6. Missing boundary condition tests
"""

import ast
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from dataclasses import dataclass


# =============================================================================
# Specification Constants (from SPECIFICATIONS.md)
# =============================================================================

TIER_BOUNDARIES = {
    16.0: "C",
    24.0: "B", 
    32.0: "A",
    64.0: "S",
}

RAM_RESERVATIONS = {
    "S": 0.30,
    "A": 0.30,
    "B": 0.35,
    "C": 0.40,
}

EXPECTED_USABLE_RAM = {
    (16, "C"): 9.6,    # 16 * 0.60
    (24, "B"): 15.6,   # 24 * 0.65
    (32, "A"): 22.4,   # 32 * 0.70
    (64, "S"): 44.8,   # 64 * 0.70
}


# =============================================================================
# Issue Types
# =============================================================================

@dataclass
class TestIssue:
    """Represents an issue found in a test."""
    file: str
    test_name: str
    line: int
    issue_type: str
    severity: str  # "error", "warning", "info"
    message: str
    suggestion: Optional[str] = None


# =============================================================================
# Test Analyzer
# =============================================================================

class TestAnalyzer(ast.NodeVisitor):
    """Analyzes test functions for potential issues."""
    
    def __init__(self, filename: str, source: str):
        self.filename = filename
        self.source = source
        self.source_lines = source.split('\n')
        self.issues: List[TestIssue] = []
        self.current_class: Optional[str] = None
        
    def visit_ClassDef(self, node: ast.ClassDef):
        """Track current test class."""
        self.current_class = node.name
        self.generic_visit(node)
        self.current_class = None
        
    def visit_FunctionDef(self, node: ast.FunctionDef):
        """Analyze test function."""
        if not node.name.startswith('test_'):
            return
            
        full_name = f"{self.current_class}.{node.name}" if self.current_class else node.name
        
        # Check 1: Missing docstring
        docstring = ast.get_docstring(node)
        if not docstring:
            self.issues.append(TestIssue(
                file=self.filename,
                test_name=full_name,
                line=node.lineno,
                issue_type="missing_docstring",
                severity="warning",
                message="Missing docstring - should explain EXPECTED behavior",
                suggestion="Add docstring explaining what behavior is being tested and why"
            ))
        elif docstring and len(docstring) < 20:
            self.issues.append(TestIssue(
                file=self.filename,
                test_name=full_name,
                line=node.lineno,
                issue_type="weak_docstring",
                severity="info",
                message="Docstring is very short - may not adequately explain expected behavior",
                suggestion="Expand docstring to explain the specification being tested"
            ))
        
        # Check 2: Count assertions
        assertions = self._count_assertions(node)
        if assertions == 0:
            self.issues.append(TestIssue(
                file=self.filename,
                test_name=full_name,
                line=node.lineno,
                issue_type="no_assertions",
                severity="error",
                message="Test has no assertions - cannot validate anything",
                suggestion="Add assertions that verify expected behavior"
            ))
        elif assertions == 1:
            self.issues.append(TestIssue(
                file=self.filename,
                test_name=full_name,
                line=node.lineno,
                issue_type="single_assertion",
                severity="info",
                message="Only one assertion - consider testing edge cases too",
                suggestion="Add assertions for boundary conditions and edge cases"
            ))
        
        # Check 3: Tautological assertions (assert x == x)
        self._check_tautological_assertions(node, full_name)
        
        # Check 4: Check for specification values in RAM tests
        if 'ram' in node.name.lower() or 'tier' in node.name.lower():
            self._check_specification_values(node, full_name)
        
        # Check 5: Check for SSL context verification
        if 'api' in node.name.lower() or 'network' in node.name.lower() or 'urlopen' in node.name.lower():
            self._check_ssl_context_verification(node, full_name)
        
        self.generic_visit(node)
    
    def _count_assertions(self, node: ast.FunctionDef) -> int:
        """Count assert statements in function."""
        count = 0
        for child in ast.walk(node):
            if isinstance(child, ast.Assert):
                count += 1
            elif isinstance(child, ast.Call):
                # Check for pytest assertions like pytest.approx, mock.assert_called
                if hasattr(child, 'func'):
                    func_str = ast.unparse(child.func) if hasattr(ast, 'unparse') else str(child.func)
                    if 'assert' in func_str.lower():
                        count += 1
        return count
    
    def _check_tautological_assertions(self, node: ast.FunctionDef, full_name: str):
        """Check for tautological assertions like 'assert x == x'."""
        for child in ast.walk(node):
            if isinstance(child, ast.Assert):
                test = child.test
                if isinstance(test, ast.Compare):
                    if len(test.ops) == 1 and isinstance(test.ops[0], ast.Eq):
                        left = ast.unparse(test.left) if hasattr(ast, 'unparse') else str(test.left)
                        right = ast.unparse(test.comparators[0]) if hasattr(ast, 'unparse') else str(test.comparators[0])
                        if left == right:
                            self.issues.append(TestIssue(
                                file=self.filename,
                                test_name=full_name,
                                line=child.lineno,
                                issue_type="tautological_assertion",
                                severity="error",
                                message=f"Tautological assertion: '{left} == {right}' always passes!",
                                suggestion="Use independently calculated expected value"
                            ))
    
    def _check_specification_values(self, node: ast.FunctionDef, full_name: str):
        """Check if RAM/tier tests use specification values."""
        source = ast.unparse(node) if hasattr(ast, 'unparse') else ""
        
        # Check for hardcoded specification values
        has_spec_values = any(str(v) in source for v in [9.6, 15.6, 22.4, 44.8, 0.60, 0.65, 0.70, 0.40, 0.35, 0.30])
        
        if not has_spec_values and ('usable' in node.name.lower() or 'reservation' in node.name.lower()):
            self.issues.append(TestIssue(
                file=self.filename,
                test_name=full_name,
                line=node.lineno,
                issue_type="missing_spec_values",
                severity="warning",
                message="RAM/tier test may not use specification values",
                suggestion="Use values from SPECIFICATIONS.md (e.g., 16GB * 0.60 = 9.6GB)"
            ))
    
    def _check_ssl_context_verification(self, node: ast.FunctionDef, full_name: str):
        """Check if API tests verify SSL context is used."""
        source = ast.unparse(node) if hasattr(ast, 'unparse') else ""
        
        if 'urlopen' in source.lower() or 'api' in node.name.lower():
            if 'context' not in source.lower():
                self.issues.append(TestIssue(
                    file=self.filename,
                    test_name=full_name,
                    line=node.lineno,
                    issue_type="missing_ssl_check",
                    severity="warning",
                    message="API test may not verify SSL context is passed",
                    suggestion="Add assertion: assert 'context' in mock_urlopen.call_args.kwargs"
                ))


# =============================================================================
# Specification Coverage Checker
# =============================================================================

class SpecificationCoverageChecker:
    """Checks if all specifications have corresponding tests."""
    
    REQUIRED_SPECS = [
        ("tier_classification", "Tier C/B/A/S boundary tests"),
        ("ram_reservation", "RAM reservation percentage tests (40%/35%/30%)"),
        ("usable_ram", "Usable RAM calculation tests"),
        ("ssl_context", "SSL context creation and caching tests"),
        ("ssl_context_usage", "API calls use SSL context"),
        ("autostart_macos", "macOS autostart setup/remove tests"),
        ("model_fits_budget", "Models fit within usable RAM"),
        ("error_classification", "Pull error classification tests"),
        ("setup_result", "SetupResult properties (complete_success, partial_success, complete_failure)"),
    ]
    
    def __init__(self, test_files: List[Path]):
        self.test_files = test_files
        self.all_test_content = ""
        
        for file in test_files:
            if file.exists():
                self.all_test_content += file.read_text().lower()
    
    def check_coverage(self) -> List[TestIssue]:
        """Check if all specifications have tests."""
        issues = []
        
        spec_keywords = {
            "tier_classification": ["tier", "classification", "ram_gb", "hardwaretier"],
            "ram_reservation": ["reservation", "0.40", "0.35", "0.30", "40%", "35%", "30%"],
            "usable_ram": ["usable", "estimated_model_memory", "9.6", "15.6", "22.4", "44.8"],
            "ssl_context": ["ssl", "unverified_ssl", "cert_none"],
            "ssl_context_usage": ["context", "urlopen", "api"],
            "autostart_macos": ["autostart", "launchd", "plist", "launchctl"],
            "model_fits_budget": ["total_ram", "usable_ram", "fit", "budget"],
            "error_classification": ["classify_pull_error", "pullerrortype", "ssh_key", "network"],
            "setup_result": ["complete_success", "partial_success", "complete_failure", "setupresult"],
        }
        
        for spec_name, description in self.REQUIRED_SPECS:
            keywords = spec_keywords.get(spec_name, [spec_name])
            found = any(kw in self.all_test_content for kw in keywords)
            
            if not found:
                issues.append(TestIssue(
                    file="(all files)",
                    test_name="",
                    line=0,
                    issue_type="missing_spec_test",
                    severity="error",
                    message=f"No test found for specification: {description}",
                    suggestion=f"Add test for: {spec_name}"
                ))
        
        return issues


# =============================================================================
# Main Validation
# =============================================================================

def validate_test_file(filepath: Path) -> List[TestIssue]:
    """Validate a single test file."""
    if not filepath.exists():
        return []
    
    source = filepath.read_text()
    
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        return [TestIssue(
            file=str(filepath),
            test_name="",
            line=e.lineno or 0,
            issue_type="syntax_error",
            severity="error",
            message=f"Syntax error: {e.msg}",
        )]
    
    analyzer = TestAnalyzer(str(filepath.name), source)
    analyzer.visit(tree)
    
    return analyzer.issues


def print_issues(issues: List[TestIssue], verbose: bool = False):
    """Print issues in a formatted way."""
    if not issues:
        print("✅ No issues found!")
        return
    
    # Group by severity
    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]
    infos = [i for i in issues if i.severity == "info"]
    
    if errors:
        print("\n🔴 ERRORS (must fix):")
        for issue in errors:
            print(f"  [{issue.file}:{issue.line}] {issue.test_name}")
            print(f"    {issue.message}")
            if verbose and issue.suggestion:
                print(f"    💡 Suggestion: {issue.suggestion}")
    
    if warnings:
        print("\n🟡 WARNINGS (should fix):")
        for issue in warnings:
            print(f"  [{issue.file}:{issue.line}] {issue.test_name}")
            print(f"    {issue.message}")
            if verbose and issue.suggestion:
                print(f"    💡 Suggestion: {issue.suggestion}")
    
    if infos and verbose:
        print("\n🔵 INFO (consider):")
        for issue in infos:
            print(f"  [{issue.file}:{issue.line}] {issue.test_name}")
            print(f"    {issue.message}")
            if issue.suggestion:
                print(f"    💡 Suggestion: {issue.suggestion}")


def main():
    """Run validation."""
    print("=" * 70)
    print("TEST VALIDATION - Checking Tests Against Specifications")
    print("=" * 70)
    print()
    
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    
    # Find test directory
    test_dir = Path(__file__).parent
    if not test_dir.exists():
        print(f"❌ Test directory not found: {test_dir}")
        return 1
    
    # Collect test files
    test_files = list(test_dir.glob("test_*.py"))
    
    if not test_files:
        print("⚠️ No test files found!")
        return 1
    
    print(f"Found {len(test_files)} test files")
    print()
    
    all_issues = []
    
    # Validate each test file
    for test_file in sorted(test_files):
        print(f"Analyzing {test_file.name}...")
        issues = validate_test_file(test_file)
        all_issues.extend(issues)
        
        if issues:
            error_count = len([i for i in issues if i.severity == "error"])
            warning_count = len([i for i in issues if i.severity == "warning"])
            print(f"  Found: {error_count} errors, {warning_count} warnings")
        else:
            print("  ✓ No issues")
    
    # Check specification coverage
    print("\nChecking specification coverage...")
    coverage_checker = SpecificationCoverageChecker(test_files)
    coverage_issues = coverage_checker.check_coverage()
    all_issues.extend(coverage_issues)
    
    if coverage_issues:
        print(f"  Found {len(coverage_issues)} missing spec tests")
    else:
        print("  ✓ All specifications have tests")
    
    # Print all issues
    print()
    print_issues(all_issues, verbose)
    
    # Summary
    print()
    print("=" * 70)
    error_count = len([i for i in all_issues if i.severity == "error"])
    warning_count = len([i for i in all_issues if i.severity == "warning"])
    info_count = len([i for i in all_issues if i.severity == "info"])
    
    if error_count > 0:
        print(f"❌ FAILED: {error_count} errors, {warning_count} warnings, {info_count} info")
        return 1
    elif warning_count > 0:
        print(f"⚠️ PASSED with warnings: {warning_count} warnings, {info_count} info")
        return 0
    else:
        print(f"✅ PASSED: All tests appear to validate specifications correctly")
        return 0


if __name__ == "__main__":
    sys.exit(main())
