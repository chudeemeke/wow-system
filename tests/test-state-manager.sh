#!/bin/bash
# WoW System - State Manager Tests
# Tests for session state management
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Will source the state manager once it's implemented
STATE_MANAGER="${SCRIPT_DIR}/../src/core/state-manager.sh"

# Test data directory
TEST_DATA_DIR=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_state_manager() {
    if [[ -f "${STATE_MANAGER}" ]]; then
        source "${STATE_MANAGER}"
        return 0
    else
        echo "State manager not implemented yet: ${STATE_MANAGER}"
        return 1
    fi
}

# ============================================================================
# Tests
# ============================================================================

test_suite "State Manager"

# Test 1: State manager can be sourced
test_state_manager_exists() {
    assert_file_exists "${STATE_MANAGER}" "State manager file should exist"
}
test_case "State manager file exists" test_state_manager_exists

# Test 2: Initialize state
test_state_init() {
    source_state_manager || return 1
    state_init
    assert_success "State initialization should succeed"
}
test_case "State initialization" test_state_init

# Test 3: Set and get session state
test_state_set_get() {
    source_state_manager || return 1
    state_init

    state_set "test_key" "test_value"
    local value
    value=$(state_get "test_key")

    assert_equals "test_value" "${value}" "Should retrieve the value that was set"
}
test_case "Set and get session state" test_state_set_get

# Test 4: Get with default value
test_state_get_default() {
    source_state_manager || return 1
    state_init

    local value
    value=$(state_get "nonexistent_key" "default_value")

    assert_equals "default_value" "${value}" "Should return default for missing key"
}
test_case "Get with default value" test_state_get_default

# Test 5: Check if key exists
test_state_exists() {
    source_state_manager || return 1
    state_init

    state_set "existing_key" "value"

    state_exists "existing_key" && local exists1="true" || local exists1="false"
    state_exists "missing_key" && local exists2="true" || local exists2="false"

    assert_equals "true" "${exists1}" "Should return true for existing key"
    assert_equals "false" "${exists2}" "Should return false for missing key"
}
test_case "Check if state key exists" test_state_exists

# Test 6: Delete state
test_state_delete() {
    source_state_manager || return 1
    state_init

    state_set "key_to_delete" "value"
    state_delete "key_to_delete"

    state_exists "key_to_delete" && local still_exists="true" || local still_exists="false"

    assert_equals "false" "${still_exists}" "Key should not exist after deletion"
}
test_case "Delete state" test_state_delete

# Test 7: Increment counter
test_state_increment() {
    source_state_manager || return 1
    state_init

    state_increment "counter"
    state_increment "counter"
    state_increment "counter"

    local value
    value=$(state_get "counter")

    assert_equals "3" "${value}" "Counter should be incremented to 3"
}
test_case "Increment counter" test_state_increment

# Test 8: Decrement counter
test_state_decrement() {
    source_state_manager || return 1
    state_init

    state_set "counter" "10"
    state_decrement "counter"
    state_decrement "counter"

    local value
    value=$(state_get "counter")

    assert_equals "8" "${value}" "Counter should be decremented to 8"
}
test_case "Decrement counter" test_state_decrement

# Test 9: Append to array
test_state_append() {
    source_state_manager || return 1
    state_init

    state_append "my_list" "item1"
    state_append "my_list" "item2"
    state_append "my_list" "item3"

    local value
    value=$(state_get "my_list")

    assert_contains "${value}" "item1" "Should contain item1"
    assert_contains "${value}" "item2" "Should contain item2"
    assert_contains "${value}" "item3" "Should contain item3"
}
test_case "Append to array" test_state_append

# Test 10: Get session info
test_state_session_info() {
    source_state_manager || return 1
    state_init

    local info
    info=$(state_session_info)

    assert_contains "${info}" "session_id" "Session info should contain session_id"
    assert_contains "${info}" "started_at" "Session info should contain started_at"
}
test_case "Get session info" test_state_session_info

# Test 11: State persistence across restarts
test_state_persistence() {
    source_state_manager || return 1

    # First session
    state_init
    local session_id1
    session_id1=$(state_get "_session_id")
    state_set "persistent_key" "persistent_value"
    state_save

    # Simulate restart
    unset _WOW_STATE
    declare -gA _WOW_STATE

    # Second session - should restore
    state_init
    state_load

    local session_id2
    session_id2=$(state_get "_session_id")
    local value
    value=$(state_get "persistent_key" "")

    assert_not_equals "${session_id1}" "${session_id2}" "New session should have different ID"
    assert_equals "persistent_value" "${value}" "Persistent data should be restored"
}
test_case "State persistence" test_state_persistence

# Test 12: Clear all state
test_state_clear() {
    source_state_manager || return 1
    state_init

    state_set "key1" "value1"
    state_set "key2" "value2"

    state_clear

    state_exists "key1" && local exists="true" || local exists="false"

    assert_equals "false" "${exists}" "All state should be cleared"
}
test_case "Clear all state" test_state_clear

# Test 13: Get all keys
test_state_keys() {
    source_state_manager || return 1
    state_init

    state_set "alpha" "1"
    state_set "beta" "2"
    state_set "gamma" "3"

    local keys
    keys=$(state_keys)

    assert_contains "${keys}" "alpha" "Should list alpha"
    assert_contains "${keys}" "beta" "Should list beta"
    assert_contains "${keys}" "gamma" "Should list gamma"
}
test_case "Get all state keys" test_state_keys

# Test 14: Namespace isolation
test_state_namespace() {
    source_state_manager || return 1
    state_init

    state_set "shared_key" "session_value"
    state_set "user:name" "John"
    state_set "metrics:count" "42"

    local session_val
    session_val=$(state_get "shared_key")
    local user_val
    user_val=$(state_get "user:name")
    local metrics_val
    metrics_val=$(state_get "metrics:count")

    assert_equals "session_value" "${session_val}" "Session value should be correct"
    assert_equals "John" "${user_val}" "User namespace value should be correct"
    assert_equals "42" "${metrics_val}" "Metrics namespace value should be correct"
}
test_case "Namespace isolation" test_state_namespace

# Run all tests
test_summary
