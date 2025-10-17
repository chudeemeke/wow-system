#!/bin/bash
# WoW System - Credential Redactor (Security-Critical)
# Safe redaction of credentials with backup and preview
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Safety First: Always backup before modifying
# - Preview Mode: Show changes before applying
# - Audit Trail: Log all redactions
# - Reversible: Maintain backup chain

# Prevent double-sourcing
if [[ -n "${WOW_CREDENTIAL_REDACTOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CREDENTIAL_REDACTOR_LOADED=1

# Source dependencies
_REDACTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_REDACTOR_DIR}/credential-detector.sh" ]]; then
    source "${_REDACTOR_DIR}/credential-detector.sh"
fi

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly REDACTED_TEXT="**REDACTED**"
readonly BACKUP_SUFFIX=".credential-backup"
readonly REDACTION_LOG="${HOME}/.wow/logs/redactions.log"

# Redaction markers for different credential types
declare -gA REDACTION_MARKERS=(
    ["github_pat"]="**REDACTED-GITHUB-PAT**"
    ["openai_api"]="**REDACTED-OPENAI-KEY**"
    ["aws_access_key"]="**REDACTED-AWS-KEY**"
    ["slack_token"]="**REDACTED-SLACK-TOKEN**"
    ["generic_api_key"]="**REDACTED-API-KEY**"
    ["generic_token"]="**REDACTED-TOKEN**"
    ["generic_secret"]="**REDACTED-SECRET**"
    ["generic_password"]="**REDACTED-PASSWORD**"
)

# ============================================================================
# Module State
# ============================================================================

# Redaction statistics
declare -gA _REDACT_STATS=(
    ["total_redactions"]=0
    ["files_processed"]=0
    ["strings_redacted"]=0
    ["backups_created"]=0
    ["errors"]=0
)

# Initialization flag
_REDACT_INITIALIZED=false

# ============================================================================
# Public API: Initialization
# ============================================================================

redact_init() {
    if [[ "${_REDACT_INITIALIZED}" == "true" ]]; then
        return 0  # Already initialized
    fi

    # Ensure log directory exists
    local log_dir
    log_dir=$(dirname "$REDACTION_LOG")
    mkdir -p "$log_dir" 2>/dev/null || true

    # Initialize log file
    if [[ ! -f "$REDACTION_LOG" ]]; then
        echo "# WoW Credential Redaction Log" > "$REDACTION_LOG"
        echo "# Format: timestamp|action|file|credential_type|status" >> "$REDACTION_LOG"
    fi

    _REDACT_INITIALIZED=true
    return 0
}

# ============================================================================
# Private: Logging
# ============================================================================

_log_redaction() {
    local action="$1"
    local filepath="$2"
    local cred_type="$3"
    local status="$4"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "${timestamp}|${action}|${filepath}|${cred_type}|${status}" >> "$REDACTION_LOG"
}

# ============================================================================
# Private: Backup Management
# ============================================================================

_create_backup() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Generate backup path with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${filepath}${BACKUP_SUFFIX}.${timestamp}"

    # Create backup
    if cp "$filepath" "$backup_path"; then
        echo "$backup_path"
        (( _REDACT_STATS["backups_created"]++ )) || true
        return 0
    else
        echo "ERROR: Failed to create backup: $backup_path" >&2
        (( _REDACT_STATS["errors"]++ )) || true
        return 1
    fi
}

_list_backups() {
    local filepath="$1"
    local dir
    local filename

    dir=$(dirname "$filepath")
    filename=$(basename "$filepath")

    # Find all backups for this file
    find "$dir" -maxdepth 1 -name "${filename}${BACKUP_SUFFIX}.*" -type f 2>/dev/null | sort -r
}

_restore_backup() {
    local filepath="$1"
    local backup_path="$2"

    if [[ ! -f "$backup_path" ]]; then
        echo "ERROR: Backup not found: $backup_path" >&2
        return 1
    fi

    # Restore from backup
    if cp "$backup_path" "$filepath"; then
        echo "Restored from backup: $backup_path"
        _log_redaction "restore" "$filepath" "N/A" "success"
        return 0
    else
        echo "ERROR: Failed to restore from backup" >&2
        _log_redaction "restore" "$filepath" "N/A" "failed"
        return 1
    fi
}

# ============================================================================
# Private: Redaction Logic
# ============================================================================

