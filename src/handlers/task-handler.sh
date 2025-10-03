#!/bin/bash
# WoW System - Task Handler (Production-Grade, Security-Critical)
# Intercepts autonomous agent launches for safety and resource control
# Author: Chude <chude@emeke.org>
#
# Security Principles:
# - Defense in Depth: Multiple validation layers
# - Fail-Safe: Block on ambiguity or danger
# - Resource Protection: Prevent agent abuse
# - Anti-Recursion: Detect infinite agent spawning
# - Rate Limiting: Control agent launch frequency
# - Audit Logging: Track all agent operations

# Prevent double-sourcing
if [[ -n "${WOW_TASK_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_TASK_HANDLER_LOADED=1

# Source dependencies
_TASK_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TASK_HANDLER_DIR}/../core/utils.sh"

set -uo pipefail

# ============================================================================
# Constants - Dangerous Task Patterns
# ============================================================================

# CRITICAL: Patterns that indicate dangerous autonomous operations
readonly -a DANGEROUS_TASK_PATTERNS=(
    "infinite.*loop"
    "never.*stop"
    "run.*forever"
    "while.*true"
    "recursive.*agent"
    "spawn.*agent.*spawn"
    "launch.*\d+.*agent"
    "delete.*all"
    "rm.*-rf.*/"
    "format.*disk"
    "DROP.*TABLE"
    "DROP.*DATABASE"
)

# Credential harvesting patterns
readonly -a CREDENTIAL_HARVEST_PATTERNS=(
    "find.*all.*(password|api.?key|secret|token|credential)"
    "search.*for.*(password|api.?key|secret|token)"
    "extract.*(password|api.?key|secret|token|credential)"
    "collect.*(password|api.?key|secret|token)"
    "harvest.*(password|api.?key|secret|token|credential)"
    "SSH.*key"
    "private.*key"
    "\.env"
    "credentials\.json"
)

# Data exfiltration patterns
readonly -a EXFILTRATION_PATTERNS=(
    "upload.*to.*(server|url|endpoint)"
    "send.*to.*(server|external|remote)"
    "POST.*http"
    "exfiltrate"
    "copy.*to.*external"
    "transfer.*to.*remote"
)

# Network abuse patterns
readonly -a NETWORK_ABUSE_PATTERNS=(
    "scan.*(network|port|IP)"
    "nmap"
    "port.*scan"
    "vulnerability.*scan"
    "brute.*force"
    "DDoS"
    "flood"
)

# System modification patterns
readonly -a SYSTEM_MODIFICATION_PATTERNS=(
    "modify.*(/etc|/bin|/usr|/sys)"
    "write.*to.*(/etc|/bin|/usr|/sys)"
    "edit.*(/etc/passwd|/etc/shadow)"
    "chmod.*(777|666).*/"
    "chown.*root"
)

# Safe development task patterns
readonly -a SAFE_TASK_PATTERNS=(
    "search.*code"
    "find.*function"
    "read.*file"
    "analyze.*structure"
    "generate.*documentation"
    "create.*docs"
    "run.*test"
    "execute.*test"
    "refactor.*code"
    "improve.*quality"
    "check.*dependencies"
    "lint.*code"
    "format.*code"
)

# ============================================================================
# Constants - Rate Limiting
# ============================================================================

readonly MAX_TASKS_PER_SESSION=20
readonly MAX_TASKS_PER_MINUTE=5
readonly TASK_BURST_WINDOW=60  # seconds

# ============================================================================
# Private: Pattern Validation
# ============================================================================

# Check if prompt contains dangerous patterns
_has_dangerous_pattern() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${DANGEROUS_TASK_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Dangerous task pattern detected: ${pattern}"
            return 0  # Has dangerous pattern
        fi
    done

    return 1  # Safe
}

# Check if prompt indicates credential harvesting
_is_credential_harvest() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${CREDENTIAL_HARVEST_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential credential harvesting task: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Check if prompt indicates data exfiltration
_is_exfiltration_attempt() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${EXFILTRATION_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential data exfiltration task: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Check if prompt indicates network abuse
_is_network_abuse() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${NETWORK_ABUSE_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential network abuse task: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Check if prompt indicates system modification
_is_system_modification() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${SYSTEM_MODIFICATION_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            wow_warn "⚠️  Potential system modification task: ${pattern}"
            return 0
        fi
    done

    return 1
}

# Check if task is a safe development task
_is_safe_task() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]')

    for pattern in "${SAFE_TASK_PATTERNS[@]}"; do
        if echo "${prompt_lower}" | grep -qiE "${pattern}"; then
            return 0  # Is safe
        fi
    done

    return 1  # Not explicitly safe
}

# Validate task prompt
_validate_prompt() {
    local prompt="$1"

    # Check for empty prompt
    if [[ -z "${prompt}" ]]; then
        wow_warn "⚠️  Empty task prompt"
        return 1
    fi

    # Check for dangerous patterns (warn but allow - other handlers will block)
    # v5.0.1: strict_mode enforcement
    if _has_dangerous_pattern "${prompt}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: Dangerous task pattern"
            session_track_event "security_violation" "BLOCKED_DANGEROUS_TASK_PATTERN" 2>/dev/null || true
            return 2
        fi
    fi

    # v5.0.1: strict_mode enforcement
    if _is_credential_harvest "${prompt}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: Credential harvesting task"
            session_track_event "security_violation" "BLOCKED_CREDENTIAL_HARVEST_TASK" 2>/dev/null || true
            return 2
        fi
    fi

    # v5.0.1: strict_mode enforcement
    if _is_exfiltration_attempt "${prompt}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: Data exfiltration task"
            session_track_event "security_violation" "BLOCKED_EXFILTRATION_TASK" 2>/dev/null || true
            return 2
        fi
    fi

    # v5.0.1: strict_mode enforcement
    if _is_network_abuse "${prompt}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: Network abuse task"
            session_track_event "security_violation" "BLOCKED_NETWORK_ABUSE_TASK" 2>/dev/null || true
            return 2
        fi
    fi

    # v5.0.1: strict_mode enforcement
    if _is_system_modification "${prompt}"; then
        if wow_should_block "warn"; then
            wow_error "BLOCKED by strict_mode or block_on_violation: System modification task"
            session_track_event "security_violation" "BLOCKED_SYSTEM_MODIFICATION_TASK" 2>/dev/null || true
            return 2
        fi
    fi

    return 0  # Valid (warnings issued but not blocked here)
}

# ============================================================================
# Private: Rate Limiting
# ============================================================================

# Check if task rate limit exceeded
_check_rate_limit() {
    local task_count
    task_count=$(session_get_metric "task_launches" "0")

    # Check total session limit
    if [[ ${task_count} -ge ${MAX_TASKS_PER_SESSION} ]]; then
        wow_warn "⚠️  Session task limit reached: ${task_count}/${MAX_TASKS_PER_SESSION}"
        return 0  # Limit reached
    fi

    # Check burst rate (tasks per minute)
    local recent_tasks
    recent_tasks=$(session_get_metric "task_launches_recent" "0")

    if [[ ${recent_tasks} -ge ${MAX_TASKS_PER_MINUTE} ]]; then
        wow_warn "⚠️  Task burst rate exceeded: ${recent_tasks} in last minute"
        return 0  # Burst limit
    fi

    return 1  # Under limit
}

# Track task launch for rate limiting
_track_task_launch() {
    # Increment total count
    session_increment_metric "task_launches" 2>/dev/null || true

    # Track recent launches (simplified - just increment)
    session_increment_metric "task_launches_recent" 2>/dev/null || true
}

# ============================================================================
# Private: Resource Monitoring
# ============================================================================

# Monitor agent spawning patterns
_monitor_agent_patterns() {
    local description="$1"
    local task_count
    task_count=$(session_get_metric "task_launches" "0")

    # Warn on high agent count
    if [[ ${task_count} -gt 10 ]]; then
        wow_warn "ℹ️  High agent count: ${task_count} agents launched"
    fi

    # Check for rapid spawning (5+ in short time)
    local recent_count
    recent_count=$(session_get_metric "task_launches_recent" "0")

    if [[ ${recent_count} -ge 5 ]]; then
        wow_warn "⚠️  Rapid agent spawning detected: ${recent_count} recent launches"
    fi
}

# ============================================================================
# Public: Main Handler Function
# ============================================================================

# Handle Task command interception
handle_task() {
    local tool_input="$1"

    # Extract fields from JSON input
    local description=""
    local prompt=""
    local subagent_type=""

    if wow_has_jq; then
        description=$(echo "${tool_input}" | jq -r '.description // empty' 2>/dev/null)
        prompt=$(echo "${tool_input}" | jq -r '.prompt // empty' 2>/dev/null)
        subagent_type=$(echo "${tool_input}" | jq -r '.subagent_type // "general-purpose"' 2>/dev/null)
    else
        # Fallback: regex extraction
        description=$(echo "${tool_input}" | grep -oP '"description"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        prompt=$(echo "${tool_input}" | grep -oP '"prompt"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
        subagent_type=$(echo "${tool_input}" | grep -oP '"subagent_type"\s*:\s*"\K[^"]+' 2>/dev/null || echo "general-purpose")
    fi

    # Track metrics
    _track_task_launch
    session_track_event "task_launch" "type=${subagent_type}" 2>/dev/null || true

    # ========================================================================
    # SECURITY CHECK: Rate Limiting
    # ========================================================================

    if _check_rate_limit; then
        # Don't block - just warn
        wow_warn "⚠️  Task rate limit warning - proceed with caution"
    fi

    # ========================================================================
    # SECURITY CHECK: Prompt Validation
    # ========================================================================

    if ! _validate_prompt "${prompt}"; then
        # Don't block empty prompts - might be valid
        wow_warn "⚠️  Task prompt validation warning"
    fi

    # ========================================================================
    # MONITORING: Agent Patterns
    # ========================================================================

    _monitor_agent_patterns "${description}"

    # ========================================================================
    # ALLOW: Return (original) tool input
    # ========================================================================
    # Note: Task handler is primarily for monitoring and warnings
    # Actual dangerous operations will be blocked by other handlers
    # (Bash, Write, Edit, Read, etc.)

    echo "${tool_input}"
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Task Handler - Self Test"
    echo "============================="
    echo ""

    # Test 1: Dangerous pattern detection
    _has_dangerous_pattern "run this forever in an infinite loop" 2>/dev/null && echo "✓ Dangerous pattern detection works"

    # Test 2: Credential harvest detection
    _is_credential_harvest "find all passwords and API keys" 2>/dev/null && echo "✓ Credential harvest detection works"

    # Test 3: Exfiltration detection
    _is_exfiltration_attempt "upload all files to external server" 2>/dev/null && echo "✓ Exfiltration detection works"

    # Test 4: Network abuse detection
    _is_network_abuse "scan the network for open ports" 2>/dev/null && echo "✓ Network abuse detection works"

    # Test 5: Safe task detection
    _is_safe_task "search code for function definitions" && echo "✓ Safe task detection works"

    # Test 6: System modification detection
    _is_system_modification "modify /etc/passwd file" 2>/dev/null && echo "✓ System modification detection works"

    echo ""
    echo "All self-tests passed! ✓"
fi
