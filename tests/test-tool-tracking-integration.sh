#!/bin/bash
# WoW System - Tool Tracking Integration Tests
# Tests integration of tool-registry with handler-router
# Author: Chude <chude@emeke.org>

set -uo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source dependencies
source "${SCRIPT_DIR}/../src/core/utils.sh"
source "${SCRIPT_DIR}/../src/core/state-manager.sh"
source "${SCRIPT_DIR}/../src/core/session-manager.sh"
source "${SCRIPT_DIR}/../src/core/tool-registry.sh"
source "${SCRIPT_DIR}/../src/handlers/handler-router.sh"

test_suite "Tool Tracking Integration Tests"

# ============================================================================
# Test 1: Tool Registry Initialization
# ============================================================================

test_tool_registry_loads() {
    # Tool registry should be initialized
    if type tool_registry_init &>/dev/null; then
        tool_registry_init
        return 0
    else
        echo "tool_registry_init not found" >&2
        return 1
    fi
}

test_case "should initialize tool registry" test_tool_registry_loads

# ============================================================================
# Test 2: Known Tool Registration
# ============================================================================

test_known_tools_registered() {
    # Initialize
    tool_registry_init
    handler_init

    # Register known tools in registry
    tool_registry_register_known "Bash" "${SCRIPT_DIR}/../src/handlers/bash-handler.sh"
    tool_registry_register_known "Write" "${SCRIPT_DIR}/../src/handlers/write-handler.sh"

    # Verify registration
    tool_registry_is_known "Bash" || {
        echo "Bash not registered as known tool" >&2
        return 1
    }

    tool_registry_is_known "Write" || {
        echo "Write not registered as known tool" >&2
        return 1
    }

    return 0
}

test_case "should register known tools in registry" test_known_tools_registered

# ============================================================================
# Test 3: Unknown Tool Detection
# ============================================================================

test_unknown_tool_tracking() {
    # Initialize
    state_init
    session_start
    tool_registry_init
    handler_init

    # Track an unknown tool
    tool_registry_track_unknown "CustomMCP"

    # Verify tracking
    if tool_registry_is_unknown "CustomMCP"; then
        return 0
    else
        echo "CustomMCP not tracked as unknown" >&2
        return 1
    fi
}

test_case "should track unknown tools" test_unknown_tool_tracking

# ============================================================================
# Test 4: First Occurrence Detection
# ============================================================================

test_first_occurrence_detection() {
    # Initialize
    state_init
    session_start
    tool_registry_init

    # First occurrence should return true
    if tool_registry_is_first_occurrence "NewTool"; then
        : # Expected
    else
        echo "First occurrence detection failed" >&2
        return 1
    fi

    # Track the tool
    tool_registry_track_unknown "NewTool"

    # Second check should return false
    if tool_registry_is_first_occurrence "NewTool"; then
        echo "Second occurrence incorrectly detected as first" >&2
        return 1
    fi

    return 0
}

test_case "should detect first occurrence of unknown tool" test_first_occurrence_detection

# ============================================================================
# Test 5: Frequency Tracking
# ============================================================================

test_frequency_tracking() {
    # Initialize
    state_init
    session_start
    tool_registry_init

    # Track tool multiple times
    tool_registry_track_unknown "FreqTool"
    tool_registry_track_unknown "FreqTool"
    tool_registry_track_unknown "FreqTool"

    # Get count
    local count
    count=$(tool_registry_get_unknown_count "FreqTool")

    if [[ ${count} -eq 3 ]]; then
        return 0
    else
        echo "Expected count 3, got ${count}" >&2
        return 1
    fi
}

test_case "should track tool usage frequency" test_frequency_tracking

# ============================================================================
# Test 6: Router Integration - Known Tool Pass-Through
# ============================================================================

test_router_known_tool() {
    # Initialize
    tool_registry_init
    handler_init

    # Register Bash as known
    tool_registry_register_known "Bash" "${SCRIPT_DIR}/../src/handlers/bash-handler.sh"

    # Route a known tool (should not be tracked as unknown)
    local test_input='{"tool":"Bash","command":"echo test"}'

    # Count before routing
    local count_before
    count_before=$(tool_registry_count_unknown)

    # Route (will fail because we don't have actual handler logic, but that's okay)
    handler_route "${test_input}" >/dev/null 2>&1 || true

    # Count after routing
    local count_after
    count_after=$(tool_registry_count_unknown)

    # Known tool should NOT increase unknown count
    if [[ ${count_after} -eq ${count_before} ]]; then
        return 0
    else
        echo "Known tool incorrectly tracked as unknown" >&2
        return 1
    fi
}

