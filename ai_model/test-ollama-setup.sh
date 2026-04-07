#!/bin/bash
# test-ollama-setup.sh - Test script for ollama-setup.sh

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the ollama setup library
source "$SCRIPT_DIR/lib/ollama-setup.sh"

#############################################
# Test Functions
#############################################

test_build() {
    print_header "TEST: Build Ollama"
    if build_ollama; then
        print_status "Build test: PASSED"
        return 0
    else
        print_error "Build test: FAILED"
        return 1
    fi
}

test_server_start() {
    print_header "TEST: Start Server"
    if start_ollama_server; then
        print_status "Server start test: PASSED"
        return 0
    else
        print_error "Server start test: FAILED"
        return 1
    fi
}

test_health_check() {
    print_header "TEST: Health Check"
    print_info "Testing: curl -s http://127.0.0.1:3456/api/tags"

    if curl -s "http://127.0.0.1:3456/api/tags" | head -10; then
        print_status "Health check test: PASSED"
        return 0
    else
        print_error "Health check test: FAILED"
        return 1
    fi
}

test_server_stop() {
    print_header "TEST: Stop Server"
    if stop_ollama_server; then
        print_status "Server stop test: PASSED"
        return 0
    else
        print_error "Server stop test: FAILED"
        return 1
    fi
}

test_status() {
    print_header "TEST: Server Status"
    ollama_status
    print_status "Status test: PASSED"
}

#############################################
# Main Test Runner
#############################################

main() {
    print_header "Ollama Setup Test Suite"

    print_info "This test will:"
    print_info "  1. Build Ollama from source"
    print_info "  2. Start the server"
    print_info "  3. Run health check"
    print_info "  4. Stop the server"
    print_info ""
    print_warning "This may take several minutes..."

    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Test cancelled"
        exit 0
    fi

    local failed=0

    # Test 1: Build
    if ! test_build; then
        ((failed++))
    fi

    # Test 2: Start server
    if ! test_server_start; then
        ((failed++))
    else
        # Test 3: Health check (only if server started)
        if ! test_health_check; then
            ((failed++))
        fi

        # Test 4: Stop server
        if ! test_server_stop; then
            ((failed++))
        fi
    fi

    # Test 5: Status
    test_status

    # Summary
    print_header "Test Summary"
    if [[ $failed -eq 0 ]]; then
        print_status "All tests passed!"
        return 0
    else
        print_error "$failed test(s) failed"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
