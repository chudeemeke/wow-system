#!/bin/bash
# WoW System - Version Change Detector
# Detects modifications to version-containing files and triggers documentation updates
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Format-agnostic: Works with ANY version numbering (1.0, 1.0.0, v1.2.3-beta, etc.)
# - File-based detection: Monitors file changes, not version parsing
# - Language-universal: Supports Node.js, Python, Rust, Java, Bash, etc.
# - Event-driven: Publishes to event bus for loose coupling

# Prevent double-sourcing
if [[ -n "${WOW_VERSION_DETECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_VERSION_DETECTOR_LOADED=1

# Source dependencies
_VERSION_DETECTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_VERSION_DETECTOR_DIR}/utils.sh"
source "${_VERSION_DETECTOR_DIR}/../patterns/event-bus.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Version File Patterns
# ============================================================================

# Primary version files (by filename)
declare -a VERSION_FILES_PRIMARY=(
    "package.json"          # Node.js, JavaScript
    "pyproject.toml"        # Python (modern)
    "setup.py"              # Python (legacy)
    "Cargo.toml"            # Rust
    "pom.xml"               # Java/Maven
    "build.gradle"          # Java/Gradle
    "composer.json"         # PHP
    "Gemfile"               # Ruby
    "go.mod"                # Go
    "mix.exs"               # Elixir
)

# Secondary version files (by filename pattern)
declare -a VERSION_FILES_SECONDARY=(
    "version.sh"            # Bash scripts
    "version.py"            # Python version modules
    "__init__.py"           # Python package init
    "version.txt"           # Generic version files
    "VERSION"               # Generic version files
    ".version"              # Hidden version files
)

# Files that commonly contain version constants (require content check)
declare -a VERSION_CONSTANT_FILES=(
    "utils.sh"              # Bash utilities
    "config.sh"             # Bash config
    "constants.py"          # Python constants
    "version.rs"            # Rust version
    "build.gradle.kts"      # Kotlin Gradle
)

# ============================================================================
# Core Detection Logic
# ============================================================================

# Main detection function - call this after file write/edit operations
# Usage: version_detect_file_change "/path/to/file.txt"
# Returns: 0 if version file detected, 1 if not
version_detect_file_change() {
    local file_path="$1"
    local file_name
    file_name=$(basename "$file_path" 2>/dev/null || echo "")

    # Skip if empty
    [[ -z "$file_path" ]] && return 1
    [[ -z "$file_name" ]] && return 1

    # Check primary version files (exact filename match)
    if _version_is_primary_file "$file_name"; then
        _version_publish_event "$file_path" "primary"
        return 0
    fi

    # Check secondary version files (pattern match)
    if _version_is_secondary_file "$file_name"; then
        _version_publish_event "$file_path" "secondary"
        return 0
    fi

    # Check if file commonly contains version constants
    if _version_has_constant "$file_path" "$file_name"; then
        _version_publish_event "$file_path" "constant"
        return 0
    fi

    return 1
}

# Check if filename matches primary version files
_version_is_primary_file() {
    local file_name="$1"

    for version_file in "${VERSION_FILES_PRIMARY[@]}"; do
        if [[ "$file_name" == "$version_file" ]]; then
            return 0
        fi
    done

    return 1
}

# Check if filename matches secondary version file patterns
_version_is_secondary_file() {
    local file_name="$1"

    for version_file in "${VERSION_FILES_SECONDARY[@]}"; do
        if [[ "$file_name" == "$version_file" ]]; then
            return 0
        fi
    done

    return 1
}

# Check if file contains version constants (requires content inspection)
_version_has_constant() {
    local file_path="$1"
    local file_name="$2"

    # Only check specific filenames to avoid performance issues
    local should_check=false
    for const_file in "${VERSION_CONSTANT_FILES[@]}"; do
        if [[ "$file_name" == "$const_file" ]]; then
            should_check=true
            break
        fi
    done

    [[ "$should_check" == false ]] && return 1

    # File must exist and be readable
    [[ ! -f "$file_path" ]] && return 1
    [[ ! -r "$file_path" ]] && return 1

    # Check if file contains version-related patterns
    # Look for: VERSION=, version=, __version__, etc.
    if grep -qE "(readonly\s+)?[A-Z_]*VERSION[A-Z_]*\s*=|__version__\s*=|version\s*=\s*['\"]" "$file_path" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Publish version bump event to event bus
_version_publish_event() {
    local file_path="$1"
    local detection_type="$2"  # primary, secondary, constant

    wow_debug "Version file detected: ${file_path} (type: ${detection_type})"

    # Publish to event bus if available
    if command -v event_bus_publish &>/dev/null; then
        event_bus_publish "version_bump" "file=${file_path}|type=${detection_type}" 2>/dev/null || {
            wow_debug "Event bus publish failed (non-fatal)"
        }
    else
        wow_debug "Event bus not available, skipping publish"
    fi

    return 0
}

# ============================================================================
# Utility Functions
# ============================================================================

# Get list of all monitored version files (for documentation/debugging)
version_get_monitored_files() {
    echo "Primary version files:"
    printf '  - %s\n' "${VERSION_FILES_PRIMARY[@]}"
    echo ""
    echo "Secondary version files:"
    printf '  - %s\n' "${VERSION_FILES_SECONDARY[@]}"
    echo ""
    echo "Version constant files:"
    printf '  - %s\n' "${VERSION_CONSTANT_FILES[@]}"
}

# Test if a specific filename would trigger detection (for testing)
version_test_filename() {
    local file_name="$1"

    if _version_is_primary_file "$file_name"; then
        echo "✓ PRIMARY: $file_name"
        return 0
    elif _version_is_secondary_file "$file_name"; then
        echo "✓ SECONDARY: $file_name"
        return 0
    else
        echo "✗ NOT DETECTED: $file_name"
        return 1
    fi
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Version Detector - Self Test"
    echo "================================="
    echo ""

    echo "Testing primary version files:"
    for file in "${VERSION_FILES_PRIMARY[@]}"; do
        version_test_filename "$file"
    done

    echo ""
    echo "Testing secondary version files:"
    for file in "${VERSION_FILES_SECONDARY[@]}"; do
        version_test_filename "$file"
    done

    echo ""
    echo "Testing non-version files:"
    version_test_filename "README.md"
    version_test_filename "src/index.js"
    version_test_filename "main.py"

    echo ""
    echo "All tests complete!"
fi

wow_debug "Version detector loaded"
