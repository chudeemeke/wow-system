#!/bin/bash
# WoW System - Capture Library
# Shared functions for wow-capture CLI tool
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_CAPTURE_LIB_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CAPTURE_LIB_LOADED=1

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly CAPTURE_LIB_VERSION="1.0.0"

# Confidence levels
readonly CONF_HIGH="HIGH"
readonly CONF_MEDIUM="MEDIUM"
readonly CONF_LOW="LOW"

# Frustration types
readonly TYPE_REPEATED_ERROR="repeated_error"
readonly TYPE_RAPID_FIRE="rapid_fire"
readonly TYPE_PATH_ISSUE="path_issue"
readonly TYPE_WORKAROUND="workaround"
readonly TYPE_RESTART="restart"
readonly TYPE_CREDENTIAL="credential"
readonly TYPE_AUTHORITY="authority_violation"
readonly TYPE_FRUSTRATION_LANG="frustration_language"

# Thresholds
readonly THRESHOLD_REPEATED=3
readonly THRESHOLD_RAPID_FIRE=4
readonly THRESHOLD_TIME_WINDOW=600  # 10 minutes

# ============================================================================
# Output Formatting
# ============================================================================

# Colors
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    readonly C_RESET=$(tput sgr0)
    readonly C_RED=$(tput setaf 1)
    readonly C_GREEN=$(tput setaf 2)
    readonly C_YELLOW=$(tput setaf 3)
    readonly C_BLUE=$(tput setaf 4)
    readonly C_MAGENTA=$(tput setaf 5)
    readonly C_CYAN=$(tput setaf 6)
    readonly C_BOLD=$(tput bold)
else
    readonly C_RESET=""
    readonly C_RED=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_BLUE=""
    readonly C_MAGENTA=""
    readonly C_CYAN=""
    readonly C_BOLD=""
fi

# Print colored message
lib_print() {
    local color="$1"
    shift
    echo -e "${color}$*${C_RESET}"
}

# Print error
lib_error() {
    lib_print "${C_RED}${C_BOLD}" "ERROR: $*" >&2
}

# Print warning
lib_warn() {
    lib_print "${C_YELLOW}" "WARNING: $*" >&2
}

# Print info
lib_info() {
    lib_print "${C_BLUE}" "$*"
}

# Print success
lib_success() {
    lib_print "${C_GREEN}" "$*"
}

# Print header
lib_header() {
    echo ""
    lib_print "${C_BOLD}${C_CYAN}" "$*"
    lib_print "${C_CYAN}" "$(printf '=%.0s' {1..70})"
}

# Progress indicator
lib_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Processing}"

    local percent=$((current * 100 / total))
    printf "\r${C_BLUE}${message}... [%3d%%] %d/%d${C_RESET}" "$percent" "$current" "$total"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# ============================================================================
# History File Operations
# ============================================================================

