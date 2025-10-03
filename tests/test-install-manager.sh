#!/bin/bash
# test-install-manager.sh - TDD test suite for installation manager
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh" 2>/dev/null || {
    # Minimal test framework if not available
    assert_success() { [[ $1 -eq 0 ]] || { echo "✗ FAIL: $2"; return 1; }; echo "✓ PASS: $2"; }
    assert_failure() { [[ $1 -ne 0 ]] || { echo "✗ FAIL: $2"; return 1; }; echo "✓ PASS: $2"; }
    assert_equals() { [[ "$1" == "$2" ]] || { echo "✗ FAIL: $3 (expected: $1, got: $2)"; return 1; }; echo "✓ PASS: $3"; }
    assert_contains() { [[ "$1" == *"$2"* ]] || { echo "✗ FAIL: $3"; return 1; }; echo "✓ PASS: $3"; }
    assert_file_exists() { [[ -f "$1" ]] || { echo "✗ FAIL: File not found: $1"; return 1; }; echo "✓ PASS: File exists: $1"; }
    assert_dir_exists() { [[ -d "$1" ]] || { echo "✗ FAIL: Directory not found: $1"; return 1; }; echo "✓ PASS: Directory exists: $1"; }
}

# Test source location
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_MANAGER="${SOURCE_DIR}/scripts/install-manager.sh"

# Test directories (use temp for isolation)
TEST_ROOT="/tmp/wow-install-test-$$"
TEST_INSTALL_DIR="${TEST_ROOT}/install"
TEST_CONFIG_DIR="${TEST_ROOT}/config"
TEST_DATA_DIR="${TEST_ROOT}/data"
TEST_BACKUP_DIR="${TEST_ROOT}/backup"

# Setup test environment
setup_test_env() {
    rm -rf "${TEST_ROOT}"
    mkdir -p "${TEST_INSTALL_DIR}"
    mkdir -p "${TEST_CONFIG_DIR}"
    mkdir -p "${TEST_DATA_DIR}"
    mkdir -p "${TEST_BACKUP_DIR}"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "${TEST_ROOT}"
}

# Trap cleanup on exit
trap cleanup_test_env EXIT

echo "======================================================"
echo "WoW Installation Manager Test Suite (TDD)"
echo "======================================================"
echo ""

# ============================================================================
# TEST GROUP 1: Pre-Installation Checks (24 tests)
# ============================================================================

echo "[TEST GROUP 1] Pre-Installation Checks"
echo "--------------------------------------"

# Test 1: Check bash version validation
test_check_bash_version() {
    setup_test_env

    # Should pass with bash 4.0+
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        source "${INSTALL_MANAGER}" 2>/dev/null || true
        if type check_bash_version &>/dev/null; then
            check_bash_version
            assert_success $? "Bash version check should pass"
        else
            echo "⊘ SKIP: check_bash_version not implemented yet"
        fi
    fi
}

# Test 2: Check jq availability
test_check_jq_available() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type check_jq_available &>/dev/null; then
        if command -v jq &>/dev/null; then
            check_jq_available
            assert_success $? "jq availability check should pass"
        fi
    else
        echo "⊘ SKIP: check_jq_available not implemented yet"
    fi
}

# Test 3: Check disk space
test_check_disk_space() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type check_disk_space &>/dev/null; then
        check_disk_space "${TEST_INSTALL_DIR}" 10  # 10MB minimum
        assert_success $? "Disk space check should pass"
    else
        echo "⊘ SKIP: check_disk_space not implemented yet"
    fi
}

# Test 4: Validate source directory exists
test_validate_source_dir() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type validate_source_dir &>/dev/null; then
        validate_source_dir "${SOURCE_DIR}"
        assert_success $? "Source directory validation should pass"
    else
        echo "⊘ SKIP: validate_source_dir not implemented yet"
    fi
}

# Test 5: Validate source directory has required files
test_validate_source_structure() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type validate_source_structure &>/dev/null; then
        validate_source_structure "${SOURCE_DIR}"
        assert_success $? "Source structure validation should pass"
    else
        echo "⊘ SKIP: validate_source_structure not implemented yet"
    fi
}

# Test 6: Check dependencies (bash + jq)
test_check_dependencies() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type check_dependencies &>/dev/null; then
        check_dependencies
        assert_success $? "Dependency check should pass"
    else
        echo "⊘ SKIP: check_dependencies not implemented yet"
    fi
}

