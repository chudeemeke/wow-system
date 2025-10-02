#!/bin/bash
# WoW System - Config Loader Tests
# Tests for configuration management
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

CONFIG_LOADER="${SCRIPT_DIR}/../src/core/config-loader.sh"
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

source_config_loader() {
    if [[ -f "${CONFIG_LOADER}" ]]; then
        source "${CONFIG_LOADER}"
        return 0
    else
        echo "Config loader not implemented yet"
        return 1
    fi
}

create_test_config() {
    local config_file="$1"
    cat > "${config_file}" <<'EOF'
{
  "version": "4.1.0",
  "enforcement": {
    "enabled": true,
    "strict_mode": false,
    "block_on_violation": false
  },
  "scoring": {
    "threshold_warn": 50,
    "threshold_block": 80,
    "decay_rate": 0.95
  },
  "rules": {
    "max_file_operations": 10,
    "max_bash_commands": 5,
    "require_documentation": true
  },
  "integrations": {
    "claude_code": {
      "hooks_enabled": true,
      "session_tracking": true
    }
  }
}
EOF
}

create_invalid_json() {
    local config_file="$1"
    cat > "${config_file}" <<'EOF'
{
  "version": "4.1.0",
  "enforcement": {
    "enabled": true,
    # Invalid comment
    "strict_mode": false
  }
}
EOF
}

# ============================================================================
# Tests
# ============================================================================

test_suite "Config Loader"

# Test 1: Config loader exists
test_config_loader_exists() {
    assert_file_exists "${CONFIG_LOADER}" "Config loader should exist"
}
test_case "Config loader file exists" test_config_loader_exists

# Test 2: Initialize config system
test_config_init() {
    source_config_loader || return 1
    config_init
    assert_success "Config initialization should succeed"
}
test_case "Config initialization" test_config_init

# Test 3: Load config from file
test_config_load() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"

    config_load "${config_file}"
    assert_success "Should load valid config file"
}
test_case "Load config from file" test_config_load

# Test 4: Get config value
test_config_get() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    local version
    version=$(config_get "version")

    assert_equals "4.1.0" "${version}" "Should get correct version"
}
test_case "Get config value" test_config_get

# Test 5: Get nested config value
test_config_get_nested() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    local enabled
    enabled=$(config_get "enforcement.enabled")

    assert_equals "true" "${enabled}" "Should get nested value"
}
test_case "Get nested config value" test_config_get_nested

# Test 6: Get with default value
test_config_get_default() {
    source_config_loader || return 1
    config_init

    local value
    value=$(config_get "nonexistent.key" "default_value")

    assert_equals "default_value" "${value}" "Should return default for missing key"
}
test_case "Get config with default" test_config_get_default

# Test 7: Set config value
test_config_set() {
    source_config_loader || return 1
    config_init

    config_set "new_key" "new_value"
    local value
    value=$(config_get "new_key")

    assert_equals "new_value" "${value}" "Should set and retrieve value"
}
test_case "Set config value" test_config_set

# Test 8: Set nested config value
test_config_set_nested() {
    source_config_loader || return 1
    config_init

    config_set "custom.nested.key" "nested_value"
    local value
    value=$(config_get "custom.nested.key")

    assert_equals "nested_value" "${value}" "Should set and retrieve nested value"
}
test_case "Set nested config value" test_config_set_nested

# Test 9: Check if config key exists
test_config_exists() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    config_exists "version" && local exists1="true" || local exists1="false"
    config_exists "nonexistent" && local exists2="true" || local exists2="false"

    assert_equals "true" "${exists1}" "Should find existing key"
    assert_equals "false" "${exists2}" "Should not find missing key"
}
test_case "Check config key exists" test_config_exists

# Test 10: Invalid JSON handling
test_config_invalid_json() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/invalid-config.json"
    create_invalid_json "${config_file}"

    config_load "${config_file}" 2>/dev/null && local result="success" || local result="failure"

    assert_equals "failure" "${result}" "Should fail on invalid JSON"
}
test_case "Handle invalid JSON" test_config_invalid_json

# Test 11: Missing file handling
test_config_missing_file() {
    source_config_loader || return 1
    config_init

    config_load "/nonexistent/path/config.json" 2>/dev/null && local result="success" || local result="failure"

    assert_equals "failure" "${result}" "Should fail on missing file"
}
test_case "Handle missing config file" test_config_missing_file

# Test 12: Save config to file
test_config_save() {
    source_config_loader || return 1
    config_init

    config_set "test_key" "test_value"
    config_set "another_key" "another_value"

    local save_file="${TEST_DATA_DIR}/saved-config.json"
    config_save "${save_file}"

    assert_file_exists "${save_file}" "Config file should be created"
}
test_case "Save config to file" test_config_save

# Test 13: Reload saved config
test_config_reload() {
    source_config_loader || return 1
    config_init

    config_set "persistent_key" "persistent_value"
    local save_file="${TEST_DATA_DIR}/reload-config.json"
    config_save "${save_file}"

    # Clear and reload
    config_clear
    config_load "${save_file}"

    local value
    value=$(config_get "persistent_key")

    assert_equals "persistent_value" "${value}" "Should reload saved config"
}
test_case "Reload saved config" test_config_reload

# Test 14: Merge configs
test_config_merge() {
    source_config_loader || return 1
    config_init

    # Load base config
    local base_config="${TEST_DATA_DIR}/base-config.json"
    echo '{"base_key": "base_value", "shared_key": "base_shared"}' > "${base_config}"
    config_load "${base_config}"

    # Load override config
    local override_config="${TEST_DATA_DIR}/override-config.json"
    echo '{"override_key": "override_value", "shared_key": "override_shared"}' > "${override_config}"
    config_merge "${override_config}"

    local base_val
    base_val=$(config_get "base_key")
    local override_val
    override_val=$(config_get "override_key")
    local shared_val
    shared_val=$(config_get "shared_key")

    assert_equals "base_value" "${base_val}" "Base key should exist"
    assert_equals "override_value" "${override_val}" "Override key should exist"
    assert_equals "override_shared" "${shared_val}" "Shared key should be overridden"
}
test_case "Merge config files" test_config_merge

# Test 15: Get all config keys
test_config_keys() {
    source_config_loader || return 1
    config_init

    config_set "key1" "value1"
    config_set "key2" "value2"
    config_set "key3" "value3"

    local keys
    keys=$(config_keys)

    assert_contains "${keys}" "key1" "Should list key1"
    assert_contains "${keys}" "key2" "Should list key2"
    assert_contains "${keys}" "key3" "Should list key3"
}
test_case "Get all config keys" test_config_keys

# Test 16: Validate config schema
test_config_validate() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    config_validate && local valid="true" || local valid="false"

    assert_equals "true" "${valid}" "Valid config should pass validation"
}
test_case "Validate config schema" test_config_validate

# Test 17: Type conversion
test_config_get_bool() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    local enabled
    enabled=$(config_get_bool "enforcement.enabled")

    assert_equals "true" "${enabled}" "Should get boolean value"
}
test_case "Get boolean config value" test_config_get_bool

# Test 18: Get integer
test_config_get_int() {
    source_config_loader || return 1
    config_init

    local config_file="${TEST_DATA_DIR}/test-config.json"
    create_test_config "${config_file}"
    config_load "${config_file}"

    local threshold
    threshold=$(config_get_int "scoring.threshold_warn")

    assert_equals "50" "${threshold}" "Should get integer value"
}
test_case "Get integer config value" test_config_get_int

# Run all tests
test_summary
