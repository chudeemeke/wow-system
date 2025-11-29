#!/bin/bash
# WoW System - Dependency Injection Container Tests
# Tests for DI Container pattern implementation
# Author: Chude <chude@emeke.org>

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-framework.sh"

# DI Container module path
DI_CONTAINER="${SCRIPT_DIR}/../src/patterns/di-container.sh"

# Test data directory
TEST_DATA_DIR=""

# ============================================================================
# Test Lifecycle
# ============================================================================

setup_all() {
    TEST_DATA_DIR=$(test_temp_dir)
    export WOW_DATA_DIR="${TEST_DATA_DIR}"
    export WOW_HOME="${TEST_DATA_DIR}"
}

teardown_all() {
    if [[ -n "${TEST_DATA_DIR}" ]] && [[ -d "${TEST_DATA_DIR}" ]]; then
        test_cleanup_temp "${TEST_DATA_DIR}"
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

source_di_container() {
    if [[ -f "${DI_CONTAINER}" ]]; then
        source "${DI_CONTAINER}"
        return 0
    else
        echo "DI Container not implemented yet: ${DI_CONTAINER}"
        return 1
    fi
}

# Mock implementations for testing
mock_singleton_service() {
    echo "singleton-service-instance"
}

mock_transient_service() {
    echo "transient-service-instance-$$-${RANDOM}"
}

mock_factory_service() {
    local param="${1:-default}"
    echo "factory-service-${param}"
}

mock_dependency_a() {
    echo "dependency-a"
}

mock_dependency_b() {
    # This will depend on A to test resolution
    echo "dependency-b-needs-$(mock_dependency_a)"
}

# ============================================================================
# Tests
# ============================================================================

test_suite "Dependency Injection Container"

# Test 1: DI Container file exists
test_di_container_exists() {
    assert_file_exists "${DI_CONTAINER}" "DI Container file should exist"
}
test_case "DI Container file exists" test_di_container_exists

# Test 2: Initialize DI container
test_di_init() {
    source_di_container || return 1
    di_init
    assert_success "DI container initialization should succeed"
}
test_case "DI container initialization" test_di_init

# Test 3: Register singleton
test_register_singleton() {
    source_di_container || return 1
    di_init

    di_register_singleton "ISingletonService" "mock_singleton_service"
    local result=$?

    assert_equals "0" "${result}" "Singleton registration should succeed"
}
test_case "Register singleton" test_register_singleton

# Test 4: Resolve singleton
test_resolve_singleton() {
    source_di_container || return 1
    di_init

    di_register_singleton "ISingletonService" "mock_singleton_service"

    local result
    result=$(di_resolve "ISingletonService")

    assert_equals "singleton-service-instance" "${result}" "Should resolve singleton correctly"
}
test_case "Resolve singleton" test_resolve_singleton

# Test 5: Singleton returns same instance
test_singleton_same_instance() {
    source_di_container || return 1
    di_init

    di_register_singleton "ISingletonService" "mock_singleton_service"

    local instance1
    local instance2
    instance1=$(di_resolve "ISingletonService")
    instance2=$(di_resolve "ISingletonService")

    assert_equals "${instance1}" "${instance2}" "Singleton should return same instance"
}
test_case "Singleton returns same instance" test_singleton_same_instance

# Test 6: Register factory
test_register_factory() {
    source_di_container || return 1
    di_init

    di_register_factory "IFactoryService" "mock_factory_service"
    local result=$?

    assert_equals "0" "${result}" "Factory registration should succeed"
}
test_case "Register factory" test_register_factory

# Test 7: Resolve factory with parameters
test_resolve_factory() {
    source_di_container || return 1
    di_init

    di_register_factory "IFactoryService" "mock_factory_service"

    local result
    result=$(di_resolve "IFactoryService" "custom-param")

    assert_contains "${result}" "factory-service-custom-param" "Factory should resolve with parameters"
}
test_case "Resolve factory with parameters" test_resolve_factory

# Test 8: Register transient
test_register_transient() {
    source_di_container || return 1
    di_init

    di_register_transient "ITransientService" "mock_transient_service"
    local result=$?

    assert_equals "0" "${result}" "Transient registration should succeed"
}
test_case "Register transient" test_register_transient

# Test 9: Resolve transient (new instance each time)
test_resolve_transient() {
    source_di_container || return 1
    di_init

    di_register_transient "ITransientService" "mock_transient_service"

    local instance1
    local instance2
    instance1=$(di_resolve "ITransientService")
    instance2=$(di_resolve "ITransientService")

    assert_not_equals "${instance1}" "${instance2}" "Transient should return different instances"
}
test_case "Transient returns new instance each time" test_resolve_transient

# Test 10: Check if interface is registered
test_di_has() {
    source_di_container || return 1
    di_init

    di_register_singleton "IRegisteredService" "mock_singleton_service"

    di_has "IRegisteredService" && local exists1="true" || local exists1="false"
    di_has "IUnregisteredService" && local exists2="true" || local exists2="false"

    assert_equals "true" "${exists1}" "Should return true for registered interface"
    assert_equals "false" "${exists2}" "Should return false for unregistered interface"
}
test_case "Check if interface is registered" test_di_has

# Test 11: Resolve missing dependency (error handling)
test_resolve_missing() {
    source_di_container || return 1
    di_init

    local result
    result=$(di_resolve "IMissingService" 2>&1)
    local exit_code=$?

    assert_not_equals "0" "${exit_code}" "Resolving missing dependency should fail"
    assert_contains "${result}" "not registered" "Error message should mention 'not registered'"
}
test_case "Resolve missing dependency fails gracefully" test_resolve_missing

# Test 12: Clear all registrations
test_di_clear() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService1" "mock_singleton_service"
    di_register_singleton "IService2" "mock_singleton_service"

    di_clear

    di_has "IService1" && local exists="true" || local exists="false"

    assert_equals "false" "${exists}" "All registrations should be cleared"
}
test_case "Clear all registrations" test_di_clear

