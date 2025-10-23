#!/bin/bash
# WoW System - Installation Script v5.4.0
# Deploys WoW System with Windows filesystem strategy for WSL2
# Author: Chude <chude@emeke.org>

set -eo pipefail

# Colors
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# Version
WOW_VERSION="5.4.0"

# Display banner
echo -e "${C_BOLD}${C_CYAN}"
cat <<'EOF'
╔══════════════════════════════════════════╗
║  WoW System Installation v5.4.0          ║
║  Ways of Working Enforcement             ║
║  Multi-Session Analytics & Custom Rules  ║
╚══════════════════════════════════════════╝
EOF
echo -e "${C_RESET}"
echo ""

# ============================================================================
# Environment Detection
# ============================================================================

echo -e "${C_BOLD}1. Detecting Environment...${C_RESET}"

# Determine project directory (where this script is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "   ${C_GREEN}✓${C_RESET} Project directory: ${C_CYAN}${SCRIPT_DIR}${C_RESET}"

# Detect WSL
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=1
    echo -e "   ${C_GREEN}✓${C_RESET} Running in WSL2"
fi

# Auto-detect Windows user directory (for WSL)
WINDOWS_CLAUDE_DIR=""
if [[ ${IS_WSL} -eq 1 ]]; then
    # Try to find Windows user directory
    if [[ -d "/mnt/c/Users" ]]; then
        # Look for the current user's directory
        WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")
        if [[ -n "${WIN_USER}" ]]; then
            WINDOWS_CLAUDE_DIR="/mnt/c/Users/${WIN_USER}/.claude"
            echo -e "   ${C_GREEN}✓${C_RESET} Detected Windows user: ${C_CYAN}${WIN_USER}${C_RESET}"
        fi
    fi
fi

# Determine deployment location
if [[ -n "${WINDOWS_CLAUDE_DIR}" ]]; then
    # WSL: Deploy to Windows filesystem for persistence
    CLAUDE_DIR="${WINDOWS_CLAUDE_DIR}"
    DEPLOYMENT_STRATEGY="Windows Filesystem (WSL)"
else
    # Native Linux: Deploy to home directory
    CLAUDE_DIR="${HOME}/.claude"
    DEPLOYMENT_STRATEGY="Linux Filesystem"
fi

echo -e "   ${C_GREEN}✓${C_RESET} Deployment location: ${C_CYAN}${CLAUDE_DIR}${C_RESET}"
echo -e "   ${C_GREEN}✓${C_RESET} Strategy: ${C_CYAN}${DEPLOYMENT_STRATEGY}${C_RESET}"

# WoW installation directory within Claude directory
WOW_INSTALL_DIR="${CLAUDE_DIR}/wow-system"

echo ""

# ============================================================================
# Prerequisites Check
# ============================================================================

echo -e "${C_BOLD}2. Checking Prerequisites...${C_RESET}"

# Check bash
if ! command -v bash &> /dev/null; then
    echo -e "   ${C_RED}✗ bash not found${C_RESET}"
    exit 1
fi
echo -e "   ${C_GREEN}✓${C_RESET} bash $(bash --version | head -1 | cut -d' ' -f4)"

# Check jq (recommended but not required)
if command -v jq &> /dev/null; then
    echo -e "   ${C_GREEN}✓${C_RESET} jq $(jq --version 2>&1 | cut -d'-' -f2)"
else
    echo -e "   ${C_YELLOW}⚠${C_RESET} jq not found (recommended for JSON parsing, will use grep fallback)"
fi

# Check git (for version info)
if command -v git &> /dev/null; then
    GIT_VERSION=$(cd "${SCRIPT_DIR}" && git describe --tags 2>/dev/null || echo "unknown")
    echo -e "   ${C_GREEN}✓${C_RESET} git version ${GIT_VERSION}"
fi

echo ""

# ============================================================================
# Check for Existing Installation
# ============================================================================

echo -e "${C_BOLD}3. Checking for Existing Installation...${C_RESET}"

EXISTING_INSTALL=0
BACKUP_DIR=""

