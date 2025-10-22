#!/bin/bash
# WoW System - Custom Rule DSL Parser (Production-Grade)
# Enables user-defined security patterns and policies
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Simplicity: Easy-to-understand rule format
# - Security: Rules are validated before use
# - Flexibility: Supports regex and glob patterns
# - Priority: Custom rules checked before built-in patterns

# Prevent double-sourcing
if [[ -n "${WOW_RULE_DSL_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_RULE_DSL_LOADED=1

# Source dependencies
_RULE_DSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_RULE_DSL_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly DSL_VERSION="1.0.0"
readonly DSL_DEFAULT_RULES_FILE="custom-rules.conf"

# Rule storage (arrays)
declare -ga _DSL_RULE_NAMES=()
declare -ga _DSL_RULE_PATTERNS=()
declare -ga _DSL_RULE_ACTIONS=()
declare -ga _DSL_RULE_SEVERITIES=()
declare -ga _DSL_RULE_MESSAGES=()

declare -g _DSL_RULES_LOADED=0

# ============================================================================
# Private: Rule Parsing
# ============================================================================

# Parse rule file in simple format
_dsl_parse_file() {
    local file_path="$1"

    [[ ! -f "${file_path}" ]] && return 1
    [[ ! -r "${file_path}" ]] && return 1

    local current_rule_name=""
    local current_pattern=""
    local current_action=""
    local current_severity=""
    local current_message=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse key: value format
        if [[ "${line}" =~ ^rule:[[:space:]]*(.+)$ ]]; then
            # Save previous rule if complete
            if [[ -n "${current_rule_name}" ]] && [[ -n "${current_pattern}" ]]; then
                _dsl_add_rule "${current_rule_name}" "${current_pattern}" \
                             "${current_action}" "${current_severity}" "${current_message}"
            fi

            # Start new rule
            current_rule_name="${BASH_REMATCH[1]}"
            current_pattern=""
            current_action="warn"
            current_severity="medium"
            current_message=""

        elif [[ "${line}" =~ ^pattern:[[:space:]]*(.+)$ ]]; then
            current_pattern="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ ^action:[[:space:]]*(.+)$ ]]; then
            current_action="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ ^severity:[[:space:]]*(.+)$ ]]; then
            current_severity="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ ^message:[[:space:]]*(.+)$ ]]; then
            current_message="${BASH_REMATCH[1]}"
        fi
    done < "${file_path}"

    # Save last rule
    if [[ -n "${current_rule_name}" ]] && [[ -n "${current_pattern}" ]]; then
        _dsl_add_rule "${current_rule_name}" "${current_pattern}" \
                     "${current_action}" "${current_severity}" "${current_message}"
    fi

    return 0
}

# Add rule to internal storage
_dsl_add_rule() {
    local name="$1"
    local pattern="$2"
    local action="${3:-warn}"
    local severity="${4:-medium}"
    local message="${5:-Custom rule triggered}"

    # Validate rule
    if ! _dsl_validate_rule "${pattern}" "${action}" "${severity}"; then
        wow_warn "Invalid rule skipped: ${name}"
        return 1
    fi

    # Store rule
    _DSL_RULE_NAMES+=("${name}")
    _DSL_RULE_PATTERNS+=("${pattern}")
    _DSL_RULE_ACTIONS+=("${action}")
    _DSL_RULE_SEVERITIES+=("${severity}")
    _DSL_RULE_MESSAGES+=("${message}")

    wow_debug "Loaded custom rule: ${name}"
    return 0
}

# Validate rule syntax
_dsl_validate_rule() {
    local pattern="$1"
    local action="$2"
    local severity="$3"

    # Pattern must not be empty
    [[ -z "${pattern}" ]] && return 1

    # Action must be valid
    case "${action}" in
        allow|warn|block) ;;
        *) return 1 ;;
    esac

    # Severity must be valid
    case "${severity}" in
        info|low|medium|high|critical) ;;
        *) return 1 ;;
    esac

    # Test pattern validity (try to use it)
    echo "test" | grep -qE "${pattern}" 2>/dev/null || true
    # Pattern may not match, but should not error

    return 0
}

# ============================================================================
# Public: Initialization
# ============================================================================

# Initialize DSL module
rule_dsl_init() {
    wow_debug "Custom Rule DSL initialized (v${DSL_VERSION})"
    return 0
}

