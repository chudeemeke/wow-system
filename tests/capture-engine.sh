#!/bin/bash
# WoW System - Capture Engine
# Real-time frustration detection and pattern analysis
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Event-driven: Integrates with event-bus for real-time detection
# - Pattern recognition: Analyzes sequences of frustration events
# - User sovereignty: Respects cooldown periods and user preferences
# - Fail-safe: Graceful degradation on errors
# - Context-aware: Provides confidence scoring for intelligent prompting

# Prevent double-sourcing
if [[ -n "${WOW_CAPTURE_ENGINE_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_CAPTURE_ENGINE_LOADED=1

# Source dependencies
_CAPTURE_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_CAPTURE_ENGINE_DIR}/../core/utils.sh"
source "${_CAPTURE_ENGINE_DIR}/../core/session-manager.sh"
source "${_CAPTURE_ENGINE_DIR}/../patterns/event-bus.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly CAPTURE_VERSION="1.0.0"

# Event types we monitor
readonly EVENT_HANDLER_BLOCKED="handler.blocked"
readonly EVENT_HANDLER_ERROR="handler.error"
readonly EVENT_HANDLER_RETRY="handler.retry"
readonly EVENT_PATH_ISSUE="path.issue"
readonly EVENT_SECURITY_CREDENTIAL="security.credential"
readonly EVENT_WORKAROUND="workaround.detected"

# Thresholds
readonly FRUSTRATION_THRESHOLD=3           # Prompt after N frustrations
readonly RAPID_FIRE_THRESHOLD=4            # N events in short time = rapid-fire
readonly RAPID_FIRE_WINDOW=60              # Seconds to consider "rapid-fire"
readonly PROMPT_COOLDOWN=300               # 5 minutes between prompts
readonly EVENT_RECENCY_WINDOW=300          # Only consider events from last 5 minutes

# Confidence levels
readonly CONFIDENCE_CRITICAL="CRITICAL"
readonly CONFIDENCE_HIGH="HIGH"
readonly CONFIDENCE_MEDIUM="MEDIUM"
readonly CONFIDENCE_LOW="LOW"

# Pattern types
readonly PATTERN_REPEATED_ERROR="repeated_error"
readonly PATTERN_RAPID_FIRE="rapid_fire"
readonly PATTERN_WORKAROUND="workaround_attempt"
readonly PATTERN_PATH="path_pattern"
readonly PATTERN_NONE="none"

# Namespaces for session storage
readonly CAPTURE_NS="capture:"
readonly FRUSTRATION_NS="frustration:"

# Global variable to store last frustration ID (avoids subshell issues)
CAPTURE_LAST_FRUSTRATION_ID=""

# ============================================================================
# Initialization
# ============================================================================

# Initialize capture engine
capture_engine_init() {
    wow_debug "Initializing capture engine v${CAPTURE_VERSION}"

    # Initialize session state
    _capture_init_state

    # Subscribe to event bus events
    _capture_subscribe_events

    wow_debug "Capture engine initialized"
    return 0
}

# Initialize capture state (private)
_capture_init_state() {
    # Always initialize/reset state for each session
    session_update_metric "frustration_count" "0"
    session_update_metric "last_prompt_at" "0"
    session_update_metric "last_frustration_at" "0"
    session_update_metric "total_frustrations_captured" "0"

    return 0
}

# Subscribe to event bus events (private)
_capture_subscribe_events() {
    event_bus_subscribe "${EVENT_HANDLER_BLOCKED}" "_capture_on_handler_blocked"
    event_bus_subscribe "${EVENT_HANDLER_ERROR}" "_capture_on_handler_error"
    event_bus_subscribe "${EVENT_HANDLER_RETRY}" "_capture_on_handler_retry"
    event_bus_subscribe "${EVENT_PATH_ISSUE}" "_capture_on_path_issue"
    event_bus_subscribe "${EVENT_SECURITY_CREDENTIAL}" "_capture_on_security_issue"
    event_bus_subscribe "${EVENT_WORKAROUND}" "_capture_on_workaround"

    return 0
}

# ============================================================================
# Event Bus Callback Handlers (Private)
# ============================================================================

# Handler blocked callback
_capture_on_handler_blocked() {
    local event_data="$1"

    # Parse event data (format: key=value|key=value)
    local handler context operation path
    handler=$(echo "${event_data}" | grep -oP 'handler=\K[^|]+' || echo "unknown")
    operation=$(echo "${event_data}" | grep -oP 'operation=\K[^|]+' || echo "unknown")
    path=$(echo "${event_data}" | grep -oP 'path=\K[^|]+' || echo "")

    local details="operation=${operation}|path=${path}"
    capture_detect_event "${EVENT_HANDLER_BLOCKED}" "${handler}" "${details}" 2>/dev/null || true
}

# Handler error callback
_capture_on_handler_error() {
    local event_data="$1"

    local handler error_type path
    handler=$(echo "${event_data}" | grep -oP 'handler=\K[^|]+' || echo "unknown")
    error_type=$(echo "${event_data}" | grep -oP 'error=\K[^|]+' || echo "unknown")
    path=$(echo "${event_data}" | grep -oP 'path=\K[^|]+' || echo "")

    local details="error=${error_type}|path=${path}"
    capture_detect_event "${EVENT_HANDLER_ERROR}" "${handler}" "${details}" 2>/dev/null || true
}

# Handler retry callback
_capture_on_handler_retry() {
    local event_data="$1"

    local handler reason
    handler=$(echo "${event_data}" | grep -oP 'handler=\K[^|]+' || echo "unknown")
    reason=$(echo "${event_data}" | grep -oP 'reason=\K[^|]+' || echo "retry")

    local details="reason=${reason}"
    capture_detect_event "${EVENT_HANDLER_RETRY}" "${handler}" "${details}" 2>/dev/null || true
}

# Path issue callback
_capture_on_path_issue() {
    local event_data="$1"
    capture_detect_event "${EVENT_PATH_ISSUE}" "${event_data}" "path_problem" 2>/dev/null || true
}

# Security issue callback
_capture_on_security_issue() {
    local event_data="$1"
    capture_detect_event "${EVENT_SECURITY_CREDENTIAL}" "${event_data}" "credential_exposed" 2>/dev/null || true
}

# Workaround detected callback
_capture_on_workaround() {
    local event_data="$1"
    capture_detect_event "${EVENT_WORKAROUND}" "${event_data}" "manual_workaround" 2>/dev/null || true
}

# ============================================================================
# Event Detection (Public API)
# ============================================================================

# Detect and record a frustration-worthy event
# Sets: CAPTURE_LAST_FRUSTRATION_ID (global variable - use this to get the ID)
# NOTE: This function modifies global state, so call it directly (not via command substitution)
# Example: capture_detect_event "event" "context" "details"; frust_id="${CAPTURE_LAST_FRUSTRATION_ID}"
capture_detect_event() {
    local event_type="$1"
    local context="${2:-}"
    local details="${3:-}"

    # Generate frustration ID
    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "0")
    frustration_count=$((frustration_count + 1))

    local timestamp
    timestamp=$(date +%s)
    local frustration_id="frust_${frustration_count}_${timestamp}"

    # Store frustration details
    local frustration_data="event=${event_type}|context=${context}|details=${details}|timestamp=${timestamp}"
    session_update_metric "${FRUSTRATION_NS}${frustration_id}" "${frustration_data}"

    # Update counters
    session_update_metric "frustration_count" "${frustration_count}"
    session_update_metric "last_frustration_at" "${timestamp}"
    session_increment_metric "total_frustrations_captured"

    # Track as session event
    session_track_event "frustration_detected" "${frustration_id}|${event_type}"

    wow_debug "Frustration detected: ${event_type} (ID: ${frustration_id})"

    # Store in global variable for retrieval by caller
    CAPTURE_LAST_FRUSTRATION_ID="${frustration_id}"

    return 0
}

