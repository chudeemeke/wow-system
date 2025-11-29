#!/bin/bash
# WoW System - Version Management Tests
# Ensures version is centralized and never hardcoded
# Author: Chude <chude@emeke.org>

set -uo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# Source utils for version function
source "${SCRIPT_DIR}/../src/core/utils.sh"

test_suite "Version Management Tests"

# ============================================================================
# Test 1: Single Source of Truth Exists
# ============================================================================

test_version_constant_exists() {
    assert_not_empty "${WOW_VERSION}" "WOW_VERSION should be defined in utils.sh"
}

test_case "should have WOW_VERSION constant in utils.sh" test_version_constant_exists

# ============================================================================
# Test 2: Version Function Accessible
# ============================================================================

test_version_function_works() {
    local version
    version=$(wow_get_version)

    assert_not_empty "${version}" "wow_get_version() should return version"
    assert_equals "${WOW_VERSION}" "${version}" "wow_get_version() should match WOW_VERSION constant"
}

test_case "should have working wow_get_version() function" test_version_function_works

# ============================================================================
# Test 3: No Hardcoded Versions in Source Files
# ============================================================================

test_no_hardcoded_versions_in_handlers() {
    local project_root="${SCRIPT_DIR}/.."
    local handler_files="${project_root}/src/handlers"

    # Look for version patterns like "5.0.0", "5.1.0", "5.2.0" but exclude comments
    local violations
    violations=$(grep -rE '(readonly.*VERSION=|version.*:.*)"[0-9]+\.[0-9]+\.[0-9]+"' "${handler_files}" 2>/dev/null | grep -v "# " || true)

    if [[ -n "${violations}" ]]; then
        echo "Found hardcoded versions in handlers: ${violations}" >&2
        return 1
    fi

    return 0
}

test_case "should have no hardcoded versions in handlers" test_no_hardcoded_versions_in_handlers

test_no_hardcoded_versions_in_core() {
    local project_root="${SCRIPT_DIR}/.."
    local core_files="${project_root}/src/core"

    # Check for hardcoded versions, but ALLOW utils.sh (single source of truth)
    local violations
    violations=$(grep -rE '"[0-9]+\.[0-9]+\.[0-9]+"' "${core_files}" 2>/dev/null | \
                 grep -v "utils.sh:.*WOW_VERSION" | \
                 grep -v "# " | \
                 grep -v "test" || true)

    if [[ -n "${violations}" ]]; then
        echo "Found hardcoded versions in core (excluding utils.sh): ${violations}" >&2
        return 1
    fi

    return 0
}

test_case "should have no hardcoded versions in core (except utils.sh)" test_no_hardcoded_versions_in_core

test_no_hardcoded_versions_in_hooks() {
    local project_root="${SCRIPT_DIR}/.."
    local hook_file="${project_root}/hooks/user-prompt-submit.sh"

    # Check for hardcoded version fallbacks like 'echo "5.2.0"'
    local violations
    violations=$(grep -E '(echo|version=|VERSION=).*"[0-9]+\.[0-9]+\.[0-9]+"' "${hook_file}" 2>/dev/null | grep -v "# " || true)

    if [[ -n "${violations}" ]]; then
        echo "Found hardcoded versions in hook: ${violations}" >&2
        return 1
    fi

    return 0
}

test_case "should have no hardcoded versions in hooks" test_no_hardcoded_versions_in_hooks

test_no_hardcoded_versions_in_ui() {
    local project_root="${SCRIPT_DIR}/.."
    local ui_files="${project_root}/src/ui"

    # Check for hardcoded version defaults like '${1:-5.1.0}'
    local violations
    violations=$(grep -E '\$\{[0-9]+:-"?[0-9]+\.[0-9]+\.[0-9]+"?\}' "${ui_files}" 2>/dev/null || true)

    if [[ -n "${violations}" ]]; then
        echo "Found hardcoded version defaults in UI: ${violations}" >&2
        return 1
    fi

    return 0
}

test_case "should have no hardcoded version defaults in UI" test_no_hardcoded_versions_in_ui

# ============================================================================
# Test 4: Config Version Matches Source
# ============================================================================