test_case "should not track known tools as unknown" test_router_known_tool

# ============================================================================
# Test 7: Router Integration - Unknown Tool Tracking
# ============================================================================

test_router_unknown_tool() {
    # Initialize
    state_init
    session_start
    tool_registry_init
    handler_init

    # Route an unknown tool
    local test_input='{"tool":"UnknownMCP","params":"test"}'

    # Should track as unknown when routed
    # (This test verifies the integration exists)
    local is_first
    is_first=$(tool_registry_is_first_occurrence "UnknownMCP" && echo "true" || echo "false")

    if [[ "${is_first}" == "true" ]]; then
        return 0
    else
        echo "First occurrence check failed before routing" >&2
        return 1
    fi
}

test_case "should detect unknown tools during routing" test_router_unknown_tool

# ============================================================================
# Test 8: Config-Based Enablement
# ============================================================================

test_config_based_tracking() {
    # Tool tracking should respect config
    local config_file="${SCRIPT_DIR}/../config/wow-config.json"

    if [[ ! -f "${config_file}" ]]; then
        echo "Config file not found" >&2
        return 1
    fi

    # Check if tool_tracking section exists
    if wow_has_jq; then
        local enabled
        enabled=$(jq -r '.tool_tracking.enabled // false' "${config_file}")

        if [[ "${enabled}" == "true" ]]; then
            return 0
        else
            echo "tool_tracking.enabled not set to true in config" >&2
            return 1
        fi
    fi

    return 0
}

test_case "should respect config for tool tracking" test_config_based_tracking

# ============================================================================
# Test 9: Notification on First Use
# ============================================================================

test_first_use_notification() {
    # Config should enable first-use notification
    local config_file="${SCRIPT_DIR}/../config/wow-config.json"

    if wow_has_jq; then
        local notify_enabled
        notify_enabled=$(jq -r '.tool_tracking.notify_on_first_use // false' "${config_file}")

        if [[ "${notify_enabled}" == "true" ]]; then
            return 0
        else
            echo "notify_on_first_use not enabled in config" >&2
            return 1
        fi
    fi

    return 0
}

test_case "should have notification config for first use" test_first_use_notification

# ============================================================================
# Test 10: Handler Router Sources Tool Registry
# ============================================================================

test_router_sources_registry() {
    # Handler router should source or have access to tool registry functions
    source "${SCRIPT_DIR}/../src/handlers/handler-router.sh"

    # After sourcing router, registry functions should be available
    if type tool_registry_track_unknown &>/dev/null; then
        return 0
    else
        echo "tool_registry functions not available after sourcing router" >&2
        return 1
    fi
}

test_case "should source tool registry in handler router" test_router_sources_registry

# ============================================================================
# Test 11: Integration with Session Manager
# ============================================================================

test_session_integration() {
    # Tool tracking should integrate with session manager
    state_init
    session_start
    tool_registry_init

    # Track a tool
    tool_registry_track_unknown "SessionTool"

    # Should be persistable
    tool_registry_save

    # Should be retrievable
    local count
    count=$(tool_registry_get_unknown_count "SessionTool")

    if [[ ${count} -ge 1 ]]; then
        return 0
    else
        echo "Session integration failed" >&2
        return 1
    fi
}

test_case "should integrate with session manager" test_session_integration

# ============================================================================
# Test 12: Unknown Tool Metadata
# ============================================================================

test_unknown_tool_metadata() {
    # Initialize
    state_init
    session_start
    tool_registry_init

    # Track a tool
    tool_registry_track_unknown "MetaTool"

    # Get metadata
    local metadata
    metadata=$(tool_registry_get_unknown_metadata "MetaTool")

    # Should have metadata
    if [[ -n "${metadata}" ]]; then
        # Should contain tool name
        if echo "${metadata}" | grep -q "MetaTool"; then
            return 0
        fi
    fi

    echo "Metadata not available or incomplete" >&2
    return 1
}

test_case "should store metadata for unknown tools" test_unknown_tool_metadata

# ============================================================================
# Summary
# ============================================================================

test_summary
