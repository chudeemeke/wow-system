#!/bin/bash
# WoW System - Credential Scanner Integration
# Real-time credential detection for handler integration
# Author: Chude <chude@emeke.org>
#
# Purpose: Integrate credential detection into existing handlers
# without modifying their core functionality

# Prevent double-sourcing
if [[ -n "${WOW_CREDENTIAL_SCANNER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CREDENTIAL_SCANNER_LOADED=1

# Source dependencies
_SCANNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCANNER_DIR}/credential-detector.sh"
source "${_SCANNER_DIR}/credential-redactor.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly SCANNER_VERSION="5.0.1"
readonly ALERT_LOG="${HOME}/.wow/logs/credential-alerts.log"
readonly URGENT_REVOKE_FILE="${HOME}/URGENT-REVOKE-TOKENS.txt"

# ============================================================================
# Module State
# ============================================================================

# Alert statistics
declare -gA _SCANNER_STATS=(
    ["total_scans"]=0
    ["alerts_triggered"]=0
    ["user_warnings"]=0
    ["auto_redactions"]=0
)

_SCANNER_INITIALIZED=false

# ============================================================================
# Public API: Initialization
# ============================================================================

scanner_init() {
    if [[ "${_SCANNER_INITIALIZED}" == "true" ]]; then
        return 0  # Already initialized
    fi

    # Ensure log directory exists
    local log_dir
    log_dir=$(dirname "$ALERT_LOG")
    mkdir -p "$log_dir" 2>/dev/null || true

    # Initialize alert log
    if [[ ! -f "$ALERT_LOG" ]]; then
        echo "# WoW Credential Alert Log" > "$ALERT_LOG"
        echo "# Format: timestamp|severity|type|context|action" >> "$ALERT_LOG"
    fi

    # Initialize both detector and redactor
    detect_init
    redact_init

    _SCANNER_INITIALIZED=true
    return 0
}

# ============================================================================
# Private: Logging and Alerting
# ============================================================================

_log_alert() {
    local severity="$1"
    local cred_type="$2"
    local context="$3"
    local action="$4"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "${timestamp}|${severity}|${cred_type}|${context}|${action}" >> "$ALERT_LOG"
}

_show_user_alert() {
    local severity="$1"
    local cred_type="$2"
    local match="$3"

    # Color-coded alerts based on severity
    case "$severity" in
        HIGH)
            echo ""
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║  ⚠️  CRITICAL: CREDENTIAL DETECTED                            ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "Type:     $cred_type"
            echo "Severity: $severity"
            echo "Preview:  ${match:0:20}..."
            echo ""
            echo "This credential should be IMMEDIATELY revoked and rotated!"
            echo ""
            ;;
        MEDIUM)
            echo ""
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║  ⚠️  WARNING: POTENTIAL CREDENTIAL DETECTED                   ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "Type:     $cred_type"
            echo "Severity: $severity"
            echo "Preview:  ${match:0:20}..."
            echo ""
            echo "Please verify if this is a real credential."
            echo ""
            ;;
        *)
            echo ""
            echo "INFO: Potential credential detected ($cred_type, $severity severity)"
            echo ""
            ;;
    esac
}

_add_to_revoke_list() {
    local cred_type="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Ensure file exists
    touch "$URGENT_REVOKE_FILE"

    # Add entry
    echo "[${timestamp}] DETECTED: $cred_type - REQUIRES IMMEDIATE REVOCATION" >> "$URGENT_REVOKE_FILE"
}

# ============================================================================
# Public API: Scan Operations
# ============================================================================

# Scan a string for credentials and alert user
scanner_scan_string() {
    local text="$1"
    local context="${2:-unknown}"

    (( _SCANNER_STATS["total_scans"]++ )) || true

    # Detect credentials
    local detection
    if ! detection=$(detect_in_string "$text"); then
        return 1  # No credentials found
    fi

    # Parse detection
    local cred_type severity match
    cred_type=$(echo "$detection" | jq -r '.type')
    severity=$(echo "$detection" | jq -r '.severity')
    match=$(echo "$detection" | jq -r '.match')

    # Check if we should alert
    if detect_should_alert "$cred_type"; then
        (( _SCANNER_STATS["alerts_triggered"]++ )) || true
        (( _SCANNER_STATS["user_warnings"]++ )) || true

        # Show user alert
        _show_user_alert "$severity" "$cred_type" "$match"

        # Log alert
        _log_alert "$severity" "$cred_type" "$context" "user_alerted"

        # For HIGH severity, ask user about revocation
        if [[ "$severity" == "HIGH" ]]; then
            echo "Add this credential to rotation reminder? (y/n): "
            read -r choice

            if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
                _add_to_revoke_list "$cred_type"
                echo "Added to revocation list: $URGENT_REVOKE_FILE"
                _log_alert "$severity" "$cred_type" "$context" "added_to_revoke_list"
            fi
        fi

        return 0  # Credential detected and alerted
    fi

    return 1  # No alert needed
}

# Scan a command before execution
scanner_scan_command() {
    local command="$1"

    scanner_scan_string "$command" "bash_command"
}

