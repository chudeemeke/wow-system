#!/bin/bash
# Git Post-Commit Hook: Version Bump Detection
# Author: Chude <chude@emeke.org>
#
# Purpose: Detects version file changes in commits and triggers docTruth updates
# Strategy: Redundant safety net - catches version bumps from ANY source
#
# Installation:
#   ln -sf ../../hooks/post-commit-version-detect.sh .git/hooks/post-commit
#   chmod +x .git/hooks/post-commit
#
# Note: This is optional - write/edit handlers already detect version changes
#       This hook provides additional coverage for manual git operations

set -eo pipefail

# Check if this is a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0  # Not a git repo, skip silently
fi

# Get WoW system location
WOW_HOME="${WOW_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Source WoW utilities if available
if [[ -f "${WOW_HOME}/src/core/utils.sh" ]]; then
    source "${WOW_HOME}/src/core/utils.sh" 2>/dev/null || true
fi

# Source event bus if available
if [[ -f "${WOW_HOME}/src/patterns/event-bus.sh" ]]; then
    source "${WOW_HOME}/src/patterns/event-bus.sh" 2>/dev/null || true
fi

# Version file patterns to detect
VERSION_FILES=(
    "package.json"
    "pyproject.toml"
    "setup.py"
    "Cargo.toml"
    "pom.xml"
    "build.gradle"
    "composer.json"
    "go.mod"
    "utils.sh"
    "version.sh"
    "version.py"
    "__init__.py"
    "VERSION"
    ".version"
)

# Get files changed in the last commit
changed_files=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || echo "")

# Check if empty (initial commit or error)
if [[ -z "$changed_files" ]]; then
    exit 0  # No files changed, skip
fi

# Check if any version files were modified
version_file_detected=false
detected_file=""

while IFS= read -r file; do
    file_name=$(basename "$file" 2>/dev/null || echo "")

    for version_file in "${VERSION_FILES[@]}"; do
        if [[ "$file_name" == "$version_file" ]]; then
            version_file_detected=true
            detected_file="$file"
            break 2
        fi
    done
done <<< "$changed_files"

# If version file detected, publish event
if [[ "$version_file_detected" == true ]]; then
    echo "🔍 Version file detected in commit: ${detected_file}"

    # Publish to event bus if available
    if command -v event_bus_publish &>/dev/null; then
        event_bus_publish "version_bump" "file=${detected_file}|source=git_commit" 2>/dev/null || {
            echo "   (Event bus unavailable, skipping)"
        }
        echo "   ✅ Documentation update triggered"
    else
        # Fallback: trigger doctruth directly if available
        if command -v doctruth &>/dev/null && [[ -f .doctruth.yml ]]; then
            echo "   📚 Running doctruth..."
            (doctruth &) || echo "   ⚠️ doctruth failed (non-fatal)"
        fi
    fi
fi

exit 0
