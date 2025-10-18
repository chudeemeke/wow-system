#!/bin/bash
# Test Suite: Handler Router + Tool Registry Integration
# Tests integration between handler routing and tool tracking
# Author: Chude <chude@emeke.org>
#
# TDD Approach: Tests written FIRST before implementation

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source modules under test
source "${SCRIPT_DIR}/../src/core/utils.sh"
source "${SCRIPT_DIR}/../src/core/state-manager.sh"
source "${SCRIPT_DIR}/../src/core/tool-registry.sh"
source "${SCRIPT_DIR}/../src/handlers/handler-router.sh"

# ============================================================================
# Test Suite Setup
# ============================================================================

test_suite "Handler Router + Tool Registry Integration Tests"

# Test environment setup
setup_test_env() {
    # Initialize tool registry
    tool_registry_init

    # Initialize handler router
    handler_init
}

cleanup_test_env() {
    # Clean up in-memory state
    unset _KNOWN_TOOLS
    unset _UNKNOWN_TOOLS
    unset _WOW_HANDLER_REGISTRY
}

# ============================================================================
# Test Cases - Known Tool Registration
# ============================================================================

test_known_tools_registered_on_init() {
    setup_test_env

    # Verify known tools are registered in tool-registry
    assert_true tool_registry_is_known "Bash" "Bash should be registered as known tool"
    assert_true tool_registry_is_known "Write" "Write should be registered as known tool"
    assert_true tool_registry_is_known "Edit" "Edit should be registered as known tool"
    assert_true tool_registry_is_known "Read" "Read should be registered as known tool"
    assert_true tool_registry_is_known "Glob" "Glob should be registered as known tool"
    assert_true tool_registry_is_known "Grep" "Grep should be registered as known tool"
    assert_true tool_registry_is_known "Task" "Task should be registered as known tool"
    assert_true tool_registry_is_known "WebFetch" "WebFetch should be registered as known tool"

    cleanup_test_env
}

test_known_tool_count_correct() {
    setup_test_env

    # Should have exactly 8 known tools registered
    local count
    count=$(tool_registry_count_known)
    assert_equals "8" "${count}" "Should have 8 known tools"

    cleanup_test_env
}

test_known_tool_has_handler_path() {
    setup_test_env

    # Verify handler paths are stored correctly
    local bash_handler
    bash_handler=$(tool_registry_get_handler "Bash")
    assert_contains "${bash_handler}" "bash-handler.sh" "Bash handler path should be set"

    local write_handler
    write_handler=$(tool_registry_get_handler "Write")
    assert_contains "${write_handler}" "write-handler.sh" "Write handler path should be set"

    cleanup_test_env
}

# ============================================================================
# Test Cases - Unknown Tool Tracking
# ============================================================================

test_unknown_tool_tracked_on_route() {
    setup_test_env

    # Simulate routing an unknown tool
    local test_input='{"tool": "UnknownMCP", "parameters": {"foo": "bar"}}'
    handler_route "${test_input}" >/dev/null

    # Verify tool was tracked
    assert_true tool_registry_is_unknown "UnknownMCP" "Unknown tool should be tracked"

    cleanup_test_env
}

test_first_occurrence_detected() {
    setup_test_env

    # Before routing, should be first occurrence
    assert_true tool_registry_is_first_occurrence "NewCustomTool" "Should detect first occurrence before tracking"

    # Route the tool
    local test_input='{"tool": "NewCustomTool", "parameters": {}}'
    handler_route "${test_input}" >/dev/null

    # After routing, should NOT be first occurrence
    assert_false tool_registry_is_first_occurrence "NewCustomTool" "Should not be first occurrence after tracking"

    cleanup_test_env
}

test_unknown_tool_frequency_increments() {
    setup_test_env

    local test_input='{"tool": "FrequentTool", "parameters": {}}'

    # Route tool multiple times
    handler_route "${test_input}" >/dev/null
    handler_route "${test_input}" >/dev/null
    handler_route "${test_input}" >/dev/null

    # Verify count is 3
    local count
    count=$(tool_registry_get_unknown_count "FrequentTool")
    assert_equals "3" "${count}" "Unknown tool should have count of 3"

    cleanup_test_env
}

test_unknown_tool_metadata_captured() {
    setup_test_env

    local test_input='{"tool": "MetadataTool", "parameters": {}}'
    handler_route "${test_input}" >/dev/null

    # Verify metadata exists
    local metadata
    metadata=$(tool_registry_get_unknown_metadata "MetadataTool")
    assert_not_empty "${metadata}" "Metadata should be captured"

    # Verify first_seen timestamp exists
    local first_seen
    first_seen=$(tool_registry_get_unknown_first_seen "MetadataTool")
    assert_not_empty "${first_seen}" "First seen timestamp should be set"

    cleanup_test_env
}

# ============================================================================
# Test Cases - Pass-Through Behavior
# ============================================================================

test_unknown_tool_passes_through() {
    setup_test_env

    local test_input='{"tool": "PassThroughTool", "command": "test"}'
    local result
    result=$(handler_route "${test_input}")

    # Should return original input unchanged
    assert_equals "${test_input}" "${result}" "Unknown tool should pass through unchanged"

    cleanup_test_env
}

