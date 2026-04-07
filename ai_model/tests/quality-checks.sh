#!/bin/bash
# quality-checks.sh - Comprehensive quality checks for all scripts
# Runs shellcheck, security audits, performance checks, and more

set -euo pipefail

#############################################
# Setup
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# Source common utilities
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
fi

# Source model families for security tests
if [[ -f "$SCRIPT_DIR/lib/model-families.sh" ]]; then
    source "$SCRIPT_DIR/lib/model-families.sh"
fi

# Result tracking
SHELLCHECK_FAILED=false
SECURITY_FAILED=false
OPT_FAILED=false
PERM_FAILED=false
DOCS_FAILED=false
JSON_FAILED=false

#############################################
# 1. Shellcheck
#############################################

run_shellcheck() {
    print_header "Running Shellcheck"

    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        print_warning "shellcheck not found. Install with: brew install shellcheck"
        SHELLCHECK_FAILED=true
        return 1
    fi

    print_info "Shellcheck version: $(shellcheck --version | grep version: | awk '{print $2}')"

    local failed_count=0
    local checked_count=0

    # Check all bash scripts in main directory
    for script in "$SCRIPT_DIR"/*.sh; do
        if [[ -f "$script" ]]; then
            ((checked_count++))
            echo -n "Checking: $(basename "$script")... "
            if shellcheck -x "$script" 2>/dev/null; then
                echo "PASS"
            else
                echo "FAIL"
                ((failed_count++))
                SHELLCHECK_FAILED=true
            fi
        fi
    done

    # Check all bash scripts in lib directory
    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        for script in "$SCRIPT_DIR/lib"/*.sh; do
            if [[ -f "$script" ]]; then
                ((checked_count++))
                echo -n "Checking: lib/$(basename "$script")... "
                if shellcheck -x "$script" 2>/dev/null; then
                    echo "PASS"
                else
                    echo "FAIL"
                    ((failed_count++))
                    SHELLCHECK_FAILED=true
                fi
            fi
        done
    fi

    # Check all bash scripts in tests directory
    if [[ -d "$SCRIPT_DIR/tests" ]]; then
        for script in "$SCRIPT_DIR/tests"/*.sh; do
            if [[ -f "$script" && "$script" != "${BASH_SOURCE[0]}" ]]; then
                ((checked_count++))
                echo -n "Checking: tests/$(basename "$script")... "
                if shellcheck -x "$script" 2>/dev/null; then
                    echo "PASS"
                else
                    echo "FAIL"
                    ((failed_count++))
                    SHELLCHECK_FAILED=true
                fi
            fi
        done
    fi

    echo ""
    if [[ $failed_count -eq 0 ]]; then
        print_status "Shellcheck: All $checked_count scripts passed"
        return 0
    else
        print_error "Shellcheck: $failed_count of $checked_count scripts failed"
        return 1
    fi
}

#############################################
# 2. Security Audit
#############################################

run_security_audit() {
    print_header "Running Security Audit"

    # Test security allowlist function
    test_allowlist() {
        local test_failed=false

        print_info "Testing model allowlist..."

        # Should allow (US/EU sources)
        local allowed_models=(
            "llama3.3:70b-instruct-q4_K_M"
            "mistral-nemo:12b-instruct-q8_0"
            "phi4:14b-q8_0"
            "gemma4:31b-it-q8_0"
            "codestral:22b-v0.1-q8_0"
        )

        for model in "${allowed_models[@]}"; do
            if ! is_model_allowed "$model"; then
                print_error "Failed to allow trusted model: $model"
                test_failed=true
            fi
        done

        # Should block (Chinese sources)
        local blocked_models=(
            "deepseek:67b"
            "qwen2.5:72b"
            "yi:34b"
            "baichuan:13b"
            "chatglm:6b"
        )

        for model in "${blocked_models[@]}"; do
            if is_model_allowed "$model"; then
                print_error "Failed to block untrusted model: $model"
                test_failed=true
            fi
        done

        if [[ "$test_failed" == "true" ]]; then
            return 1
        fi

        print_status "Allowlist tests passed"
        return 0
    }

    # Test localhost binding
    test_localhost_binding() {
        print_info "Checking localhost binding configuration..."

        local ollama_setup="$SCRIPT_DIR/lib/ollama-setup.sh"

        if [[ ! -f "$ollama_setup" ]]; then
            print_warning "ollama-setup.sh not found"
            return 1
        fi

        # Check that OLLAMA_HOST is bound to localhost
        if grep -q "OLLAMA_HOST=.*127.0.0.1" "$ollama_setup"; then
            print_status "Localhost binding verified"
            return 0
        else
            print_error "OLLAMA_HOST not bound to localhost (security risk)"
            return 1
        fi
    }

    # Run all security tests
    local security_passed=true

    if ! test_allowlist; then
        security_passed=false
        SECURITY_FAILED=true
    fi

    if ! test_localhost_binding; then
        security_passed=false
        SECURITY_FAILED=true
    fi

    echo ""
    if [[ "$security_passed" == "true" ]]; then
        print_status "Security audit: All checks passed"
        return 0
    else
        print_error "Security audit: Some checks failed"
        return 1
    fi
}

#############################################
# 3. Performance Optimizations
#############################################

check_optimizations() {
    print_header "Checking Performance Optimizations"

    local ollama_setup="$SCRIPT_DIR/lib/ollama-setup.sh"

    if [[ ! -f "$ollama_setup" ]]; then
        print_error "ollama-setup.sh not found"
        OPT_FAILED=true
        return 1
    fi

    local opt_passed=true

    # Check for LTO (Link-Time Optimization)
    print_info "Checking for LTO flag..."
    if grep -q "\-flto" "$ollama_setup"; then
        print_status "LTO enabled"
    else
        print_error "LTO flag not found"
        opt_passed=false
    fi

    # Check for Metal framework
    print_info "Checking for Metal GPU acceleration..."
    if grep -q "framework Metal" "$ollama_setup"; then
        print_status "Metal framework linked"
    else
        print_error "Metal framework not linked"
        opt_passed=false
    fi

    # Check for native architecture compilation
    print_info "Checking for native architecture optimization..."
    if grep -q "\-march=native" "$ollama_setup"; then
        print_status "Native architecture optimization enabled"
    else
        print_error "Native architecture flag not found"
        opt_passed=false
    fi

    # Check for Flash Attention
    print_info "Checking for Flash Attention..."
    if grep -q "OLLAMA_FLASH_ATTENTION" "$ollama_setup"; then
        print_status "Flash Attention enabled"
    else
        print_error "Flash Attention not configured"
        opt_passed=false
    fi

    # Check for GPU layer configuration
    print_info "Checking for GPU layer configuration..."
    if grep -q "OLLAMA_NUM_GPU" "$ollama_setup"; then
        print_status "GPU layer configuration found"
    else
        print_error "GPU layer configuration missing"
        opt_passed=false
    fi

    # Check for keep-alive optimization
    print_info "Checking for keep-alive optimization..."
    if grep -q "OLLAMA_KEEP_ALIVE" "$ollama_setup"; then
        print_status "Keep-alive optimization found"
    else
        print_error "Keep-alive optimization missing"
        opt_passed=false
    fi

    echo ""
    if [[ "$opt_passed" == "true" ]]; then
        print_status "Performance checks: All optimizations present"
        return 0
    else
        print_error "Performance checks: Some optimizations missing"
        OPT_FAILED=true
        return 1
    fi
}

#############################################
# 4. File Permissions
#############################################

check_permissions() {
    print_header "Checking File Permissions"

    local fixed_count=0
    local checked_count=0

    # Check main directory scripts
    for script in "$SCRIPT_DIR"/*.sh; do
        if [[ -f "$script" ]]; then
            ((checked_count++))
            if [[ ! -x "$script" ]]; then
                print_warning "Not executable: $(basename "$script")"
                chmod +x "$script"
                print_status "Fixed: $(basename "$script")"
                ((fixed_count++))
            fi
        fi
    done

    # Check lib directory scripts
    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        for script in "$SCRIPT_DIR/lib"/*.sh; do
            if [[ -f "$script" ]]; then
                ((checked_count++))
                if [[ ! -x "$script" ]]; then
                    print_warning "Not executable: lib/$(basename "$script")"
                    chmod +x "$script"
                    print_status "Fixed: lib/$(basename "$script")"
                    ((fixed_count++))
                fi
            fi
        done
    fi

    # Check tests directory scripts
    if [[ -d "$SCRIPT_DIR/tests" ]]; then
        for script in "$SCRIPT_DIR/tests"/*.sh; do
            if [[ -f "$script" ]]; then
                ((checked_count++))
                if [[ ! -x "$script" ]]; then
                    print_warning "Not executable: tests/$(basename "$script")"
                    chmod +x "$script"
                    print_status "Fixed: tests/$(basename "$script")"
                    ((fixed_count++))
                fi
            fi
        done
    fi

    echo ""
    if [[ $fixed_count -eq 0 ]]; then
        print_status "Permissions: All $checked_count scripts are executable"
        return 0
    else
        print_status "Permissions: Fixed $fixed_count of $checked_count scripts"
        return 0
    fi
}

#############################################
# 5. Documentation Links
#############################################

check_documentation() {
    print_header "Checking Documentation"

    local readme="$SCRIPT_DIR/README.md"

    if [[ ! -f "$readme" ]]; then
        print_warning "README.md not found"
        DOCS_FAILED=true
        return 1
    fi

    local doc_passed=true
    local checked_links=0
    local broken_links=0

    # Extract markdown links to .md files
    print_info "Checking documentation links..."

    # Use grep to extract links, then validate them
    grep -o '\](.*\.md)' "$readme" 2>/dev/null | sed 's/](\(.*\))/\1/' | while read -r link_path; do
        ((checked_links++))

        # Resolve relative path
        local full_path="$SCRIPT_DIR/$link_path"

        if [[ ! -f "$full_path" ]]; then
            print_error "Broken link: $link_path"
            doc_passed=false
            ((broken_links++))
        fi
    done

    # Check if key documentation files exist
    print_info "Checking for standard documentation files..."

    local expected_docs=(
        "docs/MODEL_GUIDE.md"
        "docs/CLIENT_SETUP.md"
        "docs/TROUBLESHOOTING.md"
        "docs/TEAM_DEPLOYMENT.md"
    )

    for doc in "${expected_docs[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$doc" ]]; then
            print_warning "Missing documentation: $doc"
            doc_passed=false
        fi
    done

    # Check if lib scripts are documented in README
    print_info "Checking if lib scripts are documented..."

    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        for script in "$SCRIPT_DIR/lib"/*.sh; do
            local script_name
            script_name=$(basename "$script")

            if ! grep -q "$script_name" "$readme"; then
                print_warning "lib/$script_name not mentioned in README.md"
            fi
        done
    fi

    echo ""
    if [[ "$doc_passed" == "true" ]]; then
        print_status "Documentation: All $checked_links links valid, all expected docs found"
        return 0
    else
        if [[ $broken_links -gt 0 ]]; then
            print_error "Documentation: $broken_links broken links found"
        fi
        DOCS_FAILED=true
        return 1
    fi
}

#############################################
# 6. Configuration Validation
#############################################

validate_configurations() {
    print_header "Validating Configuration Files"

    local config_passed=true
    local checked_count=0

    # Check preset files
    if [[ -d "$SCRIPT_DIR/presets" ]]; then
        print_info "Checking preset files..."

        for preset in "$SCRIPT_DIR/presets"/*.env; do
            if [[ -f "$preset" ]]; then
                ((checked_count++))
                local preset_name
                preset_name=$(basename "$preset")

                echo -n "Validating: $preset_name... "

                # Try to source the env file in a subshell to check for syntax errors
                if bash -n "$preset" 2>/dev/null; then
                    echo "PASS"
                else
                    echo "FAIL"
                    print_error "Invalid syntax in $preset_name"
                    config_passed=false
                    JSON_FAILED=true
                fi

                # Check for required variables
                if grep -q "MODEL_FAMILY" "$preset" && grep -q "MODEL" "$preset"; then
                    : # Variables present
                else
                    print_warning "$preset_name missing MODEL_FAMILY or MODEL"
                fi
            fi
        done
    fi

    # Check if jq is available for JSON validation
    if command -v jq &> /dev/null; then
        print_info "Checking JSON files with jq..."

        # Look for any .json files
        while IFS= read -r -d '' json_file; do
            ((checked_count++))
            local file_name
            file_name=$(basename "$json_file")

            echo -n "Validating: $file_name... "

            if jq empty "$json_file" 2>/dev/null; then
                echo "PASS"
            else
                echo "FAIL"
                print_error "Invalid JSON in $file_name"
                config_passed=false
                JSON_FAILED=true
            fi
        done < <(find "$SCRIPT_DIR" -name "*.json" -type f -print0 2>/dev/null)
    else
        print_warning "jq not installed, skipping JSON validation"
        print_info "Install with: brew install jq"
    fi

    echo ""
    if [[ "$config_passed" == "true" ]]; then
        print_status "Configuration: All $checked_count files validated"
        return 0
    else
        print_error "Configuration: Some files failed validation"
        return 1
    fi
}

#############################################
# 7. Code Quality Checks
#############################################

check_code_quality() {
    print_header "Checking Code Quality"

    local quality_passed=true

    # Check for set -euo pipefail in all scripts
    print_info "Checking for strict mode (set -euo pipefail)..."

    local strict_count=0
    local total_scripts=0

    for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh; do
        if [[ -f "$script" ]]; then
            ((total_scripts++))

            if grep -q "set -euo pipefail" "$script"; then
                ((strict_count++))
            else
                local script_name
                script_name=$(basename "$script")
                print_warning "Missing strict mode: $script_name"
            fi
        fi
    done

    if [[ $strict_count -eq $total_scripts ]]; then
        print_status "All scripts use strict mode"
    else
        print_warning "$strict_count of $total_scripts scripts use strict mode"
    fi

    # Check for common anti-patterns
    print_info "Checking for common anti-patterns..."

    # Look for unquoted variables (basic check)
    if grep -r '\$[A-Z_][A-Z_]*[^"]' "$SCRIPT_DIR"/lib/*.sh 2>/dev/null | grep -v "^#" | head -5; then
        print_warning "Found potentially unquoted variables (review recommended)"
    fi

    # Check for hardcoded paths that should be configurable
    print_info "Checking for hardcoded paths..."

    if grep -r "/tmp/" "$SCRIPT_DIR"/lib/*.sh 2>/dev/null | grep -v "OLLAMA_BUILD_DIR" | grep -v "^#" | head -5; then
        print_warning "Found hardcoded /tmp paths (should use OLLAMA_BUILD_DIR)"
    fi

    echo ""
    if [[ "$quality_passed" == "true" ]]; then
        print_status "Code quality: Basic checks passed"
        return 0
    else
        print_warning "Code quality: Some improvements suggested"
        return 0  # Don't fail on quality suggestions
    fi
}

#############################################
# 8. Dependency Checks
#############################################

check_dependencies() {
    print_header "Checking Dependencies"

    print_info "Checking for required system tools..."

    local deps_ok=true

    # Required tools
    local required_tools=(
        "bash"
        "git"
        "curl"
        "grep"
        "sed"
    )

    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo "  $tool: installed"
        else
            print_error "$tool: NOT FOUND (required)"
            deps_ok=false
        fi
    done

    # Optional but recommended tools
    print_info "Checking for optional tools..."

    local optional_tools=(
        "shellcheck"
        "jq"
        "go"
        "docker"
        "bun"
    )

    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            echo "  $tool: installed"
        else
            echo "  $tool: not installed (optional)"
        fi
    done

    echo ""
    if [[ "$deps_ok" == "true" ]]; then
        print_status "Dependencies: All required tools found"
        return 0
    else
        print_error "Dependencies: Some required tools missing"
        return 1
    fi
}

#############################################
# Main Report
#############################################

generate_report() {
    echo ""
    echo ""
    print_header "Quality Checks Report"

    # Determine results
    local shellcheck_result="PASS"
    [[ "$SHELLCHECK_FAILED" == "true" ]] && shellcheck_result="FAIL"

    local security_result="PASS"
    [[ "$SECURITY_FAILED" == "true" ]] && security_result="FAIL"

    local opt_result="PASS"
    [[ "$OPT_FAILED" == "true" ]] && opt_result="FAIL"

    local perm_result="PASS"
    [[ "$PERM_FAILED" == "true" ]] && perm_result="FAIL"

    local docs_result="PASS"
    [[ "$DOCS_FAILED" == "true" ]] && docs_result="FAIL"

    local json_result="PASS"
    [[ "$JSON_FAILED" == "true" ]] && json_result="FAIL"

    # Determine overall result
    local overall_result="PASS"
    if [[ "$SHELLCHECK_FAILED" == "true" ]] || \
       [[ "$SECURITY_FAILED" == "true" ]] || \
       [[ "$OPT_FAILED" == "true" ]] || \
       [[ "$PERM_FAILED" == "true" ]] || \
       [[ "$DOCS_FAILED" == "true" ]] || \
       [[ "$JSON_FAILED" == "true" ]]; then
        overall_result="FAIL"
    fi

    # Print results
    echo "1. Shellcheck:           $shellcheck_result"
    echo "2. Security Audit:       $security_result"
    echo "3. Optimizations:        $opt_result"
    echo "4. Permissions:          $perm_result"
    echo "5. Documentation:        $docs_result"
    echo "6. Configuration:        $json_result"
    echo ""
    echo "Overall Result:          $overall_result"
    echo ""

    if [[ "$overall_result" == "PASS" ]]; then
        print_status "All quality checks passed!"
        echo ""
        return 0
    else
        print_error "Some quality checks failed. Review output above."
        echo ""
        return 1
    fi
}

#############################################
# Main Execution
#############################################

main() {
    print_header "AI Model Setup - Quality Checks"
    echo "Script directory: $SCRIPT_DIR"
    echo ""

    # Run all checks (continue even if some fail)
    run_shellcheck || true
    run_security_audit || true
    check_optimizations || true
    check_permissions || true
    check_documentation || true
    validate_configurations || true
    check_code_quality || true
    check_dependencies || true

    # Generate final report
    generate_report
}

# Run main function
main "$@"
