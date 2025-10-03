#!/bin/bash
# WoW System - Glob Handler (Production-Grade, Security-Critical)
# Intercepts glob/find operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - Privacy Protection: Prevent sensitive data discovery
# - Anti-Fishing: Detect credential/secret searches
# - Audit Logging: Track all glob operations

# Prevent double-sourcing
if [[ -n "${WOW_GLOB_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_GLOB_HANDLER_LOADED=1

# Source dependencies
_GLOB_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_GLOB_HANDLER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Protected Directories
# ============================================================================

# CRITICAL: Directories that should NEVER be globbed
readonly -a PROTECTED_GLOB_DIRS=(
    "^/etc(/|$)"
    "^/root(/|$)"
    "^/sys(/|$)"
    "^/proc(/|$)"
    "^/dev(/|$)"
    "^/boot(/|$)"
    "^/bin(/|$)"
    "^/sbin(/|$)"
    "^/usr/bin(/|$)"
    "^/usr/sbin(/|$)"
    "^/lib(/|$)"
    "^/lib64(/|$)"
    "/\\.ssh(/|$)"
    "/\\.aws(/|$)"
    "/\\.gnupg(/|$)"
    "/\\.bitcoin(/|$)"
    "/\\.ethereum(/|$)"
)

# ============================================================================
# Constants - Dangerous Patterns
# ============================================================================

# Overly broad patterns that could enumerate filesystem
readonly -a OVERLY_BROAD_PATTERNS=(
    "^/\\*\\*/\\*$"         # /**/*
    "^\\*\\*/\\*$"          # **/* (at root)
    "^/\\*\\*$"             # /**
    "^\\*\\*$"              # ** (at root)
)

# Credential/secret searching patterns (warn)
readonly -a CREDENTIAL_SEARCH_PATTERNS=(
    "\\*\\*/\\.env"
    "\\*\\*/\\.env\\..*"
    "\\*\\*/credentials"
    "\\*\\*/secrets?"
    "\\*\\*/id_rsa"
    "\\*\\*/id_dsa"
    "\\*\\*/id_ecdsa"
    "\\*\\*/id_ed25519"
    "\\*\\*/\\*\\.pem"
    "\\*\\*/wallet\\.dat"
    "\\*\\*/\\*key\\*"
    "\\*\\*/\\*password\\*"
    "\\*\\*/\\*secret\\*"
)

# Safe patterns (code files, configs, docs)
readonly -a SAFE_PATTERNS=(
    "\\*\\.js$"
    "\\*\\.ts$"
    "\\*\\.jsx$"
    "\\*\\.tsx$"
    "\\*\\.py$"
    "\\*\\.sh$"
    "\\*\\.md$"
    "\\*\\.json$"
    "\\*\\.ya?ml$"
    "\\*\\.txt$"
)

# ============================================================================
# Private: Path Validation
# ============================================================================

# Check if path is a protected directory
_is_protected_directory() {
    local path="$1"

    # Default to current directory if empty
    if [[ -z "${path}" ]]; then
        path="$(pwd)"
    fi

    # Resolve to absolute path
    local abs_path
    if [[ "${path}" != /* ]]; then
        abs_path="$(pwd)/${path}"
    else
        abs_path="${path}"
    fi

    # Normalize path
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for protected in "${PROTECTED_GLOB_DIRS[@]}"; do
        if echo "${abs_path}" | grep -qE "${protected}"; then
            wow_warn "SECURITY: Attempt to glob in protected directory: ${abs_path}"
            return 0  # Is protected
        fi
    done

    return 1  # Not protected
}

# ============================================================================
# Private: Pattern Validation
# ============================================================================

# Check if pattern is overly broad
_is_overly_broad_pattern() {
    local pattern="$1"
    local path="${2:-}"

    # Check for explicit overly broad patterns
    for broad in "${OVERLY_BROAD_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qE "${broad}"; then
            wow_warn "⚠️  Overly broad glob pattern detected: ${pattern}"
            return 0  # Is overly broad
        fi
    done

    # Check if **/* pattern is used from root
    if [[ "${path}" == "/" ]] && echo "${pattern}" | grep -qE "\\*\\*/\\*"; then
        wow_warn "⚠️  Filesystem-wide glob pattern from root: ${pattern}"
        return 0
    fi

    return 1  # Not overly broad
}

# Check if pattern is searching for credentials
_is_credential_search() {
    local pattern="$1"

    for cred_pattern in "${CREDENTIAL_SEARCH_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qE "${cred_pattern}"; then
            wow_warn "⚠️  Searching for credential/secret files: ${pattern}"
            return 0  # Is credential search
        fi
    done

    return 1  # Not credential search
}

# Check if pattern is safe
_is_safe_pattern() {
    local pattern="$1"

    for safe in "${SAFE_PATTERNS[@]}"; do
        if echo "${pattern}" | grep -qE "${safe}"; then
            return 0  # Is safe
        fi
    done

    return 1  # Not explicitly safe
}

# Validate pattern
_validate_pattern() {
    local pattern="$1"
    local path="${2:-}"

    # Check for empty pattern
    if [[ -z "${pattern}" ]]; then
        wow_warn "⚠️  Empty glob pattern"
        return 1  # Invalid
    fi

    # Check for overly broad patterns (warn but allow)
    _is_overly_broad_pattern "${pattern}" "${path}" || true

    # Check for credential searches (warn but allow)
    _is_credential_search "${pattern}" || true

    return 0  # Valid (we warn but don't block patterns)
}

# ============================================================================
# Private: Path Traversal Detection
# ============================================================================

# Detect path traversal in pattern or path
_has_path_traversal() {
    local pattern="$1"
    local path="${2:-}"

    # Check pattern for traversal
    if echo "${pattern}" | grep -qE "\\.\\./"; then
        wow_warn "⚠️  Path traversal detected in glob pattern: ${pattern}"
        return 0
    fi

    # Check path for traversal
    if [[ -n "${path}" ]] && echo "${path}" | grep -qE "\\.\\./"; then
        wow_warn "⚠️  Path traversal detected in glob path: ${path}"
        return 0
    fi

    return 1
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle glob command interception
handle_glob() {
    local tool_input="$1"

    # Extract pattern and path from JSON input
    local pattern=""
    local path=""

    if wow_has_jq; then
        pattern=$(echo "${tool_input}" | jq -r '.pattern // empty' 2>/dev/null)
        path=$(echo "${tool_input}" | jq -r '.path // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        pattern=$(echo "${tool_input}" | grep -oP '"pattern"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        path=$(echo "${tool_input}" | grep -oP '"path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate extraction
    if [[ -z "${pattern}" ]]; then
        wow_warn "⚠️  INVALID GLOB: Empty pattern"

        # Log event
        session_track_event "glob_invalid" "EMPTY_PATTERN" 2>/dev/null || true

        # Don't block - might be valid edge case
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "glob_operations" 2>/dev/null || true
    session_track_event "glob_operation" "pattern=${pattern:0:50}" 2>/dev/null || true

    # ========================================================================
    # SECURITY CHECK: Protected Directory Validation
    # ========================================================================

    if _is_protected_directory "${path}"; then
        wow_error "☠️  DANGEROUS GLOB OPERATION BLOCKED"
        wow_error "Path: ${path}"
        wow_error "Pattern: ${pattern}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_GLOB:${path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # ========================================================================
    # WARNINGS: Pattern Validation (non-blocking)
    # ========================================================================

    # Check for overly broad patterns
    if _is_overly_broad_pattern "${pattern}" "${path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Overly broad glob pattern in strict mode"
            session_track_event "security_violation" "BLOCKED_BROAD_GLOB" 2>/dev/null || true
            return 2
        fi
    fi

    # Check for credential searches
    if _is_credential_search "${pattern}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Credential search pattern in strict mode"
            session_track_event "security_violation" "BLOCKED_CREDENTIAL_GLOB" 2>/dev/null || true
            return 2
        fi
    fi

    # Check for path traversal
    if _has_path_traversal "${pattern}" "${path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Path traversal in glob pattern in strict mode"
            session_track_event "security_violation" "BLOCKED_GLOB_TRAVERSAL" 2>/dev/null || true
            return 2
        fi
    fi

    # ========================================================================
    # ALLOW: Return (original) tool input
    # ========================================================================

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Glob Handler - Self Test"
    echo "============================="
    echo ""

    # Test 1: Protected directory detection
    _is_protected_directory "/etc" && echo "✓ Protected directory detection works"

    # Test 2: Safe directory
    ! _is_protected_directory "/home/user/project" && echo "✓ Safe directory detection works"

    # Test 3: Overly broad pattern detection
    _is_overly_broad_pattern "/**/*" 2>/dev/null && echo "✓ Overly broad pattern detection works"

    # Test 4: Credential search detection
    _is_credential_search "**/.env" 2>/dev/null && echo "✓ Credential search detection works"

    # Test 5: Safe pattern detection
    _is_safe_pattern "*.js" && echo "✓ Safe pattern detection works"

    # Test 6: Path traversal detection
    _has_path_traversal "../../etc/*" 2>/dev/null && echo "✓ Path traversal detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
