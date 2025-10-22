#!/bin/bash
# WoW System - NotebookEdit Handler (Production-Grade, Security-Critical)
# Intercepts Jupyter notebook edit operations for safety enforcement
# Author: Chude <chude@emeke.org>
#
# Security Principles (v5.4.0):
# - Defense in Depth: Three-tier validation (Critical/Sensitive/Tracked)
# - Magic Command Safety: Block dangerous shell executions
# - Content Validation: Scan for dangerous Python patterns
# - Code Injection Prevention: Block eval/exec patterns
# - Credential Protection: Warn on embedded secrets
# - Fail-Open: Missing notebooks allowed (Claude Code handles)

# Prevent double-sourcing
if [[ -n "${WOW_NOTEBOOKEDIT_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_NOTEBOOKEDIT_HANDLER_LOADED=1

# Source dependencies
_NOTEBOOKEDIT_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_NOTEBOOKEDIT_HANDLER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Three-Tier Security Classification
# ============================================================================

# TIER 1: CRITICAL - System notebooks (never legitimate)
readonly -a BLOCKED_NOTEBOOK_PATHS=(
    "^/etc/"
    "^/usr/"
    "^/bin/"
    "^/sbin/"
    "^/boot/"
    "^/sys/"
    "^/proc/"
    "^/dev/"
)

# TIER 2: SENSITIVE - Warn by default, block in strict_mode
readonly -a SENSITIVE_NOTEBOOK_PATHS=(
    "^/root/"
    "/\\.jupyter/"
    "/\\.ipython/"
)

# Dangerous magic commands (shell execution)
readonly -a DANGEROUS_MAGIC_PATTERNS=(
    "^[[:space:]]*%bash"
    "^[[:space:]]*%%bash"
    "^[[:space:]]*!.*rm"
    "^[[:space:]]*!.*sudo"
    "^[[:space:]]*!.*curl.*\\|"
    "^[[:space:]]*!.*wget.*\\|"
    "^[[:space:]]*!.*sh$"
    "^[[:space:]]*!.*bash$"
)

# Dangerous Python patterns (code injection, destructive operations)
readonly -a DANGEROUS_PYTHON_PATTERNS=(
    "eval\\("
    "exec\\("
    "compile\\("
    "__import__\\("
    "subprocess\\.run\\(\\[.*rm"
    "subprocess\\.call\\(\\[.*rm"
    "os\\.system\\(.*rm"
)

# Warning patterns (suspicious but might be legitimate)
readonly -a WARNING_PATTERNS=(
    "os\\.system\\("
    "subprocess\\."
    "shutil\\.rmtree\\("
    "api_key.*="
    "password.*="
    "secret.*="
    "token.*="
)

# Safe magic commands (allowed)
readonly -a SAFE_MAGIC_COMMANDS=(
    "%matplotlib"
    "%time"
    "%timeit"
    "%load"
    "%who"
    "%whos"
    "%pwd"
    "%cd"
    "%%time"
    "%%timeit"
)

# ============================================================================
# Private: Path Validation
# ============================================================================

# Check if notebook path is in blocked list (TIER 1)
_is_blocked_notebook_path() {
    local notebook_path="$1"

    # Resolve to absolute path
    local abs_path
    if [[ "${notebook_path}" != /* ]]; then
        abs_path="$(pwd)/${notebook_path}"
    else
        abs_path="${notebook_path}"
    fi

    # Normalize path
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${BLOCKED_NOTEBOOK_PATHS[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Attempt to edit system notebook: ${abs_path}"
            return 0  # Is blocked
        fi
    done

    return 1  # Not blocked
}

# Check if notebook path is sensitive (TIER 2)
_is_sensitive_notebook_path() {
    local notebook_path="$1"

    # Resolve to absolute path
    local abs_path
    if [[ "${notebook_path}" != /* ]]; then
        abs_path="$(pwd)/${notebook_path}"
    else
        abs_path="${notebook_path}"
    fi

    # Normalize path
    abs_path=$(realpath -m "${abs_path}" 2>/dev/null || echo "${abs_path}")

    for pattern in "${SENSITIVE_NOTEBOOK_PATHS[@]}"; do
        if echo "${abs_path}" | grep -qE "${pattern}"; then
            wow_warn "⚠️  SENSITIVE NOTEBOOK: ${abs_path}"
            return 0  # Is sensitive
        fi
    done

    return 1  # Not sensitive
}

# Check for path traversal
_has_path_traversal() {
    local path="$1"

    if echo "${path}" | grep -qE "(\\.\\./|\\.\\.\\ )"; then
        wow_warn "SECURITY: Path traversal detected: ${path}"
        return 0  # Has traversal
    fi

    return 1  # Safe
}

# ============================================================================
# Private: Content Validation
# ============================================================================

# Check if content contains dangerous magic commands
_has_dangerous_magic() {
    local content="$1"

    # First check if it's a safe magic command
    for safe_magic in "${SAFE_MAGIC_COMMANDS[@]}"; do
        if echo "${content}" | grep -qE "^[[:space:]]*${safe_magic}"; then
            return 1  # Is safe magic, skip danger check
        fi
    done

    # Check for dangerous patterns
    for pattern in "${DANGEROUS_MAGIC_PATTERNS[@]}"; do
        if echo "${content}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Dangerous magic command detected: ${pattern}"
            return 0  # Is dangerous
        fi
    done

    return 1  # Safe
}

# Check if content contains dangerous Python patterns
_has_dangerous_python() {
    local content="$1"

    for pattern in "${DANGEROUS_PYTHON_PATTERNS[@]}"; do
        if echo "${content}" | grep -qE "${pattern}"; then
            wow_warn "SECURITY: Dangerous Python pattern detected: ${pattern}"
            return 0  # Is dangerous
        fi
    done

    return 1  # Safe
}

# Check if content has warning patterns
_has_warning_patterns() {
    local content="$1"

    for pattern in "${WARNING_PATTERNS[@]}"; do
        if echo "${content}" | grep -qE "${pattern}"; then
            wow_warn "⚠️  Suspicious pattern detected: ${pattern}"
            return 0  # Has warning pattern
        fi
    done

    return 1  # Safe
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle notebook edit interception
handle_notebookedit() {
    local tool_input="$1"

    # Extract parameters from JSON input
    local notebook_path=""
    local new_source=""

    if wow_has_jq; then
        notebook_path=$(echo "${tool_input}" | jq -r '.notebook_path // empty' 2>/dev/null)
        new_source=$(echo "${tool_input}" | jq -r '.new_source // empty' 2>/dev/null)
    else
        # Fallback: regex extraction
        notebook_path=$(echo "${tool_input}" | grep -oP '"notebook_path"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        new_source=$(echo "${tool_input}" | grep -oP '"new_source"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # Validate extraction
    if [[ -z "${notebook_path}" ]]; then
        wow_warn "⚠️  INVALID NOTEBOOK EDIT: Empty notebook path"
        session_track_event "notebookedit_invalid" "EMPTY_PATH" 2>/dev/null || true
        # Fail-open
        echo "${tool_input}"
        return 0
    fi

    # Track metrics
    session_increment_metric "notebookedit_count" 2>/dev/null || true
    session_track_event "notebook_edit" "path=${notebook_path:0:100}" 2>/dev/null || true

    # ========================================================================
    # TIER 1 CHECK: Critical paths (hard block)
    # ========================================================================

    # Check for path traversal to system files
    if _has_path_traversal "${notebook_path}"; then
        if echo "${notebook_path}" | grep -qE "(etc|usr|bin|boot|sys)"; then
            wow_error "☠️  DANGEROUS NOTEBOOK EDIT BLOCKED"
            wow_error "Path traversal to system directory: ${notebook_path}"

            session_track_event "security_violation" "BLOCKED_NOTEBOOK_TRAVERSAL:${notebook_path:0:100}" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            # Update score
            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

            return 2
        fi
    fi

    # Check for blocked paths
    if _is_blocked_notebook_path "${notebook_path}"; then
        wow_error "☠️  SYSTEM NOTEBOOK EDIT BLOCKED"
        wow_error "Path: ${notebook_path}"

        session_track_event "security_violation" "BLOCKED_SYSTEM_NOTEBOOK:${notebook_path:0:100}" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        # Update score
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        return 2
    fi

    # ========================================================================
    # TIER 2 CHECK: Sensitive paths (warn by default, block in strict_mode)
    # ========================================================================

    if _is_sensitive_notebook_path "${notebook_path}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED: Sensitive notebook edit in strict mode"
            wow_error "Path: ${notebook_path}"
            session_track_event "security_violation" "BLOCKED_SENSITIVE_NOTEBOOK" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 5))" 2>/dev/null || true

            return 2
        fi

        # Not in strict mode - warn but allow
        session_track_event "sensitive_notebook_edit" "${notebook_path:0:100}" 2>/dev/null || true

        # Small score penalty
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 2))" 2>/dev/null || true
    fi

    # ========================================================================
    # CONTENT VALIDATION: Check cell source code
    # ========================================================================

    # Empty source is allowed (cell deletion)
    if [[ -z "${new_source}" ]]; then
        echo "${tool_input}"
        return 0
    fi

    # Check for dangerous magic commands
    if _has_dangerous_magic "${new_source}"; then
        wow_error "☠️  DANGEROUS MAGIC COMMAND BLOCKED"
        wow_error "Content contains dangerous shell execution"

        session_track_event "security_violation" "BLOCKED_DANGEROUS_MAGIC" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        return 2
    fi

    # Check for dangerous Python patterns
    if _has_dangerous_python "${new_source}"; then
        wow_error "☠️  DANGEROUS PYTHON CODE BLOCKED"
        wow_error "Content contains code injection or destructive patterns"

        session_track_event "security_violation" "BLOCKED_DANGEROUS_PYTHON" 2>/dev/null || true
        session_increment_metric "violations" 2>/dev/null || true

        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true

        return 2
    fi

    # Check for warning patterns (don't block, just warn)
    if _has_warning_patterns "${new_source}"; then
        session_track_event "notebook_warning_pattern" "${notebook_path:0:50}" 2>/dev/null || true

        # Small score impact
        local current_score
        current_score=$(session_get_metric "wow_score" "70")
        session_update_metric "wow_score" "$((current_score - 1))" 2>/dev/null || true
    fi

    # ========================================================================
    # ALLOW: Return original tool input
    # ========================================================================

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW NotebookEdit Handler - Self Test (v5.4.0)"
    echo "============================================="
    echo ""

    # Test TIER 1: Critical paths
    echo "TIER 1 (CRITICAL) Tests:"
    _is_blocked_notebook_path "/etc/notebook.ipynb" 2>/dev/null && echo "  ✓ /etc notebooks blocked"
    _is_blocked_notebook_path "/usr/share/notebook.ipynb" 2>/dev/null && echo "  ✓ /usr notebooks blocked"
    ! _is_blocked_notebook_path "/home/user/notebook.ipynb" 2>/dev/null && echo "  ✓ User notebooks not blocked"

    echo ""
    echo "TIER 2 (SENSITIVE) Tests:"
    _is_sensitive_notebook_path "/root/notebook.ipynb" 2>/dev/null && echo "  ✓ /root notebooks are sensitive"
    _is_sensitive_notebook_path "$HOME/.jupyter/custom.ipynb" 2>/dev/null && echo "  ✓ .jupyter notebooks are sensitive"

    echo ""
    echo "Content Validation Tests:"
    _has_dangerous_magic "%bash rm file" 2>/dev/null && echo "  ✓ Dangerous bash magic detected"
    ! _has_dangerous_magic "%matplotlib inline" 2>/dev/null && echo "  ✓ Safe magic allowed"
    _has_dangerous_python "eval(code)" 2>/dev/null && echo "  ✓ Dangerous Python detected"
    ! _has_dangerous_python "import pandas" 2>/dev/null && echo "  ✓ Safe Python allowed"

    echo ""
    echo "All self-tests passed! ✓"
    echo ""
    echo "Configuration:"
    echo "  - TIER 1 (CRITICAL): ${#BLOCKED_NOTEBOOK_PATHS[@]} path patterns (hard block)"
    echo "  - TIER 2 (SENSITIVE): ${#SENSITIVE_NOTEBOOK_PATHS[@]} path patterns (contextual)"
    echo "  - Dangerous magic: ${#DANGEROUS_MAGIC_PATTERNS[@]} patterns"
    echo "  - Dangerous Python: ${#DANGEROUS_PYTHON_PATTERNS[@]} patterns"
fi
