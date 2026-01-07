#!/bin/bash
#
# diagnose.sh - Diagnostic tool for local LLM setup
#
# Performs health checks on Ollama, models, Continue.dev config, and VS Code integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local-llm-setup"
STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="$STATE_DIR/diagnose.log"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

print_warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Check Ollama daemon
check_ollama_daemon() {
  print_header "🔍 Ollama Daemon Health"
  
  if ! command -v ollama &>/dev/null; then
    print_error "Ollama not found in PATH"
    return 1
  fi
  print_success "Ollama binary found"
  
  local version=$(ollama --version 2>/dev/null | head -n 1 || echo "unknown")
  print_info "Version: $version"
  
  # Check if service is running
  if curl -s http://localhost:11434/api/tags &>/dev/null; then
    print_success "Ollama service is running on http://localhost:11434"
    
    # Test API endpoint
    local api_response=$(curl -s http://localhost:11434/api/tags 2>/dev/null || echo "")
    if [[ -n "$api_response" ]]; then
      print_success "API endpoint responding"
    else
      print_warn "API endpoint not responding correctly"
    fi
  else
    print_error "Ollama service is not running"
    print_info "Start with: brew services start ollama"
    return 1
  fi
}

# Check installed models
check_models() {
  print_header "🤖 Installed Models"
  
  local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
  
  if [[ -z "$models" ]]; then
    print_warn "No models installed"
    return 1
  fi
  
  local model_count=$(echo "$models" | wc -l | xargs)
  print_success "Found $model_count model(s)"
  echo ""
  
  echo "$models" | while read -r model; do
    if [[ -n "$model" ]]; then
      print_info "  • $model"
      
      # Check if model is loaded
      local ps_output=$(ollama ps 2>/dev/null | grep "$model" || echo "")
      if [[ -n "$ps_output" ]]; then
        print_info "    Status: Loaded in memory"
      else
        print_info "    Status: Not loaded"
      fi
    fi
  done
}

# Check Continue.dev config
check_continue_config() {
  print_header "📝 Continue.dev Configuration"
  
  local config_file="$HOME/.continue/config.json"
  
  if [[ ! -f "$config_file" ]]; then
    print_warn "Continue.dev config not found at $config_file"
    print_info "Run setup-local-llm.sh to generate configuration"
    return 1
  fi
  
  print_success "Config file found: $config_file"
  
  # Validate JSON
  if command -v jq &>/dev/null; then
    if jq empty "$config_file" 2>/dev/null; then
      print_success "Config file is valid JSON"
      
      # Check for models
      local model_count=$(jq '.models | length' "$config_file" 2>/dev/null || echo "0")
      if [[ "$model_count" -gt 0 ]]; then
        print_success "Found $model_count model profile(s)"
        
        # List models
        echo ""
        jq -r '.models[] | "  • \(.title): \(.model)"' "$config_file" 2>/dev/null || true
      else
        print_warn "No models configured"
      fi
    else
      print_error "Config file is not valid JSON"
      return 1
    fi
  else
    print_warn "jq not found, skipping JSON validation"
  fi
}

# Check VS Code integration
check_vscode() {
  print_header "🔌 VS Code Integration"
  
  if ! command -v code &>/dev/null; then
    print_warn "VS Code CLI not found"
    print_info "Install VS Code CLI: https://code.visualstudio.com/docs/editor/command-line"
    return 1
  fi
  
  print_success "VS Code CLI found"
  
  # Check Continue.dev extension
  local continue_installed=$(code --list-extensions 2>/dev/null | grep -i continue || echo "")
  if [[ -n "$continue_installed" ]]; then
    print_success "Continue.dev extension installed"
  else
    print_warn "Continue.dev extension not installed"
    print_info "Install from: https://marketplace.visualstudio.com/items?itemName=Continue.continue"
  fi
}

# Check network connectivity (only for initial installs)
check_network() {
  print_header "🌐 Network Connectivity"
  
  if curl -s --max-time 5 https://ollama.com &>/dev/null; then
    print_success "Internet connectivity available"
    print_info "Required for: Model downloads, Ollama updates"
  else
    print_warn "Internet connectivity limited"
    print_info "Offline mode: Only local operations available"
  fi
}

# Check system resources
check_resources() {
  print_header "💻 System Resources"
  
  # RAM
  local ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  local ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
  print_info "Total RAM: ${ram_gb}GB"
  
  # Available RAM
  local vm_stat=$(vm_stat 2>/dev/null || echo "")
  if [[ -n "$vm_stat" ]]; then
    local free_pages=$(echo "$vm_stat" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    local page_size=$(pagesize)
    local free_mb=$((free_pages * page_size / 1024 / 1024))
    print_info "Available RAM: ~${free_mb}MB"
  fi
  
  # Disk space
  local disk_available=$(df -h "$HOME" | awk 'NR==2 {print $4}' || echo "Unknown")
  print_info "Available disk space: $disk_available"
  
  # CPU
  local cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "Unknown")
  print_info "CPU cores: $cpu_cores"
}

# Test model response
test_model_response() {
  print_header "🧪 Model Response Test"
  
  local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | head -n 1 || echo "")
  
  if [[ -z "$models" ]]; then
    print_warn "No models available for testing"
    return 1
  fi
  
  local test_model=$(echo "$models" | head -n 1)
  print_info "Testing model: $test_model"
  print_info "Test prompt: 'Write hello in TypeScript'"
  echo ""
  
  local start_time=$(date +%s)
  local response=$(timeout 15 ollama run "$test_model" "Write hello in TypeScript" 2>&1 | head -n 3 || echo "")
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  if [[ -n "$response" && ${#response} -gt 5 ]]; then
    print_success "Model responded (${duration}s)"
    echo -e "${CYAN}Response preview:${NC}"
    echo "$response" | head -n 3 | sed 's/^/  /'
  else
    print_error "Model did not respond or timed out"
    return 1
  fi
}

# Generate diagnostic report
generate_report() {
  print_header "📊 Diagnostic Report"
  
  local report_file="$STATE_DIR/diagnostic-report-$(date +%Y%m%d-%H%M%S).txt"
  
  {
    echo "Local LLM Diagnostic Report"
    echo "Generated: $(date)"
    echo ""
    echo "=== System Information ==="
    echo "OS: $(sw_vers -productName) $(sw_vers -productVersion)"
    echo "Architecture: $(uname -m)"
    echo ""
    
    echo "=== Ollama ==="
    if command -v ollama &>/dev/null; then
      ollama --version 2>/dev/null || echo "Version: unknown"
    else
      echo "Status: Not installed"
    fi
    echo ""
    
    echo "=== Installed Models ==="
    ollama list 2>/dev/null || echo "No models"
    echo ""
    
    echo "=== Continue.dev Config ==="
    if [[ -f "$HOME/.continue/config.json" ]]; then
      echo "Config exists: Yes"
      if command -v jq &>/dev/null; then
        jq '.' "$HOME/.continue/config.json" 2>/dev/null || echo "Invalid JSON"
      fi
    else
      echo "Config exists: No"
    fi
    echo ""
    
    echo "=== VS Code ==="
    if command -v code &>/dev/null; then
      echo "CLI available: Yes"
      code --version 2>/dev/null || echo "Version: unknown"
      echo ""
      echo "Installed extensions:"
      code --list-extensions 2>/dev/null | grep -i continue || echo "Continue.dev: Not installed"
    else
      echo "CLI available: No"
    fi
    
  } > "$report_file"
  
  print_success "Report generated: $report_file"
  print_info "View with: cat $report_file"
}

# Main diagnostic flow
main() {
  clear
  print_header "🔍 Local LLM Diagnostic Tool"
  
  local issues=0
  
  # Run checks
  check_ollama_daemon || ((issues++))
  check_models || ((issues++))
  check_continue_config || ((issues++))
  check_vscode || ((issues++))
  check_network
  check_resources
  test_model_response || ((issues++))
  
  # Generate report
  generate_report
  
  # Summary
  echo ""
  print_header "📋 Summary"
  
  if [[ $issues -eq 0 ]]; then
    print_success "All checks passed! Your setup is healthy."
  else
    print_warn "Found $issues issue(s). See details above."
    print_info "Run setup-local-llm.sh to fix issues"
  fi
  
  echo ""
}

main "$@"
