#!/usr/bin/env bash

#==============================================================================
# error_handler.sh - Error Handling and Retry Logic Utilities
#
# Provides consistent error handling, retry logic, and error recovery
#==============================================================================

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"

#------------------------------------------------------------------------------
# Logging Functions (if not already defined)
#------------------------------------------------------------------------------

log_error() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if command -v log_message &>/dev/null; then
        log_message "ERROR: $message" >&2
    else
        echo "[$timestamp] ERROR: $message" >&2
    fi
}

log_warn() {
    local message="$1"
    if command -v log_message &>/dev/null; then
        log_message "WARNING: $message"
    else
        echo "WARNING: $message"
    fi
}

log_info() {
    local message="$1"
    if command -v log_message &>/dev/null; then
        log_message "$message"
    else
        echo "$message"
    fi
}

#------------------------------------------------------------------------------
# Error Handling Functions
#------------------------------------------------------------------------------

# Execute command with retry logic
execute_with_retry() {
    local description="$1"
    shift
    local cmd=("$@")
    local attempt=1
    local delay=$RETRY_DELAY
    local last_error=""
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_info "Attempting: $description (attempt $attempt/$MAX_RETRIES)"
        
        if "${cmd[@]}" 2>&1; then
            if [[ $attempt -gt 1 ]]; then
                log_info "✅ $description succeeded on attempt $attempt"
            fi
            return 0
        else
            last_error=$?
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log_warn "$description failed (exit code: $last_error). Retrying in ${delay}s..."
                sleep "$delay"
                delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "$description failed after $MAX_RETRIES attempts (last exit code: $last_error)"
    return $last_error
}

# Execute network operation with retry (curl, wget, git)
execute_network_with_retry() {
    local description="$1"
    shift
    local cmd=("$@")
    
    # Check network connectivity first
    if ! check_network_connectivity; then
        log_error "Network connectivity check failed. Cannot proceed with: $description"
        return 1
    fi
    
    execute_with_retry "$description" "${cmd[@]}"
}

# Check network connectivity
check_network_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" &>/dev/null 2>&1 || \
           curl -s --max-time 2 "https://$host" &>/dev/null 2>&1; then
            connected=true
            break
        fi
    done
    
    if ! $connected; then
        log_error "No network connectivity detected"
        return 1
    fi
    
    return 0
}

# Execute git clone with retry
git_clone_with_retry() {
    local repo_url="$1"
    local destination="$2"
    local description="${3:-Cloning $repo_url}"
    
    # Validate URL format
    if ! validate_url "$repo_url"; then
        log_error "Invalid repository URL: $repo_url"
        return 1
    fi
    
    execute_network_with_retry "$description" \
        git clone --depth=1 "$repo_url" "$destination"
}

# Execute curl download with retry and optional checksum verification
curl_download_with_retry() {
    local url="$1"
    local output="$2"
    local description="${3:-Downloading $url}"
    local expected_checksum="${4:-}"  # Optional SHA256 checksum
    local checksum_type="${5:-sha256}"  # sha256, sha1, md5
    
    # Validate URL format
    if ! validate_url "$url"; then
        log_error "Invalid URL: $url"
        return 1
    fi
    
    # Download file
    if ! execute_network_with_retry "$description" \
        curl -fsSL "$url" -o "$output"; then
        return 1
    fi
    
    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        if ! verify_checksum "$output" "$expected_checksum" "$checksum_type"; then
            log_error "Checksum verification failed for $output"
            rm -f "$output"
            return 1
        fi
        log_info "Checksum verification passed for $output"
    fi
    
    return 0
}

# Verify file checksum
verify_checksum() {
    local file="$1"
    local expected="$2"
    local type="${3:-sha256}"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found for checksum verification: $file"
        return 1
    fi
    
    local actual_checksum=""
    
    case "$type" in
        sha256)
            if command -v shasum &>/dev/null; then
                actual_checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
            elif command -v sha256sum &>/dev/null; then
                actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
            else
                log_warn "No SHA256 tool available, skipping checksum verification"
                return 0
            fi
            ;;
        sha1)
            if command -v shasum &>/dev/null; then
                actual_checksum=$(shasum -a 1 "$file" | cut -d' ' -f1)
            elif command -v sha1sum &>/dev/null; then
                actual_checksum=$(sha1sum "$file" | cut -d' ' -f1)
            else
                log_warn "No SHA1 tool available, skipping checksum verification"
                return 0
            fi
            ;;
        md5)
            if command -v md5 &>/dev/null; then
                actual_checksum=$(md5 -q "$file" 2>/dev/null || md5sum "$file" | cut -d' ' -f1)
            elif command -v md5sum &>/dev/null; then
                actual_checksum=$(md5sum "$file" | cut -d' ' -f1)
            else
                log_warn "No MD5 tool available, skipping checksum verification"
                return 0
            fi
            ;;
        *)
            log_error "Unsupported checksum type: $type"
            return 1
            ;;
    esac
    
    # Compare checksums (case-insensitive)
    if [[ "${actual_checksum,,}" == "${expected_checksum,,}" ]]; then
        return 0
    else
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected_checksum"
        log_error "  Actual:   $actual_checksum"
        return 1
    fi
}

# Validate URL format
validate_url() {
    local url="$1"
    
    # Basic URL validation
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
        return 0
    fi
    
    # Git SSH URL validation
    if [[ "$url" =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+\.git$ ]]; then
        return 0
    fi
    
    return 1
}

# Handle errors with context
handle_error() {
    local exit_code="$1"
    local context="$2"
    local suggestion="${3:-}"
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Error in $context (exit code: $exit_code)"
        
        if [[ -n "$suggestion" ]]; then
            log_info "Suggestion: $suggestion"
        fi
        
        # Provide common troubleshooting tips based on context
        case "$context" in
            *"git clone"*)
                log_info "Troubleshooting tips:"
                log_info "  - Check your internet connection"
                log_info "  - Verify the repository URL is correct"
                log_info "  - Ensure you have git installed: git --version"
                log_info "  - Check if the repository is accessible: curl -I $url"
                ;;
            *"curl"*|*"download"*)
                log_info "Troubleshooting tips:"
                log_info "  - Check your internet connection"
                log_info "  - Verify the URL is accessible"
                log_info "  - Check firewall/proxy settings"
                log_info "  - Try accessing the URL in a browser"
                ;;
            *"brew"*)
                log_info "Troubleshooting tips:"
                log_info "  - Ensure Homebrew is installed: brew --version"
                log_info "  - Update Homebrew: brew update"
                log_info "  - Check Homebrew status: brew doctor"
                ;;
            *)
                log_info "Check the log file for more details: ${LOG_FILE:-/tmp/zsh_setup.log}"
                ;;
        esac
    fi
    
    return $exit_code
}

# Set up error trap with context
setup_error_trap() {
    local context="${1:-script execution}"
    
    trap 'handle_error $? "$context" "Check the log file for details: ${LOG_FILE:-/tmp/zsh_setup.log}"' ERR
}

# Cleanup on exit
cleanup_on_exit() {
    local cleanup_func="$1"
    trap "$cleanup_func" EXIT INT TERM
}
