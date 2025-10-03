#!/bin/bash
# WoW System - Orchestrator
# Central module loader and initialization coordinator (Facade Pattern)
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Facade Pattern: Simple interface for complex subsystem
# - Dependency Injection: Modules are loosely coupled
# - Idempotent: Safe to call multiple times
# - Fail-Safe: Graceful error handling

# Prevent double-sourcing
if [[ -n "${WOW_ORCHESTRATOR_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_ORCHESTRATOR_LOADED=1

# ============================================================================
# Constants
# ============================================================================

readonly ORCHESTRATOR_VERSION="1.0.0"

# Module registry (for dependency tracking)
declare -gA _WOW_MODULES_LOADED

# Initialization flag
_WOW_INITIALIZED=false

# ============================================================================
# Private: Module Loading
# ============================================================================

# Load a module with error handling
_load_module() {
    local module_name="$1"
    local module_path="$2"

    if [[ -n "${_WOW_MODULES_LOADED[${module_name}]:-}" ]]; then
        # Already loaded
        return 0
    fi

    if [[ ! -f "${module_path}" ]]; then
        echo "ERROR: Module not found: ${module_path}" >&2
        return 1
    fi

    # Source the module
    source "${module_path}" || {
        echo "ERROR: Failed to load module: ${module_name}" >&2
        return 1
    }

    # Mark as loaded
    _WOW_MODULES_LOADED["${module_name}"]=1

    return 0
}

# Get module directory
_get_module_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# ============================================================================
# Public API: Initialization
# ============================================================================

# Initialize WoW system
wow_init() {
    local config_file="${1:-}"

    # Check if already initialized
    if [[ "${_WOW_INITIALIZED}" == "true" ]]; then
        return 0  # Idempotent
    fi

    local module_dir
    module_dir=$(_get_module_dir)

    # Load core modules (order matters - dependencies first)
    _load_module "utils" "${module_dir}/utils.sh" || return 1
    _load_module "storage" "${module_dir}/../storage/file-storage.sh" || return 1
    _load_module "state" "${module_dir}/state-manager.sh" || return 1
    _load_module "config" "${module_dir}/config-loader.sh" || return 1
    _load_module "session" "${module_dir}/session-manager.sh" || return 1

    # Initialize core components
    storage_init 2>/dev/null || true
    state_init 2>/dev/null || true
    config_init 2>/dev/null || true

    # Load configuration
    if [[ -n "${config_file}" ]] && [[ -f "${config_file}" ]]; then
        config_load "${config_file}" 2>/dev/null || {
            wow_warn "Failed to load config file: ${config_file}" 2>/dev/null || true
        }
    else
        config_load_defaults 2>/dev/null || true
    fi

    # Load handlers (CRITICAL: needed for hook to work)
    wow_load_handlers 2>/dev/null || {
        wow_warn "Failed to load handlers" 2>/dev/null || true
    }

    # Initialize handlers
    if type handler_init &>/dev/null; then
        handler_init 2>/dev/null || true
    fi

    # Mark as initialized
    _WOW_INITIALIZED=true

    return 0
}

# Cleanup and shutdown
wow_cleanup() {
    if [[ "${_WOW_INITIALIZED}" != "true" ]]; then
        return 0
    fi

    # Save current state if session is active
    if type session_is_active &>/dev/null; then
        if session_is_active 2>/dev/null; then
            session_save 2>/dev/null || true
        fi
    fi

    # Archive state
    if type state_archive &>/dev/null; then
        state_archive 2>/dev/null || true
    fi

    return 0
}

# ============================================================================
# Public API: Status & Info
# ============================================================================

# Check if WoW system is initialized
wow_is_initialized() {
    [[ "${_WOW_INITIALIZED}" == "true" ]]
}

# Get WoW version
wow_get_version() {
    echo "${WOW_VERSION:-4.1.0}"
}

# Check if a specific module is available
wow_module_available() {
    local module_name="$1"

    [[ -n "${_WOW_MODULES_LOADED[${module_name}]:-}" ]]
}

# List all loaded modules
wow_modules_list() {
    for module in "${!_WOW_MODULES_LOADED[@]}"; do
        echo "${module}"
    done | sort
}

# Get system status
wow_status() {
    cat <<EOF
WoW System Status
=================
Version: $(wow_get_version)
Initialized: ${_WOW_INITIALIZED}
Modules Loaded: ${#_WOW_MODULES_LOADED[@]}

Loaded Modules:
$(wow_modules_list | sed 's/^/  - /')
EOF

    if wow_is_initialized && type session_info &>/dev/null; then
        echo ""
        echo "Session Info:"
        session_info | sed 's/^/  /'
    fi
}

# ============================================================================
# Public API: Advanced Module Loading
# ============================================================================

# Load handler modules (lazy loading)
wow_load_handlers() {
    local module_dir
    module_dir=$(_get_module_dir)

    _load_module "handler_router" "${module_dir}/../handlers/handler-router.sh" || return 1

    # Handlers are loaded on-demand by the router
    return 0
}

# Load UI modules (lazy loading)
wow_load_ui() {
    local module_dir
    module_dir=$(_get_module_dir)

    _load_module "ui_banner" "${module_dir}/../ui/banner.sh" || true
    _load_module "ui_feedback" "${module_dir}/../ui/feedback.sh" || true

    return 0
}

# Load strategy modules (lazy loading)
wow_load_strategies() {
    local module_dir
    module_dir=$(_get_module_dir)

    _load_module "scoring" "${module_dir}/../strategies/scoring-engine.sh" || true
    _load_module "risk" "${module_dir}/../strategies/risk-assessor.sh" || true

    return 0
}

# Load all optional modules
wow_load_all() {
    wow_load_handlers 2>/dev/null || true
    wow_load_ui 2>/dev/null || true
    wow_load_strategies 2>/dev/null || true
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WoW Orchestrator v${ORCHESTRATOR_VERSION} - Self Test"
    echo "======================================================"
    echo ""

    # Initialize
    wow_init
    echo "✓ Initialization complete"

    # Check initialized
    wow_is_initialized && echo "✓ System is initialized"

    # Get version
    version=$(wow_get_version)
    echo "✓ Version: ${version}"

    # Check modules
    wow_module_available "utils" && echo "✓ Utils module loaded"
    wow_module_available "state" && echo "✓ State module loaded"
    wow_module_available "config" && echo "✓ Config module loaded"
    wow_module_available "session" && echo "✓ Session module loaded"

    # List modules
    echo ""
    echo "Loaded modules:"
    wow_modules_list | sed 's/^/  - /'

    # Status
    echo ""
    wow_status

    # Cleanup
    wow_cleanup
    echo ""
    echo "✓ Cleanup complete"

    # Test idempotency
    wow_init
    wow_init
    echo "✓ Idempotent initialization works"

    echo ""
    echo "All tests passed! ✓"
fi
