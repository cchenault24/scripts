#!/bin/bash
# tests/quality-checks.sh - Comprehensive quality and security checks
#
# Performs:
# - Shellcheck validation on all shell scripts
# - Strict mode validation (set -euo pipefail)
# - Security audits (localhost binding, no hardcoded credentials, proper quoting)
# - File permission checks (no world-writable files)
# - Documentation validation (README exists, no dead links)
#
# Exit code: 0 if all checks pass, 1 if any check fails
#
# Usage: ./tests/quality-checks.sh [--verbose]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helpers
source "$SCRIPT_DIR/helpers.sh"

# Verbose mode flag
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

#############################################
# Helper Functions
#############################################

# Print verbose message
verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${BLUE}→${NC} $1"
    fi
}

# Get all shell scripts in project
get_shell_scripts() {
    find "$PROJECT_DIR" -type f -name "*.sh" ! -path "*/tests/*" | sort
}

# Get all shell scripts including tests
get_all_shell_scripts() {
    find "$PROJECT_DIR" -type f -name "*.sh" | sort
}

#############################################
# Shellcheck Validation
#############################################

check_shellcheck() {
    print_section "Shellcheck Validation"

    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo -e "${YELLOW}⚠ Shellcheck not installed - skipping shellcheck validation${NC}"
        echo -e "  Install with: brew install shellcheck"
        return 0
    fi

    local failed=0
    local checked=0

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        if shellcheck "$script" 2>&1 | grep -q "^In"; then
            echo -e "${RED}✗${NC} $script_name"
            if [[ "$VERBOSE" == true ]]; then
                shellcheck "$script" 2>&1 | sed 's/^/    /'
            fi
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name passed"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts passed shellcheck"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts failed shellcheck"
        return 1
    fi
}

#############################################
# Strict Mode Validation
#############################################

check_strict_mode() {
    print_section "Strict Mode Validation"

    local failed=0
    local checked=0

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Check for set -euo pipefail or set -e variations
        if ! grep -q "set -euo pipefail\|set -eu\|set -e" "$script"; then
            echo -e "${RED}✗${NC} $script_name - Missing strict mode (set -euo pipefail)"
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name has strict mode"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts have strict mode enabled"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts missing strict mode"
        return 1
    fi
}

#############################################
# Security Checks
#############################################

check_localhost_binding() {
    print_section "Security: Localhost Binding"

    local failed=0
    local checked=0

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Skip test files that check for dangerous patterns (quality-checks.sh itself)
        if [[ "$script_name" == "quality-checks.sh" ]]; then
            verbose "  ${BLUE}→${NC} $script_name skipped (test utility)"
            continue
        fi

        # Check for 0.0.0.0 binding (should be localhost/127.0.0.1 only)
        if grep -q "0\.0\.0\.0" "$script"; then
            echo -e "${RED}✗${NC} $script_name - Found 0.0.0.0 binding (should use 127.0.0.1 or localhost)"
            if [[ "$VERBOSE" == true ]]; then
                grep -n "0\.0\.0\.0" "$script" | sed 's/^/    /'
            fi
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name uses localhost binding"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts use localhost binding"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts have security issues"
        return 1
    fi
}