# ============================================================================
# Pattern Analysis (Public API)
# ============================================================================

# Analyze frustration patterns
# Returns: pattern type (repeated_error, rapid_fire, workaround_attempt, path_pattern, none)
capture_analyze_pattern() {
    local current_time
    current_time=$(date +%s)

    # Get recent frustrations (within recency window)
    local recent_frustrations=()
    local all_metrics
    all_metrics=$(session_get_metrics)

    while IFS= read -r line; do
        if [[ "${line}" =~ ^frustration: ]]; then
            local key="${line%%=*}"
            local value="${line#*=}"

            # Extract timestamp
            local frust_timestamp
            frust_timestamp=$(echo "${value}" | grep -oP 'timestamp=\K[0-9]+' || echo "0")

            # Check if within recency window
            local age=$((current_time - frust_timestamp))
            if [[ ${age} -le ${EVENT_RECENCY_WINDOW} ]]; then
                recent_frustrations+=("${value}")
            fi
        fi
    done <<< "${all_metrics}"

    local count=${#recent_frustrations[@]}

    # No pattern if too few events
    if [[ ${count} -lt 2 ]]; then
        echo "${PATTERN_NONE}"
        return 0
    fi

    # Check for rapid-fire pattern
    if [[ ${count} -ge ${RAPID_FIRE_THRESHOLD} ]]; then
        local oldest_timestamp
        oldest_timestamp=$(echo "${recent_frustrations[0]}" | grep -oP 'timestamp=\K[0-9]+' || echo "0")
        local newest_timestamp
        newest_timestamp=$(echo "${recent_frustrations[$((count-1))]}" | grep -oP 'timestamp=\K[0-9]+' || echo "${current_time}")

        local time_span=$((newest_timestamp - oldest_timestamp))
        if [[ ${time_span} -le ${RAPID_FIRE_WINDOW} ]]; then
            echo "${PATTERN_RAPID_FIRE}"
            return 0
        fi
    fi

    # Check for repeated error pattern
    local error_types=()
    local error_counts=()

    for frustration in "${recent_frustrations[@]}"; do
        local event_type
        event_type=$(echo "${frustration}" | grep -oP 'event=\K[^|]+' || echo "")
        local details
        details=$(echo "${frustration}" | grep -oP 'details=\K[^|]+' || echo "")

        # Count similar errors
        local signature="${event_type}:${details}"
        local found=false
        for i in "${!error_types[@]}"; do
            if [[ "${error_types[$i]}" == "${signature}" ]]; then
                error_counts[$i]=$((${error_counts[$i]} + 1))
                found=true
                break
            fi
        done

        if [[ "${found}" == "false" ]]; then
            error_types+=("${signature}")
            error_counts+=(1)
        fi
    done

    # Check if any error repeats 3+ times
    for count_val in "${error_counts[@]}"; do
        if [[ ${count_val} -ge 3 ]]; then
            echo "${PATTERN_REPEATED_ERROR}"
            return 0
        fi
    done

    # Check for workaround pattern (blocked -> workaround -> blocked)
    local has_block=false
    local has_workaround=false
    for frustration in "${recent_frustrations[@]}"; do
        if echo "${frustration}" | grep -q "event=${EVENT_HANDLER_BLOCKED}"; then
            has_block=true
        fi
        if echo "${frustration}" | grep -q "event=${EVENT_WORKAROUND}"; then
            has_workaround=true
        fi
    done

    if [[ "${has_block}" == "true" ]] && [[ "${has_workaround}" == "true" ]]; then
        echo "${PATTERN_WORKAROUND}"
        return 0
    fi

    # Check for path pattern (multiple path issues)
    local path_count=0
    for frustration in "${recent_frustrations[@]}"; do
        if echo "${frustration}" | grep -q "event=${EVENT_PATH_ISSUE}"; then
            path_count=$((path_count + 1))
        fi
    done

    if [[ ${path_count} -ge 2 ]]; then
        echo "${PATTERN_PATH}"
        return 0
    fi

    # Default: no clear pattern
    echo "${PATTERN_NONE}"
    return 0
}

# ============================================================================
# Prompting Decision (Public API)
# ============================================================================

# Determine if user should be prompted for feedback
# Returns: "true" or "false"
capture_should_prompt() {
    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "0")

    # Check cooldown period
    local last_prompt_at
    last_prompt_at=$(session_get_metric "last_prompt_at" "0")
    local current_time
    current_time=$(date +%s)
    local time_since_prompt=$((current_time - last_prompt_at))

    if [[ ${time_since_prompt} -lt ${PROMPT_COOLDOWN} ]]; then
        echo "false"
        return 0
    fi

    # Check for critical patterns (always prompt)
    local pattern
    pattern=$(capture_analyze_pattern)

    # Security issues are critical - always prompt
    local recent_security=false
    local all_metrics
    all_metrics=$(session_get_metrics)

    while IFS= read -r line; do
        if [[ "${line}" =~ ^frustration: ]] && [[ "${line}" =~ event=${EVENT_SECURITY_CREDENTIAL} ]]; then
            local frust_timestamp
            frust_timestamp=$(echo "${line#*=}" | grep -oP 'timestamp=\K[0-9]+' || echo "0")
            local age=$((current_time - frust_timestamp))
            if [[ ${age} -le ${EVENT_RECENCY_WINDOW} ]]; then
                recent_security=true
                break
            fi
        fi
    done <<< "${all_metrics}"

    if [[ "${recent_security}" == "true" ]]; then
        echo "true"
        return 0
    fi

    # Prompt if threshold met
    if [[ ${frustration_count} -ge ${FRUSTRATION_THRESHOLD} ]]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 0
}

