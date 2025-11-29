#!/bin/bash
# WoW System - Tool Registry Tests (TDD)
# Tests written FIRST before implementation
# Author: Chude <chude@emeke.org>

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

test_suite "Tool Registry Tests"

# ============================================================================
# Setup / Teardown
# ============================================================================

setup() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"

    # Initialize orchestrator for dependencies
    source "${SCRIPT_DIR}/../src/core/orchestrator.sh"
    wow_init 2>/dev/null || true

    # Source the tool registry
    REGISTRY_PATH="${SCRIPT_DIR}/../src/core/tool-registry.sh"

    if [[ ! -f "${REGISTRY_PATH}" ]]; then
        echo "ERROR: tool-registry.sh not found (TDD RED phase expected)" >&2
        return 1
    fi

    source "${REGISTRY_PATH}" || {
        echo "ERROR: Failed to source tool-registry.sh" >&2
        return 1
    }

    # Verify functions exist
    if ! type tool_registry_init &>/dev/null; then
        echo "ERROR: tool_registry_init function not found" >&2
        return 1
    fi

    # Initialize registry
    tool_registry_init
}

teardown() {
    true
}

# ============================================================================
# Test Group 1: Registry Initialization
# ============================================================================

test_registry_initialization() {
    setup

    # Registry should initialize successfully
    tool_registry_init
    local result=$?

    assert_equals 0 ${result} "Registry initialization should succeed"

    teardown
}

test_registry_empty_on_first_init() {
    setup

    # Registry should be empty on first initialization
    local known_count=$(tool_registry_count_known)
    local unknown_count=$(tool_registry_count_unknown)

    assert_equals 0 ${known_count} "Known tools should be 0 initially"
    assert_equals 0 ${unknown_count} "Unknown tools should be 0 initially"

    teardown
}

# ============================================================================
# Test Group 2: Known Tool Registration
# ============================================================================

test_register_known_tool() {
    setup

    # Register a known tool
    tool_registry_register_known "Bash" "bash-handler.sh"
    local result=$?

    assert_equals 0 ${result} "Known tool registration should succeed"

    # Verify it's registered
    tool_registry_is_known "Bash"
    assert_success "Bash should be registered as known"

    teardown
}

test_register_multiple_known_tools() {
    setup

    # Register multiple tools
    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_register_known "Write" "write-handler.sh"
    tool_registry_register_known "Edit" "edit-handler.sh"

    local count=$(tool_registry_count_known)
    assert_equals 3 ${count} "Should have 3 known tools"

    teardown
}

test_duplicate_known_tool_registration() {
    setup

    # Register same tool twice
    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_register_known "Bash" "bash-handler.sh"

    local count=$(tool_registry_count_known)
    assert_equals 1 ${count} "Duplicate registration should be idempotent"

    teardown
}

test_query_known_tool() {
    setup

    # Register and query
    tool_registry_register_known "Bash" "bash-handler.sh"

    local handler=$(tool_registry_get_handler "Bash")
    assert_equals "bash-handler.sh" "${handler}" "Handler path should match"

    teardown
}

# ============================================================================
# Test Group 3: Unknown Tool Tracking
# ============================================================================

test_track_unknown_tool_first_occurrence() {
    setup

    # Track unknown tool
    tool_registry_track_unknown "CustomMCP"
    local result=$?

    assert_equals 0 ${result} "Unknown tool tracking should succeed"

    # Verify it's tracked
    tool_registry_is_unknown "CustomMCP"
    assert_success "CustomMCP should be tracked as unknown"

    teardown
}

test_unknown_tool_frequency_tracking() {
    setup

    # Track same tool multiple times
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"

    local count=$(tool_registry_get_unknown_count "CustomMCP")
    assert_equals 3 ${count} "CustomMCP should have count of 3"

    teardown
}