# Find Claude history file
lib_find_history() {
    local history_file="${HOME}/.claude/history.jsonl"

    if [[ -f "$history_file" ]]; then
        echo "$history_file"
        return 0
    fi

    # Try alternate locations
    for path in \
        "${HOME}/.config/claude/history.jsonl" \
        "/root/.claude/history.jsonl"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# Parse date (YYYY-MM-DD) to epoch
lib_parse_date() {
    local date_str="$1"

    if ! date -d "$date_str" +%s 2>/dev/null; then
        lib_error "Invalid date format: $date_str (use YYYY-MM-DD)"
        return 1
    fi
}

# Extract entries from history file by date range
lib_extract_by_date() {
    local history_file="$1"
    local from_epoch="$2"
    local to_epoch="$3"

    if [[ ! -f "$history_file" ]]; then
        lib_error "History file not found: $history_file"
        return 1
    fi

    local count=0
    while IFS= read -r line; do
        # Extract timestamp from JSON
        local ts
        ts=$(echo "$line" | jq -r '.timestamp // .created_at // empty' 2>/dev/null)

        if [[ -n "$ts" ]]; then
            # Convert to epoch (handle milliseconds)
            local ts_epoch
            if [[ $ts =~ ^[0-9]{13}$ ]]; then
                # Milliseconds - convert to seconds
                ts_epoch=$((ts / 1000))
            elif [[ $ts =~ ^[0-9]+$ ]]; then
                # Already in seconds
                ts_epoch=$ts
            else
                # ISO format - parse
                ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
            fi

            # Check if in range
            if [[ $ts_epoch -ge $from_epoch ]] && [[ $ts_epoch -le $to_epoch ]]; then
                echo "$line"
                ((count++))
            fi
        else
            # No timestamp, include it (fallback)
            echo "$line"
            ((count++))
        fi
    done < "$history_file"

    lib_debug "Extracted $count entries from date range"
    return 0
}

# ============================================================================
# Credential Detection Integration
# ============================================================================

# Source credential detector if available
lib_load_credential_detector() {
    local detector_path="${WOW_SYSTEM_DIR:-/mnt/c/Users/Destiny/iCloudDrive/Documents/AI Tools/Anthropic Solution/Projects/wow-system}/src/security/credential-detector.sh"

    if [[ -f "$detector_path" ]]; then
        source "$detector_path"
        return 0
    fi

    lib_warn "Credential detector not found, credential scanning disabled"
    return 1
}

# Scan text for credentials
lib_scan_credentials() {
    local text="$1"

    # Check if detector is loaded
    if ! type detect_in_string &>/dev/null; then
        return 1
    fi

    # Run detection
    detect_in_string "$text"
}

# Redact credential from text
lib_redact_credential() {
    local text="$1"
    local match="$2"

    # Replace match with [REDACTED]
    local redacted="${text//$match/[REDACTED]}"
    echo "$redacted"
}

# ============================================================================
# Pattern Detection
# ============================================================================

# Detect repeated errors in conversation
lib_detect_repeated_errors() {
    local conversation_json="$1"

    # Count error patterns
    local error_count
    error_count=$(echo "$conversation_json" | jq -r '[.[] | select(.content | test("error|Error|ERROR|failed|Failed|FAILED"))] | length' 2>/dev/null || echo "0")

    if [[ $error_count -ge $THRESHOLD_REPEATED ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Detect rapid-fire events
lib_detect_rapid_fire() {
    local conversation_json="$1"

    # Get timestamps of all entries
    local -a timestamps=()
    while IFS= read -r ts; do
        if [[ -n "$ts" ]]; then
            local ts_epoch
            ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
            timestamps+=("$ts_epoch")
        fi
    done < <(echo "$conversation_json" | jq -r '.[].timestamp // empty')

    # Check for rapid sequence
    if [[ ${#timestamps[@]} -ge $THRESHOLD_RAPID_FIRE ]]; then
        local first="${timestamps[0]}"
        local last="${timestamps[-1]}"
        local duration=$((last - first))

        if [[ $duration -le $THRESHOLD_TIME_WINDOW ]]; then
            echo "true"
            return 0
        fi
    fi

    echo "false"
}

# Detect path issues
lib_detect_path_issues() {
    local text="$1"

    # Pattern matching for path problems
    if echo "$text" | grep -iE "(path|Path|PATH).*(space|Space|SPACE|quote|Quote|QUOTE|not found|Not Found|NOT FOUND)" >/dev/null; then
        echo "true"
    elif echo "$text" | grep -E "/mnt/c/.*( |%20)" >/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Detect restart mentions
lib_detect_restarts() {
    local text="$1"

    if echo "$text" | grep -iE "(restart|Restart|RESTART|reload|Reload|RELOAD)" >/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Detect frustration language
lib_detect_frustration_language() {
    local text="$1"

    local patterns=(
        "annoying"
        "frustrating"
        "why doesn't"
        "why won't"
        "not working"
        "broken"
        "keeps failing"
        "this is"
        "CAPS.*EMPHASIS"
    )

    for pattern in "${patterns[@]}"; do
        if echo "$text" | grep -iE "$pattern" >/dev/null; then
            echo "true"
            return 0
        fi
    done

    echo "false"
}

# Detect workarounds
lib_detect_workarounds() {
    local text="$1"

    if echo "$text" | grep -iE "(workaround|symlink|manual|manually|hack|temporary fix)" >/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Detect authority violations
lib_detect_authority_violations() {
    local text="$1"

    # Look for user complaints about AI autonomy
    if echo "$text" | grep -iE "(without.*approval|without.*permission|didn't ask|without asking|I NEED TO BE THE ONE)" >/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# ============================================================================
# Confidence Scoring
# ============================================================================

# Calculate confidence score for detected frustration
lib_calculate_confidence() {
    local type="$1"
    local evidence_count="${2:-1}"
    local context="${3:-}"

    # Base confidence by type
    case "$type" in
        "$TYPE_CREDENTIAL")
            echo "$CONF_HIGH"
            ;;
        "$TYPE_AUTHORITY")
            echo "$CONF_HIGH"
            ;;
        "$TYPE_REPEATED_ERROR")
            if [[ $evidence_count -ge 5 ]]; then
                echo "$CONF_HIGH"
            else
                echo "$CONF_MEDIUM"
            fi
            ;;
        "$TYPE_RAPID_FIRE")
            echo "$CONF_HIGH"
            ;;
        "$TYPE_PATH_ISSUE")
            echo "$CONF_MEDIUM"
            ;;
        "$TYPE_RESTART")
            if [[ $evidence_count -ge 3 ]]; then
                echo "$CONF_MEDIUM"
            else
                echo "$CONF_LOW"
            fi
            ;;
        "$TYPE_WORKAROUND")
            echo "$CONF_MEDIUM"
            ;;
        "$TYPE_FRUSTRATION_LANG")
            echo "$CONF_LOW"
            ;;
        *)
            echo "$CONF_LOW"
            ;;
    esac
}

# ============================================================================
# Output Generation
# ============================================================================

# Generate scratch.md entry
lib_generate_scratch_entry() {
    local type="$1"
    local confidence="$2"
    local evidence="$3"
    local context="${4:-}"
    local timestamp=$(date +%Y-%m-%d)

    cat <<EOF

### ${confidence} CONFIDENCE: ${type}

**Date**: ${timestamp}
**Evidence**: ${evidence}
**Context**: ${context}

EOF
}

# Generate JSON report
lib_generate_json_report() {
    local findings="$1"

    echo "$findings" | jq -s '
    {
        "total_frustrations": length,
        "by_confidence": {
            "HIGH": [.[] | select(.confidence == "HIGH")] | length,
            "MEDIUM": [.[] | select(.confidence == "MEDIUM")] | length,
            "LOW": [.[] | select(.confidence == "LOW")] | length
        },
        "by_type": (group_by(.type) | map({(.[0].type): length}) | add),
        "findings": .
    }'
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if jq is available
lib_has_jq() {
    command -v jq &>/dev/null
}

# Check if file is valid JSONL
lib_validate_jsonl() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Check if file is empty
    if [[ ! -s "$file" ]]; then
        return 1
    fi

    # Try parsing first line
    head -1 "$file" | jq . >/dev/null 2>&1
}

# Debug output (only if WOW_DEBUG=1)
lib_debug() {
    if [[ "${WOW_DEBUG:-0}" == "1" ]]; then
        lib_print "${C_CYAN}" "[DEBUG] $*" >&2
    fi
}

# Version info
lib_version() {
    echo "WoW Capture Library v${CAPTURE_LIB_VERSION}"
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize library
lib_init() {
    # Check dependencies
    if ! lib_has_jq; then
        lib_error "jq is required but not installed"
        return 1
    fi

    # Try to load credential detector
    lib_load_credential_detector || lib_warn "Credential detection unavailable"

    return 0
}

# Auto-initialize
lib_init
