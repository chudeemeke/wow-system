#!/bin/bash
# WoW System - Credential Detector (Security-Critical)
# Real-time credential detection with pattern-based analysis
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple pattern types
# - High Sensitivity: Prefer false positives over false negatives
# - Context-Aware: Consider surrounding text
# - Performance: Fast pattern matching for real-time detection

# Prevent double-sourcing
if [[ -n "${WOW_CREDENTIAL_DETECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CREDENTIAL_DETECTOR_LOADED=1

set -uo pipefail

# ============================================================================
# Constants - Credential Patterns
# ============================================================================

# Token patterns (HIGH severity)
declare -gA CREDENTIAL_PATTERNS_HIGH=(
    ["npm_token"]='npm_[a-zA-Z0-9]{32,}'
    ["github_pat"]='ghp_[a-zA-Z0-9]{36}'
    ["github_oauth"]='gho_[a-zA-Z0-9]{36}'
    ["github_app"]='(ghu|ghs)_[a-zA-Z0-9]{36}'
    ["github_refresh"]='ghr_[a-zA-Z0-9]{36}'
    ["gitlab_pat"]='glpat-[a-zA-Z0-9_-]{20,}'
    ["gitlab_runner"]='GR1348941[a-zA-Z0-9_-]{20,}'
    ["openai_api"]='sk-[a-zA-Z0-9]{32,}'
    ["anthropic_api"]='sk-ant-[a-zA-Z0-9_-]{30,}'
    ["slack_token"]='xoxb-[a-zA-Z0-9-]{50,}'
    ["slack_webhook"]='https://hooks.slack.com/services/[A-Z0-9/]+'
    ["aws_access_key"]='AKIA[A-Z0-9]{16}'
    ["aws_session_token"]='(AWS)?[A-Z0-9]{16,}'
    ["google_api"]='AIza[a-zA-Z0-9_-]{35}'
    ["stripe_live"]='sk_live_[a-zA-Z0-9]{24,}'
    ["stripe_test"]='sk_test_[a-zA-Z0-9]{24,}'
    ["twilio_account"]='AC[a-z0-9]{32}'
    ["twilio_auth"]='SK[a-z0-9]{32}'
    ["sendgrid_api"]='SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'
    ["mailgun_api"]='key-[a-zA-Z0-9]{32}'
    ["heroku_api"]='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    ["jwt_token"]='eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'
    ["pypi_token"]='pypi-AgEIcHlwaS5vcmc[a-zA-Z0-9_-]+'
    ["docker_token"]='dckr_pat_[a-zA-Z0-9_-]{32,}'
)

# Generic patterns (MEDIUM severity)
declare -gA CREDENTIAL_PATTERNS_MEDIUM=(
    ["generic_api_key"]='(api[_-]?key|apikey)\s*[:=]\s*["\047]?([a-zA-Z0-9_-]{20,})["\047]?'
    ["generic_token"]='(token|auth[_-]?token)\s*[:=]\s*["\047]?([a-zA-Z0-9_-]{20,})["\047]?'
    ["generic_secret"]='(secret|api[_-]?secret)\s*[:=]\s*["\047]?([a-zA-Z0-9_-]{20,})["\047]?'
    ["generic_password"]='(password|passwd|pwd)\s*[:=]\s*["\047]?([a-zA-Z0-9_@!#$%^&*()-]{8,})["\047]?'
    ["bearer_token"]='Bearer\s+[a-zA-Z0-9_-]{20,}'
    ["basic_auth"]='Basic\s+[a-zA-Z0-9+/=]{20,}'
    ["connection_string"]='(mongodb|mysql|postgres|redis)://[^:]+:[^@]+@'
    ["private_key_header"]='-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----'
    ["ssh_key"]='ssh-(rsa|dss|ed25519)\s+[A-Za-z0-9+/=]+'
)

# Context patterns (LOW severity - requires context)
declare -gA CREDENTIAL_PATTERNS_LOW=(
    ["uuid"]='[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}'
    ["hex_key"]='[a-fA-F0-9]{40,}'
    ["base64_long"]='[a-zA-Z0-9+/=]{60,}'
)

# Safe context indicators (reduce false positives)
readonly -a SAFE_CONTEXT_PATTERNS=(
    "example"
    "test"
    "sample"
    "placeholder"
    "dummy"
    "fake"
    "mock"
    "REPLACE_ME"
    "YOUR_.*_HERE"
    "xxx+"
    "123+"
    "abc+"
)

# ============================================================================
# Module State
# ============================================================================

# Detection statistics
declare -gA _DETECT_STATS=(
    ["total_scans"]=0
    ["total_detections"]=0
    ["high_severity"]=0
    ["medium_severity"]=0
    ["low_severity"]=0
    ["false_positives"]=0
)

# Detection history (for ML/heuristics in future)
declare -ga _DETECT_HISTORY=()

# Initialization flag
_DETECT_INITIALIZED=false

# ============================================================================
# Public API: Initialization
# ============================================================================

detect_init() {
    if [[ "${_DETECT_INITIALIZED}" == "true" ]]; then
        return 0  # Already initialized
    fi

    # Reset statistics
    _DETECT_STATS["total_scans"]=0
    _DETECT_STATS["total_detections"]=0
    _DETECT_STATS["high_severity"]=0
    _DETECT_STATS["medium_severity"]=0
    _DETECT_STATS["low_severity"]=0
    _DETECT_STATS["false_positives"]=0

    _DETECT_INITIALIZED=true
    return 0
}

# ============================================================================
# Private: Pattern Matching
# ============================================================================

# Check if text matches safe context (likely a false positive)
_is_safe_context() {
    local text="$1"
    local pattern

    for pattern in "${SAFE_CONTEXT_PATTERNS[@]}"; do
        if echo "$text" | grep -iE "$pattern" >/dev/null 2>&1; then
            return 0  # Safe context
        fi
    done

    return 1  # Not safe context
}

# Match against pattern groups
_match_pattern_group() {
    local text="$1"
    local severity="$2"  # HIGH, MEDIUM, LOW
    local -n patterns="$3"  # nameref to pattern array

    local type pattern match

    for type in "${!patterns[@]}"; do
        pattern="${patterns[$type]}"

        # Try to match pattern
        if echo "$text" | grep -E "$pattern" >/dev/null 2>&1; then
            # Extract the actual match
            match=$(echo "$text" | grep -oE "$pattern" | head -1)

            # Check if safe context (for LOW severity only)
            if [[ "$severity" == "LOW" ]] && _is_safe_context "$text"; then
                continue  # Skip, likely false positive
            fi

            # Found a credential
            echo "{\"type\":\"$type\",\"severity\":\"$severity\",\"pattern\":\"${pattern}\",\"match\":\"${match}\",\"confidence\":0.95}"
            return 0
        fi
    done

    return 1  # No match
}

# ============================================================================
# Public API: Detection
# ============================================================================

# Detect credentials in a string
# Returns: JSON object with detection details
# Example: {"type":"github_pat","severity":"HIGH","pattern":"...","match":"ghp_xxx","confidence":0.95}
detect_in_string() {
    local text="$1"

    (( _DETECT_STATS["total_scans"]++ )) || true

    # Try HIGH severity patterns first
    local result
    if result=$(_match_pattern_group "$text" "HIGH" CREDENTIAL_PATTERNS_HIGH); then
        (( _DETECT_STATS["total_detections"]++ )) || true
        (( _DETECT_STATS["high_severity"]++ )) || true
        echo "$result"
        return 0
    fi

    # Try MEDIUM severity patterns
    if result=$(_match_pattern_group "$text" "MEDIUM" CREDENTIAL_PATTERNS_MEDIUM); then
        (( _DETECT_STATS["total_detections"]++ )) || true
        (( _DETECT_STATS["medium_severity"]++ )) || true
        echo "$result"
        return 0
    fi

    # Try LOW severity patterns (with context filtering)
    if result=$(_match_pattern_group "$text" "LOW" CREDENTIAL_PATTERNS_LOW); then
        (( _DETECT_STATS["total_detections"]++ )) || true
        (( _DETECT_STATS["low_severity"]++ )) || true
        echo "$result"
        return 0
    fi

    # No credential detected
    return 1
}

# Detect credentials in a file
# Returns: Array of JSON objects (one per line with detection)
detect_in_file() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    local line_num=0
    local line result
    local -a detections=()

    while IFS= read -r line; do
        (( line_num++ )) || true

        if result=$(detect_in_string "$line"); then
            # Add line number to result
            result=$(echo "$result" | jq --arg line "$line_num" '. + {line: ($line | tonumber)}')
            detections+=("$result")
        fi
    done < "$filepath"

    # Output all detections as JSON array
    if [[ ${#detections[@]} -gt 0 ]]; then
        printf '%s\n' "${detections[@]}" | jq -s '.'
        return 0
    fi

    return 1  # No credentials found
}

# Detect credentials in conversation history (JSONL format)
detect_in_conversation() {
    local history_file="$1"

    if [[ ! -f "$history_file" ]]; then
        echo "ERROR: History file not found: $history_file" >&2
        return 1
    fi

    local line_num=0
    local line content result
    local -a detections=()

    while IFS= read -r line; do
        (( line_num++ )) || true

        # Extract content from JSON line
        content=$(echo "$line" | jq -r '.content // .text // empty' 2>/dev/null)

        if [[ -n "$content" ]] && result=$(detect_in_string "$content"); then
            # Add context
            result=$(echo "$result" | jq --arg line "$line_num" --arg file "$history_file" \
                '. + {line: ($line | tonumber), file: $file, source: "conversation"}')
            detections+=("$result")
        fi
    done < "$history_file"

    # Output all detections
    if [[ ${#detections[@]} -gt 0 ]]; then
        printf '%s\n' "${detections[@]}" | jq -s '.'
        return 0
    fi

    return 1  # No credentials found
}

# ============================================================================
# Public API: Severity and Alerting
# ============================================================================

# Get severity level for credential type
detect_get_severity() {
    local cred_type="$1"

    if [[ -n "${CREDENTIAL_PATTERNS_HIGH[$cred_type]:-}" ]]; then
        echo "HIGH"
    elif [[ -n "${CREDENTIAL_PATTERNS_MEDIUM[$cred_type]:-}" ]]; then
        echo "MEDIUM"
    elif [[ -n "${CREDENTIAL_PATTERNS_LOW[$cred_type]:-}" ]]; then
        echo "LOW"
    else
        echo "UNKNOWN"
    fi
}

# Determine if credential type should trigger immediate alert
detect_should_alert() {
    local cred_type="$1"
    local severity

    severity=$(detect_get_severity "$cred_type")

    case "$severity" in
        HIGH)
            return 0  # Always alert for HIGH
            ;;
        MEDIUM)
            return 0  # Alert for MEDIUM
            ;;
        LOW)
            return 1  # Don't alert for LOW (requires manual review)
            ;;
        *)
            return 1  # Unknown, don't alert
            ;;
    esac
}

# ============================================================================
# Public API: Statistics and Reporting
# ============================================================================

# Get detection statistics
detect_get_stats() {
    jq -n \
        --arg total_scans "${_DETECT_STATS[total_scans]}" \
        --arg total_detections "${_DETECT_STATS[total_detections]}" \
        --arg high "${_DETECT_STATS[high_severity]}" \
        --arg medium "${_DETECT_STATS[medium_severity]}" \
        --arg low "${_DETECT_STATS[low_severity]}" \
        --arg false_pos "${_DETECT_STATS[false_positives]}" \
        '{
            total_scans: ($total_scans | tonumber),
            total_detections: ($total_detections | tonumber),
            high_severity: ($high | tonumber),
            medium_severity: ($medium | tonumber),
            low_severity: ($low | tonumber),
            false_positives: ($false_pos | tonumber)
        }'
}

# Reset detection statistics
detect_reset_stats() {
    _DETECT_STATS["total_scans"]=0
    _DETECT_STATS["total_detections"]=0
    _DETECT_STATS["high_severity"]=0
    _DETECT_STATS["medium_severity"]=0
    _DETECT_STATS["low_severity"]=0
    _DETECT_STATS["false_positives"]=0
}

# Mark a detection as false positive
detect_mark_false_positive() {
    (( _DETECT_STATS["false_positives"]++ )) || true
    (( _DETECT_STATS["total_detections"]-- )) || true
}

# ============================================================================
# Public API: Utility Functions
# ============================================================================

# List all supported credential types
detect_list_types() {
    echo "=== HIGH SEVERITY ==="
    for type in "${!CREDENTIAL_PATTERNS_HIGH[@]}"; do
        echo "  - $type"
    done

    echo ""
    echo "=== MEDIUM SEVERITY ==="
    for type in "${!CREDENTIAL_PATTERNS_MEDIUM[@]}"; do
        echo "  - $type"
    done

    echo ""
    echo "=== LOW SEVERITY ==="
    for type in "${!CREDENTIAL_PATTERNS_LOW[@]}"; do
        echo "  - $type"
    done
}

# Get pattern for specific credential type
detect_get_pattern() {
    local cred_type="$1"

    if [[ -n "${CREDENTIAL_PATTERNS_HIGH[$cred_type]:-}" ]]; then
        echo "${CREDENTIAL_PATTERNS_HIGH[$cred_type]}"
    elif [[ -n "${CREDENTIAL_PATTERNS_MEDIUM[$cred_type]:-}" ]]; then
        echo "${CREDENTIAL_PATTERNS_MEDIUM[$cred_type]}"
    elif [[ -n "${CREDENTIAL_PATTERNS_LOW[$cred_type]:-}" ]]; then
        echo "${CREDENTIAL_PATTERNS_LOW[$cred_type]}"
    else
        return 1
    fi
}

# ============================================================================
# Module Info
# ============================================================================

detect_version() {
    echo "WoW Credential Detector v5.0.1"
}

# Auto-initialize on source
detect_init
