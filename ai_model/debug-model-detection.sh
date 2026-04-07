#!/bin/bash
#
# Debug script to diagnose model detection issues
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Ollama Model Detection Debug ===${NC}"
echo ""

# Check 1: Server running?
echo -e "${YELLOW}1. Checking if server is running...${NC}"
if curl -s -m 2 http://127.0.0.1:3456/api/tags >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Server is running"
    echo ""
    echo "Models via API:"
    curl -s http://127.0.0.1:3456/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4
else
    echo -e "${RED}✗${NC} Server not running"
fi
echo ""

# Check 2: Ollama directory structure
echo -e "${YELLOW}2. Checking Ollama directory structure...${NC}"
OLLAMA_DIR="$HOME/.ollama"
if [ -d "$OLLAMA_DIR" ]; then
    echo -e "${GREEN}✓${NC} Ollama directory exists: $OLLAMA_DIR"
    echo ""
    echo "Directory structure:"
    find "$OLLAMA_DIR" -maxdepth 3 -type d 2>/dev/null | sort
else
    echo -e "${RED}✗${NC} Ollama directory not found: $OLLAMA_DIR"
fi
echo ""

# Check 3: Model manifests
echo -e "${YELLOW}3. Checking model manifests...${NC}"
MANIFEST_DIR="$HOME/.ollama/models/manifests/registry.ollama.ai/library"
if [ -d "$MANIFEST_DIR" ]; then
    echo -e "${GREEN}✓${NC} Manifest directory exists"
    echo ""
    echo "Libraries found:"
    ls -la "$MANIFEST_DIR" 2>/dev/null || echo "  (empty or no access)"

    if [ -d "$MANIFEST_DIR/gemma4" ]; then
        echo ""
        echo "Gemma4 tags:"
        find "$MANIFEST_DIR/gemma4" -type f 2>/dev/null | while read -r file; do
            tag=$(basename "$(dirname "$file")")
            echo "  gemma4:$tag"
        done
    fi
else
    echo -e "${RED}✗${NC} Manifest directory not found"
fi
echo ""

# Check 4: Blobs
echo -e "${YELLOW}4. Checking model blobs...${NC}"
BLOB_DIR="$HOME/.ollama/models/blobs"
if [ -d "$BLOB_DIR" ]; then
    BLOB_COUNT=$(find "$BLOB_DIR" -type f -name "sha256-*" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${GREEN}✓${NC} Blob directory exists"
    echo "  Total blobs: $BLOB_COUNT"
    if [ "$BLOB_COUNT" -gt 0 ]; then
        echo "  First few blobs:"
        find "$BLOB_DIR" -type f -name "sha256-*" 2>/dev/null | head -3 | while read -r blob; do
            size=$(ls -lh "$blob" | awk '{print $5}')
            echo "    $(basename "$blob") ($size)"
        done
    fi
else
    echo -e "${RED}✗${NC} Blob directory not found"
fi
echo ""

# Check 5: Ollama binary
echo -e "${YELLOW}5. Checking Ollama binary...${NC}"
if [ -f "/tmp/ollama-build/ollama" ]; then
    echo -e "${GREEN}✓${NC} Build binary exists: /tmp/ollama-build/ollama"
    /tmp/ollama-build/ollama --version 2>&1 | head -1
else
    echo -e "${RED}✗${NC} Build binary not found"
fi

if command -v ollama >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} System binary exists: $(which ollama)"
    ollama --version 2>&1 | head -1
else
    echo -e "${YELLOW}⚠${NC} No system binary found"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo ""
if [ -n "$(curl -s -m 2 http://127.0.0.1:3456/api/tags 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep "^gemma4:" || true)" ]; then
    echo -e "${GREEN}✓${NC} Can detect models via API"
elif [ -d "$MANIFEST_DIR/gemma4" ]; then
    echo -e "${YELLOW}⚠${NC} Models likely installed but server not running"
    echo "  Start server with: ./llama-control.sh start"
elif [ "$BLOB_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Model files exist but manifest parsing issue"
else
    echo -e "${RED}✗${NC} No models appear to be installed"
fi
