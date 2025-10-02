# WoW System Developer Guide

Version: 4.3.0

A comprehensive guide for developers extending the WoW System with custom handlers, integrations, and modifications.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Architecture Overview](#architecture-overview)
3. [Creating Custom Handlers](#creating-custom-handlers)
4. [Testing Custom Handlers](#testing-custom-handlers)
5. [Integration Patterns](#integration-patterns)
6. [Best Practices](#best-practices)
7. [Advanced Topics](#advanced-topics)
8. [Troubleshooting Development](#troubleshooting-development)

---

## Getting Started

### Prerequisites

- Bash 4.0 or higher
- jq (JSON processor)
- Basic understanding of bash scripting
- Familiarity with Claude Code tools

### Development Environment Setup

```bash
# Clone the repository (after GitHub setup)
git clone https://github.com/yourusername/wow-system.git
cd wow-system

# Run the installer
bash install.sh

# Run all tests to verify setup
bash tests/test-framework.sh tests/test-*.sh
```

### Repository Structure

```
wow-system/
├── src/
│   ├── core/                    # Core modules
│   │   ├── utils.sh
│   │   ├── file-storage.sh
│   │   ├── state-manager.sh
│   │   ├── config-loader.sh
│   │   └── session-manager.sh
│   ├── infrastructure/          # Infrastructure modules
│   │   ├── orchestrator.sh
│   │   └── handler-router.sh
│   ├── handlers/                # Security handlers
│   │   ├── bash-handler.sh
│   │   ├── write-handler.sh
│   │   ├── edit-handler.sh
│   │   ├── read-handler.sh
│   │   ├── glob-handler.sh
│   │   ├── grep-handler.sh
│   │   ├── task-handler.sh
│   │   └── webfetch-handler.sh
│   ├── engines/                 # Analytical engines
│   │   ├── scoring-engine.sh
│   │   └── risk-assessor.sh
│   └── ui/                      # UI components
│       └── display.sh
├── tests/                       # Test suites
│   ├── test-framework.sh
│   └── test-*.sh
├── config/                      # Configuration
│   └── wow-config.json
├── hooks/                       # Claude Code hooks
│   └── user-prompt-submit.sh
└── docs/                        # Documentation
    ├── API-REFERENCE.md
    └── DEVELOPER-GUIDE.md (this file)
```

---

## Architecture Overview

### Design Patterns

The WoW System uses several Gang of Four design patterns:

#### 1. Facade Pattern (Orchestrator)
```bash
# Complex subsystem initialization hidden behind simple interface
orchestrator_init "/path/to/wow-system"
# Instead of manually initializing each module
```

#### 2. Strategy Pattern (Handler Router)
```bash
# Handlers are swappable strategies for different tools
handler_register "Bash" "${handler_dir}/bash-handler.sh"
handler_register "Write" "${handler_dir}/write-handler.sh"
```

#### 3. Observer Pattern (Session Events)
```bash
# Components observe session events
session_event "violation" "Dangerous command blocked"
# Multiple observers can react (scoring, logging, display)
```

#### 4. Template Method Pattern (Handler Interface)
```bash
# All handlers follow the same template
handle_<toolname> <json_params>
  - Validate input
  - Assess risk
  - Make decision
  - Update metrics
  - Return result
```

### SOLID Principles

The architecture follows SOLID principles:

- **Single Responsibility**: Each module has one clear purpose
- **Open/Closed**: Extensible through handlers, closed to modification
- **Liskov Substitution**: All handlers are interchangeable
- **Interface Segregation**: Clean, minimal interfaces
- **Dependency Inversion**: Depend on abstractions (handler interface), not concrete implementations

---

## Creating Custom Handlers

### Step 1: Handler Template

Create a new handler file in `src/handlers/`:

```bash
#!/bin/bash
# custom-handler.sh - Security handler for CustomTool

# Double-sourcing protection
[[ -n "${CUSTOM_HANDLER_LOADED:-}" ]] && return 0
readonly CUSTOM_HANDLER_LOADED=1

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/../core/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../core/state-manager.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../engines/scoring-engine.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../engines/risk-assessor.sh"

# Constants
readonly MAX_CUSTOM_OPS_PER_SESSION=50

# Global variables for handler output
WOW_BLOCK_REASON=""
WOW_WARN_REASON=""
WOW_RISK_LEVEL=""

#######################################
# Check if operation matches dangerous pattern
# Arguments:
#   $1 - Operation parameter to check
# Returns:
#   0 if dangerous, 1 if safe
#######################################
_is_dangerous_pattern() {
  local param="$1"

  # Check for dangerous patterns
  if [[ "$param" =~ pattern1 ]]; then
    return 0
  fi

  return 1
}

#######################################
# Check if operation exceeds rate limits
# Returns:
#   0 if within limits, 1 if exceeded
#######################################
_check_rate_limit() {
  local count
  count=$(state_get "custom_count" 2>/dev/null || echo "0")

  if [[ $count -ge $MAX_CUSTOM_OPS_PER_SESSION ]]; then
    return 1
  fi

  return 0
}

#######################################
# Main handler function for CustomTool
# Arguments:
#   $1 - JSON parameters
# Returns:
#   0 if allowed, 1 if blocked, 2 if warning
# Sets:
#   WOW_BLOCK_REASON - Reason for blocking
#   WOW_WARN_REASON - Reason for warning
#   WOW_RISK_LEVEL - Risk assessment
#######################################
handle_custom() {
  local json_params="$1"

  # Reset output variables
  WOW_BLOCK_REASON=""
  WOW_WARN_REASON=""
  WOW_RISK_LEVEL="none"

  # Extract parameters using jq
  local param1
  param1=$(echo "$json_params" | jq -r '.param1 // empty')

  # Validate required parameters
  if [[ -z "$param1" ]]; then
    WOW_BLOCK_REASON="Missing required parameter: param1"
    log "ERROR" "$WOW_BLOCK_REASON"
    return 1
  fi

  # Check rate limits
  if ! _check_rate_limit; then
    WOW_BLOCK_REASON="Rate limit exceeded: max $MAX_CUSTOM_OPS_PER_SESSION operations per session"
    log "WARN" "$WOW_BLOCK_REASON"
    score_penalize 15 "Rate limit exceeded"
    session_event "violation" "$WOW_BLOCK_REASON"
    return 1
  fi

  # Check for dangerous patterns
  if _is_dangerous_pattern "$param1"; then
    WOW_BLOCK_REASON="Dangerous pattern detected in parameter"
    WOW_RISK_LEVEL="critical"
    log "ERROR" "$WOW_BLOCK_REASON"
    score_penalize 25 "Dangerous pattern"
    session_event "violation" "$WOW_BLOCK_REASON"
    state_increment "violations"
    return 1
  fi

  # Perform risk assessment
  WOW_RISK_LEVEL=$(risk_assess "custom" "$json_params")

  # Update metrics
  state_increment "custom_count"
  state_increment "operations"
  session_event "success" "Custom operation allowed"

  log "INFO" "Custom operation allowed: $param1"
  return 0
}

#######################################
# Self-test function
#######################################
_custom_handler_selftest() {
  echo "Testing custom handler..."

  # Test 1: Valid operation
  if handle_custom '{"param1": "safe_value"}'; then
    echo "✓ Test 1 passed: Valid operation allowed"
  else
    echo "✗ Test 1 failed: Valid operation blocked"
    return 1
  fi

  # Test 2: Dangerous pattern
  if handle_custom '{"param1": "pattern1"}'; then
    echo "✗ Test 2 failed: Dangerous pattern not blocked"
    return 1
  else
    echo "✓ Test 2 passed: Dangerous pattern blocked"
  fi

  echo "Custom handler self-test passed!"
  return 0
}

# Run self-test if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _custom_handler_selftest
fi
```

### Step 2: Register Handler

Add registration in `src/handlers/handler-router.sh`:

```bash
# In handler_router_init function
handler_register "CustomTool" "${handler_dir}/custom-handler.sh"
```

### Step 3: Create Test Suite

Create `tests/test-custom-handler.sh`:

```bash
#!/bin/bash
# test-custom-handler.sh - Test suite for custom handler

source "$(dirname "${BASH_SOURCE[0]}")/test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../src/handlers/custom-handler.sh"

# Initialize
state_init
score_init

echo "Testing Custom Handler..."

# Test 1: Valid operation
if handle_custom '{"param1": "safe_value"}'; then
  assert_equals "" "$WOW_BLOCK_REASON" "Valid operation should not be blocked"
  assert_equals "none" "$WOW_RISK_LEVEL" "Risk level should be none"
else
  test_fail "Valid operation was blocked"
fi

# Test 2: Missing parameter
if handle_custom '{}'; then
  test_fail "Missing parameter should be blocked"
else
  assert_contains "$WOW_BLOCK_REASON" "Missing required parameter" "Should indicate missing parameter"
fi

# Test 3: Dangerous pattern
if handle_custom '{"param1": "pattern1"}'; then
  test_fail "Dangerous pattern should be blocked"
else
  assert_contains "$WOW_BLOCK_REASON" "Dangerous pattern" "Should indicate dangerous pattern"
  assert_equals "critical" "$WOW_RISK_LEVEL" "Risk level should be critical"
fi

# Test 4: Rate limiting
for i in {1..50}; do
  handle_custom '{"param1": "test"}' >/dev/null 2>&1
done

if handle_custom '{"param1": "test"}'; then
  test_fail "Rate limit should be enforced"
else
  assert_contains "$WOW_BLOCK_REASON" "Rate limit exceeded" "Should indicate rate limit"
fi

echo "All tests passed!"
```

### Step 4: Update Documentation

Add handler documentation to README.md:

```markdown
#### CustomTool Handler

**Purpose**: Secure CustomTool operations

**Blocks:**
- Dangerous pattern1
- Operations exceeding rate limit (50/session)

**Warns:**
- (none currently)

**Allows:**
- Safe custom operations

**Test:** `bash tests/test-custom-handler.sh`
```

---

## Testing Custom Handlers

### Test-Driven Development (TDD) Approach

The WoW System uses strict TDD:

1. **Red Phase**: Write failing tests first
2. **Green Phase**: Implement handler to pass tests
3. **Refactor Phase**: Clean up code while keeping tests passing

### Test Structure

Each handler should have 24 tests covering:

- **Valid operations** (6 tests): Operations that should be allowed
- **Blocked operations** (6 tests): Operations that should be blocked
- **Warning operations** (6 tests): Operations that should warn
- **Edge cases** (6 tests): Boundary conditions, rate limits, etc.

### Example Test Suite

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/test-framework.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../src/handlers/custom-handler.sh"

echo "Testing Custom Handler (24 tests)..."

# Initialize
state_init
score_init

# === ALLOWED OPERATIONS (6 tests) ===
echo "Testing allowed operations..."

# Test 1: Safe operation
handle_custom '{"param1": "safe"}'
assert_success $? "Safe operation should be allowed"

# Test 2-6: More allowed cases...

# === BLOCKED OPERATIONS (6 tests) ===
echo "Testing blocked operations..."

# Test 7: Dangerous pattern
handle_custom '{"param1": "pattern1"}'
assert_failure $? "Dangerous pattern should be blocked"
assert_contains "$WOW_BLOCK_REASON" "dangerous" "Should explain why blocked"

# Test 8-12: More blocked cases...

# === WARNING OPERATIONS (6 tests) ===
echo "Testing warning operations..."

# Test 13: Suspicious but allowed
result=$(handle_custom '{"param1": "suspicious"}')
if [[ $? -eq 2 ]]; then
  assert_contains "$WOW_WARN_REASON" "suspicious" "Should warn on suspicious"
fi

# Test 14-18: More warning cases...

# === EDGE CASES (6 tests) ===
echo "Testing edge cases..."

# Test 19: Empty parameter
handle_custom '{"param1": ""}'
assert_failure $? "Empty parameter should be blocked"

# Test 20: Rate limiting
for i in {1..51}; do
  handle_custom '{"param1": "test"}' >/dev/null 2>&1
done
assert_contains "$WOW_BLOCK_REASON" "rate limit" "Should enforce rate limit"

# Test 21-24: More edge cases...

echo "All 24 tests passed!"
```

### Running Tests

```bash
# Run specific handler tests
bash tests/test-custom-handler.sh

# Run all handler tests
for test in tests/test-*-handler.sh; do
  echo "=== Running $test ==="
  bash "$test"
done

# Run complete test suite
bash tests/test-framework.sh tests/test-*.sh
```

---

## Integration Patterns

### Pattern 1: Pre-Hook Integration

Intercept operations before execution:

```bash
#!/bin/bash
# In Claude Code hook: ~/.claude/hooks/user-prompt-submit.sh

WOW_DIR="/path/to/wow-system"
source "$WOW_DIR/src/infrastructure/orchestrator.sh"
orchestrator_init "$WOW_DIR"

tool_name="$1"
json_params="$2"

# Route through handler
if ! handler_route "$tool_name" "$json_params"; then
  echo "❌ WoW System blocked operation"
  echo "Reason: $WOW_BLOCK_REASON"
  echo "Risk Level: $WOW_RISK_LEVEL"
  echo "Current Score: $(state_get wow_score)"
  exit 1
fi

# If warning issued
if [[ -n "$WOW_WARN_REASON" ]]; then
  echo "⚠️  Warning: $WOW_WARN_REASON"
fi

exit 0
```

### Pattern 2: Wrapper Integration

Wrap tool calls with security checks:

```bash
#!/bin/bash
# secure_write.sh - Wrapper for Write tool

secure_write() {
  local file_path="$1"
  local content="$2"

  # Prepare JSON
  local json_params
  json_params=$(jq -n \
    --arg fp "$file_path" \
    --arg c "$content" \
    '{file_path: $fp, content: $c}')

  # Check with handler
  if ! handler_route "Write" "$json_params"; then
    echo "Write blocked: $WOW_BLOCK_REASON"
    return 1
  fi

  # Perform actual write
  echo "$content" > "$file_path"
}

# Usage
secure_write "/tmp/test.txt" "Hello World"
```

### Pattern 3: API Integration

Expose WoW System as an API:

```bash
#!/bin/bash
# wow-api.sh - HTTP API wrapper

handle_api_request() {
  local request="$1"

  # Parse request (pseudo-code)
  local tool=$(parse_tool "$request")
  local params=$(parse_params "$request")

  # Route through handler
  if handler_route "$tool" "$params"; then
    return_json "{ \"allowed\": true, \"risk\": \"$WOW_RISK_LEVEL\" }"
  else
    return_json "{ \"allowed\": false, \"reason\": \"$WOW_BLOCK_REASON\" }"
  fi
}
```

---

## Best Practices

### Handler Design

1. **Defense in Depth**: Multiple layers of validation
   ```bash
   # Check path
   if _is_system_path "$path"; then return 1; fi

   # Check content
   if _has_malicious_content "$content"; then return 1; fi

   # Check rate
   if ! _check_rate_limit; then return 1; fi
   ```

2. **Fail-Safe Design**: Block on ambiguity
   ```bash
   # If uncertain, block
   if [[ -z "$param" ]] || ! _can_validate "$param"; then
     WOW_BLOCK_REASON="Cannot validate parameter"
     return 1
   fi
   ```

3. **Clear Error Messages**: Explain why blocked
   ```bash
   WOW_BLOCK_REASON="Cannot write to system directory: $path"
   # Not: WOW_BLOCK_REASON="Blocked"
   ```

4. **Comprehensive Logging**: Log all decisions
   ```bash
   log "INFO" "Operation allowed: $operation"
   log "WARN" "Suspicious pattern: $pattern"
   log "ERROR" "Blocked dangerous operation: $details"
   ```

5. **Metric Tracking**: Track all operations
   ```bash
   state_increment "custom_count"
   state_increment "operations"
   session_event "violation" "$reason"
   ```

### Code Organization

1. **Use Helper Functions**: Keep handlers readable
   ```bash
   # Good
   if _is_dangerous_command "$cmd"; then
     _block_operation "Dangerous command"
     return 1
   fi

   # Bad
   if [[ "$cmd" =~ rm.*-rf ]] || [[ "$cmd" =~ dd.*if= ]]; then
     WOW_BLOCK_REASON="Dangerous command detected"
     log "ERROR" "$WOW_BLOCK_REASON"
     score_penalize 50 "Dangerous command"
     return 1
   fi
   ```

2. **Consistent Naming**: Follow conventions
   - Public functions: `handle_custom`, `custom_init`
   - Private helpers: `_is_dangerous`, `_check_rate`
   - Constants: `MAX_OPERATIONS`, `BLOCKED_PATTERNS`

3. **Double-Sourcing Protection**: Prevent re-initialization
   ```bash
   [[ -n "${CUSTOM_HANDLER_LOADED:-}" ]] && return 0
   readonly CUSTOM_HANDLER_LOADED=1
   ```

### Testing Best Practices

1. **Test First**: Write tests before implementation
2. **Complete Coverage**: Test allowed, blocked, warned, edge cases
3. **Clear Assertions**: Explain what each test validates
4. **Independent Tests**: Each test should be self-contained
5. **Meaningful Messages**: Test failure messages should guide debugging

---

## Advanced Topics

### Custom Risk Assessment

Extend risk assessment for custom operations:

```bash
# In risk-assessor.sh, add custom risk scoring

risk_score_custom_operation() {
  local params="$1"
  local score=0

  # Extract custom parameters
  local param1=$(echo "$params" | jq -r '.param1 // empty')

  # Custom risk logic
  if [[ "$param1" =~ dangerous ]]; then
    score=$((score + 50))
  fi

  echo "$score"
}
```

### Custom Scoring Rules

Add custom scoring behavior:

```bash
# In scoring-engine.sh, add custom rewards/penalties

score_custom_reward() {
  local operation="$1"

  case "$operation" in
    "safe_pattern")
      score_reward 5 "Using safe pattern"
      ;;
    "best_practice")
      score_reward 10 "Following best practice"
      ;;
  esac
}
```

### Multi-Handler Coordination

Coordinate between multiple handlers:

```bash
# In handler-router.sh

handler_route_with_coordination() {
  local tool="$1"
  local params="$2"

  # Check primary handler
  if ! handler_route "$tool" "$params"; then
    return 1
  fi

  # Cross-check with related handlers
  if [[ "$tool" == "Write" ]]; then
    # Also validate with Edit handler logic
    if _requires_edit_validation "$params"; then
      handler_route "Edit" "$params"
    fi
  fi

  return 0
}
```

### Plugin System

Create a plugin system for extensions:

```bash
# plugins/example-plugin.sh

plugin_init() {
  echo "Initializing example plugin..."

  # Register custom hooks
  hook_register "pre_operation" "_plugin_pre_op"
  hook_register "post_operation" "_plugin_post_op"
}

_plugin_pre_op() {
  local operation="$1"
  # Custom pre-operation logic
}

_plugin_post_op() {
  local operation="$1"
  local result="$2"
  # Custom post-operation logic
}
```

---

## Troubleshooting Development

### Common Issues

#### Issue 1: Handler Not Registered

**Symptom**: Handler not called when tool is invoked

**Solution**:
```bash
# Check handler registration
grep "handler_register.*CustomTool" src/handlers/handler-router.sh

# Verify handler is sourced correctly
source src/infrastructure/orchestrator.sh
orchestrator_init
handler_list  # Should show CustomTool
```

#### Issue 2: JSON Parsing Errors

**Symptom**: `jq` errors or empty parameter values

**Solution**:
```bash
# Validate JSON syntax
echo "$json_params" | jq '.'

# Check for special characters
echo "$json_params" | jq -r '.param1' | od -c

# Use proper jq syntax
param1=$(echo "$json_params" | jq -r '.param1 // empty')  # Good
param1=$(echo "$json_params" | jq '.param1')  # Bad (includes quotes)
```

#### Issue 3: State Not Persisting

**Symptom**: Metrics reset between operations

**Solution**:
```bash
# Ensure state is saved
state_set "custom_count" "5"
state_save  # Important!

# Ensure state is loaded
state_init
state_load  # Important!
```

#### Issue 4: Tests Failing

**Symptom**: Handler works but tests fail

**Solution**:
```bash
# Reset state between tests
state_init
score_init

# Clear previous state
rm -f /tmp/wow-state-*

# Check for test interdependencies
# Each test should be independent
```

### Debugging Tools

#### Enable Debug Logging

```bash
# In config/wow-config.json
{
  "logging": {
    "level": "DEBUG",
    "file": "/tmp/wow-debug.log"
  }
}

# View debug log
tail -f /tmp/wow-debug.log
```

#### Trace Handler Execution

```bash
# Add set -x to handler
set -x  # Enable trace
handle_custom "$params"
set +x  # Disable trace
```

#### Inspect State

```bash
# View all state
state_list

# View specific keys
state_get "custom_count"
state_get "wow_score"
state_get "violations"
```

#### Verify Risk Assessment

```bash
# Test risk assessment directly
risk_assess "custom" '{"param1": "test"}'

# Should output: none/low/medium/high/critical
```

---

## Contributing

### Contribution Workflow

1. **Fork Repository**: Create your own fork
2. **Create Branch**: `git checkout -b feature/custom-handler`
3. **Write Tests**: Follow TDD methodology (24 tests minimum)
4. **Implement Handler**: Pass all tests
5. **Update Documentation**: Add to README.md, API-REFERENCE.md
6. **Submit PR**: Include test results and documentation

### Code Review Checklist

- [ ] All tests passing (100%)
- [ ] Follows TDD methodology
- [ ] Double-sourcing protection implemented
- [ ] Error messages are clear and helpful
- [ ] Logging added at appropriate levels
- [ ] Metrics tracking implemented
- [ ] Documentation updated
- [ ] Self-test function included
- [ ] Follows naming conventions
- [ ] No hardcoded paths
- [ ] Security-first design

---

## Resources

### Internal Documentation

- [API Reference](./API-REFERENCE.md)
- [README](../README.md)
- [Implementation Plan](../IMPLEMENTATION-PLAN.md)
- [Release Notes](../RELEASE-NOTES.md)

### External Resources

- [Bash Best Practices](https://google.github.io/styleguide/shellguide.html)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- [Gang of Four Design Patterns](https://refactoring.guru/design-patterns)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)

---

## Support

For development questions or issues:

**Author**: Chude <chude@emeke.org>

**Repository**: (pending GitHub setup)

---

Last Updated: 2025-10-02