# ============================================================================
# TEST GROUP 2: Backup Operations (24 tests)
# ============================================================================

echo ""
echo "[TEST GROUP 2] Backup Operations"
echo "--------------------------------"

# Test 7: Create backup directory
test_create_backup_dir() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type create_backup_dir &>/dev/null; then
        local backup_dir
        backup_dir=$(create_backup_dir "${TEST_BACKUP_DIR}")
        assert_dir_exists "${backup_dir}" "Backup directory should be created"
    else
        echo "⊘ SKIP: create_backup_dir not implemented yet"
    fi
}

# Test 8: Backup existing installation
test_backup_installation() {
    setup_test_env

    # Create fake existing installation
    mkdir -p "${TEST_INSTALL_DIR}/lib"
    echo "test" > "${TEST_INSTALL_DIR}/lib/test.sh"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type backup_installation &>/dev/null; then
        backup_installation "${TEST_INSTALL_DIR}" "${TEST_BACKUP_DIR}/install"
        assert_file_exists "${TEST_BACKUP_DIR}/install/lib/test.sh" "Installation backup should contain files"
    else
        echo "⊘ SKIP: backup_installation not implemented yet"
    fi
}

# Test 9: Backup configuration
test_backup_configuration() {
    setup_test_env

    # Create fake config
    mkdir -p "${TEST_CONFIG_DIR}"
    echo '{"test": true}' > "${TEST_CONFIG_DIR}/wow-config.json"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type backup_configuration &>/dev/null; then
        backup_configuration "${TEST_CONFIG_DIR}" "${TEST_BACKUP_DIR}/config"
        assert_file_exists "${TEST_BACKUP_DIR}/config/wow-config.json" "Config backup should contain files"
    else
        echo "⊘ SKIP: backup_configuration not implemented yet"
    fi
}

# Test 10: Create rollback manifest
test_create_rollback_manifest() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type create_rollback_manifest &>/dev/null; then
        create_rollback_manifest "${TEST_BACKUP_DIR}/rollback-manifest.json" "4.3.0" "${TEST_BACKUP_DIR}"
        assert_file_exists "${TEST_BACKUP_DIR}/rollback-manifest.json" "Rollback manifest should be created"
    else
        echo "⊘ SKIP: create_rollback_manifest not implemented yet"
    fi
}

# ============================================================================
# TEST GROUP 3: Installation Operations (24 tests)
# ============================================================================

echo ""
echo "[TEST GROUP 3] Installation Operations"
echo "--------------------------------------"

# Test 11: Create XDG directories
test_create_xdg_directories() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type create_xdg_directories &>/dev/null; then
        create_xdg_directories "${TEST_INSTALL_DIR}" "${TEST_CONFIG_DIR}" "${TEST_DATA_DIR}"
        assert_dir_exists "${TEST_INSTALL_DIR}" "Install directory should exist"
        assert_dir_exists "${TEST_CONFIG_DIR}" "Config directory should exist"
        assert_dir_exists "${TEST_DATA_DIR}" "Data directory should exist"
    else
        echo "⊘ SKIP: create_xdg_directories not implemented yet"
    fi
}

# Test 12: Copy source to staging
test_copy_source_to_staging() {
    setup_test_env

    local staging_dir="${TEST_ROOT}/staging"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type copy_source_to_staging &>/dev/null; then
        copy_source_to_staging "${SOURCE_DIR}" "${staging_dir}"
        assert_dir_exists "${staging_dir}/src" "Staging should contain src/"
        assert_dir_exists "${staging_dir}/tests" "Staging should contain tests/"
    else
        echo "⊘ SKIP: copy_source_to_staging not implemented yet"
    fi
}

# Test 13: Validate staged files
test_validate_staged_files() {
    setup_test_env

    local staging_dir="${TEST_ROOT}/staging"
    mkdir -p "${staging_dir}/src/core"
    cp "${SOURCE_DIR}/src/core/orchestrator.sh" "${staging_dir}/src/core/" 2>/dev/null || true

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type validate_staged_files &>/dev/null; then
        validate_staged_files "${staging_dir}"
        assert_success $? "Staged files validation should pass"
    else
        echo "⊘ SKIP: validate_staged_files not implemented yet"
    fi
}