if [[ -d "${WOW_INSTALL_DIR}" ]]; then
    EXISTING_INSTALL=1
    echo -e "   ${C_YELLOW}⚠${C_RESET} Existing WoW System found at: ${WOW_INSTALL_DIR}"

    # Check existing version
    if [[ -f "${WOW_INSTALL_DIR}/src/core/utils.sh" ]]; then
        EXISTING_VERSION=$(grep "readonly WOW_VERSION=" "${WOW_INSTALL_DIR}/src/core/utils.sh" | cut -d'"' -f2 || echo "unknown")
        echo -e "   ${C_CYAN}ℹ${C_RESET} Existing version: ${EXISTING_VERSION}"
    fi

    # Ask user for confirmation
    echo ""
    echo -e "   ${C_BOLD}${C_YELLOW}WARNING:${C_RESET} This will ${C_BOLD}backup${C_RESET} the existing installation and install v${WOW_VERSION}"
    read -p "   Continue? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${C_RED}Installation cancelled by user${C_RESET}"
        exit 0
    fi

    # Create backup
    BACKUP_DIR="${WOW_INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "   ${C_CYAN}ℹ${C_RESET} Creating backup: ${BACKUP_DIR}"
    mv "${WOW_INSTALL_DIR}" "${BACKUP_DIR}"
    echo -e "   ${C_GREEN}✓${C_RESET} Backup created"
else
    echo -e "   ${C_GREEN}✓${C_RESET} No existing installation found (fresh install)"
fi

echo ""

# ============================================================================
# Create Directory Structure
# ============================================================================

echo -e "${C_BOLD}4. Creating Directory Structure...${C_RESET}"

# Create main .claude directory
mkdir -p "${CLAUDE_DIR}"
echo -e "   ${C_GREEN}✓${C_RESET} Created: ${CLAUDE_DIR}"

# Create hooks directory
mkdir -p "${CLAUDE_DIR}/hooks"
echo -e "   ${C_GREEN}✓${C_RESET} Created: ${CLAUDE_DIR}/hooks"

# Create WoW installation directory
mkdir -p "${WOW_INSTALL_DIR}"
echo -e "   ${C_GREEN}✓${C_RESET} Created: ${WOW_INSTALL_DIR}"

# Create data directory (session data, metrics)
mkdir -p "${HOME}/.wow-data"
echo -e "   ${C_GREEN}✓${C_RESET} Created: ${HOME}/.wow-data"

echo ""

# ============================================================================
# Copy Project Files
# ============================================================================

echo -e "${C_BOLD}5. Deploying WoW System v${WOW_VERSION}...${C_RESET}"

# Copy src directory
cp -r "${SCRIPT_DIR}/src" "${WOW_INSTALL_DIR}/"
echo -e "   ${C_GREEN}✓${C_RESET} Deployed: src/"

# Copy config directory
cp -r "${SCRIPT_DIR}/config" "${WOW_INSTALL_DIR}/"
echo -e "   ${C_GREEN}✓${C_RESET} Deployed: config/"

# Copy tests directory
cp -r "${SCRIPT_DIR}/tests" "${WOW_INSTALL_DIR}/"
echo -e "   ${C_GREEN}✓${C_RESET} Deployed: tests/"

# Copy hooks to Claude hooks directory
cp "${SCRIPT_DIR}/hooks/user-prompt-submit.sh" "${CLAUDE_DIR}/hooks/"
chmod +x "${CLAUDE_DIR}/hooks/user-prompt-submit.sh"
echo -e "   ${C_GREEN}✓${C_RESET} Deployed: hooks/user-prompt-submit.sh"

# Copy documentation
for doc in README.md CHANGELOG.md CLAUDE.md; do
    if [[ -f "${SCRIPT_DIR}/${doc}" ]]; then
        cp "${SCRIPT_DIR}/${doc}" "${WOW_INSTALL_DIR}/"
        echo -e "   ${C_GREEN}✓${C_RESET} Deployed: ${doc}"
    fi
done

echo ""

# ============================================================================
# Create Symlink (WSL only)
# ============================================================================