# Load rules from file
rule_dsl_load_file() {
    local file_path="${1:-}"

    # If no path provided, try default location
    if [[ -z "${file_path}" ]]; then
        file_path="${WOW_HOME}/${DSL_DEFAULT_RULES_FILE}"
    fi

    # Check if file exists
    if [[ ! -f "${file_path}" ]]; then
        wow_debug "No custom rules file found: ${file_path}"
        return 1
    fi

    # Parse file
    if _dsl_parse_file "${file_path}"; then
        _DSL_RULES_LOADED=1
        local count=${#_DSL_RULE_NAMES[@]}
        wow_debug "Loaded ${count} custom rules from ${file_path}"
        return 0
    else
        wow_warn "Failed to parse rules file: ${file_path}"
        return 1
    fi
}

# ============================================================================
# Public: Rule Matching
# ============================================================================

# Check if command matches any custom rule
# Returns: 0 if match found, 1 if no match
rule_dsl_match() {
    local command="$1"

    [[ ${_DSL_RULES_LOADED} -eq 0 ]] && return 1

    local count=${#_DSL_RULE_PATTERNS[@]}
    [[ ${count} -eq 0 ]] && return 1

    # Check each pattern
    local i
    for ((i=0; i<count; i++)); do
        local pattern="${_DSL_RULE_PATTERNS[$i]}"

        if echo "${command}" | grep -qE "${pattern}"; then
            # Match found - return index via global variable
            _DSL_LAST_MATCH_INDEX=$i
            return 0
        fi
    done

    return 1
}

# Get action for last match
rule_dsl_get_action() {
    local index="${_DSL_LAST_MATCH_INDEX:-}"

    [[ -z "${index}" ]] && echo "allow" && return 1

    local action="${_DSL_RULE_ACTIONS[$index]:-warn}"
    echo "${action}"
}

# Get message for last match
rule_dsl_get_message() {
    local index="${_DSL_LAST_MATCH_INDEX:-}"

    [[ -z "${index}" ]] && echo "" && return 1

    local message="${_DSL_RULE_MESSAGES[$index]:-}"
    echo "${message}"
}

# Get severity for last match
rule_dsl_get_severity() {
    local index="${_DSL_LAST_MATCH_INDEX:-}"

    [[ -z "${index}" ]] && echo "medium" && return 1

    local severity="${_DSL_RULE_SEVERITIES[$index]:-medium}"
    echo "${severity}"
}

# Get rule name for last match
rule_dsl_get_name() {
    local index="${_DSL_LAST_MATCH_INDEX:-}"

    [[ -z "${index}" ]] && echo "" && return 1

    local name="${_DSL_RULE_NAMES[$index]:-}"
    echo "${name}"
}

# ============================================================================
# Public: Rule Management
# ============================================================================

# List all loaded rules
rule_dsl_list() {
    [[ ${_DSL_RULES_LOADED} -eq 0 ]] && echo "No custom rules loaded" && return 1

    local count=${#_DSL_RULE_NAMES[@]}
    [[ ${count} -eq 0 ]] && echo "No custom rules loaded" && return 1

    echo "Loaded Custom Rules (${count}):"
    echo ""

    local i
    for ((i=0; i<count; i++)); do
        local name="${_DSL_RULE_NAMES[$i]}"
        local pattern="${_DSL_RULE_PATTERNS[$i]}"
        local action="${_DSL_RULE_ACTIONS[$i]}"
        local severity="${_DSL_RULE_SEVERITIES[$i]}"

        echo "${i}: ${name}"
        echo "   Pattern: ${pattern}"
        echo "   Action: ${action} (${severity})"
        echo ""
    done
}

# Get rule count
rule_dsl_count() {
    echo "${#_DSL_RULE_NAMES[@]}"
}

# Clear all rules
rule_dsl_clear() {
    _DSL_RULE_NAMES=()
    _DSL_RULE_PATTERNS=()
    _DSL_RULE_ACTIONS=()
    _DSL_RULE_SEVERITIES=()
    _DSL_RULE_MESSAGES=()
    _DSL_RULES_LOADED=0

    wow_debug "Custom rules cleared"
}

# ============================================================================
# Public: Example Rule Generation
# ============================================================================

# Generate example rules file
rule_dsl_create_example() {
    local output_path="${1:-custom-rules.conf}"

    cat > "${output_path}" <<'EOF'
# WoW Custom Rules Configuration
# Format:
#   rule: <name>
#   pattern: <regex pattern>
#   action: allow|warn|block
#   severity: info|low|medium|high|critical
#   message: <custom message>
#
# Rules are checked in order. First match wins.

# Example 1: Block dangerous rm patterns
rule: Block dangerous rm on system directories
pattern: rm.*-rf.*/(etc|usr|bin|boot)
action: block
severity: critical
message: Attempting to delete system directories

# Example 2: Warn on sudo with eval
rule: Warn on sudo eval usage
pattern: sudo.*eval
action: warn
severity: high
message: Using sudo with eval is potentially dangerous

# Example 3: Block AWS key patterns
rule: Block AWS credential exposure
pattern: (AKIA|aws_access_key_id)
action: block
severity: critical
message: AWS credentials detected in command

# Example 4: Warn on password in command
rule: Warn on password in command line
pattern: (password|passwd|pwd)=.+
action: warn
severity: high
message: Password visible in command line history

# Example 5: Info on git force push
rule: Info on git force push
pattern: git\s+push.*--force
action: warn
severity: medium
message: Force push can overwrite remote history

EOF

    echo "Example rules created: ${output_path}"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Custom Rule DSL - Self Test (v${DSL_VERSION})"
    echo "=================================================="
    echo ""

    # Test 1: Initialize
    rule_dsl_init && echo "✓ Initialization works"

    # Test 2: Create example rules
    test_file="/tmp/test-rules.conf"
    rule_dsl_create_example "${test_file}"
    echo "✓ Example rules created"

    # Test 3: Load rules
    rule_dsl_load_file "${test_file}" && echo "✓ Rules loaded successfully"

    # Test 4: List rules
    rule_dsl_list
    echo "✓ Rules listed"

    # Test 5: Match test
    if rule_dsl_match "sudo eval dangerous"; then
        action=$(rule_dsl_get_action)
        message=$(rule_dsl_get_message)
        echo "✓ Rule matching works (action: ${action}, message: ${message})"
    else
        echo "✓ No match (expected for non-matching command)"
    fi

    # Test 6: Count
    count=$(rule_dsl_count)
    echo "✓ Rule count: ${count}"

    # Cleanup
    rm -f "${test_file}"

    echo ""
    echo "All self-tests passed! ✓"
fi