# ============================================================================
# Confidence Scoring (Public API)
# ============================================================================

# Get confidence level for current frustration state
# Returns: CRITICAL, HIGH, MEDIUM, LOW
capture_get_confidence() {
    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "0")

    local current_time
    current_time=$(date +%s)

    # Check for security issues (critical)
    local all_metrics
    all_metrics=$(session_get_metrics)

    local has_recent_security=false
    while IFS= read -r line; do
        if [[ "${line}" =~ ^frustration: ]] && [[ "${line}" =~ event=${EVENT_SECURITY_CREDENTIAL} ]]; then
            local frust_timestamp
            frust_timestamp=$(echo "${line#*=}" | grep -oP 'timestamp=\K[0-9]+' || echo "0")
            local age=$((current_time - frust_timestamp))
            if [[ ${age} -le ${EVENT_RECENCY_WINDOW} ]]; then
                has_recent_security=true
                break
            fi
        fi
    done <<< "${all_metrics}"

    if [[ "${has_recent_security}" == "true" ]]; then
        echo "${CONFIDENCE_CRITICAL}"
        return 0
    fi

    # Analyze pattern
    local pattern
    pattern=$(capture_analyze_pattern)

    # High confidence for clear patterns
    if [[ "${pattern}" == "${PATTERN_REPEATED_ERROR}" ]]; then
        echo "${CONFIDENCE_HIGH}"
        return 0
    fi

    if [[ "${pattern}" == "${PATTERN_RAPID_FIRE}" ]]; then
        echo "${CONFIDENCE_HIGH}"
        return 0
    fi

    # Medium confidence for multiple different events
    if [[ ${frustration_count} -ge 3 ]]; then
        echo "${CONFIDENCE_MEDIUM}"
        return 0
    fi

    # Boost confidence for 2 recent events (not just single event)
    if [[ ${frustration_count} -ge 2 ]]; then
        echo "${CONFIDENCE_MEDIUM}"
        return 0
    fi

    # Low confidence for single event
    echo "${CONFIDENCE_LOW}"
    return 0
}

