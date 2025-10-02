#!/bin/bash
# WoW System - Installation Script
# Sets up WoW System integration with Claude Code
# Author: Chude <chude@emeke.org>

set -eo pipefail

# Colors
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

echo -e "${C_BOLD}${C_CYAN}"
cat <<'EOF'
╔══════════════════════════════════════╗
║  WoW System Installation v4.1.0      ║
║  Ways of Working Enforcement         ║
╚══════════════════════════════════════╝
EOF
echo -e "${C_RESET}"

# Determine installation directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOW_INSTALL_DIR="${SCRIPT_DIR}"

echo -e "${C_BOLD}Installation Directory:${C_RESET} ${WOW_INSTALL_DIR}"
echo ""

# Check for required tools
echo -e "${C_BOLD}Checking dependencies...${C_RESET}"

if ! command -v bash &> /dev/null; then
    echo -e "${C_RED}✗ bash not found${C_RESET}"
    exit 1
fi
echo -e "${C_GREEN}✓ bash found${C_RESET}"

if command -v jq &> /dev/null; then
    echo -e "${C_GREEN}✓ jq found${C_RESET}"
else
    echo -e "${C_YELLOW}⚠ jq not found (recommended but not required)${C_RESET}"
fi

echo ""

# Set up environment
echo -e "${C_BOLD}Setting up environment...${C_RESET}"

# Create data directory
DATA_DIR="${HOME}/.wow-data"
mkdir -p "${DATA_DIR}"
echo -e "${C_GREEN}✓ Created data directory: ${DATA_DIR}${C_RESET}"

# Create config directory
CONFIG_DIR="${WOW_INSTALL_DIR}/config"
mkdir -p "${CONFIG_DIR}"
echo -e "${C_GREEN}✓ Created config directory: ${CONFIG_DIR}${C_RESET}"

# Create default config if not exists
CONFIG_FILE="${CONFIG_DIR}/wow-config.json"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    cat > "${CONFIG_FILE}" <<'CONFIGEOF'
{
  "version": "4.1.0",
  "enforcement": {
    "enabled": true,
    "strict_mode": false,
    "block_on_violation": false
  },
  "scoring": {
    "threshold_warn": 50,
    "threshold_block": 30,
    "decay_rate": 0.95
  },
  "rules": {
    "max_file_operations": 10,
    "max_bash_commands": 5,
    "require_documentation": true
  },
  "integrations": {
    "claude_code": {
      "hooks_enabled": true,
      "session_tracking": true
    }
  }
}
CONFIGEOF
    echo -e "${C_GREEN}✓ Created default configuration${C_RESET}"
else
    echo -e "${C_YELLOW}⚠ Config already exists, skipping${C_RESET}"
fi

echo ""

# Claude Code Integration
echo -e "${C_BOLD}Claude Code Integration${C_RESET}"
echo -e "${C_CYAN}To integrate with Claude Code, add this to your Claude Code config:${C_RESET}"
echo ""

cat <<EOF
{
  "hooks": {
    "user-prompt-submit": "${WOW_INSTALL_DIR}/hooks/user-prompt-submit.sh"
  }
}
EOF

echo ""
echo -e "${C_YELLOW}Note: Hook scripts need to be added to your Claude Code configuration manually.${C_RESET}"
echo -e "${C_YELLOW}Location: ~/.claude/config.json or your project's .claude/config.json${C_RESET}"

echo ""

# Environment variables
echo -e "${C_BOLD}Environment Variables${C_RESET}"
echo -e "Add these to your ~/.bashrc or ~/.zshrc:"
echo ""
echo "export WOW_HOME=\"${WOW_INSTALL_DIR}\""
echo "export WOW_DATA_DIR=\"${DATA_DIR}\""
echo ""

# Test installation
echo -e "${C_BOLD}Testing installation...${C_RESET}"

if bash "${WOW_INSTALL_DIR}/src/core/orchestrator.sh" &>/dev/null; then
    echo -e "${C_GREEN}✓ Orchestrator loads successfully${C_RESET}"
else
    echo -e "${C_RED}✗ Orchestrator test failed${C_RESET}"
    exit 1
fi

# Run quick self-tests
echo ""
echo -e "${C_BOLD}Running self-tests...${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/handlers/bash-handler.sh" | grep -q "All self-tests passed" && \
    echo -e "${C_GREEN}✓ Bash handler${C_RESET}" || echo -e "${C_RED}✗ Bash handler${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/handlers/write-handler.sh" | grep -q "All self-tests passed" && \
    echo -e "${C_GREEN}✓ Write handler${C_RESET}" || echo -e "${C_RED}✗ Write handler${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/handlers/edit-handler.sh" | grep -q "All self-tests passed" && \
    echo -e "${C_GREEN}✓ Edit handler${C_RESET}" || echo -e "${C_RED}✗ Edit handler${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/engines/scoring-engine.sh" | grep -q "All tests passed" && \
    echo -e "${C_GREEN}✓ Scoring engine${C_RESET}" || echo -e "${C_RED}✗ Scoring engine${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/engines/risk-assessor.sh" | grep -q "All tests passed" && \
    echo -e "${C_GREEN}✓ Risk assessor${C_RESET}" || echo -e "${C_RED}✗ Risk assessor${C_RESET}"

echo ""
echo -e "${C_BOLD}${C_GREEN}✓ WoW System installed successfully!${C_RESET}"
echo ""
echo -e "${C_BOLD}Next Steps:${C_RESET}"
echo "1. Add hook configuration to Claude Code config"
echo "2. Add environment variables to your shell config"
echo "3. Restart your shell or Claude Code"
echo "4. Start using Claude Code with WoW protection!"
echo ""
echo -e "${C_CYAN}For more information, see: ${WOW_INSTALL_DIR}/README.md${C_RESET}"