_get_redaction_marker() {
    local cred_type="$1"

    if [[ -n "${REDACTION_MARKERS[$cred_type]:-}" ]]; then
        echo "${REDACTION_MARKERS[$cred_type]}"
    else
        echo "$REDACTED_TEXT"
    fi
}

# Redact a single match in text
_redact_match() {
    local text="$1"
    local match="$2"
    local marker="$3"

    # Escape special regex characters in match
    local escaped_match
    escaped_match=$(printf '%s\n' "$match" | sed 's/[[\.*^$/]/\\&/g')

    # Replace match with marker
    echo "$text" | sed "s/${escaped_match}/${marker}/g"
}

# ============================================================================
# Public API: String Redaction
# ============================================================================

# Redact credentials in a string
redact_string() {
    local text="$1"
    local pattern="${2:-}"  # Optional: specific pattern to redact

    # If no pattern specified, detect and redact all
    if [[ -z "$pattern" ]]; then
        local detection
        if detection=$(detect_in_string "$text"); then
            local cred_type match marker
            cred_type=$(echo "$detection" | jq -r '.type')
            match=$(echo "$detection" | jq -r '.match')
            marker=$(_get_redaction_marker "$cred_type")

            text=$(_redact_match "$text" "$match" "$marker")
            (( _REDACT_STATS["strings_redacted"]++ )) || true

            # Continue detecting (there might be multiple credentials)
            redact_string "$text"
        else
            echo "$text"
        fi
    else
        # Redact specific pattern
        echo "$text" | sed "s/${pattern}/${REDACTED_TEXT}/g"
    fi
}

# Preview what would be redacted in a string
redact_preview() {
    local text="$1"

    local detection
    if detection=$(detect_in_string "$text"); then
        local cred_type match severity
        cred_type=$(echo "$detection" | jq -r '.type')
        match=$(echo "$detection" | jq -r '.match')
        severity=$(echo "$detection" | jq -r '.severity')

        echo "=== REDACTION PREVIEW ==="
        echo "Type: $cred_type"
        echo "Severity: $severity"
        echo "Match: $match"
        echo ""
        echo "Before:"
        echo "$text"
        echo ""
        echo "After:"
        redact_string "$text"
        return 0
    else
        echo "No credentials detected."
        return 1
    fi
}

# ============================================================================
# Public API: File Redaction
# ============================================================================

# Redact credentials in a file (IN-PLACE - DANGEROUS!)
redact_file() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Read file content
    local content
    content=$(<"$filepath")

    # Detect all credentials
    local detections
    if ! detections=$(detect_in_file "$filepath"); then
        echo "No credentials detected in file."
        return 0
    fi

    # Redact each detection
    local detection cred_type match marker
    while IFS= read -r detection; do
        cred_type=$(echo "$detection" | jq -r '.type')
        match=$(echo "$detection" | jq -r '.match')
        marker=$(_get_redaction_marker "$cred_type")

        content=$(_redact_match "$content" "$match" "$marker")
        (( _REDACT_STATS["total_redactions"]++ )) || true

        _log_redaction "redact" "$filepath" "$cred_type" "success"
    done < <(echo "$detections" | jq -c '.[]')

    # Write redacted content back
    echo "$content" > "$filepath"
    (( _REDACT_STATS["files_processed"]++ )) || true

    return 0
}

# Redact with automatic backup (SAFE)
redact_with_backup() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Create backup first
    local backup_path
    if ! backup_path=$(_create_backup "$filepath"); then
        echo "ERROR: Failed to create backup, aborting redaction" >&2
        return 1
    fi

    echo "Backup created: $backup_path"

    # Perform redaction
    if redact_file "$filepath"; then
        echo "Redaction complete."
        _log_redaction "redact_with_backup" "$filepath" "multiple" "success"
        return 0
    else
        echo "ERROR: Redaction failed, restoring from backup" >&2
        _restore_backup "$filepath" "$backup_path"
        _log_redaction "redact_with_backup" "$filepath" "multiple" "failed"
        return 1
    fi
}

