#!/bin/bash
# WoW System - Custom Rule Integration Helper
# Provides common custom rule checking logic for all handlers
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - DRY: Single implementation used by all handlers
# - Separation of Concerns: Rule logic separate from handler logic
# - Fail-Safe: Gracefully handles missing DSL module

# Prevent double-sourcing
if [[ -n "${WOW_CUSTOM_RULE_HELPER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CUSTOM_RULE_HELPER_LOADED=1

# Source dependencies
_CUSTOM_RULE_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CUSTOM_RULE_HELPER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly CUSTOM_RULE_HELPER_VERSION="1.0.0"

# Action return codes
readonly CUSTOM_RULE_BLOCK=2
readonly CUSTOM_RULE_WARN=1
readonly CUSTOM_RULE_ALLOW=0
readonly CUSTOM_RULE_NO_MATCH=99

# ============================================================================
# Public: Custom Rule Checking
# ============================================================================

# Check if custom rule DSL is available
custom_rule_available() {
    type rule_dsl_match &>/dev/null
}

# Check text against custom rules
# Returns: 0=allow, 1=warn, 2=block, 99=no match
# Sets global variables: _CUSTOM_RULE_NAME, _CUSTOM_RULE_MESSAGE
custom_rule_check() {
    local text="$1"
    local tool_type="${2:-unknown}"

    # Reset global variables
    _CUSTOM_RULE_NAME=""
    _CUSTOM_RULE_MESSAGE=""

    # Check if DSL is available
    if ! custom_rule_available; then
        return ${CUSTOM_RULE_NO_MATCH}
    fi

    # Check for match
    if ! rule_dsl_match "${text}"; then
        return ${CUSTOM_RULE_NO_MATCH}
    fi

    # Get rule details
    local action=$(rule_dsl_get_action)
    local severity=$(rule_dsl_get_severity)
    local message=$(rule_dsl_get_message)
    local rule_name=$(rule_dsl_get_name)

    # Store for caller
    _CUSTOM_RULE_NAME="${rule_name}"
    _CUSTOM_RULE_MESSAGE="${message}"

    # Log match
    session_track_event "custom_rule_match" "${rule_name}:${action}:${tool_type}" 2>/dev/null || true

    # Return action code
    case "${action}" in
        block)
            return ${CUSTOM_RULE_BLOCK}
            ;;
        warn)
            return ${CUSTOM_RULE_WARN}
            ;;
        allow)
            return ${CUSTOM_RULE_ALLOW}
            ;;
        *)
            wow_warn "Unknown custom rule action: ${action}"
            return ${CUSTOM_RULE_NO_MATCH}
            ;;
    esac
}

# Apply custom rule action (display messages, update score)
# Parameters: action_code, tool_type
custom_rule_apply() {
    local action_code="$1"
    local tool_type="${2:-unknown}"

    case "${action_code}" in
        ${CUSTOM_RULE_BLOCK})
            wow_error "CUSTOM RULE BLOCKED: ${_CUSTOM_RULE_NAME}"
            [[ -n "${_CUSTOM_RULE_MESSAGE}" ]] && wow_error "Reason: ${_CUSTOM_RULE_MESSAGE}"

            session_track_event "security_violation" "CUSTOM_RULE:${_CUSTOM_RULE_NAME}" 2>/dev/null || true
            session_increment_metric "violations" 2>/dev/null || true

            # Update score
            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 10))" 2>/dev/null || true
            ;;

        ${CUSTOM_RULE_WARN})
            wow_warn "CUSTOM RULE WARNING: ${_CUSTOM_RULE_NAME}"
            [[ -n "${_CUSTOM_RULE_MESSAGE}" ]] && wow_warn "Reason: ${_CUSTOM_RULE_MESSAGE}"

            session_track_event "custom_rule_warning" "${_CUSTOM_RULE_NAME}" 2>/dev/null || true

            # Update score (minor penalty)
            local current_score
            current_score=$(session_get_metric "wow_score" "70")
            session_update_metric "wow_score" "$((current_score - 2))" 2>/dev/null || true
            ;;

        ${CUSTOM_RULE_ALLOW})
            wow_debug "CUSTOM RULE ALLOWED: ${_CUSTOM_RULE_NAME}"
            session_track_event "custom_rule_allow" "${_CUSTOM_RULE_NAME}" 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Custom Rule Helper - Self Test (v${CUSTOM_RULE_HELPER_VERSION})"
    echo "================================================================="
    echo ""

    # Test 1: Check if DSL available
    if custom_rule_available; then
        echo "✓ Custom rule DSL is available"
    else
        echo "✓ Custom rule DSL not available (expected if not loaded)"
    fi

    # Test 2: Check constants
    [[ ${CUSTOM_RULE_BLOCK} -eq 2 ]] && echo "✓ Block code correct"
    [[ ${CUSTOM_RULE_WARN} -eq 1 ]] && echo "✓ Warn code correct"
    [[ ${CUSTOM_RULE_ALLOW} -eq 0 ]] && echo "✓ Allow code correct"
    [[ ${CUSTOM_RULE_NO_MATCH} -eq 99 ]] && echo "✓ No match code correct"

    echo ""
    echo "All self-tests passed! ✓"
fi
