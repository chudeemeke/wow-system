#!/bin/bash
# WoW System - Edit Handler (Production-Grade, Security-Critical)
# Intercepts file edit operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on dangerous edits
# - Path Validation: Prevent system file edits
# - Content Scanning: Detect malicious replacements
# - Change Validation: Detect security code removal
# - Audit Logging: Track all edit operations

# Prevent double-sourcing
if [[ -n "${WOW_EDIT_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_EDIT_HANDLER_LOADED=1

# Source dependencies
_EDIT_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_EDIT_HANDLER_DIR}/../core/utils.sh"
source "${_EDIT_HANDLER_DIR}/../core/version-detector.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Protected Paths (Same as write handler)
# ============================================================================

readonly -a PROTECTED_PATHS=(
    "^/etc(/|$)"
    "^/bin(/|$)"
    "^/sbin(/|$)"
    "^/usr/bin(/|$)"
    "^/usr/sbin(/|$)"
    "^/boot(/|$)"
    "^/sys(/|$)"
    "^/proc(/|$)"
    "^/dev(/|$)"
    "^/lib(/|$)"
    "^/lib64(/|$)"
    "^/var/lib(/|$)"
    "^/root(/|$)"
)

readonly -a PATH_TRAVERSAL_PATTERNS=(
    "\\.\\./\\.\\./"
    "\\.\\./"
    "/\\.\\./"
)

# ============================================================================
# Constants - Dangerous Edit Patterns
# ============================================================================

# Patterns that indicate security code removal
readonly -a SECURITY_REMOVAL_PATTERNS=(
    "security_check"
    "validate_"
    "sanitize_"
    "authenticate"
    "authorize"
    "permission"
    "if.*check"
    "return 1"              # Removing error handling
    "exit 1"                # Removing exit conditions
)

# Patterns that indicate dangerous replacements
readonly -a DANGEROUS_REPLACEMENT_PATTERNS=(
    "rm\\s+-rf\\s+/"
    "sudo\\s+rm"
    "chmod\\s+(777|666)"
    "dd\\s+.*of=/dev/"
    "mkfs\\."
    ":\\(\\)"               # Fork bomb
    "eval.*\\$"
    "return\\s+0.*#.*bypass"
    "return\\s+0.*#.*backdoor"
)

# ============================================================================
# Private: Enforcement Checks
# ============================================================================

# Check if file operations limit is exceeded
_check_file_operations_limit() {
    local max_operations
    max_operations=$(config_get "rules.max_file_operations" "0" 2>/dev/null || echo "0")

    # 0 = unlimited
    if [[ "$max_operations" -eq 0 ]]; then
        return 0  # No limit
    fi

    # Count both writes and edits as file operations
    local writes edits total
    writes=$(session_get_metric "file_writes" "0" 2>/dev/null || echo "0")
    edits=$(session_get_metric "file_edits" "0" 2>/dev/null || echo "0")
    total=$((writes + edits))

    if [[ "$total" -ge "$max_operations" ]]; then
        wow_error "LIMIT EXCEEDED: max_file_operations = $max_operations (current: $total)"
        return 1  # Limit exceeded
    fi

    return 0  # Within limit
}

# ============================================================================
# Private: Path Validation (Same as write handler)
# ============================================================================

_is_protected_path() {
    local file_path="$1"

    local abs_path
    if [[ "${file_path}" != /* ]]; then
        abs_path="$(pwd)/${file_path}"
    else
        abs_path="${file_path}"
    fi

    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${PROTECTED_PATHS[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Attempt to edit protected path: ${abs_path}"
            return 0
        fi
    done

    return 1
}

_has_path_traversal() {
    local file_path="$1"

    for pattern in "${PATH_TRAVERSAL_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Path traversal detected: ${file_path}"
            return 0
        fi
    done

    return 1
}

_validate_file_path() {
    local file_path="$1"

    if [[ -z "${file_path}" ]]; then
        wow_warn "SECURITY: Empty file path"
        return 1
    fi

    if _has_path_traversal "${file_path}"; then
        return 1
    fi

    if _is_protected_path "${file_path}"; then
        return 1
    fi

    return 0
}

# ============================================================================
# Private: Edit Validation
# ============================================================================

# Check if old_string being removed contains security code
_is_security_code_removal() {
    local old_string="$1"

    for pattern in "${SECURITY_REMOVAL_PATTERNS[@]}"; do
        if echo "${old_string}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  SECURITY: Removing security-related code: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Check if new_string contains dangerous patterns
_has_dangerous_replacement() {
    local new_string="$1"

    for pattern in "${DANGEROUS_REPLACEMENT_PATTERNS[@]}"; do
        if echo "${new_string}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Dangerous replacement pattern detected: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Validate edit operation
_validate_edit() {
    local old_string="$1"
    local new_string="$2"

    # Check for empty old_string (not allowed)
    if [[ -z "${old_string}" ]]; then
        wow_warn "SECURITY: Empty old_string not allowed"
        return 1
    fi

    # Check if strings are identical (no-op)
    if [[ "${old_string}" == "${new_string}" ]]; then
        wow_warn "ℹ️  Edit is no-op: old_string equals new_string"
        # Allow but warn
        return 0
    fi

    # Check for security code removal (warn but allow, unless strict_mode)
    if _is_security_code_removal "${old_string}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Security code removal in strict mode"
            return 1  # Invalid
        fi
    fi

    # Check for dangerous replacement (block)
    if _has_dangerous_replacement "${new_string}"; then
        return 1
    fi

    return 0
}

# ============================================================================
# Private: File Existence Check
# ============================================================================

# Warn if file doesn't exist
_check_file_exists() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        wow_warn "⚠️  File does not exist: ${file_path}"
        return 1
    fi

    return 0
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle edit command interception
handle_edit() {
    local tool_input="$1"

    # Extract fields from JSON input
    local file_path=""
    local old_string=""
    local new_string=""
    local replace_all="false"

    if wow_has_jq; then
        file_path=$(echo "${tool_input}" | jq -r '.file_path // empty' 2>/dev/null)
        old_string=$(echo "${tool_input}" | jq -r '.old_string // empty' 2>/dev/null)
        new_string=$(echo "${tool_input}" | jq -r '.new_string // empty' 2>/dev/null)
        replace_all=$(echo "${tool_input}" | jq -r '.replace_all // false' 2>/dev/null)
    else
        # Fallback: regex extraction
        file_path=$(echo "${tool_input}" | grep -oP '"file_path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        old_string=$(echo "${tool_input}" | grep -oP '"old_string"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        new_string=$(echo "${tool_input}" | grep -oP '"new_string"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        replace_all=$(echo "${tool_input}" | grep -oP '"replace_all"\s*:\s*\K(true|false)' 2>/dev/null || echo "false")
    fi

    # Validate extraction
    if [[ -z "${file_path}" ]]; then
        wow_error "☠️  INVALID FILE EDIT: Empty file path"

        session_track_event "security_violation" "BLOCKED_EMPTY_PATH" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        return 2
    fi

    # Track metrics
    session_increment_metric "file_edits" 2>/dev/null || true
    session_track_event "file_edit" "path=${file_path:0:100}" 2>/dev/null || true

    # ========================================================================
    # ENFORCEMENT CHECK: File Operations Limit
    # ========================================================================

    if ! _check_file_operations_limit; then
        session_track_event "limit_exceeded" "file_operations" 2>/dev/null || true
        return 2  # Block
    fi

    # ========================================================================
    # SECURITY CHECK: Path Validation
    # ========================================================================

    if ! _validate_file_path "${file_path}"; then
        wow_error "☠️  DANGEROUS FILE EDIT BLOCKED"
        wow_error "Path: ${file_path}"

        session_track_event "security_violation" "BLOCKED_EDIT:${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # SECURITY CHECK: Edit Validation
    # ========================================================================

    if ! _validate_edit "${old_string}" "${new_string}"; then
        wow_error "☠️  DANGEROUS EDIT BLOCKED"
        wow_error "Path: ${file_path}"
        wow_error "Replacement contains dangerous patterns"

        session_track_event "security_violation" "BLOCKED_DANGEROUS_EDIT:${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # WARNINGS: Non-blocking checks (with v5.0.1 strict_mode enforcement)
    # ========================================================================

    # Warn if file doesn't exist
    if ! _check_file_exists "${file_path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Cannot edit non-existent file in strict mode"
            session_track_event "security_violation" "BLOCKED_NONEXISTENT_FILE" 2>/dev/null || true
            return 2
        fi
    fi

    # ========================================================================
    # VERSION DETECTION: Check if this is a version file
    # ========================================================================

    # Detect version file changes and trigger documentation updates
    if command -v version_detect_file_change &>/dev/null; then
        version_detect_file_change "${file_path}" 2>/dev/null || true
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
    echo "WoW Edit Handler - Self Test"
    echo "============================="
    echo ""

    # Test 1: Protected path detection
    _is_protected_path "/etc/hosts" && echo "✓ Protected path detection works"

    # Test 2: Safe path
    ! _is_protected_path "/tmp/test.txt" && echo "✓ Safe path detection works"

    # Test 3: Security code removal detection
    _is_security_code_removal "validate_input()" 2>/dev/null && echo "✓ Security code detection works"

    # Test 4: Dangerous replacement detection
    _has_dangerous_replacement "rm -rf /" && echo "✓ Dangerous replacement detection works"

    # Test 5: Safe edit
    ! _has_dangerous_replacement "echo 'hello'" && echo "✓ Safe edit detection works"

    # Test 6: Empty old_string validation
    ! _validate_edit "" "new" 2>/dev/null && echo "✓ Empty old_string blocked"

    echo ""
    echo "All self-tests passed! ✓"
fi
