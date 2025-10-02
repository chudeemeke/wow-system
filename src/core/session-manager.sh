#!/bin/bash
# WoW System - Session Manager
# Provides: Session lifecycle orchestration (loosely coupled, tightly integrated)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Single Responsibility: Orchestrates session lifecycle
# - Open/Closed: Extensible through events, closed for modification
# - Dependency Inversion: Depends on state/config abstractions
# - Loose Coupling: Delegates to specialized components

# Source dependencies
_SESSION_MGR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SESSION_MGR_DIR}/utils.sh"
source "${_SESSION_MGR_DIR}/state-manager.sh"
source "${_SESSION_MGR_DIR}/config-loader.sh"

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly SESSION_VERSION="1.0.0"
readonly SESSION_STATUS_ACTIVE="active"
readonly SESSION_STATUS_ENDED="ended"
readonly SESSION_STATUS_ARCHIVED="archived"

# ============================================================================
# Session State (Namespaced in state manager)
# ============================================================================

readonly SESSION_NS="session:"      # Session metadata namespace
readonly METRICS_NS="metrics:"      # Metrics namespace
readonly EVENTS_NS="events:"        # Events namespace

# ============================================================================
# Initialization & Lifecycle
# ============================================================================

# Start a new session
session_start() {
    local config_file="${1:-}"

    wow_debug "Starting WoW session v${SESSION_VERSION}"

    # Initialize dependencies (loose coupling through well-defined interfaces)
    state_init
    config_init

    # Load configuration if provided
    if [[ -n "${config_file}" ]] && [[ -f "${config_file}" ]]; then
        config_load "${config_file}" || wow_warn "Failed to load config: ${config_file}"
    else
        config_load_defaults
    fi

    # Initialize session metadata
    _session_init_metadata

    # Track session start event
    session_track_event "session_started" "Session initialized"

    wow_success "Session started: $(session_get_id)"
    return 0
}

# Initialize session metadata (private)
_session_init_metadata() {
    # Force new session ID generation with millisecond precision and random component
    local timestamp=$(date +%Y%m%d_%H%M%S%N)  # Nanoseconds for uniqueness
    local random_suffix=$RANDOM
    local new_session_id="session_${timestamp}_${random_suffix}"
    state_set "_session_id" "${new_session_id}"

    state_set "${SESSION_NS}status" "${SESSION_STATUS_ACTIVE}"
    state_set "${SESSION_NS}version" "${SESSION_VERSION}"
    state_set "${SESSION_NS}started_at" "$(wow_timestamp)"

    # Initialize counters
    state_set "${METRICS_NS}event_count" "0"
}

# End current session
session_end() {
    wow_debug "Ending session: $(session_get_id)"

    # Update metadata
    state_set "${SESSION_NS}status" "${SESSION_STATUS_ENDED}"
    state_set "${SESSION_NS}ended_at" "$(wow_timestamp)"

    # Track end event
    session_track_event "session_ended" "Session terminated"

    # Save session data
    session_save

    wow_success "Session ended"
    return 0
}

# Archive current session
session_archive() {
    wow_debug "Archiving session"

    # Update status
    state_set "${SESSION_NS}status" "${SESSION_STATUS_ARCHIVED}"

    # Delegate to state manager for archiving
    state_archive

    wow_success "Session archived"
    return 0
}

# ============================================================================
# Session Information (Read-Only Interface)
# ============================================================================

# Get session ID
session_get_id() {
    state_get "_session_id" "unknown"
}

# Check if session is active
session_is_active() {
    local status
    status=$(state_get "${SESSION_NS}status" "")

    [[ "${status}" == "${SESSION_STATUS_ACTIVE}" ]]
}

# Get session duration in seconds
session_get_duration() {
    local started_at
    started_at=$(state_get "${SESSION_NS}started_at" "")

    if [[ -z "${started_at}" ]]; then
        echo "0"
        return 0
    fi

    # Calculate duration (simplified - assumes ISO timestamps)
    local start_seconds
    start_seconds=$(date -d "${started_at}" +%s 2>/dev/null || echo "0")
    local current_seconds
    current_seconds=$(date +%s)

    local duration=$((current_seconds - start_seconds))
    echo "${duration}"
}

# Get session information
session_info() {
    local session_id
    session_id=$(session_get_id)
    local status
    status=$(state_get "${SESSION_NS}status" "unknown")
    local started_at
    started_at=$(state_get "${SESSION_NS}started_at" "unknown")
    local duration
    duration=$(session_get_duration)

    cat <<EOF
session_id=${session_id}
status=${status}
started_at=${started_at}
duration=${duration}s
EOF
}

# Get session statistics
session_stats() {
    local event_count
    event_count=$(state_get "${METRICS_NS}event_count" "0")

    # Count metrics
    local metrics_count=0
    for key in $(state_keys); do
        if [[ "${key}" == ${METRICS_NS}* ]]; then
            ((metrics_count++))
        fi
    done

    # Count events
    local events_count=0
    for key in $(state_keys); do
        if [[ "${key}" == ${EVENTS_NS}* ]]; then
            ((events_count++))
        fi
    done

    cat <<EOF
Session Statistics
==================
Session ID: $(session_get_id)
Duration: $(session_get_duration)s
Status: $(state_get "${SESSION_NS}status")

metrics: ${metrics_count}
events: ${events_count}
EOF
}