# ============================================================================
# Frustration Retrieval (Public API)
# ============================================================================

# Get details of a specific frustration
capture_get_frustration() {
    local frustration_id="$1"

    local value
    value=$(session_get_metric "${FRUSTRATION_NS}${frustration_id}" "")

    echo "${value}"
    return 0
}

# Get all frustrations
capture_get_all_frustrations() {
    local all_metrics
    all_metrics=$(session_get_metrics)

    while IFS= read -r line; do
        if [[ "${line}" =~ ^frustration: ]]; then
            echo "${line}"
        fi
    done <<< "${all_metrics}"

    return 0
}

# ============================================================================
# Context Creation (Public API)
# ============================================================================

# Create comprehensive context for external systems (email, logs, etc)
# Returns JSON with version, timestamp, and system state
capture_create_context() {
    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "0")

    local pattern
    pattern=$(capture_analyze_pattern)

    local confidence
    confidence=$(capture_get_confidence)

    # Get system version for security audit
    local system_version
    system_version=$(wow_get_version 2>/dev/null || echo "${WOW_VERSION:-unknown}")

    local timestamp
    timestamp=$(date -Iseconds)

    local session_id
    session_id=$(session_get_metric "session_id" "unknown")

    # Create JSON context (if jq available)
    if wow_has_jq; then
        jq -n \
            --arg version "${system_version}" \
            --arg timestamp "${timestamp}" \
            --arg session "${session_id}" \
            --argjson frust_count "${frustration_count}" \
            --arg pattern "${pattern}" \
            --arg confidence "${confidence}" \
            '{
                system_version: $version,
                timestamp: $timestamp,
                session_id: $session,
                frustration_count: $frust_count,
                pattern_detected: $pattern,
                confidence_level: $confidence
            }'
    else
        # Fallback: simple key=value format
        cat <<EOF