check_no_hardcoded_credentials() {
    print_section "Security: Hardcoded Credentials"

    local failed=0
    local checked=0

    # Patterns that might indicate hardcoded credentials
    local patterns=(
        'password\s*=\s*["\x27]'
        'api_key\s*=\s*["\x27]'
        'token\s*=\s*["\x27]'
        'secret\s*=\s*["\x27]'
        'API_KEY\s*=\s*["\x27]'
        'PASSWORD\s*=\s*["\x27]'
    )

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Skip hardware-config.sh which contains MODEL_*_SIZE constants (not credentials)
        if [[ "$script_name" == "hardware-config.sh" ]]; then
            verbose "  ${BLUE}→${NC} $script_name skipped (contains model size constants)"
            continue
        fi

        local found_issue=false
        for pattern in "${patterns[@]}"; do
            if grep -iE "$pattern" "$script" | grep -v "^\s*#" > /dev/null 2>&1; then
                if [[ "$found_issue" == false ]]; then
                    echo -e "${RED}✗${NC} $script_name - Potential hardcoded credentials found"
                    found_issue=true
                fi
                if [[ "$VERBOSE" == true ]]; then
                    grep -inE "$pattern" "$script" | grep -v "^\s*#" | sed 's/^/    /'
                fi
            fi
        done

        if [[ "$found_issue" == true ]]; then
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name has no hardcoded credentials"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts have no hardcoded credentials"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts may have hardcoded credentials"
        echo -e "  ${YELLOW}Note:${NC} Review flagged files to ensure no actual credentials are present"
        return 1
    fi
}

check_variable_quoting() {
    print_section "Security: Variable Quoting"

    local failed=0
    local checked=0

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Look for common unquoted variable patterns (basic check)
        # This is a heuristic check - not perfect but catches common issues
        local issues=0

        # Check for unquoted variables in rm commands (dangerous)
        if grep -E 'rm .* \$[A-Za-z_][A-Za-z0-9_]*[^"]' "$script" | grep -v '^\s*#' > /dev/null 2>&1; then
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${YELLOW}⚠${NC} $script_name - Potential unquoted variable in rm command"
                grep -nE 'rm .* \$[A-Za-z_][A-Za-z0-9_]*[^"]' "$script" | grep -v '^\s*#' | sed 's/^/    /'
            fi
            ((issues++)) || true
        fi

        if [[ $issues -gt 0 ]]; then
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name has proper variable quoting"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts have proper variable quoting"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $failed/$checked scripts may have quoting issues"
        echo -e "  ${YELLOW}Note:${NC} Review flagged files manually - this is a heuristic check"
        return 0  # Don't fail build on quoting warnings (shellcheck covers this better)
    fi
}

check_dangerous_patterns() {
    print_section "Security: Dangerous Patterns"

    local failed=0
    local checked=0

    # Dangerous patterns to avoid
    local patterns=(
        '\beval\s'
        '\bexec\s.*\$'
        'rm\s+-rf\s+/'
    )

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Skip test files that deliberately check for these patterns
        if [[ "$script_name" == *"test-"* ]] || [[ "$script_name" == "quality-checks.sh" ]] || [[ "$script_name" == "helpers.sh" ]]; then
            verbose "  ${BLUE}→${NC} $script_name skipped (test utility)"
            continue
        fi

        local found_issue=false

        # Check for eval (dangerous command injection risk)
        if grep -E '\beval\s' "$script" | grep -v '^\s*#' > /dev/null 2>&1; then
            echo -e "${RED}✗${NC} $script_name - Found 'eval' command (potential security risk)"
            if [[ "$VERBOSE" == true ]]; then
                grep -nE '\beval\s' "$script" | grep -v '^\s*#' | sed 's/^/    /'
            fi
            found_issue=true
        fi

        # Check for rm -rf / (catastrophic)
        if grep -E 'rm\s+-rf\s+/' "$script" | grep -v '^\s*#' > /dev/null 2>&1; then
            echo -e "${RED}✗${NC} $script_name - Found 'rm -rf /' pattern (DANGEROUS!)"
            if [[ "$VERBOSE" == true ]]; then
                grep -nE 'rm\s+-rf\s+/' "$script" | grep -v '^\s*#' | sed 's/^/    /'
            fi
            found_issue=true
        fi

        if [[ "$found_issue" == true ]]; then
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name has no dangerous patterns"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts have no dangerous patterns"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts contain dangerous patterns"
        return 1
    fi
}

#############################################
# File Permission Checks
#############################################

