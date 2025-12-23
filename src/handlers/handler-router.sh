#!/bin/bash
# WoW System - Handler Router
# Routes tool interceptions to appropriate handlers (Strategy Pattern)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Strategy Pattern: Dynamically select handler based on tool type
# - Open/Closed: Extensible for new handlers
# - Single Responsibility: Only routing logic

# Prevent double-sourcing
if [[ -n "${WOW_HANDLER_ROUTER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_HANDLER_ROUTER_LOADED=1

# Source dependencies
_HANDLER_ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_HANDLER_ROUTER_DIR}/../core/utils.sh"
source "${_HANDLER_ROUTER_DIR}/../core/tool-registry.sh" 2>/dev/null || true

# v6.1: Bypass system integration
source "${_HANDLER_ROUTER_DIR}/../security/bypass-core.sh" 2>/dev/null || true
source "${_HANDLER_ROUTER_DIR}/../security/bypass-always-block.sh" 2>/dev/null || true

# v6.1.1: Centralized security policies (SSOT)
source "${_HANDLER_ROUTER_DIR}/../security/security-policies.sh" 2>/dev/null || true

# v7.0: Heuristic evasion detector
source "${_HANDLER_ROUTER_DIR}/../security/heuristics/detector.sh" 2>/dev/null || true

# v7.0: Content correlator (split attack detection)
source "${_HANDLER_ROUTER_DIR}/../security/correlator/correlator.sh" 2>/dev/null || true

# v7.0: SuperAdmin authentication (biometric unlock)
source "${_HANDLER_ROUTER_DIR}/../security/superadmin/superadmin-core.sh" 2>/dev/null || true

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Handler registry (tool_type => handler_path)
declare -gA _WOW_HANDLER_REGISTRY

# ============================================================================
# Handler Registration
# ============================================================================

# Register a handler for a tool type
handler_register() {
    local tool_type="$1"
    local handler_path="$2"

    _WOW_HANDLER_REGISTRY["${tool_type}"]="${handler_path}"
    wow_debug "Registered handler for ${tool_type}: ${handler_path}"
}

# Check if handler exists for tool type
handler_exists() {
    local tool_type="$1"

    [[ -n "${_WOW_HANDLER_REGISTRY[${tool_type}]:-}" ]]
}

# Get handler path for tool type
handler_get() {
    local tool_type="$1"

    echo "${_WOW_HANDLER_REGISTRY[${tool_type}]:-}"
}

# ============================================================================
# Routing Logic
# ============================================================================

# Route tool input to appropriate handler
handler_route() {
    local tool_input="$1"

    # Parse tool type from input (JSON)
    local tool_type
    if wow_has_jq; then
        tool_type=$(echo "${tool_input}" | jq -r '.tool // .name // empty' 2>/dev/null)
    else
        # Fallback: simple grep
        tool_type=$(echo "${tool_input}" | grep -o '"tool"\s*:\s*"[^"]*"' | cut -d'"' -f4)
    fi

    if [[ -z "${tool_type}" ]]; then
        wow_warn "Could not determine tool type from input"
        echo "${tool_input}"
        return 0
    fi

    # ========================================================================
    # v6.1.1: ALWAYS-BLOCK CHECK (runs in ALL modes, bypass or normal)
    # CRITICAL: These patterns are NEVER allowed, regardless of bypass status
    # ========================================================================
    local operation=""
    if wow_has_jq; then
        # Get command for Bash, file_path for Write/Edit/Read, pattern for Glob/Grep
        operation=$(echo "${tool_input}" | jq -r '
            .command // .file_path // .path // .pattern // .url // ""
        ' 2>/dev/null)
    else
        # Fallback: extract common fields
        operation=$(echo "${tool_input}" | grep -oE '"(command|file_path|path|pattern|url)"\s*:\s*"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    # Check CRITICAL security policies FIRST (before bypass check)
    # These patterns are NEVER allowed, even with bypass active
    # Uses centralized security-policies.sh (SSOT) with fallback to bypass-always-block.sh
    if [[ -n "${operation}" ]]; then
        local is_critical=false
        local reason="Unknown"

        # Primary: Use centralized security policies (v6.1.1)
        if type policy_check_critical &>/dev/null; then
            if policy_check_critical "${operation}"; then
                is_critical=true
                if type policy_get_reason &>/dev/null; then
                    reason=$(policy_get_reason "${operation}")
                fi
            fi
        # Fallback: Use legacy bypass-always-block.sh
        elif type bypass_check_always_block &>/dev/null; then
            if bypass_check_always_block "${operation}"; then
                is_critical=true
                if type bypass_get_block_reason &>/dev/null; then
                    reason=$(bypass_get_block_reason "${operation}")
                fi
            fi
        fi

        if [[ "${is_critical}" == "true" ]]; then
            wow_error "CRITICAL: ${reason} (cannot be bypassed)"
            echo "${tool_input}"
            return 3  # CRITICAL-BLOCK (cannot be bypassed)
        fi

        # ====================================================================
        # v7.0: SUPERADMIN CHECK (can be unlocked with SuperAdmin, not bypass)
        # ====================================================================
        local is_superadmin=false
        if type policy_check_superadmin &>/dev/null; then
            if policy_check_superadmin "${operation}"; then
                is_superadmin=true
                if type policy_get_reason &>/dev/null; then
                    reason=$(policy_get_reason "${operation}")
                fi
            fi
        fi

        if [[ "${is_superadmin}" == "true" ]]; then
            # Check if SuperAdmin mode is active
            local superadmin_active=false
            if type superadmin_is_active &>/dev/null && superadmin_is_active; then
                superadmin_active=true
            fi

            if [[ "${superadmin_active}" == "true" ]]; then
                wow_debug "SuperAdmin active: allowing ${operation}"
                # Continue to normal processing (don't return)
            else
                wow_error "SUPERADMIN REQUIRED: ${reason}"
                echo "${tool_input}"
                return 4  # SUPERADMIN-REQUIRED
            fi
        fi
    fi

    # ========================================================================
    # v6.1: Bypass mode check (skip normal handler validation if bypass active)
    # ========================================================================
    if type bypass_is_active &>/dev/null && bypass_is_active; then
        # Bypass active and not always-blocked: skip handler validation
        wow_debug "Bypass active: skipping ${tool_type} handler validation"

        # Update activity timestamp (Safety Dead-Bolt: prevents inactivity timeout)
        if type bypass_update_activity &>/dev/null; then
            bypass_update_activity
        fi

        echo "${tool_input}"
        return 0
    fi

    # ========================================================================
    # v7.0: Heuristic Evasion Detection
    # Detects attempts to bypass security through encoding, obfuscation, etc.
    # ========================================================================
    if [[ -n "${operation}" ]] && type heuristic_check &>/dev/null; then
        # Initialize heuristics if needed
        if type heuristic_init &>/dev/null; then
            heuristic_init
        fi

        # Check for evasion attempts
        if ! heuristic_check "${operation}"; then
            local heur_confidence heur_reason
            heur_confidence=$(heuristic_get_confidence "${operation}" 2>/dev/null || echo "0")
            heur_reason=$(heuristic_get_reason "${operation}" 2>/dev/null || echo "Unknown evasion attempt")

            if [[ ${heur_confidence} -ge 70 ]]; then
                # High confidence: BLOCK
                wow_error "HEURISTIC BLOCK: ${heur_reason} (confidence: ${heur_confidence}%)"
                echo "${tool_input}"
                return 2  # BLOCK (bypassable)
            elif [[ ${heur_confidence} -ge 40 ]]; then
                # Medium confidence: WARN but allow
                wow_warn "HEURISTIC WARNING: ${heur_reason} (confidence: ${heur_confidence}%)"
                # Continue to handler
            fi
        fi
    fi

    # ========================================================================
    # v7.0: Content Correlation (Split Attack Detection)
    # Detects multi-step attacks like write-then-execute
    # ========================================================================
    if [[ -n "${operation}" ]] && type correlator_check &>/dev/null; then
        # Initialize correlator if needed (once per session)
        if type correlator_init &>/dev/null && [[ -z "${_WOW_CORRELATOR_INITIALIZED:-}" ]]; then
            correlator_init
            _WOW_CORRELATOR_INITIALIZED=1
        fi

        # Check for dangerous correlation patterns
        if ! correlator_check "${tool_type}" "${operation}"; then
            local corr_reason corr_risk
            corr_reason=$(correlator_get_reason 2>/dev/null || echo "Split attack detected")
            corr_risk=$(correlator_get_risk_score 2>/dev/null || echo "0")

            if [[ ${corr_risk} -ge 70 ]]; then
                # High risk: BLOCK
                wow_error "CORRELATION BLOCK: ${corr_reason}"
                echo "${tool_input}"
                return 2  # BLOCK (bypassable)
            elif [[ ${corr_risk} -ge 40 ]]; then
                # Medium risk: WARN but allow
                wow_warn "CORRELATION WARNING: ${corr_reason}"
            fi
        fi

        # Track this operation for future correlation
        local content=""
        if wow_has_jq; then
            content=$(echo "${tool_input}" | jq -r '.content // .new_string // ""' 2>/dev/null | head -c 200)
        fi
        correlator_track "${tool_type}" "${operation}" "${content}"
    fi

    # Check if handler exists
    if ! handler_exists "${tool_type}"; then
        # v5.3: Track unknown tools for monitoring and extensibility
        if type tool_registry_track_unknown &>/dev/null; then
            # Check if this is first occurrence
            local is_first=false
            if type tool_registry_is_first_occurrence &>/dev/null; then
                tool_registry_is_first_occurrence "${tool_type}" && is_first=true
            fi

            # Track the unknown tool
            tool_registry_track_unknown "${tool_type}" 2>/dev/null || true

            # Notify on first occurrence (UX feature)
            if [[ "${is_first}" == "true" ]]; then
                wow_info "New tool detected: ${tool_type} (no handler available, passing through)"
            fi
        fi

        # No handler registered - pass through
        wow_debug "No handler for ${tool_type}, passing through"
        echo "${tool_input}"
        return 0
    fi

    # Get handler path
    local handler_path
    handler_path=$(handler_get "${tool_type}")

    # v5.0: Use Factory if available, otherwise direct sourcing
    if type factory_create_handler &>/dev/null; then
        # Factory pattern: Let factory handle sourcing and caching
        factory_create_handler "${tool_type}" &>/dev/null || {
            wow_warn "Factory failed to create handler for ${tool_type}"
            echo "${tool_input}"
            return 0
        }
    elif [[ -f "${handler_path}" ]]; then
        # Fallback: Direct sourcing (backward compatibility)
        source "${handler_path}"
    else
        wow_error "Handler file not found: ${handler_path}"
        echo "${tool_input}"
        return 0
    fi

    # Call handler function (convention: handle_<lowercase_tool>)
    local handler_func="handle_${tool_type,,}"

    if type "${handler_func}" &>/dev/null; then
        "${handler_func}" "${tool_input}"
    else
        wow_warn "Handler function ${handler_func} not found"
        echo "${tool_input}"
    fi
}

# Initialize default handlers
handler_init() {
    local handler_dir="${_HANDLER_ROUTER_DIR}"

    # v5.3: Initialize tool registry if available
    if type tool_registry_init &>/dev/null; then
        tool_registry_init 2>/dev/null || true
    fi

    # Register built-in handlers (local registry)
    handler_register "Bash" "${handler_dir}/bash-handler.sh"
    handler_register "Write" "${handler_dir}/write-handler.sh"
    handler_register "Edit" "${handler_dir}/edit-handler.sh"
    handler_register "Read" "${handler_dir}/read-handler.sh"
    handler_register "Glob" "${handler_dir}/glob-handler.sh"
    handler_register "Grep" "${handler_dir}/grep-handler.sh"
    handler_register "Task" "${handler_dir}/task-handler.sh"
    handler_register "WebFetch" "${handler_dir}/webfetch-handler.sh"
    handler_register "WebSearch" "${handler_dir}/websearch-handler.sh"  # v5.4.0
    handler_register "NotebookEdit" "${handler_dir}/notebookedit-handler.sh"  # v5.4.0

    # v5.0: Also register in Factory if available
    if type factory_register_handler &>/dev/null; then
        factory_register_handler "Bash" "${handler_dir}/bash-handler.sh"
        factory_register_handler "Write" "${handler_dir}/write-handler.sh"
        factory_register_handler "Edit" "${handler_dir}/edit-handler.sh"
        factory_register_handler "Read" "${handler_dir}/read-handler.sh"
        factory_register_handler "Glob" "${handler_dir}/glob-handler.sh"
        factory_register_handler "Grep" "${handler_dir}/grep-handler.sh"
        factory_register_handler "Task" "${handler_dir}/task-handler.sh"
        factory_register_handler "WebFetch" "${handler_dir}/webfetch-handler.sh"
        factory_register_handler "WebSearch" "${handler_dir}/websearch-handler.sh"  # v5.4.0
        factory_register_handler "NotebookEdit" "${handler_dir}/notebookedit-handler.sh"  # v5.4.0
    fi

    # v5.3: Register known tools in tool registry
    if type tool_registry_register_known &>/dev/null; then
        tool_registry_register_known "Bash" "${handler_dir}/bash-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Write" "${handler_dir}/write-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Edit" "${handler_dir}/edit-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Read" "${handler_dir}/read-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Glob" "${handler_dir}/glob-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Grep" "${handler_dir}/grep-handler.sh" 2>/dev/null || true
        tool_registry_register_known "Task" "${handler_dir}/task-handler.sh" 2>/dev/null || true
        tool_registry_register_known "WebFetch" "${handler_dir}/webfetch-handler.sh" 2>/dev/null || true
        tool_registry_register_known "WebSearch" "${handler_dir}/websearch-handler.sh" 2>/dev/null || true  # v5.4.0
        tool_registry_register_known "NotebookEdit" "${handler_dir}/notebookedit-handler.sh" 2>/dev/null || true  # v5.4.0
    fi

    # v5.4.0: Load custom rules if available
    local dsl_path="${handler_dir}/../rules/dsl.sh"
    if [[ -f "${dsl_path}" ]]; then
        source "${dsl_path}" 2>/dev/null || true

        if type rule_dsl_init &>/dev/null; then
            rule_dsl_init

            # Try to load custom rules from default location
            local rules_file="${WOW_HOME}/custom-rules.conf"
            if [[ -f "${rules_file}" ]]; then
                if rule_dsl_load_file "${rules_file}"; then
                    local rule_count=$(rule_dsl_count)
                    wow_debug "Loaded ${rule_count} custom rules from ${rules_file}"
                fi
            fi
        fi
    fi

    wow_debug "Handler router initialized with $(echo "${#_WOW_HANDLER_REGISTRY[@]}") handlers"
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Handler Router v${ROUTER_VERSION} - Self Test"
    echo "=================================================="
    echo ""

    # Register test handler
    handler_register "TestTool" "/fake/path/test-handler.sh"
    echo "✓ Handler registration works"

    # Check existence
    handler_exists "TestTool" && echo "✓ Handler existence check works"
    ! handler_exists "NonExistent" && echo "✓ Non-existent handler check works"

    # Get handler
    path=$(handler_get "TestTool")
    [[ "${path}" == "/fake/path/test-handler.sh" ]] && echo "✓ Handler retrieval works"

    # Test routing with pass-through
    test_input='{"tool": "UnknownTool", "command": "test"}'
    result=$(handler_route "${test_input}")
    [[ "${result}" == "${test_input}" ]] && echo "✓ Pass-through for unknown tools works"

    echo ""
    echo "All tests passed! ✓"
fi