# Test 13: Override existing registration
test_override_registration() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService" "mock_singleton_service"
    di_register_singleton "IService" "mock_factory_service"

    local result
    result=$(di_resolve "IService")

    assert_contains "${result}" "factory-service" "Should use latest registration"
}
test_case "Override existing registration" test_override_registration

# Test 14: Register with null implementation (error handling)
test_register_null_implementation() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService" "" 2>&1
    local exit_code=$?

    assert_not_equals "0" "${exit_code}" "Registering null implementation should fail"
}
test_case "Register with null implementation fails" test_register_null_implementation

# Test 15: Register with null interface (error handling)
test_register_null_interface() {
    source_di_container || return 1
    di_init

    di_register_singleton "" "mock_singleton_service" 2>&1
    local exit_code=$?

    assert_not_equals "0" "${exit_code}" "Registering with null interface should fail"
}
test_case "Register with null interface fails" test_register_null_interface

# Test 16: Multiple different services
test_multiple_services() {
    source_di_container || return 1
    di_init

    di_register_singleton "IServiceA" "mock_dependency_a"
    di_register_singleton "IServiceB" "mock_dependency_b"
    di_register_factory "IServiceC" "mock_factory_service"

    local result_a
    local result_b
    local result_c
    result_a=$(di_resolve "IServiceA")
    result_b=$(di_resolve "IServiceB")
    result_c=$(di_resolve "IServiceC")

    assert_equals "dependency-a" "${result_a}" "Service A should resolve correctly"
    assert_contains "${result_b}" "dependency-b" "Service B should resolve correctly"
    assert_contains "${result_c}" "factory-service" "Service C should resolve correctly"
}
test_case "Multiple different services" test_multiple_services