# Scan tool input (JSON format)
scanner_scan_tool_input() {
    local tool_input="$1"
    local tool_name="${2:-unknown}"

    # Extract all string values from JSON
    local strings
    if command -v jq >/dev/null 2>&1; then
        strings=$(echo "$tool_input" | jq -r '.. | strings' 2>/dev/null || echo "")

        # Scan each string
        local string detection_found=false
        while IFS= read -r string; do
            if [[ -n "$string" ]] && scanner_scan_string "$string" "${tool_name}_input"; then
                detection_found=true
            fi
        done <<< "$strings"

        if [[ "$detection_found" == "true" ]]; then
            return 0  # Credential detected
        fi
    fi

    return 1  # No credentials
}

# Scan a file for credentials
scanner_scan_file() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Detect credentials in file
    local detections
    if ! detections=$(detect_in_file "$filepath"); then
        return 1  # No credentials found
    fi

    # Count and report
    local count
    count=$(echo "$detections" | jq 'length')

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  CREDENTIALS DETECTED IN FILE                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "File:        $filepath"
    echo "Credentials: $count found"
    echo ""

    # Show each detection
    local detection cred_type severity line_num
    local idx=0
    while IFS= read -r detection; do
        (( idx++ )) || true
        cred_type=$(echo "$detection" | jq -r '.type')
        severity=$(echo "$detection" | jq -r '.severity')
        line_num=$(echo "$detection" | jq -r '.line')

        echo "[$idx] Line $line_num: $cred_type ($severity)"

        # Log
        _log_alert "$severity" "$cred_type" "file:$filepath:$line_num" "file_scan"
    done < <(echo "$detections" | jq -c '.[]')

    (( _SCANNER_STATS["alerts_triggered"]++ )) || true

    # Offer redaction
    echo ""
    echo "Options:"
    echo "  1. Preview redaction:   redact_preview_file \"$filepath\""
    echo "  2. Redact with backup:  redact_with_backup \"$filepath\""
    echo "  3. Ignore"
    echo ""

    return 0
}

# Scan conversation history
scanner_scan_conversation() {
    local history_file="${1:-${HOME}/.claude/history.jsonl}"

    if [[ ! -f "$history_file" ]]; then
        echo "No conversation history found."
        return 1
    fi

    echo "Scanning conversation history for credentials..."

    # Detect credentials
    local detections
    if ! detections=$(detect_in_conversation "$history_file"); then
        echo "No credentials detected in conversation history."
        return 0
    fi

    # Count and report
    local count
    count=$(echo "$detections" | jq 'length')

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  CREDENTIALS DETECTED IN CONVERSATION HISTORY             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "File:        $history_file"
    echo "Credentials: $count found"
    echo ""

    # Recommend immediate action
    echo "IMMEDIATE ACTION REQUIRED:"
    echo "  1. Revoke all detected credentials"
    echo "  2. Redact conversation history: redact_with_backup \"$history_file\""
    echo "  3. Rotate all affected tokens"
    echo ""

    _log_alert "HIGH" "multiple" "conversation_history" "history_scan"
    (( _SCANNER_STATS["alerts_triggered"]++ )) || true

    return 0
}

# ============================================================================
# Public API: Auto-Redaction
# ============================================================================

# Automatically redact credentials in text (for logging/output)
scanner_auto_redact() {
    local text="$1"

    # Check if contains credentials
    if detect_in_string "$text" >/dev/null 2>&1; then
        (( _SCANNER_STATS["auto_redactions"]++ )) || true
        redact_string "$text"
    else
        echo "$text"
    fi
}

# ============================================================================
# Public API: Statistics
# ============================================================================

scanner_get_stats() {
    jq -n \
        --arg total_scans "${_SCANNER_STATS[total_scans]}" \
        --arg alerts "${_SCANNER_STATS[alerts_triggered]}" \
        --arg warnings "${_SCANNER_STATS[user_warnings]}" \
        --arg redactions "${_SCANNER_STATS[auto_redactions]}" \
        '{
            total_scans: ($total_scans | tonumber),
            alerts_triggered: ($alerts | tonumber),
            user_warnings: ($warnings | tonumber),
            auto_redactions: ($redactions | tonumber)
        }'
}

scanner_reset_stats() {
    _SCANNER_STATS["total_scans"]=0
    _SCANNER_STATS["alerts_triggered"]=0
    _SCANNER_STATS["user_warnings"]=0
    _SCANNER_STATS["auto_redactions"]=0
}

# View alert log
scanner_view_alerts() {
    local lines="${1:-50}"

    if [[ ! -f "$ALERT_LOG" ]]; then
        echo "No alerts logged yet."
        return 1
    fi

    echo "=== CREDENTIAL ALERTS (last $lines entries) ==="
    tail -n "$lines" "$ALERT_LOG"
}

# ============================================================================
# Public API: Utility
# ============================================================================

# Check if text contains credentials (silent check)
scanner_has_credentials() {
    local text="$1"
    detect_in_string "$text" >/dev/null 2>&1
}

# ============================================================================
# Module Info
# ============================================================================

scanner_version() {
    echo "WoW Credential Scanner v${SCANNER_VERSION}"
}

# Auto-initialize
scanner_init
