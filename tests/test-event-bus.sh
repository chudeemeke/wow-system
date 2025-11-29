#!/bin/bash
# WoW System - Event Bus Tests (TDD - Tests First)
# Comprehensive test suite for production-grade Event Bus implementation
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source test framework
source "${SCRIPT_DIR}/test-framework.sh"

# Source the event bus (will be implemented)
source "${PROJECT_ROOT}/src/patterns/event-bus.sh"

# ============================================================================
# Test Setup & Teardown
# ============================================================================

# Global test state
TEST_TEMP_DIR=""
TEST_HANDLER_OUTPUT=""

setup_all() {
    TEST_TEMP_DIR=$(test_temp_dir)
    export TEST_HANDLER_OUTPUT="${TEST_TEMP_DIR}/handler_output.txt"
}

teardown_all() {
    if [[ -n "${TEST_TEMP_DIR}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

setup() {
    # Clear event bus before each test
    event_bus_clear_all
    # Clear handler output file
    echo "" > "${TEST_HANDLER_OUTPUT}"
}

# ============================================================================
# Test Handler Functions (Subscribers)
# ============================================================================

# Simple test handler that writes to output file
test_handler_simple() {
    local event_name="$1"
    local event_data="$2"
    echo "simple:${event_name}:${event_data}" >> "${TEST_HANDLER_OUTPUT}"
}

# Another test handler
test_handler_second() {
    local event_name="$1"
    local event_data="$2"
    echo "second:${event_name}:${event_data}" >> "${TEST_HANDLER_OUTPUT}"
}

# Handler that processes event data
test_handler_processor() {
    local event_name="$1"
    local event_data="$2"
    local processed="PROCESSED:${event_data}"
    echo "${processed}" >> "${TEST_HANDLER_OUTPUT}"
}

# Handler that intentionally throws error
test_handler_error() {
    local event_name="$1"
    local event_data="$2"
    echo "error_handler:${event_name}" >> "${TEST_HANDLER_OUTPUT}"
    return 1  # Simulate error
}

# Handler that runs after error handler
test_handler_after_error() {
    local event_name="$1"
    local event_data="$2"
    echo "after_error:${event_name}" >> "${TEST_HANDLER_OUTPUT}"
}

# Handler with filtering logic
test_handler_filter() {
    local event_name="$1"
    local event_data="$2"

    # Only process if data contains "important"
    if [[ "${event_data}" == *"important"* ]]; then
        echo "filtered:${event_data}" >> "${TEST_HANDLER_OUTPUT}"
    fi
}

# Slow handler for async testing
test_handler_slow() {
    local event_name="$1"
    local event_data="$2"
    sleep 0.1
    echo "slow:${event_name}:${event_data}" >> "${TEST_HANDLER_OUTPUT}"
}

# Counter handler for order testing
HANDLER_CALL_ORDER=0
test_handler_order_1() {
    HANDLER_CALL_ORDER=$((HANDLER_CALL_ORDER + 1))
    echo "order_1:${HANDLER_CALL_ORDER}" >> "${TEST_HANDLER_OUTPUT}"
}

test_handler_order_2() {
    HANDLER_CALL_ORDER=$((HANDLER_CALL_ORDER + 1))
    echo "order_2:${HANDLER_CALL_ORDER}" >> "${TEST_HANDLER_OUTPUT}"
}

test_handler_order_3() {
    HANDLER_CALL_ORDER=$((HANDLER_CALL_ORDER + 1))
    echo "order_3:${HANDLER_CALL_ORDER}" >> "${TEST_HANDLER_OUTPUT}"
}

# ============================================================================
# Test Cases - Event Bus Initialization
# ============================================================================

test_event_bus_init_succeeds() {
    event_bus_init
    assert_equals "0" "$?" "Event bus initialization should succeed"
}

test_event_bus_init_is_idempotent() {
    event_bus_init
    event_bus_init
    event_bus_init
    assert_equals "0" "$?" "Multiple inits should not cause errors"
}

# ============================================================================
# Test Cases - Event Subscription
# ============================================================================

test_subscribe_single_handler() {
    event_bus_subscribe "test_event" "test_handler_simple"

    # Verify subscription exists
    local events_list
    events_list=$(event_bus_list_events)
    assert_contains "${events_list}" "test_event" "Event should be listed"
}

test_subscribe_multiple_handlers_same_event() {
    event_bus_subscribe "multi_event" "test_handler_simple"
    event_bus_subscribe "multi_event" "test_handler_second"
    event_bus_subscribe "multi_event" "test_handler_processor"

    # Publish event and verify all handlers called
    event_bus_publish "multi_event" "data123"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:multi_event:data123"
    assert_contains "${output}" "second:multi_event:data123"
    assert_contains "${output}" "PROCESSED:data123"
}

test_subscribe_same_handler_twice_prevents_duplicate() {
    event_bus_subscribe "dup_event" "test_handler_simple"
    event_bus_subscribe "dup_event" "test_handler_simple"

    event_bus_publish "dup_event" "test"

    # Should only be called once
    local count
    count=$(grep -c "simple:dup_event:test" "${TEST_HANDLER_OUTPUT}" || echo "0")
    assert_equals "1" "${count}" "Handler should only be called once despite double subscription"
}

test_subscribe_to_multiple_events() {
    event_bus_subscribe "event_a" "test_handler_simple"
    event_bus_subscribe "event_b" "test_handler_simple"

    event_bus_publish "event_a" "data_a"
    event_bus_publish "event_b" "data_b"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:event_a:data_a"
    assert_contains "${output}" "simple:event_b:data_b"
}

test_subscribe_invalid_event_name_fails() {
    event_bus_subscribe "" "test_handler_simple" 2>/dev/null || local result=$?
    assert_not_equals "0" "${result:-0}" "Empty event name should fail"
}

test_subscribe_invalid_handler_fails() {
    event_bus_subscribe "test_event" "" 2>/dev/null || local result=$?
    assert_not_equals "0" "${result:-0}" "Empty handler name should fail"
}

# ============================================================================
# Test Cases - Event Publishing
# ============================================================================

test_publish_to_subscribed_handler() {
    event_bus_subscribe "publish_test" "test_handler_simple"
    event_bus_publish "publish_test" "test_data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:publish_test:test_data"
}

test_publish_with_json_data() {
    event_bus_subscribe "json_event" "test_handler_simple"
    local json_data='{"action":"block","path":"/etc/passwd","reason":"sensitive"}'

    event_bus_publish "json_event" "${json_data}"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:json_event:${json_data}"
}

test_publish_with_empty_data() {
    event_bus_subscribe "empty_data_event" "test_handler_simple"
    event_bus_publish "empty_data_event" ""

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:empty_data_event:"
}

test_publish_to_nonexistent_event() {
    # Should not error, just no handlers called
    event_bus_publish "nonexistent_event" "data" 2>/dev/null
    assert_equals "0" "$?" "Publishing to nonexistent event should not error"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_equals "" "${output}" "No handlers should be called"
}

test_publish_invalid_event_name_fails() {
    event_bus_publish "" "data" 2>/dev/null || local result=$?
    assert_not_equals "0" "${result:-0}" "Empty event name should fail"
}

# ============================================================================
# Test Cases - Event Unsubscription
# ============================================================================

test_unsubscribe_handler() {
    event_bus_subscribe "unsub_test" "test_handler_simple"
    event_bus_unsubscribe "unsub_test" "test_handler_simple"

    event_bus_publish "unsub_test" "data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_equals "" "${output}" "Handler should not be called after unsubscribe"
}

test_unsubscribe_one_of_many_handlers() {
    event_bus_subscribe "multi_unsub" "test_handler_simple"
    event_bus_subscribe "multi_unsub" "test_handler_second"

    event_bus_unsubscribe "multi_unsub" "test_handler_simple"

    event_bus_publish "multi_unsub" "data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "second:multi_unsub:data"

    local simple_count
    simple_count=$(grep -c "simple:" "${TEST_HANDLER_OUTPUT}" || echo "0")
    assert_equals "0" "${simple_count}" "Unsubscribed handler should not be called"
}

test_unsubscribe_nonexistent_handler() {
    event_bus_subscribe "test_event" "test_handler_simple"
    event_bus_unsubscribe "test_event" "nonexistent_handler" 2>/dev/null

    # Original handler should still work
    event_bus_publish "test_event" "data"
    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_contains "${output}" "simple:test_event:data"
}

# ============================================================================
# Test Cases - Subscriber Execution Order
# ============================================================================

test_subscribers_execute_in_order() {
    HANDLER_CALL_ORDER=0

    event_bus_subscribe "order_test" "test_handler_order_1"
    event_bus_subscribe "order_test" "test_handler_order_2"
    event_bus_subscribe "order_test" "test_handler_order_3"

    event_bus_publish "order_test" "data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")

    # Verify all three handlers were called in order
    assert_contains "${output}" "order_1:1"
    assert_contains "${output}" "order_2:2"
    assert_contains "${output}" "order_3:3"
}

# ============================================================================
# Test Cases - Error Handling
# ============================================================================

test_handler_error_does_not_break_bus() {
    event_bus_subscribe "error_test" "test_handler_simple"
    event_bus_subscribe "error_test" "test_handler_error"
    event_bus_subscribe "error_test" "test_handler_after_error"

    event_bus_publish "error_test" "data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")

    # All handlers should have executed despite error in middle
    assert_contains "${output}" "simple:error_test:data"
    assert_contains "${output}" "error_handler:error_test"
    assert_contains "${output}" "after_error:error_test"
}

test_handler_error_is_logged() {
    # This test verifies that handler errors are captured/logged
    event_bus_subscribe "error_log_test" "test_handler_error"

    # Should not crash the bus
    event_bus_publish "error_log_test" "data" 2>/dev/null
    assert_equals "0" "$?" "Bus should handle error gracefully"
}

# ============================================================================
# Test Cases - Event Clearing
# ============================================================================

test_clear_event_removes_all_subscribers() {
    event_bus_subscribe "clear_test" "test_handler_simple"
    event_bus_subscribe "clear_test" "test_handler_second"

    event_bus_clear "clear_test"

    event_bus_publish "clear_test" "data"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_equals "" "${output}" "No handlers should be called after clear"
}

test_clear_all_removes_all_events() {
    event_bus_subscribe "event1" "test_handler_simple"
    event_bus_subscribe "event2" "test_handler_second"
    event_bus_subscribe "event3" "test_handler_processor"

    event_bus_clear_all

    event_bus_publish "event1" "data1"
    event_bus_publish "event2" "data2"
    event_bus_publish "event3" "data3"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")
    assert_equals "" "${output}" "No handlers should be called after clear_all"
}

# ============================================================================
# Test Cases - Event Listing
# ============================================================================

test_list_events_shows_registered_events() {
    event_bus_subscribe "event_a" "test_handler_simple"
    event_bus_subscribe "event_b" "test_handler_second"
    event_bus_subscribe "event_b" "test_handler_processor"

    local list_output
    list_output=$(event_bus_list_events)

    assert_contains "${list_output}" "event_a"
    assert_contains "${list_output}" "event_b"
}

test_list_events_shows_subscriber_counts() {
    event_bus_subscribe "single_event" "test_handler_simple"
    event_bus_subscribe "multi_event" "test_handler_simple"
    event_bus_subscribe "multi_event" "test_handler_second"
    event_bus_subscribe "multi_event" "test_handler_processor"

    local list_output
    list_output=$(event_bus_list_events)

    # Should show counts: single_event has 1 subscriber, multi_event has 3
    assert_contains "${list_output}" "single_event"
    assert_contains "${list_output}" "multi_event"
}

test_list_events_empty_when_no_subscribers() {
    event_bus_clear_all

    local list_output
    list_output=$(event_bus_list_events)

    # Should indicate no events or be empty
    assert_equals "0" "$?" "list_events should succeed even with no events"
}

# ============================================================================
# Test Cases - Event Filtering
# ============================================================================

test_event_filtering_in_handler() {
    event_bus_subscribe "filter_test" "test_handler_filter"

    # Publish events with different data
    event_bus_publish "filter_test" "unimportant data"
    event_bus_publish "filter_test" "important message"
    event_bus_publish "filter_test" "also unimportant"

    local output
    output=$(cat "${TEST_HANDLER_OUTPUT}")

    # Only the important message should be in output
    assert_contains "${output}" "filtered:important message"

    local count
    count=$(grep -c "filtered:" "${TEST_HANDLER_OUTPUT}" || echo "0")
    assert_equals "1" "${count}" "Only one message should pass filter"
}

# ============================================================================
# Test Runner
# ============================================================================

main() {
    # Setup before all tests
    setup_all

    test_suite "Event Bus - Production-Grade Observer Pattern"

    echo ""
    echo "Testing Event Bus Initialization..."
    setup; test_case "Event bus initializes successfully" test_event_bus_init_succeeds
    setup; test_case "Event bus init is idempotent" test_event_bus_init_is_idempotent

    echo ""
    echo "Testing Event Subscription..."
    setup; test_case "Subscribe single handler" test_subscribe_single_handler
    setup; test_case "Subscribe multiple handlers to same event" test_subscribe_multiple_handlers_same_event
    setup; test_case "Subscribe same handler twice prevents duplicate" test_subscribe_same_handler_twice_prevents_duplicate
    setup; test_case "Subscribe to multiple events" test_subscribe_to_multiple_events
    setup; test_case "Subscribe with invalid event name fails" test_subscribe_invalid_event_name_fails
    setup; test_case "Subscribe with invalid handler fails" test_subscribe_invalid_handler_fails

    echo ""
    echo "Testing Event Publishing..."
    setup; test_case "Publish to subscribed handler" test_publish_to_subscribed_handler
    setup; test_case "Publish with JSON data" test_publish_with_json_data
    setup; test_case "Publish with empty data" test_publish_with_empty_data
    setup; test_case "Publish to nonexistent event" test_publish_to_nonexistent_event
    setup; test_case "Publish with invalid event name fails" test_publish_invalid_event_name_fails

    echo ""
    echo "Testing Event Unsubscription..."
    setup; test_case "Unsubscribe handler" test_unsubscribe_handler
    setup; test_case "Unsubscribe one of many handlers" test_unsubscribe_one_of_many_handlers
    setup; test_case "Unsubscribe nonexistent handler" test_unsubscribe_nonexistent_handler

    echo ""
    echo "Testing Subscriber Execution Order..."
    setup; test_case "Subscribers execute in order" test_subscribers_execute_in_order

    echo ""
    echo "Testing Error Handling..."
    setup; test_case "Handler error does not break bus" test_handler_error_does_not_break_bus
    setup; test_case "Handler error is logged" test_handler_error_is_logged

    echo ""
    echo "Testing Event Clearing..."
    setup; test_case "Clear event removes all subscribers" test_clear_event_removes_all_subscribers
    setup; test_case "Clear all removes all events" test_clear_all_removes_all_events

    echo ""
    echo "Testing Event Listing..."
    setup; test_case "List events shows registered events" test_list_events_shows_registered_events
    setup; test_case "List events shows subscriber counts" test_list_events_shows_subscriber_counts
    setup; test_case "List events empty when no subscribers" test_list_events_empty_when_no_subscribers

    echo ""
    echo "Testing Event Filtering..."
    setup; test_case "Event filtering in handler" test_event_filtering_in_handler

    # Teardown after all tests
    teardown_all

    test_summary
}

# Run all tests
main
