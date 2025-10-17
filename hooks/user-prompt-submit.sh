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

# Optional debug logging (enable via WOW_DEBUG=1)
if [[ "${WOW_DEBUG:-0}" == "1" ]]; then
    echo "[$(date -Iseconds)] WoW Hook: Invoked (PID=$$)" >> "${WOW_DEBUG_LOG:-/tmp/wow-debug.log}" 2>&1 || true
fi

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
    # Read tool call JSON from stdin (official Claude Code format)
    local hook_input
    hook_input=$(cat)

    # Initialize WoW system (if not already initialized)
    if ! wow_is_initialized 2>/dev/null; then
        wow_init 2>/dev/null || {
            echo "WARN: WoW initialization failed, allowing operation" >&2
            echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"WoW initialization failed"}}' | jq -c
            exit 0
        }
    fi

    # Extract tool information from Claude Code PreToolUse format
    local tool_type=""
    local handler_input=""

    if wow_has_jq; then
        # Extract tool_name and tool_input from official PreToolUse format
        tool_type=$(echo "${hook_input}" | jq -r '.tool_name // empty' 2>/dev/null)

        if [[ -n "${tool_type}" ]]; then
            # Reconstruct handler-compatible JSON from tool_input
            # Handlers expect: {"tool":"Bash","command":"..."}
            local tool_params
            tool_params=$(echo "${hook_input}" | jq -r '.tool_input // {}' 2>/dev/null)
            handler_input=$(jq -n --arg tool "${tool_type}" --argjson params "${tool_params}" '$params + {tool: $tool}')
        else
            # No tool_name found, allow by default
            echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"No tool_name in input"}}' | jq -c
            exit 0
        fi
    else
        # No jq available, allow by default
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"jq not available"}}' | jq -c
        exit 0
    fi

    # If no tool type, allow by default
    if [[ -z "${tool_type}" ]]; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"No tool type found"}}' | jq -c
        exit 0
    fi

    # Track tool usage
    session_increment_metric "total_tools" 2>/dev/null || true
    session_track_event "tool_call" "type=${tool_type}" 2>/dev/null || true

    # Route through handler (if handler exists for this tool type)
    local output
    if type handler_route &>/dev/null; then
        output=$(handler_route "${handler_input}" 2>&1) && local handler_result=$? || local handler_result=$?

        # Check handler result and return hookSpecificOutput
        if [[ ${handler_result} -eq 2 ]]; then
            # Handler blocked the operation
            wow_error "WoW System: Operation blocked by handler" >&2

            # Display alert
            if type display_alert &>/dev/null; then
                display_alert "error" "Operation Blocked" "WoW System prevented a dangerous operation" >&2
            fi

            # Return deny decision with reason
            local reason="WoW System blocked this operation as potentially dangerous"
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${reason}\"}}" | jq -c
            exit 0
        elif [[ ${handler_result} -eq 0 ]]; then
            # Handler allowed
            echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"WoW System validated operation"}}' | jq -c
            exit 0
        else
            # Handler error - allow by default (fail open for safety)
            wow_warn "WoW System: Handler error, allowing operation" >&2
            echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Handler error, failing open"}}' | jq -c
            exit 0
        fi
    else
        # No handler router available - allow by default
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"No handler router available"}}' | jq -c
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