# Test 14: Atomic move to production
test_atomic_move_to_production() {
    setup_test_env

    local staging_dir="${TEST_ROOT}/staging"
    mkdir -p "${staging_dir}/lib"
    echo "test" > "${staging_dir}/lib/test.sh"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type atomic_move_to_production &>/dev/null; then
        atomic_move_to_production "${staging_dir}" "${TEST_INSTALL_DIR}"
        assert_file_exists "${TEST_INSTALL_DIR}/lib/test.sh" "File should be moved to production"
        [[ ! -d "${staging_dir}" ]] && echo "✓ PASS: Staging directory cleaned up"
    else
        echo "⊘ SKIP: atomic_move_to_production not implemented yet"
    fi
}

# Test 15: Set file permissions
test_set_file_permissions() {
    setup_test_env

    mkdir -p "${TEST_INSTALL_DIR}/bin"
    mkdir -p "${TEST_INSTALL_DIR}/lib"
    touch "${TEST_INSTALL_DIR}/bin/wow-cli"
    touch "${TEST_INSTALL_DIR}/lib/test.sh"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type set_file_permissions &>/dev/null; then
        set_file_permissions "${TEST_INSTALL_DIR}"

        # Check bin is executable
        [[ -x "${TEST_INSTALL_DIR}/bin/wow-cli" ]] && echo "✓ PASS: Bin files are executable"

        # Check lib is readable
        [[ -r "${TEST_INSTALL_DIR}/lib/test.sh" ]] && echo "✓ PASS: Lib files are readable"
    else
        echo "⊘ SKIP: set_file_permissions not implemented yet"
    fi
}

# ============================================================================
# TEST GROUP 4: Configuration (24 tests)
# ============================================================================

echo ""
echo "[TEST GROUP 4] Configuration"
echo "---------------------------"

# Test 16: Copy default configuration
test_copy_default_configuration() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type copy_default_configuration &>/dev/null; then
        copy_default_configuration "${SOURCE_DIR}/config" "${TEST_CONFIG_DIR}"
        assert_file_exists "${TEST_CONFIG_DIR}/wow-config.json" "Default config should be copied"
    else
        echo "⊘ SKIP: copy_default_configuration not implemented yet"
    fi
}

# Test 17: Preserve existing configuration
test_preserve_existing_configuration() {
    setup_test_env

    # Create existing config
    mkdir -p "${TEST_CONFIG_DIR}"
    echo '{"custom": "value"}' > "${TEST_CONFIG_DIR}/wow-config.json"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type copy_default_configuration &>/dev/null; then
        copy_default_configuration "${SOURCE_DIR}/config" "${TEST_CONFIG_DIR}"

        # Should NOT overwrite
        content=$(cat "${TEST_CONFIG_DIR}/wow-config.json")
        assert_contains "$content" "custom" "Existing config should be preserved"
    else
        echo "⊘ SKIP: copy_default_configuration not implemented yet"
    fi
}

# Test 18: Migrate configuration
test_migrate_configuration() {
    setup_test_env

    # Create old config
    mkdir -p "${TEST_CONFIG_DIR}"
    echo '{"version": "4.3.0"}' > "${TEST_CONFIG_DIR}/wow-config.json"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type migrate_configuration &>/dev/null; then
        migrate_configuration "${TEST_CONFIG_DIR}/wow-config.json" "4.3.0" "5.0.0"

        # Should update version
        content=$(cat "${TEST_CONFIG_DIR}/wow-config.json")
        assert_contains "$content" "5.0.0" "Config should be migrated to new version"
    else
        echo "⊘ SKIP: migrate_configuration not implemented yet"
    fi
}

# Test 19: Validate configuration
test_validate_configuration() {
    setup_test_env

    # Create valid config
    mkdir -p "${TEST_CONFIG_DIR}"
    cp "${SOURCE_DIR}/config/wow-config.json" "${TEST_CONFIG_DIR}/" 2>/dev/null || {
        echo '{"version": "5.0.0"}' > "${TEST_CONFIG_DIR}/wow-config.json"
    }

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type validate_configuration &>/dev/null; then
        validate_configuration "${TEST_CONFIG_DIR}/wow-config.json"
        assert_success $? "Configuration validation should pass"
    else
        echo "⊘ SKIP: validate_configuration not implemented yet"
    fi
}