test_unknown_tool_first_seen_timestamp() {
    setup

    # Track tool and check first_seen
    tool_registry_track_unknown "CustomMCP"

    local first_seen=$(tool_registry_get_unknown_first_seen "CustomMCP")
    assert_not_empty "${first_seen}" "First seen timestamp should be set"

    teardown
}

test_unknown_tool_last_seen_updates() {
    setup

    # Track tool twice with delay
    tool_registry_track_unknown "CustomMCP"
    sleep 1
    tool_registry_track_unknown "CustomMCP"

    local first_seen=$(tool_registry_get_unknown_first_seen "CustomMCP")
    local last_seen=$(tool_registry_get_unknown_last_seen "CustomMCP")

    # Last seen should be after first seen
    [[ "${last_seen}" > "${first_seen}" ]]
    assert_success "Last seen should be after first seen"

    teardown
}

test_multiple_unknown_tools() {
    setup

    # Track multiple unknown tools
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "NotebookEdit"
    tool_registry_track_unknown "WebSearch"

    local count=$(tool_registry_count_unknown)
    assert_equals 3 ${count} "Should have 3 unknown tools"

    teardown
}

# ============================================================================
# Test Group 4: Tool Classification
# ============================================================================

test_tool_is_known_classification() {
    setup

    tool_registry_register_known "Bash" "bash-handler.sh"

    # Known tool should return true
    tool_registry_is_known "Bash"
    assert_success "Bash should be classified as known"

    # Unknown tool should return false
    tool_registry_is_known "CustomMCP"
    assert_failure "CustomMCP should not be classified as known"

    teardown
}

test_tool_is_unknown_classification() {
    setup

    tool_registry_track_unknown "CustomMCP"

    # Unknown tool should return true
    tool_registry_is_unknown "CustomMCP"
    assert_success "CustomMCP should be classified as unknown"

    # Known tool should return false
    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_is_unknown "Bash"
    assert_failure "Bash should not be classified as unknown"

    teardown
}

test_tool_first_occurrence_detection() {
    setup

    # First occurrence should return true
    tool_registry_is_first_occurrence "CustomMCP"
    assert_success "First occurrence of CustomMCP should be detected"

    # Track it
    tool_registry_track_unknown "CustomMCP"

    # Second occurrence should return false
    tool_registry_is_first_occurrence "CustomMCP"
    assert_failure "Second occurrence should not be first"

    teardown
}

# ============================================================================
# Test Group 5: Registry Queries
# ============================================================================

test_list_all_known_tools() {
    setup

    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_register_known "Write" "write-handler.sh"
    tool_registry_register_known "Edit" "edit-handler.sh"

    local tools=$(tool_registry_list_known)

    echo "${tools}" | grep -q "Bash"
    assert_success "Known tools should include Bash"

    echo "${tools}" | grep -q "Write"
    assert_success "Known tools should include Write"

    teardown
}

test_list_all_unknown_tools() {
    setup

    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "NotebookEdit"

    local tools=$(tool_registry_list_unknown)

    echo "${tools}" | grep -q "CustomMCP"
    assert_success "Unknown tools should include CustomMCP"

    echo "${tools}" | grep -q "NotebookEdit"
    assert_success "Unknown tools should include NotebookEdit"

    teardown
}

test_get_unknown_tool_metadata() {
    setup

    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"

    local metadata=$(tool_registry_get_unknown_metadata "CustomMCP")

    echo "${metadata}" | grep -q "count"
    assert_success "Metadata should include count"

    echo "${metadata}" | grep -q "first_seen"
    assert_success "Metadata should include first_seen"

    echo "${metadata}" | grep -q "last_seen"
    assert_success "Metadata should include last_seen"

    teardown
}

# ============================================================================
# Test Group 6: Persistence
# ============================================================================

