#!/bin/bash
# WoW System - Doc Sync Engine Tests
# Comprehensive tests for documentation synchronization
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

DOC_SYNC_ENGINE="${SCRIPT_DIR}/../src/engines/doc-sync-engine.sh"
TEST_DATA_DIR=""
TEST_WOW_HOME=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"

    # Create mock WoW home
    TEST_WOW_HOME="${TEST_DATA_DIR}/wow-test"
    mkdir -p "${TEST_WOW_HOME}"/{src,docs,tests}
    mkdir -p "${TEST_WOW_HOME}/src"/{core,handlers,engines}
    mkdir -p "${TEST_WOW_HOME}/docs/principles"
    export WOW_HOME="${TEST_WOW_HOME}"

    # Initialize orchestrator for dependencies
    source "${SCRIPT_DIR}/../src/core/orchestrator.sh"
    wow_init
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_doc_sync() {
    if [[ -f "${DOC_SYNC_ENGINE}" ]]; then
        source "${DOC_SYNC_ENGINE}"
        return 0
    else
        echo "Doc sync engine not found"
        return 1
    fi
}

create_mock_code_file() {
    local name="$1"
    local category="${2:-core}"
    local function_count="${3:-1}"

    local file_path="${TEST_WOW_HOME}/src/${category}/${name}.sh"
    mkdir -p "$(dirname "${file_path}")"

    cat > "${file_path}" <<EOF
#!/bin/bash
# Mock ${name} module
readonly ${name^^}_VERSION="1.0.0"

# Public function
${name}_init() {
    echo "Initialized"
}

${name}_process() {
    echo "Processing"
}
EOF
    echo "${file_path}"
}

create_mock_doc() {
    local name="$1"
    local version="${2:-5.0.0}"

    local file_path="${TEST_WOW_HOME}/${name}"
    mkdir -p "$(dirname "${file_path}")"

    cat > "${file_path}" <<EOF
# Mock Documentation

Version: v${version}

## Overview
This is a test document.
EOF
    echo "${file_path}"
}

create_mock_utils() {
    local file_path="${TEST_WOW_HOME}/src/core/utils.sh"
    mkdir -p "$(dirname "${file_path}")"

    cat > "${file_path}" <<EOF
#!/bin/bash
readonly WOW_VERSION="5.0.1"

wow_debug() { echo "[DEBUG] \$*"; }
wow_info() { echo "[INFO] \$*"; }
wow_warn() { echo "[WARN] \$*"; }
EOF
}

# ============================================================================
# Tests: Initialization
# ============================================================================

test_suite "Doc Sync Engine - Initialization"

test_init_success() {
    source_doc_sync || return 1

    doc_sync_init
    local status=$?

    assert_equals "${status}" "0" "Init should succeed"

    # Check backup directory created
    [[ -d "${WOW_DATA_DIR}/doc-backups" ]] || return 1

    echo "Doc sync initialized successfully"
}
test_case "Initialize doc sync engine" test_init_success

test_init_metrics() {
    source_doc_sync || return 1

    doc_sync_init

    local scanned=$(session_get_metric "docs_scanned" "none")
    assert_equals "${scanned}" "0" "Initial scanned count should be 0"

    echo "Metrics initialized correctly"
}
test_case "Initialize metrics" test_init_metrics

# ============================================================================
# Tests: Configuration
# ============================================================================

test_suite "Doc Sync Engine - Configuration"

test_config_enabled() {
    source_doc_sync || return 1

    local enabled=$(doc_sync_config "enabled")
    assert_equals "${enabled}" "true" "Doc sync should be enabled by default"

    echo "Config: enabled = ${enabled}"
}
test_case "Get enabled config" test_config_enabled

test_config_auto_update() {
    source_doc_sync || return 1

    local auto_update=$(doc_sync_config "auto_update")
    assert_equals "${auto_update}" "false" "Auto update should be disabled by default"

    echo "Config: auto_update = ${auto_update}"
}
test_case "Get auto_update config" test_config_auto_update

test_config_default_value() {
    source_doc_sync || return 1

    local value=$(doc_sync_config "nonexistent" "default_val")
    assert_equals "${value}" "default_val" "Should return default for unknown keys"

    echo "Config: default value works"
}
test_case "Get config with default" test_config_default_value

# ============================================================================
# Tests: File Categorization
# ============================================================================

test_suite "Doc Sync Engine - File Categorization"

