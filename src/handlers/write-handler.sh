#!/bin/bash
# WoW System - Write Handler (Production-Grade, Security-Critical)
# Intercepts file write operations for safety enforcement and validation
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - Path Validation: Prevent system directory writes
# - Content Scanning: Detect malicious patterns
# - Audit Logging: Track all write operations

# Prevent double-sourcing
if [[ -n "${WOW_WRITE_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_WRITE_HANDLER_LOADED=1

# Source dependencies
_WRITE_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_WRITE_HANDLER_DIR}/../core/utils.sh"
source "${_WRITE_HANDLER_DIR}/../core/version-detector.sh" 2>/dev/null || true
source "${_WRITE_HANDLER_DIR}/custom-rule-helper.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants - Protected Paths
# ============================================================================

# CRITICAL: System directories that should NEVER be written to
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

# Path traversal patterns
readonly -a PATH_TRAVERSAL_PATTERNS=(
    "\\.\\./\\.\\./"      # ../..
    "\\.\\./"             # ../
    "/\\.\\./"            # /../
)

# ============================================================================
# Constants - Dangerous Content Patterns
# ============================================================================

# Malicious code patterns to detect in file content
readonly -a MALICIOUS_PATTERNS=(
    "rm\\s+-rf\\s+/"                    # rm -rf /
    "sudo\\s+rm\\s+-rf"                 # sudo rm -rf
    "dd\\s+.*of=/dev/"                  # dd to device
    "mkfs\\."                            # Format filesystem
    ":\\(\\)"                            # Fork bomb
    "chmod\\s+(777|666)\\s+/"           # Dangerous chmod
    "eval.*\\$\\("                      # Eval with command substitution
    "/dev/(null|zero|random)\\s*>"      # Suspicious redirects
)

# Credential patterns (warn but don't block)
readonly -a CREDENTIAL_PATTERNS=(
    "password\\s*=\\s*['\"]?[a-zA-Z0-9]+"
    "api[_-]?key\\s*=\\s*['\"]?[a-zA-Z0-9]+"
    "secret\\s*=\\s*['\"]?[a-zA-Z0-9]+"
    "token\\s*=\\s*['\"]?[a-zA-Z0-9]+"
    "sk_live_[a-zA-Z0-9]+"              # Stripe live keys
    "-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----"  # Private keys
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

    local current_count
    current_count=$(session_get_metric "file_writes" "0" 2>/dev/null || echo "0")

    if [[ "$current_count" -ge "$max_operations" ]]; then
        wow_error "LIMIT EXCEEDED: max_file_operations = $max_operations (current: $current_count)"
        return 1  # Limit exceeded
    fi

    return 0  # Within limit
}

# ============================================================================
# Private: Path Validation
# ============================================================================

# Check if path is protected (system directory)
_is_protected_path() {
    local file_path="$1"

    # Resolve to absolute path
    local abs_path
    if [[ "${file_path}" != /* ]]; then
        abs_path="$(pwd)/${file_path}"
    else
        abs_path="${file_path}"
    fi

    # Normalize path (remove ./ and ../)
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${PROTECTED_PATHS[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Attempt to write to protected path: ${abs_path}"
            return 0  # Is protected
        fi
    done

    return 1  # Not protected
}

# Check for path traversal attacks
_has_path_traversal() {
    local file_path="$1"

    for pattern in "${PATH_TRAVERSAL_PATTERNS[@]}"; do
        if echo "${file_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Path traversal detected: ${file_path}"
            return 0  # Has traversal
        fi
    done

    return 1  # Safe
}

# Validate file path
_validate_file_path() {
    local file_path="$1"

    # Check for empty path
    if [[ -z "${file_path}" ]]; then
        wow_warn "SECURITY: Empty file path"
        return 1  # Invalid
    fi

    # Check for path traversal
    if _has_path_traversal "${file_path}"; then
        return 1  # Invalid
    fi

    # Check for protected paths
    if _is_protected_path "${file_path}"; then
        return 1  # Invalid
    fi

    return 0  # Valid
}

# ============================================================================
# Private: Content Validation
# ============================================================================

# Check if content contains malicious patterns
_has_malicious_content() {
    local content="$1"

    # Normalize content (remove extra spaces)
    local normalized
    normalized=$(echo "${content}" | tr -s ' ')

    for pattern in "${MALICIOUS_PATTERNS[@]}"; do
        if echo "${normalized}" | grep -qiE "${pattern}"; then
            wow_warn "SECURITY: Malicious pattern detected in content: ${pattern}"
            return 0  # Has malicious content
        fi
    done

    return 1  # Safe
}

# Check if content contains credentials (warn only)
_has_credentials() {
    local content="$1"

    for pattern in "${CREDENTIAL_PATTERNS[@]}"; do
        if echo "${content}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  CREDENTIALS DETECTED in file content"
            return 0  # Has credentials
        fi
    done

    return 1  # No credentials
}

# Validate file content
_validate_content() {
    local content="$1"

    # Check for malicious patterns (blocking)
    if _has_malicious_content "${content}"; then
        return 1  # Invalid
    fi

    # Check for credentials (warning only, but respect strict_mode)
    if _has_credentials "${content}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Credential detected in strict mode"
            return 1  # Invalid
        fi
    fi

    return 0  # Valid
}

# ============================================================================
# Private: File Type Checks
# ============================================================================

# Check if file appears to be binary
_is_binary_content() {
    local content="$1"

    # Check for null bytes or common binary headers
    if echo "${content}" | grep -qP "\\x00|^MZ|^PK|^\\x7fELF"; then
        return 0  # Is binary
    fi

    return 1  # Not binary
}

# Warn on binary file writes
_check_binary_write() {
    local file_path="$1"
    local content="$2"

    if _is_binary_content "${content}"; then
        wow_warn "⚠️  Binary file write detected: ${file_path}"
        return 0
    fi

    return 1
}

# ============================================================================
# Private: Documentation Checks
# ============================================================================

# Check if shell script has proper header
_has_proper_header() {
    local content="$1"
    local file_path="$2"

    # Only check shell scripts
    if [[ ! "${file_path}" =~ \\.sh$ ]]; then
        return 0  # Not a shell script, skip
    fi

    # Check for shebang and comment block
    if echo "${content}" | head -10 | grep -qE "^#!/bin/(ba)?sh" && \
       echo "${content}" | head -10 | grep -qE "^#.*[Aa]uthor"; then
        return 0  # Has proper header
    fi

    wow_warn "ℹ️  Shell script missing proper header documentation: ${file_path}"
    return 1  # Missing header
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle write command interception
handle_write() {
    local tool_input="$1"

    # Extract file_path and content from JSON input
    local file_path=""
    local content=""

    if wow_has_jq; then
        file_path=$(echo "${tool_input}" | jq -r '.file_path // empty' 2>/dev/null)
        content=$(echo "${tool_input}" | jq -r '.content // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        file_path=$(echo "${tool_input}" | grep -oP '"file_path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        content=$(echo "${tool_input}" | grep -oP '"content"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate extraction
    if [[ -z "${file_path}" ]]; then
        wow_error "☠️  INVALID FILE WRITE: Empty file path"

        # Log violation
        session_track_event "security_violation" "BLOCKED_EMPTY_PATH" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # Track metrics
    session_increment_metric "file_writes" 2>/dev/null || true
    session_track_event "file_write" "path=${file_path:0:100}" 2>/dev/null || true

    # ========================================================================
    # CUSTOM RULES CHECK (v5.4.0)
    # ========================================================================

    if custom_rule_available; then
        # Check path
        custom_rule_check "${file_path}" "Write"
        local path_result=$?

        # Check content (first 1000 chars)
        custom_rule_check "${content:0:1000}" "Write"
        local content_result=$?

        # Take more restrictive action
        local rule_result=${path_result}
        if [[ ${content_result} -lt ${path_result} ]]; then
            rule_result=${content_result}
        fi

        if [[ ${rule_result} -ne ${CUSTOM_RULE_NO_MATCH} ]]; then
            custom_rule_apply "${rule_result}" "Write"

            case "${rule_result}" in
                ${CUSTOM_RULE_BLOCK})
                    return 2
                    ;;
                ${CUSTOM_RULE_ALLOW})
                    echo "${tool_input}"
                    return 0
                    ;;
                ${CUSTOM_RULE_WARN})
                    # Continue to built-in checks
                    ;;
            esac
        fi
    fi

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
        wow_error "☠️  DANGEROUS FILE WRITE BLOCKED"
        wow_error "Path: ${file_path}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_WRITE:${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        # BLOCK: Exit with error code 2
        return 2
    fi

    # ========================================================================
    # SECURITY CHECK: Content Validation
    # ========================================================================

    if ! _validate_content "${content}"; then
        wow_error "☠️  DANGEROUS FILE CONTENT BLOCKED"
        wow_error "Path: ${file_path}"

        # Log violation
        session_track_event "security_violation" "BLOCKED_CONTENT:${file_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # WARNINGS: Non-blocking checks (with v5.0.1 strict_mode enforcement)
    # ========================================================================

    # Check for binary writes
    if _check_binary_write "${file_path}" "${content}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Binary file write in strict mode"
            session_track_event "security_violation" "BLOCKED_BINARY_WRITE" 2>/dev/null || true
            return 2
        fi
    fi

    # Check for documentation
    if ! _has_proper_header "${content}" "${file_path}"; then
        # v5.0.1: strict_mode enforcement
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Missing documentation in strict mode"
            session_track_event "security_violation" "BLOCKED_MISSING_DOCS" 2>/dev/null || true
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
    echo "WoW Write Handler - Self Test"
    echo "=============================="
    echo ""

    # Test 1: Protected path detection
    _is_protected_path "/etc/hosts" && echo "✓ Protected path detection works"

    # Test 2: Safe path
    ! _is_protected_path "/tmp/test.txt" && echo "✓ Safe path detection works"

    # Test 3: Path traversal detection
    _has_path_traversal "../../etc/passwd" && echo "✓ Path traversal detection works"

    # Test 4: Malicious content detection
    _has_malicious_content "rm -rf /" && echo "✓ Malicious content detection works"

    # Test 5: Safe content
    ! _has_malicious_content "echo 'Hello World'" && echo "✓ Safe content detection works"

    # Test 6: Credential detection
    _has_credentials "password=secret123" 2>/dev/null && echo "✓ Credential detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
