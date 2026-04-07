#!/bin/bash
# test-compare-models.sh - Test script for compare-models.sh with mock data

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/model-families.sh"

# Source the compare-models functions (without executing)
source "$SCRIPT_DIR/compare-models.sh"

#############################################
# Test with Mock Ollama
#############################################

print_header "Testing compare-models.sh with Mock Data"

# Create a temporary mock Ollama binary that outputs test data
TEMP_DIR=$(mktemp -d)
MOCK_OLLAMA="$TEMP_DIR/ollama"

cat > "$MOCK_OLLAMA" << 'EOF'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    cat << 'MODELS'
NAME                              ID            SIZE      MODIFIED
llama3.3:70b-instruct-q4_K_M      abc123        42 GB     2 days ago
codestral:22b-v0.1-q8_0           def456        25 GB     1 week ago
gemma4:e4b-it-q8_0                ghi789        12 GB     3 days ago
phi4:14b-q8_0                     jkl012        14 GB     5 days ago
MODELS
else
    echo "Mock Ollama - Version test"
fi
EOF

chmod +x "$MOCK_OLLAMA"

# Override the OLLAMA_BUILD_DIR to use our mock
export OLLAMA_BUILD_DIR="$TEMP_DIR"

# Create mock PID file
mkdir -p ~/.local/var
echo "$$" > "$OLLAMA_PID_FILE"

print_info "Mock Ollama created at: $MOCK_OLLAMA"
print_info "Testing model comparison..."
echo ""

# Run the comparison
compare_models

# Cleanup
rm -rf "$TEMP_DIR"
rm -f "$OLLAMA_PID_FILE"

print_status "Test complete!"