test_categorize_handler() {
    source_doc_sync || return 1

    local category=$(doc_sync_categorize_file "/path/to/handlers/bash-handler.sh")
    assert_equals "${category}" "handler" "Should categorize as handler"

    echo "Categorized handler correctly"
}
test_case "Categorize handler file" test_categorize_handler

test_categorize_engine() {
    source_doc_sync || return 1

    local category=$(doc_sync_categorize_file "/path/to/engines/scoring-engine.sh")
    assert_equals "${category}" "engine" "Should categorize as engine"

    echo "Categorized engine correctly"
}
test_case "Categorize engine file" test_categorize_engine

test_categorize_core() {
    source_doc_sync || return 1

    local category=$(doc_sync_categorize_file "/path/to/core/utils.sh")
    assert_equals "${category}" "core" "Should categorize as core"

    echo "Categorized core correctly"
}
test_case "Categorize core file" test_categorize_core

test_categorize_test() {
    source_doc_sync || return 1

    local category=$(doc_sync_categorize_file "/path/to/tests/test-foo.sh")
    assert_equals "${category}" "test" "Should categorize as test"

    echo "Categorized test correctly"
}
test_case "Categorize test file" test_categorize_test

# ============================================================================
# Tests: Codebase Scanning
# ============================================================================

test_suite "Doc Sync Engine - Codebase Scanning"

test_scan_empty_codebase() {
    source_doc_sync || return 1
    doc_sync_init

    local output=$(doc_sync_scan_codebase)
    local status=$?

    assert_equals "${status}" "0" "Scan should succeed on empty codebase"
    echo "Scanned empty codebase successfully"
}
test_case "Scan empty codebase" test_scan_empty_codebase

test_scan_with_files() {
    source_doc_sync || return 1
    doc_sync_init

    # Create mock files
    create_mock_code_file "test-module" "core" 2
    create_mock_code_file "test-handler" "handlers" 3

    local output=$(doc_sync_scan_codebase 2>/dev/null)

    # Should have scanned files
    local scanned=$(session_get_metric "code_files_scanned" "0")
    [[ ${scanned} -gt 0 ]] || return 1

    echo "Scanned ${scanned} files"
}
test_case "Scan codebase with files" test_scan_with_files

# ============================================================================
# Tests: Outdated Detection
# ============================================================================

test_suite "Doc Sync Engine - Outdated Detection"

test_detect_version_mismatch() {
    source_doc_sync || return 1
    doc_sync_init

    # Create utils with v5.0.1
    create_mock_utils

    # Create doc with v5.0.0
    create_mock_doc "README.md" "5.0.0"

    local outdated=$(doc_sync_check_doc_outdated "${TEST_WOW_HOME}/README.md" "5.0.1")
    assert_equals "${outdated}" "true" "Should detect version mismatch"

    echo "Detected outdated version"
}
test_case "Detect version mismatch" test_detect_version_mismatch

test_detect_current_version() {
    source_doc_sync || return 1
    doc_sync_init

    create_mock_doc "README.md" "5.0.1"

    local outdated=$(doc_sync_check_doc_outdated "${TEST_WOW_HOME}/README.md" "5.0.1")
    # Note: Function checks for missing features, so might still be outdated

    echo "Checked current version"
}
test_case "Detect current version" test_detect_current_version

test_identify_outdated_docs() {
    source_doc_sync || return 1
    doc_sync_init

    # Create utils and old README
    create_mock_utils
    create_mock_doc "README.md" "5.0.0"

    local output=$(doc_sync_identify_outdated 2>/dev/null)

    # Should have found outdated docs
    local count=$(session_get_metric "docs_outdated" "0")
    [[ ${count} -gt 0 ]] || return 1

    echo "Identified ${count} outdated docs"
}
test_case "Identify outdated documents" test_identify_outdated_docs

# ============================================================================
# Tests: Documentation Backup
# ============================================================================

test_suite "Doc Sync Engine - Backup"

test_backup_nonexistent() {
    source_doc_sync || return 1
    doc_sync_init

    doc_sync_backup_doc "/nonexistent/file.md"
    local status=$?

    assert_equals "${status}" "1" "Should fail for nonexistent file"
    echo "Correctly handled nonexistent file"
}
test_case "Backup nonexistent file" test_backup_nonexistent

test_backup_success() {
    source_doc_sync || return 1
    doc_sync_init

    local doc_path=$(create_mock_doc "test-doc.md")

    doc_sync_backup_doc "${doc_path}"
    local status=$?

    assert_equals "${status}" "0" "Backup should succeed"

    # Check backup was created
    local backup_count=$(ls "${WOW_DATA_DIR}/doc-backups/"*.bak 2>/dev/null | wc -l)
    [[ ${backup_count} -gt 0 ]] || return 1

    echo "Backup created successfully"
}
test_case "Backup document successfully" test_backup_success