# ============================================================================
# TEST GROUP 5: Hook Integration (24 tests)
# ============================================================================

echo ""
echo "[TEST GROUP 5] Hook Integration"
echo "-------------------------------"

# Test 20: Detect Claude Code settings location
test_detect_claude_settings() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type detect_claude_settings &>/dev/null; then
        local settings_path
        settings_path=$(detect_claude_settings)

        if [[ -n "$settings_path" ]]; then
            echo "✓ PASS: Detected Claude settings at: $settings_path"
        else
            echo "⊘ SKIP: No Claude Code settings found (expected in test env)"
        fi
    else
        echo "⊘ SKIP: detect_claude_settings not implemented yet"
    fi
}

# Test 21: Generate hooks
test_generate_hooks() {
    setup_test_env

    local claude_dir="${TEST_ROOT}/.claude"
    mkdir -p "${claude_dir}/hooks"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type generate_hooks &>/dev/null; then
        generate_hooks "${TEST_INSTALL_DIR}" "${claude_dir}/hooks"
        assert_file_exists "${claude_dir}/hooks/user-prompt-submit.sh" "Hook should be generated"
    else
        echo "⊘ SKIP: generate_hooks not implemented yet"
    fi
}

# Test 22: Register hooks in settings.json
test_register_hooks() {
    setup_test_env

    local claude_dir="${TEST_ROOT}/.claude"
    mkdir -p "${claude_dir}"
    echo '{}' > "${claude_dir}/settings.json"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type register_hooks &>/dev/null; then
        register_hooks "${claude_dir}/settings.json" "${claude_dir}/hooks/user-prompt-submit.sh"

        content=$(cat "${claude_dir}/settings.json")
        assert_contains "$content" "UserPromptSubmit" "Settings should contain hook registration"
    else
        echo "⊘ SKIP: register_hooks not implemented yet"
    fi
}

# Test 23: Verify hook registration
test_verify_hook_registration() {
    setup_test_env

    local claude_dir="${TEST_ROOT}/.claude"
    mkdir -p "${claude_dir}/hooks"
    touch "${claude_dir}/hooks/user-prompt-submit.sh"
    echo '{"hooks": {"UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "command", "command": "test"}]}]}}' > "${claude_dir}/settings.json"

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type verify_hook_registration &>/dev/null; then
        verify_hook_registration "${claude_dir}/settings.json"
        assert_success $? "Hook registration verification should pass"
    else
        echo "⊘ SKIP: verify_hook_registration not implemented yet"
    fi
}

# ============================================================================
# TEST GROUP 6: Post-Installation (24 tests)
# ============================================================================

echo ""
echo "[TEST GROUP 6] Post-Installation"
echo "--------------------------------"

# Test 24: Create installation manifest
test_create_installation_manifest() {
    setup_test_env

    source "${INSTALL_MANAGER}" 2>/dev/null || true
    if type create_installation_manifest &>/dev/null; then
        create_installation_manifest "${TEST_INSTALL_DIR}/.manifest.json" "5.0.0" "${SOURCE_DIR}"
        assert_file_exists "${TEST_INSTALL_DIR}/.manifest.json" "Manifest should be created"

        content=$(cat "${TEST_INSTALL_DIR}/.manifest.json")
        assert_contains "$content" "5.0.0" "Manifest should contain version"
    else
        echo "⊘ SKIP: create_installation_manifest not implemented yet"
    fi
}

# Run all tests
echo ""
echo "======================================================"
echo "Running All Tests"
echo "======================================================"
echo ""

test_check_bash_version
test_check_jq_available
test_check_disk_space
test_validate_source_dir
test_validate_source_structure
test_check_dependencies

test_create_backup_dir
test_backup_installation
test_backup_configuration
test_create_rollback_manifest

test_create_xdg_directories
test_copy_source_to_staging
test_validate_staged_files
test_atomic_move_to_production
test_set_file_permissions

test_copy_default_configuration
test_preserve_existing_configuration
test_migrate_configuration
test_validate_configuration

test_detect_claude_settings
test_generate_hooks
test_register_hooks
test_verify_hook_registration

test_create_installation_manifest

echo ""
echo "======================================================"
echo "Test Suite Complete"
echo "======================================================"
echo ""
echo "Note: Some tests skipped (functions not implemented yet)"
echo "This is expected in TDD - tests drive implementation"
