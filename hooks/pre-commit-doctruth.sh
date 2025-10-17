#!/bin/bash
# Pre-commit Hook: docTruth Documentation Validation
# Author: Chude <chude@emeke.org>
#
# Purpose: Ensures documentation is current before allowing commits
# Strategy: Hybrid enforcement - check and offer to fix
#
# Installation:
#   ln -sf ../../hooks/pre-commit-doctruth.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Bypass (emergency use only):
#   git commit --no-verify

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if doctruth is installed
if ! command -v doctruth &>/dev/null; then
    echo -e "${YELLOW}⚠️  doctruth not installed - skipping documentation check${NC}"
    echo -e "${BLUE}ℹ️  Install with: npm install -g doctruth${NC}"
    exit 0
fi

# Check if .doctruth.yml exists
if [ ! -f .doctruth.yml ]; then
    echo -e "${YELLOW}⚠️  No .doctruth.yml found - skipping documentation check${NC}"
    exit 0
fi

echo -e "${BLUE}📚 Checking documentation status with docTruth...${NC}"

# Check if documentation is current
if doctruth --check &>/dev/null; then
    echo -e "${GREEN}✓ Documentation is up to date${NC}"
    exit 0
else
    echo -e "${RED}❌ Documentation is outdated${NC}"
    echo ""
    echo -e "${YELLOW}Your CURRENT_TRUTH.md does not match the current codebase state.${NC}"
    echo ""
    echo "Options:"
    echo "  1. Update documentation now (recommended)"
    echo "  2. Skip this check (use --no-verify)"
    echo ""
    read -p "Update documentation now? [Y/n] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo -e "${BLUE}🔄 Updating documentation...${NC}"

        # Run doctruth to generate updated docs
        if doctruth; then
            echo -e "${GREEN}✓ Documentation updated successfully${NC}"

            # Stage the updated truth file
            if git add CURRENT_TRUTH.md; then
                echo -e "${GREEN}✓ CURRENT_TRUTH.md staged for commit${NC}"
                echo ""
                echo -e "${BLUE}ℹ️  Documentation update will be included in this commit${NC}"
                exit 0
            else
                echo -e "${YELLOW}⚠️  Could not stage CURRENT_TRUTH.md${NC}"
                exit 1
            fi
        else
            echo -e "${RED}✗ doctruth update failed${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  Commit blocked - documentation is outdated${NC}"
        echo ""
        echo "To commit anyway, use:"
        echo "  git commit --no-verify"
        echo ""
        echo "To update documentation manually:"
        echo "  doctruth"
        echo "  git add CURRENT_TRUTH.md"
        echo ""
        exit 1
    fi
fi