system_version=${system_version}
timestamp=${timestamp}
session_id=${session_id}
frustration_count=${frustration_count}
pattern_detected=${pattern}
confidence_level=${confidence}
EOF
    fi

    return 0
}

# ============================================================================
# Reporting (Public API)
# ============================================================================

# Generate capture summary report
capture_summary() {
    local frustration_count
    frustration_count=$(session_get_metric "frustration_count" "0")

    local total_captured
    total_captured=$(session_get_metric "total_frustrations_captured" "0")

    local pattern
    pattern=$(capture_analyze_pattern)

    local confidence
    confidence=$(capture_get_confidence)

    local should_prompt
    should_prompt=$(capture_should_prompt)

    # Get system version for security audit trail
    local system_version
    system_version=$(wow_get_version 2>/dev/null || echo "${WOW_VERSION:-unknown}")

    cat <<EOF
Capture Engine Summary
======================
WoW System Version: ${system_version}
Timestamp: $(date -Iseconds)

Active Frustrations: ${frustration_count}
Total Captured: ${total_captured}

Pattern Analysis: ${pattern}
Confidence Level: ${confidence}
Should Prompt User: ${should_prompt}

Recent Frustrations:
EOF

    # List recent frustrations
    local all_frustrations
    all_frustrations=$(capture_get_all_frustrations)

    if [[ -z "${all_frustrations}" ]]; then
        echo "  (none)"
    else
        echo "${all_frustrations}" | tail -5 | while IFS= read -r line; do
            local frust_id="${line%%=*}"
            frust_id="${frust_id#frustration:}"
            local value="${line#*=}"
            local event_type
            event_type=$(echo "${value}" | grep -oP 'event=\K[^|]+' || echo "unknown")
            local context
            context=$(echo "${value}" | grep -oP 'context=\K[^|]+' || echo "unknown")

            echo "  - ${frust_id}: ${event_type} (${context})"
        done
    fi

    return 0
}

# ============================================================================
# Management (Public API)
# ============================================================================

# Clear all frustrations
capture_clear_frustrations() {
    # Reset counters
    session_update_metric "frustration_count" "0"
    session_update_metric "last_frustration_at" "0"

    # Clear all frustration entries
    local all_metrics
    all_metrics=$(session_get_metrics)

    while IFS= read -r line; do
        if [[ "${line}" =~ ^frustration: ]]; then
            local key="${line%%=*}"
            session_update_metric "${key}" ""
        fi
    done <<< "${all_metrics}"

    wow_debug "All frustrations cleared"
    return 0
}

# Reset capture engine (unsubscribe and clear state)
capture_engine_reset() {
    # Unsubscribe from events
    event_bus_unsubscribe "${EVENT_HANDLER_BLOCKED}" "_capture_on_handler_blocked"
    event_bus_unsubscribe "${EVENT_HANDLER_ERROR}" "_capture_on_handler_error"
    event_bus_unsubscribe "${EVENT_HANDLER_RETRY}" "_capture_on_handler_retry"
    event_bus_unsubscribe "${EVENT_PATH_ISSUE}" "_capture_on_path_issue"
    event_bus_unsubscribe "${EVENT_SECURITY_CREDENTIAL}" "_capture_on_security_issue"
    event_bus_unsubscribe "${EVENT_WORKAROUND}" "_capture_on_workaround"

    # Clear state
    capture_clear_frustrations

    wow_debug "Capture engine reset"
    return 0
}

