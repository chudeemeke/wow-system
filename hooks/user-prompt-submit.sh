#!/bin/bash
# WoW System - Claude Code User Prompt Submit Hook
# Intercepts tool calls before execution for safety enforcement
# Author: Chude <chude@emeke.org>
#
# Integration: This hook is called by Claude Code before executing any tool
# Input: JSON tool call via stdin
# Output: Modified JSON or error code to block
#
# Hook Lifecycle:
# 1. Claude Code prepares tool call → sends to this hook
# 2. Hook validates and potentially modifies
# 3. If exit 0: tool call proceeds (possibly modified)
# 4. If exit non-zero: tool call is blocked

set -uo pipefail

# ============================================================================
# Environment Setup
# ============================================================================

# Determine WoW system location
if [[ -n "${WOW_HOME:-}" ]]; then
    WOW_SYSTEM_DIR="${WOW_HOME}"
elif [[ -d "${HOME}/.claude/wow-system" ]]; then
    WOW_SYSTEM_DIR="${HOME}/.claude/wow-system"
elif [[ -d "/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system" ]]; then
    WOW_SYSTEM_DIR="/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system"
else
    # Fallback: relative to this script
    HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WOW_SYSTEM_DIR="$(dirname "${HOOK_DIR}")"
fi

# Verify WoW system exists
if [[ ! -d "${WOW_SYSTEM_DIR}/src" ]]; then
    echo "ERROR: WoW system not found at ${WOW_SYSTEM_DIR}" >&2
    exit 0  # Don't block if WoW not installed
fi

# Source WoW system
source "${WOW_SYSTEM_DIR}/src/core/orchestrator.sh" 2>/dev/null || {
    echo "ERROR: Failed to load WoW orchestrator" >&2
    exit 0  # Don't block on errors
}

# ============================================================================
# Main Hook Logic
# ============================================================================

main() {
    # Read tool call JSON from stdin
    local tool_input
    tool_input=$(cat)

    # Initialize WoW system (if not already initialized)
    if ! wow_is_initialized 2>/dev/null; then
        wow_init 2>/dev/null || {
            echo "WARN: WoW initialization failed, bypassing" >&2
            echo "${tool_input}"
            exit 0
        }
    fi

    # Extract tool type
    local tool_type=""
    if wow_has_jq; then
        tool_type=$(echo "${tool_input}" | jq -r '.tool // .name // empty' 2>/dev/null)
    else
        tool_type=$(echo "${tool_input}" | grep -oP '"tool"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
    fi

    # If no tool type, pass through
    if [[ -z "${tool_type}" ]]; then
        echo "${tool_input}"
        exit 0
    fi

    # Track tool usage
    session_increment_metric "total_tools" 2>/dev/null || true
    session_track_event "tool_call" "type=${tool_type}" 2>/dev/null || true

    # Route through handler (if handler exists for this tool type)
    local output
    if type handler_route &>/dev/null; then
        output=$(handler_route "${tool_input}" 2>&1) && local handler_result=$? || local handler_result=$?

        # Check handler result
        if [[ ${handler_result} -eq 2 ]]; then
            # Handler blocked the operation
            wow_error "WoW System: Operation blocked by handler" >&2

            # Display alert
            if type display_alert &>/dev/null; then
                display_alert "error" "Operation Blocked" "WoW System prevented a dangerous operation" >&2
            fi

            # Exit non-zero to block in Claude Code
            exit 1
        elif [[ ${handler_result} -eq 0 ]]; then
            # Handler allowed (possibly modified)
            echo "${output}"
            exit 0
        else
            # Handler error - pass through original
            wow_warn "WoW System: Handler error, allowing original operation" >&2
            echo "${tool_input}"
            exit 0
        fi
    else
        # No handler router available - pass through
        echo "${tool_input}"
        exit 0
    fi
}

# ============================================================================
# Error Handling
# ============================================================================

# Trap errors and exit gracefully
trap 'echo "ERROR: Hook failed at line $LINENO" >&2; exit 0' ERR

# Run main logic
main "$@"
