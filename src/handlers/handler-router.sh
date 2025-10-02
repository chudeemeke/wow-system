#!/bin/bash
# WoW System - Handler Router
# Routes tool interceptions to appropriate handlers (Strategy Pattern)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Strategy Pattern: Dynamically select handler based on tool type
# - Open/Closed: Extensible for new handlers
# - Single Responsibility: Only routing logic

# Prevent double-sourcing
if [[ -n "${WOW_HANDLER_ROUTER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_HANDLER_ROUTER_LOADED=1

# Source dependencies
_HANDLER_ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_HANDLER_ROUTER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly ROUTER_VERSION="1.0.0"

# Handler registry (tool_type => handler_path)
declare -gA _WOW_HANDLER_REGISTRY

# ============================================================================
# Handler Registration
# ============================================================================

# Register a handler for a tool type
handler_register() {
    local tool_type="$1"
    local handler_path="$2"

    _WOW_HANDLER_REGISTRY["${tool_type}"]="${handler_path}"
    wow_debug "Registered handler for ${tool_type}: ${handler_path}"
}

# Check if handler exists for tool type
handler_exists() {
    local tool_type="$1"

    [[ -n "${_WOW_HANDLER_REGISTRY[${tool_type}]:-}" ]]
}

# Get handler path for tool type
handler_get() {
    local tool_type="$1"

    echo "${_WOW_HANDLER_REGISTRY[${tool_type}]:-}"
}

# ============================================================================
# Routing Logic
# ============================================================================

# Route tool input to appropriate handler
handler_route() {
    local tool_input="$1"

    # Parse tool type from input (JSON)
    local tool_type
    if wow_has_jq; then
        tool_type=$(echo "${tool_input}" | jq -r '.tool // .name // empty' 2>/dev/null)
    else
        # Fallback: simple grep
        tool_type=$(echo "${tool_input}" | grep -o '"tool"\s*:\s*"[^"]*"' | cut -d'"' -f4)
    fi

    if [[ -z "${tool_type}" ]]; then
        wow_warn "Could not determine tool type from input"
        echo "${tool_input}"
        return 0
    fi

    # Check if handler exists
    if ! handler_exists "${tool_type}"; then
        # No handler registered - pass through
        wow_debug "No handler for ${tool_type}, passing through"
        echo "${tool_input}"
        return 0
    fi

    # Get handler path
    local handler_path
    handler_path=$(handler_get "${tool_type}")

    # Source and execute handler
    if [[ -f "${handler_path}" ]]; then
        source "${handler_path}"

        # Call handler function (convention: handle_<lowercase_tool>)
        local handler_func="handle_${tool_type,,}"

        if type "${handler_func}" &>/dev/null; then
            "${handler_func}" "${tool_input}"
        else
            wow_warn "Handler function ${handler_func} not found"
            echo "${tool_input}"
        fi
    else
        wow_error "Handler file not found: ${handler_path}"
        echo "${tool_input}"
    fi
}

# Initialize default handlers
handler_init() {
    local handler_dir="${_HANDLER_ROUTER_DIR}"

    # Register built-in handlers
    handler_register "Bash" "${handler_dir}/bash-handler.sh"
    handler_register "Write" "${handler_dir}/write-handler.sh"
    handler_register "Edit" "${handler_dir}/edit-handler.sh"
    handler_register "Read" "${handler_dir}/read-handler.sh"
    handler_register "Glob" "${handler_dir}/glob-handler.sh"
    handler_register "Grep" "${handler_dir}/grep-handler.sh"
    handler_register "Task" "${handler_dir}/task-handler.sh"
    handler_register "WebFetch" "${handler_dir}/webfetch-handler.sh"

    wow_debug "Handler router initialized with $(echo "${#_WOW_HANDLER_REGISTRY[@]}") handlers"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Handler Router v${ROUTER_VERSION} - Self Test"
    echo "=================================================="
    echo ""

    # Register test handler
    handler_register "TestTool" "/fake/path/test-handler.sh"
    echo "✓ Handler registration works"

    # Check existence
    handler_exists "TestTool" && echo "✓ Handler existence check works"
    ! handler_exists "NonExistent" && echo "✓ Non-existent handler check works"

    # Get handler
    path=$(handler_get "TestTool")
    [[ "${path}" == "/fake/path/test-handler.sh" ]] && echo "✓ Handler retrieval works"

    # Test routing with pass-through
    test_input='{"tool": "UnknownTool", "command": "test"}'
    result=$(handler_route "${test_input}")
    [[ "${result}" == "${test_input}" ]] && echo "✓ Pass-through for unknown tools works"

    echo ""
    echo "All tests passed! ✓"
fi