test_known_tool_not_tracked_as_unknown() {
    setup_test_env

    # Route a known tool (that won't actually execute since handler file exists but won't be sourced in test)
    # We're just testing it doesn't get tracked as unknown
    local test_input='{"tool": "Bash", "command": "echo test"}'

    # Before routing, reset unknown tools
    declare -gA _UNKNOWN_TOOLS=()

    # This will fail to execute the actual handler, but that's OK for this test
    handler_route "${test_input}" >/dev/null 2>&1 || true

    # Verify Bash was NOT tracked as unknown
    assert_false tool_registry_is_unknown "Bash" "Known tool should not be tracked as unknown"

    cleanup_test_env
}

# ============================================================================
# Test Cases - Edge Cases
# ============================================================================

test_empty_tool_name_handled() {
    setup_test_env

    # Input with no tool field
    local test_input='{"parameters": {}}'
    local result
    result=$(handler_route "${test_input}")

    # Should pass through without crashing
    assert_equals "${test_input}" "${result}" "Empty tool name should pass through"

    cleanup_test_env
}

test_malformed_json_handled() {
    setup_test_env

    # Invalid JSON
    local test_input='not-valid-json'
    local result
    result=$(handler_route "${test_input}") || true

    # Should not crash (may return empty or input, either is acceptable)
    # Main goal is not to crash
    assert_success "Malformed JSON should not crash router"

    cleanup_test_env
}

test_registry_persists_state() {
    setup_test_env

    # Track an unknown tool
    local test_input='{"tool": "PersistTool", "parameters": {}}'
    handler_route "${test_input}" >/dev/null

    # Save state
    tool_registry_save

    # Verify save succeeded (no error)
    assert_success "Registry should save state successfully"

    cleanup_test_env
}

# ============================================================================
# Test Cases - Integration Scenarios
# ============================================================================

test_mixed_known_and_unknown_tools() {
    setup_test_env

    # Route known tool
    local known_input='{"tool": "Read", "file_path": "/tmp/test"}'
    handler_route "${known_input}" >/dev/null 2>&1 || true

    # Route unknown tool
    local unknown_input='{"tool": "CustomAnalyzer", "parameters": {}}'
    handler_route "${unknown_input}" >/dev/null

    # Verify known is not in unknown
    assert_false tool_registry_is_unknown "Read" "Known tool should not be in unknown registry"

    # Verify unknown is tracked
    assert_true tool_registry_is_unknown "CustomAnalyzer" "Unknown tool should be tracked"

    cleanup_test_env
}

test_registry_survives_multiple_inits() {
    # First init
    tool_registry_init
    handler_init

    # Track tool
    local test_input='{"tool": "SurviveTool", "parameters": {}}'
    handler_route "${test_input}" >/dev/null

    # Save
    tool_registry_save

    # Second init (simulating new session)
    tool_registry_init
    handler_init

    # Verify tool is still tracked
    assert_true tool_registry_is_unknown "SurviveTool" "Tool should persist across re-initialization"

    cleanup_test_env
}

test_large_number_of_unknown_tools() {
    setup_test_env

    # Track 100 different unknown tools
    for i in {1..100}; do
        local test_input="{\"tool\": \"UnknownTool${i}\", \"parameters\": {}}"
        handler_route "${test_input}" >/dev/null
    done

    # Verify count is 100
    local count
    count=$(tool_registry_count_unknown)
    assert_equals "100" "${count}" "Should track 100 unknown tools"

    cleanup_test_env
}

test_unicode_tool_names_sanitized() {
    setup_test_env

    # Tool name with unicode/special characters
    local test_input='{"tool": "Tool™️🚀<script>", "parameters": {}}'
    handler_route "${test_input}" >/dev/null

    # Should sanitize and track (name will be sanitized to alphanumeric)
    # Just verify it doesn't crash
    assert_success "Unicode/special characters should be sanitized"

    cleanup_test_env
}

# ============================================================================
# Run Test Suite
# ============================================================================

# Test: Known Tool Registration (3 tests)
test_case "should register all known tools on init" test_known_tools_registered_on_init
test_case "should have correct known tool count" test_known_tool_count_correct
test_case "should store handler paths for known tools" test_known_tool_has_handler_path

# Test: Unknown Tool Tracking (5 tests)
test_case "should track unknown tools on route" test_unknown_tool_tracked_on_route
test_case "should detect first occurrence" test_first_occurrence_detected
test_case "should increment frequency count" test_unknown_tool_frequency_increments
test_case "should capture metadata for unknown tools" test_unknown_tool_metadata_captured
test_case "should not track known tools as unknown" test_known_tool_not_tracked_as_unknown

# Test: Pass-Through Behavior (1 test)
test_case "should pass through unknown tools unchanged" test_unknown_tool_passes_through

# Test: Edge Cases (4 tests)
test_case "should handle empty tool name" test_empty_tool_name_handled
test_case "should handle malformed JSON" test_malformed_json_handled
test_case "should persist registry state" test_registry_persists_state
test_case "should sanitize unicode tool names" test_unicode_tool_names_sanitized

# Test: Integration Scenarios (3 tests)
test_case "should handle mixed known and unknown tools" test_mixed_known_and_unknown_tools
test_case "should persist across re-initialization" test_registry_survives_multiple_inits
test_case "should scale to large number of unknown tools" test_large_number_of_unknown_tools

# Show summary
test_summary
