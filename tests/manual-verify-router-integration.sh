#!/bin/bash
# Manual Verification Script: Handler Router + Tool Registry Integration
# Quick sanity check that the integration works
# Author: Chude <chude@emeke.org>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Manual Verification: Handler Router + Tool Registry Integration ==="
echo ""

# Source modules
source "${SCRIPT_DIR}/../src/core/utils.sh"
source "${SCRIPT_DIR}/../src/core/file-storage.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/core/state-manager.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../src/handlers/handler-router.sh"

echo "✓ Modules sourced"

# Debug: Check if tool-registry functions are available
if type tool_registry_track_unknown &>/dev/null; then
    echo "✓ tool-registry functions available"
else
    echo "✗ tool-registry functions NOT available - source failed"
    exit 1
fi

# Initialize
handler_init
echo "✓ Handler router initialized"

# Test 1: Check known tools are registered
echo ""
echo "Test 1: Known tools should be registered in tool registry"
if tool_registry_is_known "Bash"; then
    echo "  ✓ Bash is registered as known tool"
else
    echo "  ✗ FAILED: Bash not registered"
    exit 1
fi

if tool_registry_is_known "Write"; then
    echo "  ✓ Write is registered as known tool"
else
    echo "  ✗ FAILED: Write not registered"
    exit 1
fi

# Test 2: Count known tools
known_count=$(tool_registry_count_known)
if [[ ${known_count} -eq 8 ]]; then
    echo "  ✓ Correct known tool count: ${known_count}"
else
    echo "  ✗ FAILED: Expected 8 known tools, got ${known_count}"
    exit 1
fi

# Test 3: Route unknown tool and verify tracking
echo ""
echo "Test 2: Unknown tools should be tracked"
unknown_input='{"tool": "CustomMCP", "parameters": {"test": "value"}}'
# Don't use subshell - call directly and redirect to temp file
handler_route "${unknown_input}" > /tmp/route_result.txt
result=$(cat /tmp/route_result.txt)

# Debug: Check array contents
echo "  [DEBUG] Unknown tools count: $(tool_registry_count_unknown)"
echo "  [DEBUG] Unknown tools list: $(tool_registry_list_unknown | tr '\n' ' ')"

if tool_registry_is_unknown "CustomMCP"; then
    echo "  ✓ CustomMCP tracked as unknown tool"
else
    echo "  ✗ FAILED: CustomMCP not tracked"
    # More debug info
    declare -p _UNKNOWN_TOOLS 2>/dev/null || echo "  [DEBUG] _UNKNOWN_TOOLS not declared"
    exit 1
fi

# Verify pass-through
if [[ "${result}" == "${unknown_input}" ]]; then
    echo "  ✓ Unknown tool passed through unchanged"
else
    echo "  ✗ FAILED: Unknown tool modified"
    exit 1
fi

# Test 4: Frequency tracking
echo ""
echo "Test 3: Frequency tracking should work"
handler_route "${unknown_input}" > /tmp/route_result2.txt
handler_route "${unknown_input}" > /tmp/route_result3.txt

freq_count=$(tool_registry_get_unknown_count "CustomMCP")
if [[ ${freq_count} -eq 3 ]]; then
    echo "  ✓ Frequency count correct: ${freq_count}"
else
    echo "  ✗ FAILED: Expected count 3, got ${freq_count}"
    exit 1
fi

# Test 5: Metadata capture
echo ""
echo "Test 4: Metadata should be captured"
metadata=$(tool_registry_get_unknown_metadata "CustomMCP")
if [[ -n "${metadata}" ]]; then
    echo "  ✓ Metadata captured"
    if wow_has_jq; then
        echo "    Tool: $(echo "${metadata}" | jq -r '.tool')"
        echo "    Count: $(echo "${metadata}" | jq -r '.count')"
        echo "    First seen: $(echo "${metadata}" | jq -r '.first_seen')"
    fi
else
    echo "  ✗ FAILED: No metadata captured"
    exit 1
fi

# Test 6: Known tool should not be tracked as unknown
echo ""
echo "Test 5: Known tools should NOT be tracked as unknown"
# Route a known tool (will fail because handler file doesn't exist in test context, but that's OK)
known_input='{"tool": "Read", "file_path": "/tmp/test"}'
handler_route "${known_input}" > /tmp/route_known.txt 2>&1 || true

if ! tool_registry_is_unknown "Read"; then
    echo "  ✓ Known tool (Read) not tracked as unknown"
else
    echo "  ✗ FAILED: Known tool incorrectly tracked as unknown"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "All manual verification tests PASSED! ✓"
echo "=========================================="
echo ""
echo "Integration verified:"
echo "  • Known tools registered in tool registry"
echo "  • Unknown tools tracked on route"
echo "  • Frequency counting works"
echo "  • Metadata captured correctly"
echo "  • Known tools not tracked as unknown"
echo ""