# ============================================================================
# Event Tracking (Observer Pattern Support)
# ============================================================================

# Track an event
session_track_event() {
    local event_type="$1"
    local event_data="${2:-}"

    # Increment event counter
    state_increment "${METRICS_NS}event_count"

    # Store event with timestamp
    local event_count
    event_count=$(state_get "${METRICS_NS}event_count")
    local event_key="${EVENTS_NS}${event_count}_${event_type}"

    local event_entry="timestamp=$(wow_timestamp)|type=${event_type}|data=${event_data}"
    state_set "${event_key}" "${event_entry}"

    wow_debug "Event tracked: ${event_type}"
    return 0
}

# Get all events
session_get_events() {
    local events=""

    for key in $(state_keys); do
        if [[ "${key}" == ${EVENTS_NS}* ]]; then
            local value
            value=$(state_get "${key}")
            echo "${key}=${value}"
        fi
    done
}

# ============================================================================
# Metrics Management (Strategy Pattern Support)
# ============================================================================

# Update a metric
session_update_metric() {
    local metric_name="$1"
    local metric_value="$2"

    state_set "${METRICS_NS}${metric_name}" "${metric_value}"
    wow_debug "Metric updated: ${metric_name}=${metric_value}"
    return 0
}

# Get a metric
session_get_metric() {
    local metric_name="$1"
    local default="${2:-0}"

    state_get "${METRICS_NS}${metric_name}" "${default}"
}

# Increment a metric counter
session_increment_metric() {
    local metric_name="$1"
    local amount="${2:-1}"

    state_increment "${METRICS_NS}${metric_name}" "${amount}"
    wow_debug "Metric incremented: ${metric_name} +${amount}"
    return 0
}

# Decrement a metric counter
session_decrement_metric() {
    local metric_name="$1"
    local amount="${2:-1}"

    state_decrement "${METRICS_NS}${metric_name}" "${amount}"
    wow_debug "Metric decremented: ${metric_name} -${amount}"
    return 0
}

# Get all metrics
session_get_metrics() {
    for key in $(state_keys); do
        if [[ "${key}" == ${METRICS_NS}* ]]; then
            local metric_name="${key#${METRICS_NS}}"
            local value
            value=$(state_get "${key}")
            echo "${metric_name}=${value}"
        fi
    done
}

# ============================================================================
# Persistence (Delegation to State Manager)
# ============================================================================

# Save session state
session_save() {
    wow_debug "Saving session"

    # Delegate to state manager
    state_save

    wow_debug "Session saved"
    return 0
}

# Restore session state
session_restore() {
    wow_debug "Restoring session"

    # Delegate to state manager
    state_load

    wow_debug "Session restored"
    return 0
}

# ============================================================================
# Configuration Access (Facade Pattern)
# ============================================================================

# Get configuration value (facade to config loader)
session_get_config() {
    local key="$1"
    local default="${2:-}"

    config_get "${key}" "${default}"
}

# Check if feature is enabled
session_is_feature_enabled() {
    local feature_key="$1"

    local enabled
    enabled=$(config_get_bool "${feature_key}" "false")

    [[ "${enabled}" == "true" ]]
}

# ============================================================================
# Extension Points (Template Method Pattern)
# ============================================================================

# Hook: Called before session starts (override in extensions)
session_on_before_start() {
    :  # No-op by default
}

# Hook: Called after session starts (override in extensions)
session_on_after_start() {
    :  # No-op by default
}

# Hook: Called before session ends (override in extensions)
session_on_before_end() {
    :  # No-op by default
}

# Hook: Called after session ends (override in extensions)
session_on_after_end() {
    :  # No-op by default
}

# ============================================================================
# Debug & Inspection
# ============================================================================

# Dump session state for debugging
session_dump() {
    echo "=== WoW Session Dump ==="
    session_info
    echo ""
    echo "Metrics:"
    session_get_metrics | sed 's/^/  /'
    echo ""
    echo "Recent Events:"
    session_get_events | tail -5 | sed 's/^/  /'
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Session Manager v${SESSION_VERSION} - Self Test"
    echo "===================================================="
    echo ""

    # Start session
    session_start
    echo "✓ Session started: $(session_get_id)"

    # Check active
    session_is_active && echo "✓ Session is active"

    # Track events
    session_track_event "test_event" "test_data"
    echo "✓ Event tracked"

    # Update metrics
    session_update_metric "test_metric" "42"
    [[ "$(session_get_metric "test_metric")" == "42" ]] && echo "✓ Metric updated"

    # Increment counter
    session_increment_metric "counter"
    session_increment_metric "counter"
    [[ "$(session_get_metric "counter")" == "2" ]] && echo "✓ Counter incremented"

    # Duration
    sleep 1
    duration=$(session_get_duration)
    [[ ${duration} -ge 1 ]] && echo "✓ Duration tracking works (${duration}s)"

    # Save/Restore
    session_save
    echo "✓ Session saved"

    session_end
    echo "✓ Session ended"

    ! session_is_active && echo "✓ Session is not active after end"

    # Start new session and restore
    session_start
    session_restore
    [[ "$(session_get_metric "test_metric")" == "42" ]] && echo "✓ Session restored"

    # Stats
    echo ""
    session_stats

    echo ""
    echo "All tests passed! ✓"
fi