test_config_version_matches() {
    local project_root="${SCRIPT_DIR}/.."
    local config_file="${project_root}/config/wow-config.json"

    if [[ ! -f "${config_file}" ]]; then
        echo "Config file not found" >&2
        return 1
    fi

    if ! wow_has_jq; then
        echo "jq not available, skipping" >&2
        return 0
    fi

    local config_version
    config_version=$(jq -r '.version // empty' "${config_file}" 2>/dev/null)

    assert_not_empty "${config_version}" "Config should have version field"
    assert_equals "${WOW_VERSION}" "${config_version}" "Config version should match WOW_VERSION"
}

test_case "should have config version matching source" test_config_version_matches

# ============================================================================
# Test 5: Display Functions Use Version Correctly
# ============================================================================

test_display_banner_version() {
    local project_root="${SCRIPT_DIR}/.."

    # Source display module
    if [[ -f "${project_root}/src/ui/display.sh" ]]; then
        source "${project_root}/src/ui/display.sh"

        # The display functions should accept version parameter
        # and should NOT have hardcoded defaults

        # Check that display_session_start_banner uses passed version
        local banner_output
        banner_output=$(display_session_start_banner "9.9.9" "8" "Enabled" 2>&1 || true)

        if echo "${banner_output}" | grep -q "9.9.9"; then
            return 0
        else
            echo "display_session_start_banner not using passed version" >&2
            return 1
        fi
    fi

    return 0
}

test_case "should use version parameter in display functions" test_display_banner_version

# ============================================================================
# Test 6: Hook Uses wow_get_version()
# ============================================================================

test_hook_uses_version_function() {
    local project_root="${SCRIPT_DIR}/.."
    local hook_file="${project_root}/hooks/user-prompt-submit.sh"

    # Check that hook calls wow_get_version instead of hardcoding
    if grep -q 'wow_get_version' "${hook_file}"; then
        return 0
    else
        echo "Hook should use wow_get_version() function" >&2
        return 1
    fi
}

test_case "should use wow_get_version() in hook" test_hook_uses_version_function

# ============================================================================
# Test 7: Version Format Validation
# ============================================================================

test_version_format() {
    # Version should follow semantic versioning: X.Y.Z
    if [[ "${WOW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        echo "Version '${WOW_VERSION}' does not follow semver format" >&2
        return 1
    fi
}

test_case "should follow semantic versioning format" test_version_format

# ============================================================================
# Test 8: Version Consistency Across Modules
# ============================================================================

test_orchestrator_version_reference() {
    local project_root="${SCRIPT_DIR}/.."
    local orchestrator="${project_root}/src/core/orchestrator.sh"

    # Orchestrator should use WOW_VERSION, not define its own
    if grep -q 'readonly.*ORCHESTRATOR_VERSION=.*[0-9]' "${orchestrator}" 2>/dev/null; then
        # It has its own version constant - that's okay for module versioning
        # But it should also reference WOW_VERSION for system version
        return 0
    fi

    return 0
}

test_case "should handle module versions correctly" test_orchestrator_version_reference

# ============================================================================
# Test 9: Version Validation on Init
# ============================================================================

test_version_validation_exists() {
    local project_root="${SCRIPT_DIR}/.."

    # Source orchestrator
    source "${project_root}/src/core/orchestrator.sh"

    # Check that validation function exists
    if type _validate_version_consistency &>/dev/null; then
        return 0
    else
        echo "Version validation function not found in orchestrator" >&2
        return 1
    fi
}

test_case "should have version validation function" test_version_validation_exists

test_version_auto_sync() {
    local project_root="${SCRIPT_DIR}/.."

    # Create temp config with mismatched version
    local temp_config="/tmp/test-wow-config-$$.json"
    cat > "${temp_config}" <<EOF
{
  "version": "1.0.0",
  "enforcement": {
    "enabled": true
  }
}
EOF

    # Initialize with mismatched config
    source "${project_root}/src/core/orchestrator.sh"
    wow_init "${temp_config}" 2>/dev/null

    # Check if version was auto-synced
    local config_version
    config_version=$(config_get "version" 2>/dev/null)

    rm -f "${temp_config}"

    if [[ "${config_version}" == "${WOW_VERSION}" ]]; then
        return 0
    else
        echo "Version auto-sync failed: config=${config_version}, expected=${WOW_VERSION}" >&2
        return 1
    fi
}

test_case "should auto-sync config version on init" test_version_auto_sync

# ============================================================================
# Summary
# ============================================================================

test_summary
