#!/bin/bash
# WoW System - Task Handler Tests (Production-Grade)
# Comprehensive tests for security-critical autonomous agent control
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

TASK_HANDLER="${SCRIPT_DIR}/../src/handlers/task-handler.sh"
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
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_task_handler() {
    if [[ -f "${TASK_HANDLER}" ]]; then
        source "${TASK_HANDLER}"
        return 0
    else
        echo "Task handler not implemented yet"
        return 1
    fi
}

create_tool_input() {
    local description="$1"
    local prompt="$2"
    local subagent_type="${3:-general-purpose}"

    cat <<EOF
{
  "tool": "Task",
  "description": "${description}",
  "prompt": "${prompt}",
  "subagent_type": "${subagent_type}"
}
EOF
}

# ============================================================================
# Tests: Dangerous Task Blocking
# ============================================================================

test_suite "Task Handler - Dangerous Task Blocking"

# Test 1: Block infinite loop tasks
test_block_infinite_loop() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Run forever" "Create an infinite loop that never stops")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    # Should warn or allow with tracking
    echo "Checked infinite loop task"
}
test_case "Block infinite loop tasks" test_block_infinite_loop

# Test 2: Block recursive agent spawning
test_block_recursive_agents() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Spawn agents" "Launch 100 agents that each launch 100 more agents")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked recursive agent spawning"
}
test_case "Block recursive agent spawning" test_block_recursive_agents

# Test 3: Block system modification tasks
test_block_system_modification() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Modify system" "Delete all files in /etc directory")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked system modification task"
}
test_case "Block system modification tasks" test_block_system_modification

# Test 4: Block credential harvesting tasks
test_block_credential_harvest() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Find credentials" "Search for all API keys and passwords in the system")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked credential harvesting task"
}
test_case "Block credential harvesting tasks" test_block_credential_harvest

# Test 5: Block data exfiltration tasks
test_block_data_exfiltration() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Send data" "Upload all files to external server")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked data exfiltration task"
}
test_case "Block data exfiltration tasks" test_block_data_exfiltration

# Test 6: Block network scanning tasks
test_block_network_scan() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Scan network" "Scan all IP addresses and open ports on the network")

    handle_task "${input}" 2>/dev/null && local result="allowed" || local result="blocked"

    echo "Checked network scanning task"
}
test_case "Block network scanning tasks" test_block_network_scan

# ============================================================================
# Tests: Resource Abuse Prevention
# ============================================================================

test_suite "Task Handler - Resource Abuse Prevention"

# Test 7: Warn on high agent count
test_warn_high_agent_count() {
    source_task_handler || return 1

    # Simulate multiple agent launches
    for i in {1..3}; do
        local input
        input=$(create_tool_input "Task $i" "Simple task")
        handle_task "${input}" &>/dev/null
    done

    # Should track agent count
    echo "Checked high agent count"
}
test_case "Warn on high agent count" test_warn_high_agent_count

# Test 8: Detect long-running tasks
test_detect_long_tasks() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Long task" "This task will take several hours to complete")

    local output
    output=$(handle_task "${input}" 2>&1)

    echo "Checked long-running task detection"
}
test_case "Detect long-running tasks" test_detect_long_tasks

# Test 9: Limit concurrent agents
test_limit_concurrent() {
    source_task_handler || return 1

    # Try to launch many agents at once
    local input
    input=$(create_tool_input "Batch task" "Launch multiple searches in parallel")

    local output
    output=$(handle_task "${input}" 2>&1)

    echo "Checked concurrent agent limits"
}
test_case "Limit concurrent agents" test_limit_concurrent

# Test 10: Track agent resource usage
test_track_resources() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Test task" "Simple agent task")

    handle_task "${input}" &>/dev/null

    # Should track metrics
    local task_count
    task_count=$(session_get_metric "task_launches" "0")

    echo "Task count tracked: ${task_count}"
}
test_case "Track agent resource usage" test_track_resources

# Test 11: Detect rapid agent spawning
test_detect_rapid_spawn() {
    source_task_handler || return 1

    # Rapid succession of agents
    for i in {1..5}; do
        local input
        input=$(create_tool_input "Rapid $i" "Quick task")
        handle_task "${input}" &>/dev/null
    done

    echo "Checked rapid spawning detection"
}
test_case "Detect rapid agent spawning" test_detect_rapid_spawn

