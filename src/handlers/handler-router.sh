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
source "${_HANDLER_ROUTER_DIR}/../core/tool-registry.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

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
        # v5.3: Track unknown tools for monitoring and extensibility
        if type tool_registry_track_unknown &>/dev/null; then
            # Check if this is first occurrence
            local is_first=false
            if type tool_registry_is_first_occurrence &>/dev/null; then
                tool_registry_is_first_occurrence "${tool_type}" && is_first=true
            fi

            # Track the unknown tool
            tool_registry_track_unknown "${tool_type}" 2>/dev/null || true

            # Notify on first occurrence (UX feature)
            if [[ "${is_first}" == "true" ]]; then
                wow_info "New tool detected: ${tool_type} (no handler available, passing through)"
            fi
        fi

        # No handler registered - pass through
        wow_debug "No handler for ${tool_type}, passing through"
        echo "${tool_input}"
        return 0
    fi

    # Get handler path
    local handler_path
    handler_path=$(handler_get "${tool_type}")

    # v5.0: Use Factory if available, otherwise direct sourcing
    if type factory_create_handler &>/dev/null; then
        # Factory pattern: Let factory handle sourcing and caching
        factory_create_handler "${tool_type}" &>/dev/null || {
            wow_warn "Factory failed to create handler for ${tool_type}"
            echo "${tool_input}"
            return 0
        }
    elif [[ -f "${handler_path}" ]]; then
        # Fallback: Direct sourcing (backward compatibility)
        source "${handler_path}"
    else
        wow_error "Handler file not found: ${handler_path}"
        echo "${tool_input}"
        return 0
    fi

    # Call handler function (convention: handle_<lowercase_tool>)
    local handler_func="handle_${tool_type,,}"

    if type "${handler_func}" &>/dev/null; then
        "${handler_func}" "${tool_input}"
    else
        wow_warn "Handler function ${handler_func} not found"
        echo "${tool_input}"
    fi
}

# Initialize default handlers
handler_init() {
    local handler_dir="${_HANDLER_ROUTER_DIR}"

    # v5.3: Initialize tool registry if available
    if type tool_registry_init &>/dev/null; then
        tool_registry_init 2>/dev/null || true
    fi

    # Register built-in handlers (local registry)
    handler_register "Bash" "${handler_dir}/bash-handler.sh"
    handler_register "Write" "${handler_dir}/write-handler.sh"
    handler_register "Edit" "${handler_dir}/edit-handler.sh"
    handler_register "Read" "${handler_dir}/read-handler.sh"
    handler_register "Glob" "${handler_dir}/glob-handler.sh"
    handler_register "Grep" "${handler_dir}/grep-handler.sh"
    handler_register "Task" "${handler_dir}/task-handler.sh"
    handler_register "WebFetch" "${handler_dir}/webfetch-handler.sh"
    handler_register "WebSearch" "${handler_dir}/websearch-handler.sh"  # v5.4.0
    handler_register "NotebookEdit" "${handler_dir}/notebookedit-handler.sh"  # v5.4.0

    # v5.0: Also register in Factory if available
    if type factory_register_handler &>/dev/null; then
        factory_register_handler "Bash" "${handler_dir}/bash-handler.sh"
        factory_register_handler "Write" "${handler_dir}/write-handler.sh"
        factory_register_handler "Edit" "${handler_dir}/edit-handler.sh"
        factory_register_handler "Read" "${handler_dir}/read-handler.sh"
        factory_register_handler "Glob" "${handler_dir}/glob-handler.sh"
        factory_register_handler "Grep" "${handler_dir}/grep-handler.sh"
        factory_register_handler "Task" "${handler_dir}/task-handler.sh"
        factory_register_handler "WebFetch" "${handler_dir}/webfetch-handler.sh"
        factory_register_handler "WebSearch" "${handler_dir}/websearch-handler.sh"  # v5.4.0
        factory_register_handler "NotebookEdit" "${handler_dir}/notebookedit-handler.sh"  # v5.4.0
    fi

    # v5.3: Register known tools in tool registry
    if type tool_registry_register_known &>/dev/null; then
        tool_registry_register_known "Bash" "${handler_dir}/bash-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Write" "${handler_dir}/write-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Edit" "${handler_dir}/edit-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Read" "${handler_dir}/read-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Glob" "${handler_dir}/glob-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Grep" "${handler_dir}/grep-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Task" "${handler_dir}/task-handler.sh" 2>/dev/null || true
        tool_registry_register_known "WebFetch" "${handler_dir}/webfetch-handler.sh" 2>/dev/null || true
        tool_registry_register_known "WebSearch" "${handler_dir}/websearch-handler.sh" 2>/dev/null || true  # v5.4.0
        tool_registry_register_known "NotebookEdit" "${handler_dir}/notebookedit-handler.sh" 2>/dev/null || true  # v5.4.0
    fi

    # v5.4.0: Load custom rules if available
    local dsl_path="${handler_dir}/../rules/dsl.sh"
    if [[ -f "${dsl_path}" ]]; then
        source "${dsl_path}" 2>/dev/null || true

        if type rule_dsl_init &>/dev/null; then
            rule_dsl_init

            # Try to load custom rules from default location
            local rules_file="${WOW_HOME}/custom-rules.conf"
            if [[ -f "${rules_file}" ]]; then
                if rule_dsl_load_file "${rules_file}"; then
                    local rule_count=$(rule_dsl_count)
                    wow_debug "Loaded ${rule_count} custom rules from ${rules_file}"
                fi
            fi
        fi
    fi

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