# Preview redactions in a file without modifying it
redact_preview_file() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Detect all credentials
    local detections
    if ! detections=$(detect_in_file "$filepath"); then
        echo "No credentials detected in file: $filepath"
        return 0
    fi

    echo "=== REDACTION PREVIEW FOR: $filepath ==="
    echo ""

    # Show each detection
    local detection cred_type severity line_num
    local count=0
    while IFS= read -r detection; do
        (( count++ )) || true
        cred_type=$(echo "$detection" | jq -r '.type')
        severity=$(echo "$detection" | jq -r '.severity')
        line_num=$(echo "$detection" | jq -r '.line')

        echo "[$count] Line $line_num: $cred_type ($severity severity)"
    done < <(echo "$detections" | jq -c '.[]')

    echo ""
    echo "Total credentials found: $count"
    echo ""
    echo "Use 'redact_with_backup \"$filepath\"' to redact with automatic backup."

    return 0
}

# ============================================================================
# Public API: Backup Management
# ============================================================================

# List all backups for a file
redact_list_backups() {
    local filepath="$1"

    local backups
    backups=$(_list_backups "$filepath")

    if [[ -z "$backups" ]]; then
        echo "No backups found for: $filepath"
        return 1
    fi

    echo "=== BACKUPS FOR: $filepath ==="
    echo "$backups"
    return 0
}

# Restore from latest backup
redact_restore_latest() {
    local filepath="$1"

    local latest_backup
    latest_backup=$(_list_backups "$filepath" | head -1)

    if [[ -z "$latest_backup" ]]; then
        echo "ERROR: No backups found for: $filepath" >&2
        return 1
    fi

    _restore_backup "$filepath" "$latest_backup"
}

# Restore from specific backup
redact_restore_from() {
    local filepath="$1"
    local backup_path="$2"

    _restore_backup "$filepath" "$backup_path"
}

# Clean old backups (keep only N most recent)
redact_cleanup_backups() {
    local filepath="$1"
    local keep_count="${2:-5}"  # Default: keep 5 most recent

    local backups
    backups=$(_list_backups "$filepath")

    if [[ -z "$backups" ]]; then
        echo "No backups to clean up."
        return 0
    fi

    # Count backups
    local total_backups
    total_backups=$(echo "$backups" | wc -l)

    if [[ $total_backups -le $keep_count ]]; then
        echo "Only $total_backups backup(s) exist, nothing to clean up."
        return 0
    fi

    # Delete old backups
    local deleted=0
    echo "$backups" | tail -n +$((keep_count + 1)) | while IFS= read -r backup; do
        if rm "$backup"; then
            (( deleted++ )) || true
            echo "Deleted old backup: $backup"
        fi
    done

    echo "Cleanup complete. Kept $keep_count most recent backup(s)."
    return 0
}

# ============================================================================
# Public API: Statistics and Reporting
# ============================================================================

# Get redaction statistics
redact_get_stats() {
    jq -n \
        --arg total "${_REDACT_STATS[total_redactions]}" \
        --arg files "${_REDACT_STATS[files_processed]}" \
        --arg strings "${_REDACT_STATS[strings_redacted]}" \
        --arg backups "${_REDACT_STATS[backups_created]}" \
        --arg errors "${_REDACT_STATS[errors]}" \
        '{
            total_redactions: ($total | tonumber),
            files_processed: ($files | tonumber),
            strings_redacted: ($strings | tonumber),
            backups_created: ($backups | tonumber),
            errors: ($errors | tonumber)
        }'
}

# Reset statistics
redact_reset_stats() {
    _REDACT_STATS["total_redactions"]=0
    _REDACT_STATS["files_processed"]=0
    _REDACT_STATS["strings_redacted"]=0
    _REDACT_STATS["backups_created"]=0
    _REDACT_STATS["errors"]=0
}

# View redaction log
redact_view_log() {
    local lines="${1:-50}"  # Default: show last 50 lines

    if [[ ! -f "$REDACTION_LOG" ]]; then
        echo "No redaction log found."
        return 1
    fi

    echo "=== REDACTION LOG (last $lines entries) ==="
    tail -n "$lines" "$REDACTION_LOG"
}

# ============================================================================
# Public API: Interactive Redaction
# ============================================================================

# Interactive file redaction with user prompts
redact_interactive() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    # Preview first
    redact_preview_file "$filepath"

    # Ask user
    echo ""
    echo -n "Proceed with redaction? (y/n): "
    read -r choice

    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "Redaction cancelled."
        return 0
    fi

    # Redact with backup
    redact_with_backup "$filepath"
}

# ============================================================================
# Module Info
# ============================================================================

redact_version() {
    echo "WoW Credential Redactor v5.0.1"
}

# Auto-initialize on source
redact_init
