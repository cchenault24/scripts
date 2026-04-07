#!/bin/bash
# Demo script showing model-selection.sh in action

# Source the library
source "$(dirname "$0")/lib/model-selection.sh"

# Show header
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Model Selection Library - Interactive Demo            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Display hardware info
print_header "Hardware Detection"
echo -e "${GREEN}Chip:${NC} $M_CHIP"
echo -e "${GREEN}GPU Cores:${NC} $GPU_CORES"
echo -e "${GREEN}RAM:${NC} ${TOTAL_RAM_GB}GB (Tier: $RAM_TIER)"

# Show what happens at different RAM tiers
echo ""
print_header "RAM-Based Filtering Examples"

echo -e "\n${YELLOW}Scenario 1: 48GB RAM (Tier 3)${NC}"
echo "  → Shows ALL models including 70B Llama"
display_model_menu llama 48 | grep -E "^[0-9]|RECOMMENDED|Context"

echo -e "\n${YELLOW}Scenario 2: 32GB RAM (Tier 2)${NC}"
echo "  → Hides 70B model (too large)"
display_model_menu llama 32 | grep -E "^[0-9]|RECOMMENDED|Context"

echo -e "\n${YELLOW}Scenario 3: 16GB RAM (Tier 1)${NC}"
echo "  → Shows only small models"
display_model_menu llama 16 | grep -E "^[0-9]|RECOMMENDED|Context"

# Show recommendations
echo ""
print_header "Smart Recommendations"
echo "The system recommends the best model for your RAM:"
echo ""
echo -e "${BLUE}48GB:${NC} $(get_family_recommendation llama 48)"
echo -e "${BLUE}32GB:${NC} $(get_family_recommendation llama 32)"
echo -e "${BLUE}16GB:${NC} $(get_family_recommendation llama 16)"

# Show security
echo ""
print_header "Security Filter"
echo "Only trusted sources allowed:"
echo -e "  ${GREEN}✓${NC} Meta Llama (llama*)"
echo -e "  ${GREEN}✓${NC} Mistral AI (mistral*, codestral*)"
echo -e "  ${GREEN}✓${NC} Microsoft (phi*)"
echo -e "  ${GREEN}✓${NC} Google (gemma*)"
echo ""
echo "Blocked sources:"
echo -e "  ${RED}✗${NC} Chinese models (deepseek, qwen, yi, etc.)"

echo ""
print_header "Usage in Scripts"
echo "# Source the library"
echo "source lib/model-selection.sh"
echo ""
echo "# Run interactive selection"
echo "run_model_selection"
echo ""
echo "# Access selected values"
echo "echo \"Family: \$SELECTED_FAMILY\""
echo "echo \"Model: \$SELECTED_MODEL\""

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      Demo Complete                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