if [[ ${IS_WSL} -eq 1 ]] && [[ -n "${WINDOWS_CLAUDE_DIR}" ]]; then
    echo -e "${C_BOLD}6. Creating Symlink...${C_RESET}"

    # Check if ~/.claude already exists
    if [[ -L "${HOME}/.claude" ]]; then
        # It's a symlink
        CURRENT_TARGET=$(readlink -f "${HOME}/.claude")
        echo -e "   ${C_CYAN}ℹ${C_RESET} Existing symlink found: ${HOME}/.claude → ${CURRENT_TARGET}"

        if [[ "${CURRENT_TARGET}" == "${WINDOWS_CLAUDE_DIR}" ]]; then
            echo -e "   ${C_GREEN}✓${C_RESET} Symlink already correct"
        else
            echo -e "   ${C_YELLOW}⚠${C_RESET} Updating symlink to point to Windows filesystem"
            rm "${HOME}/.claude"
            ln -sf "${WINDOWS_CLAUDE_DIR}" "${HOME}/.claude"
            echo -e "   ${C_GREEN}✓${C_RESET} Symlink updated"
        fi
    elif [[ -d "${HOME}/.claude" ]]; then
        # It's a directory - need to decide what to do
        echo -e "   ${C_YELLOW}⚠${C_RESET} ${HOME}/.claude is a directory (not a symlink)"
        echo -e "   ${C_CYAN}ℹ${C_RESET} For WSL, we recommend symlinking to Windows filesystem"
        read -p "   Convert to symlink? (y/N): " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup the directory
            mv "${HOME}/.claude" "${HOME}/.claude.backup.$(date +%Y%m%d_%H%M%S)"
            ln -sf "${WINDOWS_CLAUDE_DIR}" "${HOME}/.claude"
            echo -e "   ${C_GREEN}✓${C_RESET} Created symlink: ~/.claude → ${WINDOWS_CLAUDE_DIR}"
        fi
    else
        # Doesn't exist - create symlink
        ln -sf "${WINDOWS_CLAUDE_DIR}" "${HOME}/.claude"
        echo -e "   ${C_GREEN}✓${C_RESET} Created symlink: ~/.claude → ${WINDOWS_CLAUDE_DIR}"
    fi

    echo ""
fi

# ============================================================================
# Configure Claude Code Settings
# ============================================================================

echo -e "${C_BOLD}7. Configuring Claude Code...${C_RESET}"

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# Create or update settings.json
if [[ ! -f "${SETTINGS_FILE}" ]]; then
    # Create new settings file
    cat > "${SETTINGS_FILE}" <<SETTINGSEOF
{
  "hooks": {
    "PreToolUse": "${CLAUDE_DIR}/hooks/user-prompt-submit.sh"
  },
  "wow_system": {
    "version": "${WOW_VERSION}",
    "enabled": true
  }
}
SETTINGSEOF
    echo -e "   ${C_GREEN}✓${C_RESET} Created: ${SETTINGS_FILE}"
else
    echo -e "   ${C_CYAN}ℹ${C_RESET} Settings file exists: ${SETTINGS_FILE}"
    echo -e "   ${C_YELLOW}⚠${C_RESET} Please ensure PreToolUse hook is configured:"
    echo -e "       ${C_CYAN}\"PreToolUse\": \"${CLAUDE_DIR}/hooks/user-prompt-submit.sh\"${C_RESET}"
fi

echo ""

# ============================================================================
# Set Environment Variables
# ============================================================================

echo -e "${C_BOLD}8. Environment Variables Setup...${C_RESET}"

# Determine shell config file
SHELL_CONFIG=""
if [[ -f "${HOME}/.bashrc" ]]; then
    SHELL_CONFIG="${HOME}/.bashrc"
elif [[ -f "${HOME}/.zshrc" ]]; then
    SHELL_CONFIG="${HOME}/.zshrc"
fi

echo -e "   ${C_CYAN}ℹ${C_RESET} Add these to your shell config (${SHELL_CONFIG}):"
echo ""
echo -e "${C_CYAN}export WOW_HOME=\"${WOW_INSTALL_DIR}\"${C_RESET}"
echo -e "${C_CYAN}export WOW_DATA_DIR=\"${HOME}/.wow-data\"${C_RESET}"
echo ""

