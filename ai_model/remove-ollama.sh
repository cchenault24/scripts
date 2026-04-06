#!/bin/bash
#
# Remove Ollama Script
#
# This script safely removes Ollama and its models to free up disk space.
# Run this after switching to llama.cpp for OpenCode.
#
# Usage: bash remove-ollama.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════"
echo -e "  🗑️  Remove Ollama"
echo -e "════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ollama is not installed"
    exit 0
fi

# Show current Ollama status
echo -e "${CYAN}Current Ollama status:${NC}"
ollama list || true
echo ""

# Check disk space that will be freed
OLLAMA_DIR="$HOME/.ollama"
if [ -d "$OLLAMA_DIR" ]; then
    OLLAMA_SIZE=$(du -sh "$OLLAMA_DIR" 2>/dev/null | cut -f1)
    echo -e "${YELLOW}⚠${NC}  Ollama models directory: $OLLAMA_DIR"
    echo -e "   Size: ${YELLOW}$OLLAMA_SIZE${NC}"
    echo ""
fi

# Confirm removal
echo -e "${YELLOW}This will:${NC}"
echo "  1. Stop Ollama service"
echo "  2. Uninstall Ollama via Homebrew"
echo "  3. Remove all downloaded models (~$OLLAMA_SIZE)"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}ℹ${NC}  Removal cancelled"
    exit 0
fi

echo ""

# Step 1: Stop Ollama service
echo -e "${CYAN}▸ Stopping Ollama service...${NC}"
brew services stop ollama 2>/dev/null || true
pkill -9 ollama 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓${NC} Ollama stopped"
echo ""

# Step 2: Uninstall via Homebrew
echo -e "${CYAN}▸ Uninstalling Ollama...${NC}"
brew uninstall ollama
echo -e "${GREEN}✓${NC} Ollama uninstalled"
echo ""

# Step 3: Remove models and data
echo -e "${CYAN}▸ Removing models and data...${NC}"
if [ -d "$OLLAMA_DIR" ]; then
    rm -rf "$OLLAMA_DIR"
    echo -e "${GREEN}✓${NC} Removed $OLLAMA_DIR"
else
    echo -e "${CYAN}ℹ${NC}  No models directory found"
fi
echo ""

# Check for any remaining Ollama files
REMAINING=$(find "$HOME" -maxdepth 3 -name "*ollama*" 2>/dev/null | wc -l)
if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC}  Found $REMAINING remaining files with 'ollama' in name:"
    find "$HOME" -maxdepth 3 -name "*ollama*" 2>/dev/null | head -5
    echo ""
    read -p "Remove these too? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "$HOME" -maxdepth 3 -name "*ollama*" -exec rm -rf {} + 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Cleaned up remaining files"
    fi
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════"
echo -e "  ✅ Ollama Removed Successfully!"
echo -e "════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  • Freed: ~$OLLAMA_SIZE disk space"
echo "  • Use: llama.cpp + OpenCode for Gemma 4"
echo "  • Run: python3 opencode-llama-setup.py --force-reinstall"
echo ""