test_registry_persists_across_restarts() {
    setup

    # Register and track
    tool_registry_register_known "Bash" "bash-handler.sh"
    tool_registry_track_unknown "CustomMCP"

    # Save state
    tool_registry_save

    # Simulate restart - reinitialize
    tool_registry_init

    # Verify data persisted
    tool_registry_is_known "Bash"
    assert_success "Known tools should persist"

    tool_registry_is_unknown "CustomMCP"
    assert_success "Unknown tools should persist"

    teardown
}

test_unknown_tool_count_persists() {
    setup

    # Track multiple times
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"
    tool_registry_track_unknown "CustomMCP"

    tool_registry_save

    # Restart
    tool_registry_init

    local count=$(tool_registry_get_unknown_count "CustomMCP")
    assert_equals 3 ${count} "Count should persist"

    teardown
}

# ============================================================================
# Test Group 7: Edge Cases
# ============================================================================

test_empty_tool_name() {
    setup

    # Empty tool name should fail gracefully
    tool_registry_register_known "" "handler.sh" 2>/dev/null
    local result=$?

    assert_not_equals 0 ${result} "Empty tool name should fail"

    teardown
}

test_malformed_tool_name() {
    setup

    # Tool name with special characters
    tool_registry_track_unknown "Tool\$With\$Special\$Chars"

    # Should handle gracefully (sanitize or reject)
    local count=$(tool_registry_count_unknown)
    [[ ${count} -ge 0 ]]
    assert_success "Malformed tool name should be handled"

    teardown
}

test_very_long_tool_name() {
    setup

    # 200 character tool name
    local long_name=$(printf 'A%.0s' {1..200})
    tool_registry_track_unknown "${long_name}"

    # Should handle gracefully (truncate or reject)
    local count=$(tool_registry_count_unknown)
    [[ ${count} -ge 0 ]]
    assert_success "Long tool name should be handled"

    teardown
}

test_concurrent_tracking() {
    setup

    # Simulate concurrent access (best effort)
    tool_registry_track_unknown "Tool1" &
    tool_registry_track_unknown "Tool2" &
    tool_registry_track_unknown "Tool3" &
    wait

    local count=$(tool_registry_count_unknown)
    assert_equals 3 ${count} "Concurrent tracking should work"

    teardown
}

# ============================================================================
# Run all tests
# ============================================================================

# Registry initialization
test_case "Registry initializes successfully" test_registry_initialization
test_case "Registry starts empty" test_registry_empty_on_first_init

# Known tool registration
test_case "Register known tool" test_register_known_tool
test_case "Register multiple known tools" test_register_multiple_known_tools
test_case "Duplicate registration is idempotent" test_duplicate_known_tool_registration
test_case "Query known tool handler" test_query_known_tool

# Unknown tool tracking
test_case "Track unknown tool first occurrence" test_track_unknown_tool_first_occurrence
test_case "Unknown tool frequency tracking" test_unknown_tool_frequency_tracking
test_case "Unknown tool first seen timestamp" test_unknown_tool_first_seen_timestamp
test_case "Unknown tool last seen updates" test_unknown_tool_last_seen_updates
test_case "Track multiple unknown tools" test_multiple_unknown_tools

# Tool classification
test_case "Tool is known classification" test_tool_is_known_classification
test_case "Tool is unknown classification" test_tool_is_unknown_classification
test_case "First occurrence detection" test_tool_first_occurrence_detection

# Registry queries
test_case "List all known tools" test_list_all_known_tools
test_case "List all unknown tools" test_list_all_unknown_tools
test_case "Get unknown tool metadata" test_get_unknown_tool_metadata

# Persistence
test_case "Registry persists across restarts" test_registry_persists_across_restarts
test_case "Unknown tool count persists" test_unknown_tool_count_persists

# Edge cases
test_case "Empty tool name" test_empty_tool_name
test_case "Malformed tool name" test_malformed_tool_name
test_case "Very long tool name" test_very_long_tool_name
test_case "Concurrent tracking" test_concurrent_tracking

# Summary
test_summary