# Optionally add to shell config
if [[ -n "${SHELL_CONFIG}" ]]; then
    read -p "   Add environment variables to ${SHELL_CONFIG}? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Check if already exists
        if grep -q "WOW_HOME" "${SHELL_CONFIG}"; then
            echo -e "   ${C_YELLOW}⚠${C_RESET} WOW_HOME already set in ${SHELL_CONFIG}"
        else
            cat >> "${SHELL_CONFIG}" <<ENVEOF

# WoW System v${WOW_VERSION}
export WOW_HOME="${WOW_INSTALL_DIR}"
export WOW_DATA_DIR="${HOME}/.wow-data"
ENVEOF
            echo -e "   ${C_GREEN}✓${C_RESET} Added to ${SHELL_CONFIG}"
        fi
    fi
fi

echo ""

# ============================================================================
# Test Installation
# ============================================================================

echo -e "${C_BOLD}9. Testing Installation...${C_RESET}"

# Set environment for testing
export WOW_HOME="${WOW_INSTALL_DIR}"
export WOW_DATA_DIR="${HOME}/.wow-data"

# Test orchestrator
if bash "${WOW_INSTALL_DIR}/src/core/orchestrator.sh" &>/dev/null; then
    echo -e "   ${C_GREEN}✓${C_RESET} Core orchestrator loads successfully"
else
    echo -e "   ${C_RED}✗${C_RESET} Orchestrator test FAILED"
    exit 1
fi

echo ""
echo -e "${C_BOLD}10. Running Handler Self-Tests...${C_RESET}"

# Test all 10 handlers
bash "${WOW_INSTALL_DIR}/src/handlers/bash-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Bash handler" || echo -e "   ${C_RED}✗${C_RESET} Bash handler"

bash "${WOW_INSTALL_DIR}/src/handlers/write-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Write handler" || echo -e "   ${C_RED}✗${C_RESET} Write handler"

bash "${WOW_INSTALL_DIR}/src/handlers/edit-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Edit handler" || echo -e "   ${C_RED}✗${C_RESET} Edit handler"

bash "${WOW_INSTALL_DIR}/src/handlers/read-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Read handler" || echo -e "   ${C_RED}✗${C_RESET} Read handler"

bash "${WOW_INSTALL_DIR}/src/handlers/glob-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Glob handler" || echo -e "   ${C_RED}✗${C_RESET} Glob handler"

bash "${WOW_INSTALL_DIR}/src/handlers/grep-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Grep handler" || echo -e "   ${C_RED}✗${C_RESET} Grep handler"

bash "${WOW_INSTALL_DIR}/src/handlers/task-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Task handler" || echo -e "   ${C_RED}✗${C_RESET} Task handler"

bash "${WOW_INSTALL_DIR}/src/handlers/webfetch-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} WebFetch handler" || echo -e "   ${C_RED}✗${C_RESET} WebFetch handler"

bash "${WOW_INSTALL_DIR}/src/handlers/websearch-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} WebSearch handler (v5.4.0)" || echo -e "   ${C_RED}✗${C_RESET} WebSearch handler"

bash "${WOW_INSTALL_DIR}/src/handlers/notebookedit-handler.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} NotebookEdit handler (v5.4.0)" || echo -e "   ${C_RED}✗${C_RESET} NotebookEdit handler"

echo ""
echo -e "${C_BOLD}11. Testing Analytics & Pattern Modules (v5.4.0)...${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/analytics/patterns.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Pattern recognition engine" || echo -e "   ${C_YELLOW}⚠${C_RESET} Pattern recognition (optional)"

bash "${WOW_INSTALL_DIR}/src/rules/dsl.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Custom Rule DSL" || echo -e "   ${C_YELLOW}⚠${C_RESET} Custom Rule DSL (optional)"

bash "${WOW_INSTALL_DIR}/src/handlers/custom-rule-helper.sh" 2>/dev/null | grep -q "All self-tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Custom Rule Helper" || echo -e "   ${C_YELLOW}⚠${C_RESET} Custom Rule Helper (optional)"

echo ""
echo -e "${C_BOLD}12. Testing Core Engines...${C_RESET}"

