#!/bin/bash
# WoW System - Orchestrator Tests
# Tests for central module loading and initialization
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

ORCHESTRATOR="${SCRIPT_DIR}/../src/core/orchestrator.sh"
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

source_orchestrator() {
    if [[ -f "${ORCHESTRATOR}" ]]; then
        source "${ORCHESTRATOR}"
        return 0
    else
        echo "Orchestrator not implemented yet"
        return 1
    fi
}

# ============================================================================
# Tests
# ============================================================================

test_suite "Orchestrator"

# Test 1: Orchestrator file exists
test_orchestrator_exists() {
    assert_file_exists "${ORCHESTRATOR}" "Orchestrator should exist"
}
test_case "Orchestrator file exists" test_orchestrator_exists

# Test 2: Initialize orchestrator
test_orchestrator_init() {
    source_orchestrator || return 1
    wow_init
    assert_success "Orchestrator initialization should succeed"
}
test_case "Initialize orchestrator" test_orchestrator_init

# Test 3: All core modules loaded
test_core_modules_loaded() {
    source_orchestrator || return 1
    wow_init

    # Check if core functions are available
    type state_init &>/dev/null && local has_state="true" || local has_state="false"
    type config_init &>/dev/null && local has_config="true" || local has_config="false"
    type session_start &>/dev/null && local has_session="true" || local has_session="false"

    assert_equals "true" "${has_state}" "State manager should be loaded"
    assert_equals "true" "${has_config}" "Config loader should be loaded"
    assert_equals "true" "${has_session}" "Session manager should be loaded"
}
test_case "All core modules loaded" test_core_modules_loaded

# Test 4: Storage module loaded
test_storage_loaded() {
    source_orchestrator || return 1
    wow_init

    type storage_init &>/dev/null && local has_storage="true" || local has_storage="false"

    assert_equals "true" "${has_storage}" "Storage adapter should be loaded"
}
test_case "Storage module loaded" test_storage_loaded

# Test 5: Check module load order (dependencies first)
test_module_load_order() {
    source_orchestrator || return 1

    # Utils should be loaded before everything else
    # This is verified by the fact that other modules use utils functions
    wow_init

    # If we can call state_init without error, dependencies are loaded correctly
    state_init
    assert_success "Modules loaded in correct order"
}
test_case "Module load order correct" test_module_load_order

# Test 6: Graceful handling of missing modules
test_missing_module_handling() {
    source_orchestrator || return 1

    # Temporarily rename a module to simulate missing file
    local state_mgr="${SCRIPT_DIR}/../src/core/state-manager.sh"
    local backup="${state_mgr}.backup"

    mv "${state_mgr}" "${backup}" 2>/dev/null || true

    wow_init 2>/dev/null && local result="success" || local result="failure"

    # Restore the file
    mv "${backup}" "${state_mgr}" 2>/dev/null || true

    # Should fail gracefully
    assert_equals "failure" "${result}" "Should fail when module is missing"
}
test_case "Handle missing modules gracefully" test_missing_module_handling

# Test 7: Idempotent initialization
test_idempotent_init() {
    source_orchestrator || return 1

    wow_init
    local first_init=$?

    wow_init
    local second_init=$?

    assert_equals "0" "${first_init}" "First init should succeed"
    assert_equals "0" "${second_init}" "Second init should succeed (idempotent)"
}
test_case "Initialization is idempotent" test_idempotent_init

# Test 8: Get WoW version
test_get_version() {
    source_orchestrator || return 1
    wow_init

    local version
    version=$(wow_get_version)

    # Version format check - should be semantic version (X.Y.Z), not hardcoded
    assert_contains "${version}" "." "Should return version number with dots"
}
test_case "Get WoW version" test_get_version

# Test 9: Check if system is initialized
test_is_initialized() {
    source_orchestrator || return 1

    wow_is_initialized && local before="true" || local before="false"

    wow_init

    wow_is_initialized && local after="true" || local after="false"

    assert_equals "false" "${before}" "Should not be initialized before init"
    assert_equals "true" "${after}" "Should be initialized after init"
}
test_case "Check initialization status" test_is_initialized

# Test 10: Cleanup on shutdown
test_cleanup() {
    source_orchestrator || return 1
    wow_init

    # Set some state
    state_set "test_data" "test_value"

    wow_cleanup
    assert_success "Cleanup should succeed"
}
test_case "Cleanup on shutdown" test_cleanup

# Test 11: Load custom config file
test_load_custom_config() {
    source_orchestrator || return 1

    local config_file="${TEST_DATA_DIR}/custom-config.json"
    echo '{"version": "5.0.0", "custom_setting": "custom_value"}' > "${config_file}"

    wow_init "${config_file}"

    local setting
    setting=$(config_get "custom_setting" "")

    assert_equals "custom_value" "${setting}" "Should load custom config"
}
test_case "Load custom config file" test_load_custom_config

# Test 12: Module availability check
test_check_module_available() {
    source_orchestrator || return 1
    wow_init

    wow_module_available "state" && local has_state="true" || local has_state="false"
    wow_module_available "config" && local has_config="true" || local has_config="false"
    wow_module_available "nonexistent" && local has_fake="true" || local has_fake="false"

    assert_equals "true" "${has_state}" "State module should be available"
    assert_equals "true" "${has_config}" "Config module should be available"
    assert_equals "false" "${has_fake}" "Nonexistent module should not be available"
}
test_case "Check module availability" test_check_module_available

# Test 13: Error handling during init
test_init_error_handling() {
    source_orchestrator || return 1

    # Test with invalid config
    local invalid_config="${TEST_DATA_DIR}/invalid.json"
    echo "{ invalid json }" > "${invalid_config}"

    wow_init "${invalid_config}" 2>/dev/null && local result="success" || local result="failure"

    # Should still initialize (config errors shouldn't prevent init)
    assert_equals "success" "${result}" "Should handle config errors gracefully"
}
test_case "Error handling during init" test_init_error_handling

# Test 14: Double-sourcing protection
test_double_sourcing_protection() {
    source_orchestrator || return 1
    wow_init

    # Source again - should not cause errors
    source_orchestrator
    wow_init

    assert_success "Should handle double-sourcing gracefully"
}
test_case "Double-sourcing protection" test_double_sourcing_protection

# Run all tests
test_summary