# Mark that user was prompted (updates cooldown)
capture_mark_prompted() {
    local current_time
    current_time=$(date +%s)
    session_update_metric "last_prompt_at" "${current_time}"

    wow_debug "User prompted - cooldown started"
    return 0
}

# ============================================================================
# Documentation Integration
# ============================================================================

# Update project documentation using docTruth
capture_update_docs() {
    local wow_home="${WOW_HOME:-.}"

    wow_debug "Triggering documentation update via docTruth"

    # Check if doctruth is available
    if ! command -v doctruth &>/dev/null; then
        wow_warn "doctruth not installed, skipping documentation update"
        return 1
    fi

    # Check if config exists
    if [[ ! -f "${wow_home}/.doctruth.yml" ]]; then
        wow_warn "No .doctruth.yml config found, skipping documentation update"
        return 1
    fi

    # Run doctruth in background to avoid blocking
    (
        cd "${wow_home}" 2>/dev/null || exit 1
        doctruth 2>&1 | while IFS= read -r line; do
            wow_debug "doctruth: ${line}"
        done
    ) &

    session_update_metric "last_doc_update" "$(date +%s)"
    wow_debug "Documentation update triggered (running in background)"

    return 0
}

# Trigger documentation update on significant events
capture_trigger_doc_update_if_needed() {
    local event_type="$1"

    # Only trigger on significant events
    case "${event_type}" in
        version_bump|feature_added|tests_passed|session_end)
            capture_update_docs
            ;;
        *)
            # For other events, check if enough time has passed
            local last_update
            last_update=$(session_get_metric "last_doc_update" "0")
            local now=$(date +%s)
            local elapsed=$((now - last_update))

            # Update every 30 minutes if there's activity
            if [[ ${elapsed} -gt 1800 ]]; then
                capture_update_docs
            fi
            ;;
    esac
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Capture Engine v${CAPTURE_VERSION} - Self Test"
    echo "=================================================="
    echo ""

    # Initialize dependencies
    state_init
    session_start
    event_bus_init

    # Initialize capture engine
    capture_engine_init
    echo "Initialized"

    # Detect some events
    echo ""
    echo "Testing event detection..."
    capture_detect_event "${EVENT_HANDLER_BLOCKED}" "Bash" "rm_operation" >/dev/null
    frust1="${CAPTURE_LAST_FRUSTRATION_ID}"
    echo "Detected: ${frust1}"

    capture_detect_event "${EVENT_HANDLER_ERROR}" "Write" "permission_denied" >/dev/null
    frust2="${CAPTURE_LAST_FRUSTRATION_ID}"
    echo "Detected: ${frust2}"

    capture_detect_event "${EVENT_HANDLER_BLOCKED}" "Bash" "rm_operation" >/dev/null
    frust3="${CAPTURE_LAST_FRUSTRATION_ID}"
    echo "Detected: ${frust3}"

    # Test pattern analysis
    echo ""
    echo "Testing pattern analysis..."
    pattern=$(capture_analyze_pattern)
    echo "Pattern: ${pattern}"

    # Test confidence
    echo ""
    echo "Testing confidence scoring..."
    confidence=$(capture_get_confidence)
    echo "Confidence: ${confidence}"

    # Test prompting decision
    echo ""
    echo "Testing prompting decision..."
    should_prompt=$(capture_should_prompt)
    echo "Should prompt: ${should_prompt}"

    # Test event bus integration
    echo ""
    echo "Testing event bus integration..."
    event_bus_publish "${EVENT_HANDLER_ERROR}" "handler=Edit|error=EACCES|path=/etc/test"
    sleep 0.1

    # Summary
    echo ""
    capture_summary

    # Cleanup
    echo ""
    echo "Testing cleanup..."
    capture_clear_frustrations
    echo "Cleared frustrations"

    echo ""
    echo "All self-tests complete!"
fi
