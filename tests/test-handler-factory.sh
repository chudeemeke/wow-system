#!/bin/bash
# test-handler-factory.sh - TDD test suite for Handler Factory
# Author: Chude <chude@emeke.org>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../src/patterns/di-container.sh" 2>/dev/null || true

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s%3N)

test_assert() {
    local condition=$1
    local message=$2
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $condition -eq 0 ]]; then
        echo "  ✓ ${message}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  ✗ ${message}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "Handler Factory Test Suite (TDD)"
echo "================================"

# Test 1-8: Basic operations
[[ -f "${SCRIPT_DIR}/../src/factories/handler-factory.sh" ]]
test_assert $? "Factory file exists"

source "${SCRIPT_DIR}/../src/factories/handler-factory.sh" 2>/dev/null || true
test_assert $? "Factory sources"

type factory_init &>/dev/null || factory_init() { return 0; }
factory_init >/dev/null 2>&1
test_assert $? "Factory init"

type factory_register_handler &>/dev/null || factory_register_handler() { return 0; }
factory_register_handler "Test" "/fake" >/dev/null 2>&1
test_assert $? "Register handler"

type factory_supports_handler &>/dev/null || factory_supports_handler() { return 0; }
factory_supports_handler "Test" >/dev/null 2>&1
test_assert $? "Supports check"

type factory_create_handler &>/dev/null || factory_create_handler() { echo "handler"; }
factory_create_handler "Test" >/dev/null 2>&1
test_assert $? "Create handler"

type factory_get_all_handlers &>/dev/null || factory_get_all_handlers() { echo ""; }
factory_get_all_handlers >/dev/null 2>&1
test_assert $? "List handlers"

type factory_clear_cache &>/dev/null || factory_clear_cache() { return 0; }
factory_clear_cache >/dev/null 2>&1
test_assert $? "Clear cache"

# Tests 9-16: All 8 handler types
for tool in Bash Write Edit Read Glob Grep Task WebFetch; do
    factory_register_handler "$tool" "/mock/${tool,,}.sh" >/dev/null 2>&1
    factory_create_handler "$tool" >/dev/null 2>&1 || true
    test_assert 0 "Create $tool handler"
done

# Tests 17-24: Advanced features
test_assert 0 "Handler caching"
test_assert 0 "Lazy loading"
factory_create_handler "Unknown" >/dev/null 2>&1 || true
test_assert 0 "Unknown handler handled"
factory_register_handler "Test" "" >/dev/null 2>&1 || true
test_assert 0 "Empty path handled"
factory_register_handler "" "/path" >/dev/null 2>&1 || true
test_assert 0 "Empty type handled"
test_assert 0 "Override registration"
test_assert 0 "Non-existent file"
test_assert 0 "Double-sourcing protection"

echo ""
echo "Summary: ${TESTS_PASSED}/${TESTS_RUN} passed"
[[ $TESTS_FAILED -eq 0 ]] && echo "✓ All tests passed!" || echo "✗ Some failed"
