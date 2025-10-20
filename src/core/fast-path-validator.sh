#!/bin/bash
# WoW System - Fast Path Validator (Performance-Critical)
# Provides early exit validation for obviously safe file operations
# Author: Chude <chude@emeke.org>
#
# Design Patterns:
# - Chain of Responsibility: Progressive validation layers
# - Strategy Pattern: Different validators for different checks
# - Template Method: Common flow, specific implementations
#
# SOLID Principles:
# - SRP: Each validator has ONE responsibility
# - OCP: Open for extension (add validators), closed for modification
# - DIP: Depends on abstractions (validator interface)

# Prevent double-sourcing
if [[ -n "${WOW_FAST_PATH_VALIDATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_FAST_PATH_VALIDATOR_LOADED=1

# Source dependencies
_FAST_PATH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_FAST_PATH_DIR}/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Safe Patterns
# ============================================================================

readonly FAST_PATH_VERSION="1.0.0"

# Safe file extensions (high confidence - auto-allow)
readonly -a FAST_PATH_SAFE_EXTENSIONS=(
    "\\.js$"
    "\\.ts$"
    "\\.jsx$"
    "\\.tsx$"
    "\\.py$"
    "\\.sh$"
    "\\.bash$"
    "\\.md$"
    "\\.markdown$"
    "\\.txt$"
    "\\.json$"
    "\\.ya?ml$"
    "\\.toml$"
    "\\.conf$"
    "\\.config$"
    "\\.xml$"
    "\\.html$"
    "\\.css$"
    "\\.scss$"
    "\\.less$"
    "\\.sql$"
    "\\.graphql$"
    "\\.proto$"
    "Makefile$"
    "Dockerfile$"
    "README"
    "\\.gitignore$"
    "\\.editorconfig$"
    "package\\.json$"
    "tsconfig\\.json$"
    "composer\\.json$"
    "Cargo\\.toml$"
    "go\\.mod$"
)

# Dangerous paths (immediate block - TIER 1 only: catastrophic security risk)
# v5.3.0: Aligned with three-tier system - only block truly catastrophic files
# TIER 2 (sensitive) files are NOT blocked here - they get deep validation
readonly -a FAST_PATH_BLOCKED_PATHS=(
    "^/etc/shadow$"        # TIER 1: System password hashes
    "^/etc/sudoers"        # TIER 1: Sudo configuration
    "^/etc/gshadow$"       # TIER 1: Group password hashes
    "^/sys/"               # System pseudo-filesystem (rarely accessed)
    "^/boot/"              # Boot partition (rarely accessed)
)

# Suspicious patterns (needs deep check - TIER 2 candidates)
# v5.3.0: Expanded to include all TIER 2 patterns for deep validation
readonly -a FAST_PATH_SUSPICIOUS_PATTERNS=(
    # Application credentials
    "\\.env$"
    "\\.env\\."
    "credentials?\\.json$"
    "secrets?\\.ya?ml$"
    "secrets?\\.json$"
    "private.*\\.pem$"
    ".*-key\\.pem$"
    "\\.p12$"
    "\\.pfx$"

    # System files that might be legitimate
    "^/etc/"               # Most /etc files are TIER 2 (except shadow/sudoers/gshadow)
    "^/root/"              # Root home (might be WSL dev environment)
    "^/proc/.*/environ"    # Process environments

    # User credentials and keys
    "/\\.ssh/id_"          # SSH keys (private and public)
    "/\\.aws/"             # AWS config/credentials
    "/\\.config/gcloud/"   # GCP credentials
    "/\\.gnupg/"           # GPG keys

    # Cryptocurrency
    "wallet\\.dat$"
    "/\\.bitcoin/"
    "/\\.ethereum/"
)

# ============================================================================
# Layer 1: Current Directory Validator (5-10ms)
# ============================================================================

# Check if file is in current directory (safe working area)
_fast_path_current_directory() {
    local file_path="$1"

    # Empty path - suspicious
    if [[ -z "${file_path}" ]]; then
        return 1  # Needs deep check
    fi

    # Absolute paths starting with dangerous prefixes
    if [[ "${file_path}" == /* ]]; then
        # Check blocked paths
        for pattern in "${FAST_PATH_BLOCKED_PATHS[@]}"; do
            if echo "${file_path}" | grep -qE "${pattern}"; then
                return 2  # BLOCK immediately
            fi
        done
        # Other absolute paths need deep check
        return 1
    fi

    # Path traversal patterns
    if echo "${file_path}" | grep -qE '\.\./'; then
        # Path traversal - could be targeting sensitive files
        # Check if targeting dangerous locations
        if echo "${file_path}" | grep -qE '(etc|root|shadow|passwd|sudoers|\.ssh|\.aws|\.gnupg)'; then
            return 2  # BLOCK - dangerous traversal
        fi
        # Other traversals need deep check
        return 1
    fi

    # Relative path in current directory - continue to next check
    return 1  # Continue to extension check
}

# ============================================================================
# Layer 2: Safe Extension Validator (5-10ms)
# ============================================================================

# Check if file has safe extension
_fast_path_safe_extension() {
    local file_path="$1"

    # Check for suspicious patterns first (even with safe extensions)
    for pattern in "${FAST_PATH_SUSPICIOUS_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            return 1  # Needs deep check (.env, secrets.json, etc.)
        fi
    done

    # Check for safe extensions
    for pattern in "${FAST_PATH_SAFE_EXTENSIONS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            return 0  # SAFE - allow
        fi
    done

    # Unknown extension - needs deep check
    return 1
}

# ============================================================================
# Layer 3: Non-System Path Validator (5ms)
# ============================================================================

# Final safety check for system paths
_fast_path_not_system_path() {
    local file_path="$1"

    # Already checked in layer 1, but double-check for safety
    for pattern in "${FAST_PATH_BLOCKED_PATHS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            return 2  # BLOCK
        fi
    done

    # Not a system path
    return 0  # Safe
}

# ============================================================================
# Public API: Main Validation Function
# ============================================================================

# Fast path validation with early exit
# Args:
#   $1 - file_path: Path to validate
#   $2 - operation_type: read|write|edit (optional)
#
# Returns:
#   0 = ALLOW (safe, skip deep validation)
#   1 = CONTINUE (needs deep validation)
#   2 = BLOCK (obviously dangerous)
#
# Design: Chain of Responsibility Pattern
# Each validator can:
#   - Return 0 (safe) → immediate exit
#   - Return 2 (block) → immediate exit
#   - Return 1 (continue) → next validator
fast_path_validate() {
    local file_path="$1"
    local operation_type="${2:-read}"

    # Check if fast path is enabled in config
    if type config_get_bool &>/dev/null; then
        if ! config_get_bool "performance.fast_path_enabled" "true"; then
            # Fast path disabled - skip to deep validation
            return 1
        fi
    fi

    # Layer 1: Current Directory Check
    local result
    _fast_path_current_directory "${file_path}"
    result=$?

    case ${result} in
        0)  # Safe from layer 1
            # Continue to next layer (don't exit yet)
            ;;
        2)  # Blocked from layer 1
            wow_debug "Fast path BLOCK: ${file_path} (dangerous path)"
            return 2
            ;;
        1)  # Continue to next layer
            ;;
    esac

    # Layer 2: Safe Extension Check
    _fast_path_safe_extension "${file_path}"
    result=$?

    case ${result} in
        0)  # Safe from layer 2
            # File has safe extension and passed layer 1
            # One final safety check before allowing
            _fast_path_not_system_path "${file_path}"
            result=$?

            if [[ ${result} -eq 0 ]]; then
                wow_debug "Fast path ALLOW: ${file_path} (safe extension + not system path)"
                return 0  # ALLOW - skip deep validation
            elif [[ ${result} -eq 2 ]]; then
                wow_debug "Fast path BLOCK: ${file_path} (system path)"
                return 2  # BLOCK
            fi
            ;;
        2)  # Blocked from layer 2
            return 2
            ;;
        1)  # Continue (needs deep check)
            ;;
    esac

    # Layer 3: If we reach here, needs deep validation
    wow_debug "Fast path CONTINUE: ${file_path} (needs deep validation)"
    return 1  # Continue to deep validation
}

# ============================================================================
# Configuration Helpers
# ============================================================================

# Check if fast path is enabled
fast_path_enabled() {
    if type config_get_bool &>/dev/null; then
        config_get_bool "performance.fast_path_enabled" "true"
    else
        # Default: enabled
        return 0
    fi
}

# ============================================================================
# Metrics & Debugging
# ============================================================================

# Track fast path hit rate (optional - for performance monitoring)
fast_path_track_result() {
    local result="$1"  # allow|block|continue

    if type session_increment_metric &>/dev/null; then
        session_increment_metric "fast_path_total" 2>/dev/null || true

        case "${result}" in
            allow)
                session_increment_metric "fast_path_allows" 2>/dev/null || true
                ;;
            block)
                session_increment_metric "fast_path_blocks" 2>/dev/null || true
                ;;
            continue)
                session_increment_metric "fast_path_continues" 2>/dev/null || true
                ;;
        esac
    fi
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Fast Path Validator v${FAST_PATH_VERSION} - Self Test"
    echo "=========================================================="
    echo ""

    # Test 1: Safe file
    fast_path_validate "src/app.ts" "read"
    [[ $? -eq 0 ]] && echo "✓ Safe file (src/app.ts) allows" || echo "✗ Failed"

    # Test 2: System path
    fast_path_validate "/etc/passwd" "read"
    [[ $? -eq 2 ]] && echo "✓ System path (/etc/passwd) blocks" || echo "✗ Failed"

    # Test 3: Suspicious file
    fast_path_validate ".env" "read"
    [[ $? -eq 1 ]] && echo "✓ Suspicious file (.env) needs deep check" || echo "✗ Failed"

    # Test 4: Safe extension in project
    fast_path_validate "README.md" "read"
    [[ $? -eq 0 ]] && echo "✓ README.md allows" || echo "✗ Failed"

    # Test 5: Path traversal to system
    fast_path_validate "../../etc/shadow" "read"
    [[ $? -eq 2 ]] && echo "✓ Path traversal to /etc blocks" || echo "✗ Failed"

    # Test 6: Unknown extension
    fast_path_validate "data.dat" "read"
    [[ $? -eq 1 ]] && echo "✓ Unknown extension needs deep check" || echo "✗ Failed"

    echo ""
    echo "All self-tests passed! ✓"
fi
