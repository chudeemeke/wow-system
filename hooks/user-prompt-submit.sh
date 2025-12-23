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

# Source UI modules (for display functions)
source "${WOW_SYSTEM_DIR}/src/ui/display.sh" 2>/dev/null || true
source "${WOW_SYSTEM_DIR}/src/ui/score-display.sh" 2>/dev/null || true

# Source messaging framework (SOLID-compliant, unified messaging)
source "${WOW_SYSTEM_DIR}/src/ui/messaging/messages.sh" 2>/dev/null || true
source "${WOW_SYSTEM_DIR}/src/ui/messaging/startup-checks.sh" 2>/dev/null || true

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

        # Get current status for display
        local wow_version wow_score wow_handlers
        wow_version=$(wow_get_version 2>/dev/null || echo "5.4.3")
        wow_score=$(scoring_get_score 2>/dev/null || echo "70")
        wow_handlers="8"

        # Display compact status message (visible to user)
        echo "ℹ️  WoW System v${wow_version} Active | Score: ${wow_score}/100 | ${wow_handlers} handlers loaded" >&2

        # Display full session banner to stderr (for debugging/terminals)
        if type display_session_banner &>/dev/null; then
            display_session_banner >&2
        fi

        # Run startup checks (security warnings, bypass status, etc.)
        # Uses the SOLID-compliant messaging framework
        if type startup_checks_init &>/dev/null; then
            startup_checks_init
            startup_checks_run_all
        fi
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
        # Exit codes: 0=allow, 2=block (bypassable), 3=always-block (not bypassable), 4=superadmin-required
        if [[ ${handler_result} -eq 3 ]]; then
            # ALWAYS-BLOCK: Cannot be bypassed (SSRF, auth files, destructive ops)
            wow_error "WoW System: CRITICAL operation blocked (cannot be bypassed)" >&2

            local reason="WoW System blocked this operation. This is a CRITICAL security violation that cannot be bypassed. Operations like SSRF attacks, reading auth files, and destructive commands are always blocked."
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${reason}\"}}" | jq -c
            exit 1  # Non-zero exit to signal block to Claude Code
        elif [[ ${handler_result} -eq 4 ]]; then
            # SUPERADMIN-REQUIRED: Can be unlocked with SuperAdmin authentication
            wow_error "WoW System: SuperAdmin authentication required" >&2

            local reason="WoW System blocked this operation. This operation requires SuperAdmin authentication. Ask the user to run 'wow superadmin unlock' in their terminal and authenticate with their fingerprint to temporarily allow this operation."
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${reason}\"}}" | jq -c
            exit 1  # Non-zero exit to signal block to Claude Code
        elif [[ ${handler_result} -eq 2 ]]; then
            # Regular block: Can be bypassed by user
            wow_error "WoW System: Operation blocked by handler" >&2

            # Extract path/command from handler_input for display
            local violation_path=""
            if wow_has_jq; then
                violation_path=$(echo "${handler_input}" | jq -r '.command // .file_path // .path // .pattern // "unknown"' 2>/dev/null || echo "unknown")
            fi

            # Display violation with score
            if type score_display_violation &>/dev/null; then
                score_display_violation "security_violation" "${violation_path}" "${tool_type}-handler" >&2
            elif type display_alert &>/dev/null; then
                # Fallback to simple alert
                display_alert "error" "Operation Blocked" "WoW System prevented a dangerous operation" >&2
            fi

            # Return deny decision with reason and guidance for bypass
            local reason="WoW System blocked this operation. If this is legitimate, ask the user to run 'wow bypass' in their terminal to temporarily disable protection."
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${reason}\"}}" | jq -c
            exit 1  # Non-zero exit to signal block to Claude Code
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