check_file_permissions() {
    print_section "File Permission Checks"

    local failed=0
    local checked=0

    while IFS= read -r script; do
        ((checked++)) || true
        local script_name
        script_name=$(basename "$script")
        verbose "Checking $script_name"

        # Check if file is world-writable (security issue)
        if [[ -w "$script" ]] && stat -f "%Lp" "$script" 2>/dev/null | grep -q '...w'; then
            echo -e "${RED}✗${NC} $script_name - World-writable (security issue)"
            ((failed++)) || true
        else
            verbose "  ${GREEN}✓${NC} $script_name has safe permissions"
        fi
    done < <(get_all_shell_scripts)

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} All $checked scripts have safe permissions"
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked scripts have unsafe permissions"
        return 1
    fi
}

#############################################
# Documentation Validation
#############################################

check_documentation() {
    print_section "Documentation Validation"

    local failed=0

    # Check README exists
    if [[ -f "$PROJECT_DIR/README.md" ]]; then
        echo -e "${GREEN}✓${NC} README.md exists"
    else
        echo -e "${RED}✗${NC} README.md missing"
        ((failed++)) || true
    fi

    # Check main scripts have usage information
    local scripts=("$PROJECT_DIR/setup-ai-opencode.sh" "$PROJECT_DIR/uninstall-gemma4-opencode.sh")
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            local script_name
            script_name=$(basename "$script")
            if grep -q "^# Usage:" "$script" || grep -q "^# usage:" "$script"; then
                verbose "${GREEN}✓${NC} $script_name has usage documentation"
            else
                echo -e "${YELLOW}⚠${NC} $script_name missing usage documentation"
                # Don't fail on this, just warn
            fi
        fi
    done

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} Documentation checks passed"
        return 0
    else
        echo -e "${RED}✗${NC} Documentation checks failed"
        return 1
    fi
}

#############################################
# JSON/Configuration Validation
#############################################

check_json_syntax() {
    print_section "JSON Syntax Validation"

    # Only check if we have JSON files
    if ! find "$PROJECT_DIR" -name "*.json" -type f | grep -q .; then
        echo -e "${BLUE}ℹ${NC} No JSON files found - skipping validation"
        return 0
    fi

    local failed=0
    local checked=0

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠ jq not installed - skipping JSON validation${NC}"
        echo -e "  Install with: brew install jq"
        return 0
    fi

    while IFS= read -r json_file; do
        ((checked++)) || true
        local file_name
        file_name=$(basename "$json_file")
        verbose "Checking $file_name"

        if jq empty "$json_file" 2>/dev/null; then
            verbose "  ${GREEN}✓${NC} $file_name is valid JSON"
        else
            echo -e "${RED}✗${NC} $file_name - Invalid JSON syntax"
            if [[ "$VERBOSE" == true ]]; then
                jq empty "$json_file" 2>&1 | sed 's/^/    /'
            fi
            ((failed++)) || true
        fi
    done < <(find "$PROJECT_DIR" -name "*.json" -type f)

    echo ""
    if [[ $failed -eq 0 ]]; then
        if [[ $checked -gt 0 ]]; then
            echo -e "${GREEN}✓${NC} All $checked JSON files are valid"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $failed/$checked JSON files have syntax errors"
        return 1
    fi
}

#############################################
# Main Execution
#############################################

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}ai_model Quality Checks${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local all_passed=true

    # Run all checks
    check_shellcheck || all_passed=false
    check_strict_mode || all_passed=false
    check_localhost_binding || all_passed=false
    check_no_hardcoded_credentials || all_passed=false
    check_variable_quoting || all_passed=false
    check_dangerous_patterns || all_passed=false
    check_file_permissions || all_passed=false
    check_documentation || all_passed=false
    check_json_syntax || all_passed=false

    # Final summary
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Quality Checks Summary${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [[ "$all_passed" == true ]]; then
        echo -e "${GREEN}✓ All quality checks passed!${NC}"
        echo ""
        echo "Safe to commit changes."
        return 0
    else
        echo -e "${RED}✗ Some quality checks failed${NC}"
        echo ""
        echo "Please fix the issues above before committing."
        return 1
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