bash "${WOW_INSTALL_DIR}/src/engines/scoring-engine.sh" 2>/dev/null | grep -q "All tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Scoring engine" || echo -e "   ${C_YELLOW}⚠${C_RESET} Scoring engine"

bash "${WOW_INSTALL_DIR}/src/engines/risk-assessor.sh" 2>/dev/null | grep -q "All tests passed" && \
    echo -e "   ${C_GREEN}✓${C_RESET} Risk assessor" || echo -e "   ${C_YELLOW}⚠${C_RESET} Risk assessor"

echo ""

# ============================================================================
# Installation Complete
# ============================================================================

echo -e "${C_BOLD}${C_GREEN}✓ WoW System v${WOW_VERSION} installed successfully!${C_RESET}"
echo ""
echo -e "${C_BOLD}Installation Summary:${C_RESET}"
echo -e "  • Deployment: ${C_CYAN}${WOW_INSTALL_DIR}${C_RESET}"
echo -e "  • Hooks: ${C_CYAN}${CLAUDE_DIR}/hooks/${C_RESET}"
echo -e "  • Data: ${C_CYAN}${HOME}/.wow-data${C_RESET}"
echo -e "  • Strategy: ${C_CYAN}${DEPLOYMENT_STRATEGY}${C_RESET}"
if [[ -n "${BACKUP_DIR}" ]]; then
    echo -e "  • Backup: ${C_CYAN}${BACKUP_DIR}${C_RESET}"
fi
echo ""

echo -e "${C_BOLD}${C_YELLOW}IMPORTANT: Next Steps${C_RESET}"
echo ""
echo -e "${C_BOLD}1. Close ALL WSL2 Tabs/Instances${C_RESET}"
echo -e "   For the changes to take full effect, close:"
echo -e "   • All WSL2 terminal tabs"
echo -e "   • The entire WSL2 Ubuntu application"
echo -e "   • Claude Code (if running)"
echo ""
echo -e "${C_BOLD}2. Restart WSL2 Fresh${C_RESET}"
echo -e "   • Open a new WSL2 terminal"
echo -e "   • Source your shell config: ${C_CYAN}source ${SHELL_CONFIG}${C_RESET}"
echo -e "   • Or just restart the terminal"
echo ""
echo -e "${C_BOLD}3. Launch Claude Code${C_RESET}"
echo -e "   You should see the WoW System v${WOW_VERSION} banner:"
echo -e "${C_CYAN}"
cat <<'BANNEREOF'
   ╔══════════════════════════════════════════════════════════╗
   ║  WoW System v5.4.0 - Ways of Working Enforcement         ║
   ║  Status: ✅ Active                                       ║
   ╚══════════════════════════════════════════════════════════╝
BANNEREOF
echo -e "${C_RESET}"
echo ""
echo -e "${C_BOLD}4. Verify Installation${C_RESET}"
echo -e "   Run a simple command to test: ${C_CYAN}echo test${C_RESET}"
echo -e "   The WoW System should intercept and validate it"
echo ""

if [[ -n "${BACKUP_DIR}" ]]; then
    echo -e "${C_BOLD}${C_CYAN}ℹ Backup Information${C_RESET}"
    echo -e "   Your previous installation was backed up to:"
    echo -e "   ${C_CYAN}${BACKUP_DIR}${C_RESET}"
    echo -e "   You can safely delete it after verifying v${WOW_VERSION} works"
    echo ""
fi

echo -e "${C_BOLD}Troubleshooting:${C_RESET}"
echo -e "  • Hook not firing? Check ${C_CYAN}${SETTINGS_FILE}${C_RESET}"
echo -e "  • Banner not showing? Ensure you closed ALL WSL2 instances"
echo -e "  • Need help? See ${C_CYAN}${WOW_INSTALL_DIR}/README.md${C_RESET}"
echo ""

echo -e "${C_CYAN}For documentation: ${WOW_INSTALL_DIR}/README.md${C_RESET}"
echo -e "${C_CYAN}For changelog: ${WOW_INSTALL_DIR}/CHANGELOG.md${C_RESET}"
echo ""