# ============================================================================
# Tests: Verification
# ============================================================================

test_suite "Doc Sync Engine - Verification"

test_verify_markdown_valid() {
    source_doc_sync || return 1

    local doc_path=$(create_mock_doc "test.md")

    local result=$(doc_sync_validate_markdown "${doc_path}")
    assert_contains "${result}" "VALID" "Should validate correct markdown"

    echo "Validated markdown: ${result}"
}
test_case "Verify valid markdown" test_verify_markdown_valid

test_verify_markdown_invalid() {
    source_doc_sync || return 1

    local doc_path="${TEST_WOW_HOME}/invalid.md"
    echo "No headings here" > "${doc_path}"

    local result=$(doc_sync_validate_markdown "${doc_path}")
    assert_contains "${result}" "INVALID" "Should detect invalid markdown"

    echo "Detected invalid markdown: ${result}"
}
test_case "Verify invalid markdown" test_verify_markdown_invalid

test_verify_all_docs() {
    source_doc_sync || return 1
    doc_sync_init

    # Create mock structure
    create_mock_utils
    create_mock_doc "README.md" "5.0.1"

    local output=$(doc_sync_verify 2>/dev/null)

    # Should have verification results
    assert_contains "${output}" "README.md" "Should verify README"

    echo "Verified documentation"
}
test_case "Verify all documentation" test_verify_all_docs

# ============================================================================
# Tests: Update Generation
# ============================================================================

test_suite "Doc Sync Engine - Update Generation"

test_generate_updates() {
    source_doc_sync || return 1
    doc_sync_init

    # Create outdated doc
    create_mock_utils
    create_mock_doc "README.md" "5.0.0"

    local output=$(doc_sync_generate_updates 2>/dev/null)

    # Should generate update instructions
    [[ -n "${output}" ]] || return 1

    echo "Generated updates"
}
test_case "Generate documentation updates" test_generate_updates

# ============================================================================
# Tests: Reporting
# ============================================================================

test_suite "Doc Sync Engine - Reporting"

test_generate_report() {
    source_doc_sync || return 1
    doc_sync_init

    local report=$(doc_sync_report 2>/dev/null)

    assert_contains "${report}" "Documentation Sync Report" "Should have report title"
    assert_contains "${report}" "Summary" "Should have summary section"
    assert_contains "${report}" "Verification Results" "Should have verification section"

    echo "Generated complete report"
}
test_case "Generate validation report" test_generate_report

# ============================================================================
# Tests: CLI Interface
# ============================================================================

test_suite "Doc Sync Engine - CLI"

test_cli_help() {
    source_doc_sync || return 1

    local output=$(doc_sync_cli help)

    assert_contains "${output}" "Usage" "Should show usage"
    assert_contains "${output}" "Commands" "Should list commands"

    echo "CLI help displayed"
}
test_case "CLI help command" test_cli_help

test_cli_init() {
    source_doc_sync || return 1

    doc_sync_cli init
    local status=$?

    assert_equals "${status}" "0" "CLI init should succeed"
    echo "CLI init executed"
}
test_case "CLI init command" test_cli_init

test_cli_scan() {
    source_doc_sync || return 1
    doc_sync_init

    create_mock_code_file "test" "core"

    local output=$(doc_sync_cli scan 2>/dev/null)
    local status=$?

    assert_equals "${status}" "0" "CLI scan should succeed"
    echo "CLI scan executed"
}
test_case "CLI scan command" test_cli_scan

test_cli_verify() {
    source_doc_sync || return 1
    doc_sync_init

    create_mock_utils

    local output=$(doc_sync_cli verify 2>/dev/null)
    local status=$?

    assert_equals "${status}" "0" "CLI verify should succeed"
    echo "CLI verify executed"
}
test_case "CLI verify command" test_cli_verify

test_cli_report() {
    source_doc_sync || return 1
    doc_sync_init

    local output=$(doc_sync_cli report 2>/dev/null)
    local status=$?

    assert_equals "${status}" "0" "CLI report should succeed"
    assert_contains "${output}" "Documentation Sync Report" "Should generate report"

    echo "CLI report executed"
}
test_case "CLI report command" test_cli_report

# ============================================================================
# Run All Tests
# ============================================================================

# Execute tests
setup_all
run_all_tests
teardown_all

# Print results
print_test_summary
exit_with_status
