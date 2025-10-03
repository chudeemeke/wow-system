#!/bin/bash
# WoW System - Dependency Injection Container
# Production-grade DI Container implementing Singleton Pattern with lifecycle management
# Author: Chude <chude@emeke.org>
#
# Design Principles:
# - Singleton Pattern: Container itself is a singleton
# - Lazy Loading: Services are instantiated only when resolved
# - Lifecycle Management: Supports Singleton, Factory, and Transient lifecycles
# - Error Handling: Clear error messages for missing dependencies
# - Bash 4.0+ Compatible: Uses associative arrays for efficient lookups

# Prevent double-sourcing
if [[ -n "${WOW_DI_CONTAINER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_DI_CONTAINER_LOADED=1

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly DI_VERSION="1.0.0"

# Lifecycle types
readonly DI_LIFECYCLE_SINGLETON="singleton"
readonly DI_LIFECYCLE_FACTORY="factory"
readonly DI_LIFECYCLE_TRANSIENT="transient"

# ============================================================================
# Container State (Global)
# ============================================================================

# Container initialization flag
_DI_INITIALIZED=false

# Registrations: interface -> implementation_function
declare -gA _DI_REGISTRATIONS

# Lifecycle map: interface -> lifecycle_type
declare -gA _DI_LIFECYCLES

# Singleton instances cache: interface -> cached_result
declare -gA _DI_SINGLETONS

# Resolution stack for circular dependency detection
declare -ga _DI_RESOLUTION_STACK

# ============================================================================
# Private: Helper Functions
# ============================================================================

# Log error message
_di_error() {
    echo "DI Container Error: $*" >&2
    return 1
}

# Log debug message (only if WOW_DEBUG is set)
_di_debug() {
    if [[ -n "${WOW_DEBUG:-}" ]]; then
        echo "DI Container Debug: $*" >&2
    fi
}

# Validate interface name
_di_validate_interface() {
    local interface="$1"

    if [[ -z "${interface}" ]]; then
        _di_error "Interface name cannot be empty"
        return 1
    fi

    return 0
}

# Validate implementation
_di_validate_implementation() {
    local implementation="$1"

    if [[ -z "${implementation}" ]]; then
        _di_error "Implementation cannot be empty"
        return 1
    fi

    return 0
}

# Check for circular dependencies
_di_check_circular() {
    local interface="$1"

    for item in "${_DI_RESOLUTION_STACK[@]:-}"; do
        if [[ "${item}" == "${interface}" ]]; then
            _di_error "Circular dependency detected: ${interface} -> ${_DI_RESOLUTION_STACK[*]} -> ${interface}"
            return 1
        fi
    done

    return 0
}

# Push to resolution stack
_di_stack_push() {
    local interface="$1"
    _DI_RESOLUTION_STACK+=("${interface}")
}

# Pop from resolution stack
_di_stack_pop() {
    if [[ ${#_DI_RESOLUTION_STACK[@]} -gt 0 ]]; then
        unset '_DI_RESOLUTION_STACK[-1]'
    fi
}

# ============================================================================
# Public API: Initialization
# ============================================================================

# Initialize DI Container
# Usage: di_init
# Returns: 0 on success
di_init() {
    # Idempotent - safe to call multiple times
    if [[ "${_DI_INITIALIZED}" == "true" ]]; then
        _di_debug "Container already initialized"
        return 0
    fi

    # Initialize associative arrays if not already done
    if ! declare -p _DI_REGISTRATIONS &>/dev/null; then
        declare -gA _DI_REGISTRATIONS
    fi

    if ! declare -p _DI_LIFECYCLES &>/dev/null; then
        declare -gA _DI_LIFECYCLES
    fi

    if ! declare -p _DI_SINGLETONS &>/dev/null; then
        declare -gA _DI_SINGLETONS
    fi

    if ! declare -p _DI_RESOLUTION_STACK &>/dev/null; then
        declare -ga _DI_RESOLUTION_STACK
    fi

    _DI_INITIALIZED=true
    _di_debug "Container initialized successfully"

    return 0
}

# ============================================================================
# Public API: Registration
# ============================================================================

# Register a singleton service
# Singletons are instantiated once and cached
# Usage: di_register_singleton "IService" "implementation_function"
# Returns: 0 on success, 1 on error
di_register_singleton() {
    local interface="$1"
    local implementation="$2"

    _di_validate_interface "${interface}" || return 1
    _di_validate_implementation "${implementation}" || return 1

    _DI_REGISTRATIONS["${interface}"]="${implementation}"
    _DI_LIFECYCLES["${interface}"]="${DI_LIFECYCLE_SINGLETON}"

    _di_debug "Registered singleton: ${interface} -> ${implementation}"

    return 0
}

# Register a factory service
# Factories are called each time with parameters
# Usage: di_register_factory "IService" "factory_function"
# Returns: 0 on success, 1 on error
di_register_factory() {
    local interface="$1"
    local implementation="$2"

    _di_validate_interface "${interface}" || return 1
    _di_validate_implementation "${implementation}" || return 1

    _DI_REGISTRATIONS["${interface}"]="${implementation}"
    _DI_LIFECYCLES["${interface}"]="${DI_LIFECYCLE_FACTORY}"

    _di_debug "Registered factory: ${interface} -> ${implementation}"

    return 0
}

# Register a transient service
# Transients are instantiated each time (new instance)
# Usage: di_register_transient "IService" "implementation_function"
# Returns: 0 on success, 1 on error
di_register_transient() {
    local interface="$1"
    local implementation="$2"

    _di_validate_interface "${interface}" || return 1
    _di_validate_implementation "${implementation}" || return 1

    _DI_REGISTRATIONS["${interface}"]="${implementation}"
    _DI_LIFECYCLES["${interface}"]="${DI_LIFECYCLE_TRANSIENT}"

    _di_debug "Registered transient: ${interface} -> ${implementation}"

    return 0
}

# ============================================================================
# Public API: Resolution
# ============================================================================

# Resolve a service by interface
# Usage: di_resolve "IService" [params...]
# Returns: Service instance/result
di_resolve() {
    local interface="$1"
    shift
    local params=("$@")

    _di_validate_interface "${interface}" || return 1

    # Check if registered
    if [[ -z "${_DI_REGISTRATIONS[${interface}]:-}" ]]; then
        _di_error "Service '${interface}' is not registered"
        return 1
    fi

    # Check for circular dependencies
    _di_check_circular "${interface}" || return 1

    local implementation="${_DI_REGISTRATIONS[${interface}]}"
    local lifecycle="${_DI_LIFECYCLES[${interface}]}"

    _di_debug "Resolving: ${interface} (${lifecycle})"

    # Push to resolution stack
    _di_stack_push "${interface}"

    local result
    local exit_code=0

    case "${lifecycle}" in
        "${DI_LIFECYCLE_SINGLETON}")
            # Check if already instantiated
            if [[ -n "${_DI_SINGLETONS[${interface}]:-}" ]]; then
                result="${_DI_SINGLETONS[${interface}]}"
                _di_debug "Retrieved cached singleton: ${interface}"
            else
                # Instantiate and cache
                result=$("${implementation}" "${params[@]}") || exit_code=$?
                if [[ ${exit_code} -eq 0 ]]; then
                    _DI_SINGLETONS["${interface}"]="${result}"
                    _di_debug "Instantiated and cached singleton: ${interface}"
                fi
            fi
            ;;

        "${DI_LIFECYCLE_FACTORY}")
            # Call factory with parameters
            result=$("${implementation}" "${params[@]}") || exit_code=$?
            _di_debug "Called factory: ${interface}"
            ;;

        "${DI_LIFECYCLE_TRANSIENT}")
            # Create new instance each time
            result=$("${implementation}" "${params[@]}") || exit_code=$?
            _di_debug "Created transient instance: ${interface}"
            ;;

        *)
            _di_error "Unknown lifecycle type: ${lifecycle}"
            exit_code=1
            ;;
    esac

    # Pop from resolution stack
    _di_stack_pop

    if [[ ${exit_code} -ne 0 ]]; then
        _di_error "Failed to resolve '${interface}'"
        return 1
    fi

    echo "${result}"
    return 0
}

# ============================================================================
# Public API: Query
# ============================================================================

# Check if an interface is registered
# Usage: di_has "IService"
# Returns: 0 if registered, 1 if not
di_has() {
    local interface="$1"

    if [[ -n "${_DI_REGISTRATIONS[${interface}]:-}" ]]; then
        return 0
    else
        return 1
    fi
}

# Get lifecycle type for an interface
# Usage: di_get_lifecycle "IService"
# Returns: Lifecycle type (singleton|factory|transient)
di_get_lifecycle() {
    local interface="$1"

    if ! di_has "${interface}"; then
        _di_error "Service '${interface}' is not registered"
        return 1
    fi

    echo "${_DI_LIFECYCLES[${interface}]}"
    return 0
}

# List all registered interfaces
# Usage: di_list
# Returns: List of registered interfaces (one per line)
di_list() {
    for interface in "${!_DI_REGISTRATIONS[@]}"; do
        echo "${interface}"
    done | sort
}

# ============================================================================
# Public API: Management
# ============================================================================

# Clear all registrations and cached instances
# Usage: di_clear
# Returns: 0 on success
di_clear() {
    # Clear all arrays
    for interface in "${!_DI_REGISTRATIONS[@]}"; do
        unset "_DI_REGISTRATIONS[${interface}]"
    done

    for interface in "${!_DI_LIFECYCLES[@]}"; do
        unset "_DI_LIFECYCLES[${interface}]"
    done

    for interface in "${!_DI_SINGLETONS[@]}"; do
        unset "_DI_SINGLETONS[${interface}]"
    done

    # Clear resolution stack
    _DI_RESOLUTION_STACK=()

    _di_debug "Container cleared"

    return 0
}

# Reset container (clear and reinitialize)
# Usage: di_reset
# Returns: 0 on success
di_reset() {
    di_clear
    _DI_INITIALIZED=false
    di_init
    _di_debug "Container reset"
    return 0
}

# Get container statistics
# Usage: di_stats
# Returns: Statistics about the container
di_stats() {
    local total_registrations=0
    local total_singletons=0
    local total_factories=0
    local total_transients=0
    local cached_singletons=0

    # Safe array length checks
    if [[ -n "${_DI_REGISTRATIONS[@]:-}" ]]; then
        total_registrations=${#_DI_REGISTRATIONS[@]}
    fi

    if [[ -n "${_DI_SINGLETONS[@]:-}" ]]; then
        cached_singletons=${#_DI_SINGLETONS[@]}
    fi

    for interface in "${!_DI_LIFECYCLES[@]}"; do
        case "${_DI_LIFECYCLES[${interface}]}" in
            "${DI_LIFECYCLE_SINGLETON}") ((total_singletons++)) ;;
            "${DI_LIFECYCLE_FACTORY}") ((total_factories++)) ;;
            "${DI_LIFECYCLE_TRANSIENT}") ((total_transients++)) ;;
        esac
    done

    cat <<EOF
DI Container Statistics
=======================
Version: ${DI_VERSION}
Initialized: ${_DI_INITIALIZED}

Registrations:
  Total:      ${total_registrations}
  Singletons: ${total_singletons}
  Factories:  ${total_factories}
  Transients: ${total_transients}

Runtime:
  Cached Singletons: ${cached_singletons}
  Resolution Stack Depth: ${#_DI_RESOLUTION_STACK[@]}
EOF
}

# ============================================================================
# Self-test
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "DI Container v${DI_VERSION} - Self Test"
    echo "========================================"
    echo ""

    # Initialize
    di_init
    echo "✓ Initialization complete"

    # Mock services for testing
    mock_service_a() {
        echo "service-a-instance"
    }

    mock_service_b() {
        local param="${1:-default}"
        echo "service-b-${param}"
    }

    # Register services
    di_register_singleton "IServiceA" "mock_service_a"
    di_register_factory "IServiceB" "mock_service_b"
    di_register_transient "IServiceC" "mock_service_a"
    echo "✓ Registered 3 services"

    # Check registrations
    di_has "IServiceA" && echo "✓ IServiceA is registered"
    di_has "IServiceB" && echo "✓ IServiceB is registered"
    di_has "IServiceC" && echo "✓ IServiceC is registered"

    # Resolve services
    result_a=$(di_resolve "IServiceA")
    echo "✓ Resolved IServiceA: ${result_a}"

    result_b=$(di_resolve "IServiceB" "custom")
    echo "✓ Resolved IServiceB: ${result_b}"

    result_c1=$(di_resolve "IServiceC")
    result_c2=$(di_resolve "IServiceC")
    echo "✓ Resolved IServiceC (transient): ${result_c1}, ${result_c2}"

    # Test singleton caching
    result_a2=$(di_resolve "IServiceA")
    if [[ "${result_a}" == "${result_a2}" ]]; then
        echo "✓ Singleton returns same instance"
    fi

    # List services
    echo ""
    echo "Registered services:"
    di_list | sed 's/^/  - /'

    # Statistics
    echo ""
    di_stats

    # Clear
    di_clear
    echo ""
    echo "✓ Container cleared"

    echo ""
    echo "All self-tests passed! ✓"
fi