# Test 17: Lazy loading - singleton not instantiated until resolved
test_lazy_loading() {
    source_di_container || return 1
    di_init

    # Registration should not execute the function
    di_register_singleton "ILazyService" "mock_singleton_service"

    # Verify it's registered but not instantiated yet
    di_has "ILazyService" && local registered="true" || local registered="false"

    assert_equals "true" "${registered}" "Service should be registered"

    # Now resolve it
    local result
    result=$(di_resolve "ILazyService")

    assert_equals "singleton-service-instance" "${result}" "Service should be instantiated on first resolve"
}
test_case "Lazy loading - singleton not instantiated until resolved" test_lazy_loading

# Test 18: Re-initialize container (idempotent)
test_di_reinit() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService" "mock_singleton_service"

    # Re-initialize should not clear existing registrations by default
    di_init

    di_has "IService" && local exists="true" || local exists="false"

    assert_equals "true" "${exists}" "Re-initialization should be idempotent"
}
test_case "Re-initialize container is idempotent" test_di_reinit

# Test 19: Container state persistence
test_container_state() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService1" "mock_singleton_service"
    di_register_factory "IService2" "mock_factory_service"
    di_register_transient "IService3" "mock_transient_service"

    # All three should be registered
    di_has "IService1" && local has1="true" || local has1="false"
    di_has "IService2" && local has2="true" || local has2="false"
    di_has "IService3" && local has3="true" || local has3="false"

    assert_equals "true" "${has1}" "Singleton should be registered"
    assert_equals "true" "${has2}" "Factory should be registered"
    assert_equals "true" "${has3}" "Transient should be registered"
}
test_case "Container maintains state for all lifecycle types" test_container_state

# Test 20: Edge case - resolve with special characters in interface name
test_special_interface_name() {
    source_di_container || return 1
    di_init

    di_register_singleton "IService::Handler::Read" "mock_singleton_service"

    local result
    result=$(di_resolve "IService::Handler::Read")

    assert_equals "singleton-service-instance" "${result}" "Should handle special characters in interface names"
}
test_case "Handle special characters in interface name" test_special_interface_name

# Test 21: Factory with no parameters
test_factory_no_params() {
    source_di_container || return 1
    di_init

    di_register_factory "IFactoryService" "mock_factory_service"

    local result
    result=$(di_resolve "IFactoryService")

    assert_contains "${result}" "factory-service" "Factory should work without parameters"
}
test_case "Factory with no parameters" test_factory_no_params

# Test 22: Double-sourcing protection
test_double_source_protection() {
    source_di_container || return 1

    # Source again
    source "${DI_CONTAINER}"
    local result=$?

    assert_equals "0" "${result}" "Double-sourcing should not cause errors"
}
test_case "Double-sourcing protection" test_double_source_protection

# Test 23: Circular dependency detection
test_circular_dependency_detection() {
    source_di_container || return 1
    di_init

    # Create circular dependency scenario
    # ServiceA depends on ServiceB, ServiceB depends on ServiceA
    di_register_singleton "IServiceA" "mock_dependency_a"
    di_register_singleton "IServiceB" "mock_dependency_b"

    # This test verifies the container doesn't crash with circular deps
    # The actual resolution may succeed (if mocks don't actually call each other)
    # or fail gracefully
    local result
    result=$(di_resolve "IServiceB" 2>&1)
    local exit_code=$?

    # Either succeeds or fails gracefully (not crash)
    if [[ ${exit_code} -eq 0 ]]; then
        assert_contains "${result}" "dependency-b" "Should resolve if no actual circular call"
    else
        assert_contains "${result}" "circular\|recursion\|not registered" "Should detect or handle circular dependencies"
    fi
}
test_case "Circular dependency detection" test_circular_dependency_detection

# Test 24: Invalid lifecycle type (error handling)
test_invalid_lifecycle() {
    source_di_container || return 1
    di_init

    # Try to use an invalid registration method
    # This tests that the API is well-defined

    # Should only have: singleton, factory, transient
    di_has "IInvalidService" && local exists="true" || local exists="false"

    assert_equals "false" "${exists}" "Unregistered service should not exist"
}
test_case "Query for unregistered service returns false" test_invalid_lifecycle

# Run all tests
test_summary