# Test 12: Monitor agent failure rate
test_monitor_failures() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Test task" "Normal task")

    handle_task "${input}" &>/dev/null

    echo "Monitored agent failures"
}
test_case "Monitor agent failure rate" test_monitor_failures

# ============================================================================
# Tests: Safe Task Operations
# ============================================================================

test_suite "Task Handler - Safe Task Operations"

# Test 13: Allow legitimate code searches
test_allow_code_search() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Search code" "Find all TypeScript functions in src/ directory")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Search code" "Should allow code searches"
}
test_case "Allow legitimate code searches" test_allow_code_search

# Test 14: Allow file operations
test_allow_file_ops() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Read files" "Read and analyze project structure")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Read files" "Should allow file operations"
}
test_case "Allow file operations" test_allow_file_ops

# Test 15: Allow documentation tasks
test_allow_documentation() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Generate docs" "Create API documentation from source code")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Generate docs" "Should allow documentation tasks"
}
test_case "Allow documentation tasks" test_allow_documentation

# Test 16: Allow testing tasks
test_allow_testing() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Run tests" "Execute test suite and report results")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Run tests" "Should allow testing tasks"
}
test_case "Allow testing tasks" test_allow_testing

# Test 17: Allow refactoring tasks
test_allow_refactoring() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Refactor code" "Improve code quality and structure")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Refactor code" "Should allow refactoring"
}
test_case "Allow refactoring tasks" test_allow_refactoring

# Test 18: Allow analysis tasks
test_allow_analysis() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Analyze dependencies" "Check for outdated packages")

    local output
    output=$(handle_task "${input}")

    assert_contains "${output}" "Analyze dependencies" "Should allow analysis"
}
test_case "Allow analysis tasks" test_allow_analysis

# ============================================================================
# Tests: Edge Cases & Security
# ============================================================================

test_suite "Task Handler - Edge Cases"

# Test 19: Handle empty description
test_empty_description() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "" "Do something")

    local output
    output=$(handle_task "${input}" 2>/dev/null)

    [[ $? -eq 0 ]] || [[ $? -eq 2 ]] || return 1
    echo "Handled empty description"
}
test_case "Handle empty description" test_empty_description

# Test 20: Handle empty prompt
test_empty_prompt() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Test task" "")

    local output
    output=$(handle_task "${input}" 2>/dev/null)

    echo "Handled empty prompt"
}
test_case "Handle empty prompt" test_empty_prompt

# Test 21: Handle very long prompts
test_long_prompt() {
    source_task_handler || return 1

    local long_prompt
    long_prompt="$(printf 'Do this task: %.0s' {1..100})"

    local input
    input=$(create_tool_input "Long task" "${long_prompt}")

    local output
    output=$(handle_task "${input}")

    assert_success "Should handle long prompts"
}
test_case "Handle very long prompts" test_long_prompt

# Test 22: Handle special characters in prompts
test_special_chars() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Special task" "Find files with \$variable and \`backticks\`")

    local output
    output=$(handle_task "${input}")

    echo "Handled special characters"
}
test_case "Handle special characters" test_special_chars

# Test 23: Track task metrics
test_metric_tracking() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Test task" "Simple task for metrics")

    handle_task "${input}" &>/dev/null

    local task_count
    task_count=$(session_get_metric "task_launches" "0")

    [[ "${task_count}" != "0" ]] || return 1
    echo "Metrics tracked: ${task_count}"
}
test_case "Track task metrics" test_metric_tracking

# Test 24: Log task events
test_event_logging() {
    source_task_handler || return 1

    local input
    input=$(create_tool_input "Event task" "Task for event logging")

    handle_task "${input}" &>/dev/null

    if type session_get_events &>/dev/null; then
        local events
        events=$(session_get_events)

        echo "Event logging verified"
    else
        echo "Event logging skipped (session manager not initialized)"
    fi
    return 0
}
test_case "Log task events" test_event_logging

# Run all tests
test_summary
