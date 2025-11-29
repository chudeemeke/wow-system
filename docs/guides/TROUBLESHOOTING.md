# WoW System Troubleshooting Guide

Version: 4.3.0

Comprehensive troubleshooting guide for diagnosing and resolving issues with the WoW System.

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Installation Issues](#installation-issues)
3. [Runtime Issues](#runtime-issues)
4. [Handler Issues](#handler-issues)
5. [Integration Issues](#integration-issues)
6. [Performance Issues](#performance-issues)
7. [Configuration Issues](#configuration-issues)
8. [Testing Issues](#testing-issues)
9. [Recovery Procedures](#recovery-procedures)
10. [Getting Help](#getting-help)

---

## Quick Diagnostics

### System Health Check

Run this quick diagnostic to check overall system health:

```bash
#!/bin/bash
# health-check.sh

echo "WoW System Health Check"
echo "======================="

# Check bash version
bash_version=$(bash --version | head -1)
echo "Bash version: $bash_version"
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "❌ Bash 4.0+ required"
else
  echo "✓ Bash version OK"
fi

# Check jq
if command -v jq >/dev/null 2>&1; then
  echo "✓ jq installed: $(jq --version)"
else
  echo "❌ jq not installed"
fi

# Check WoW installation
if [[ -f "src/infrastructure/orchestrator.sh" ]]; then
  echo "✓ WoW System found"
else
  echo "❌ WoW System not found"
fi

# Check configuration
if [[ -f "config/wow-config.json" ]]; then
  if jq '.' config/wow-config.json >/dev/null 2>&1; then
    echo "✓ Configuration valid"
  else
    echo "❌ Configuration invalid JSON"
  fi
else
  echo "❌ Configuration file missing"
fi

# Check handlers
handler_count=$(find src/handlers -name "*-handler.sh" 2>/dev/null | wc -l)
echo "Handlers found: $handler_count"
if [[ $handler_count -eq 8 ]]; then
  echo "✓ All handlers present"
else
  echo "⚠️  Expected 8 handlers, found $handler_count"
fi

# Check tests
test_count=$(find tests -name "test-*.sh" 2>/dev/null | wc -l)
echo "Test files found: $test_count"

# Test orchestrator initialization
if source src/infrastructure/orchestrator.sh 2>/dev/null; then
  if orchestrator_init "$(pwd)" 2>/dev/null; then
    echo "✓ Orchestrator initialization OK"
  else
    echo "❌ Orchestrator initialization failed"
  fi
else
  echo "❌ Failed to source orchestrator"
fi

echo "======================="
echo "Health check complete"
```

---

## Installation Issues

### Issue 1: Installation Fails with "Permission Denied"

**Symptom:**
```
bash: ./install.sh: Permission denied
```

**Cause:** Script doesn't have execute permissions

**Solution:**
```bash
chmod +x install.sh
bash install.sh
```

---

### Issue 2: jq Not Found

**Symptom:**
```
Error: jq is required but not installed
```

**Cause:** jq JSON processor not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# macOS
brew install jq

# CentOS/RHEL
sudo yum install -y jq

# Verify installation
jq --version
```

---

### Issue 3: Bash Version Too Old

**Symptom:**
```
Error: Bash 4.0+ required, found 3.2
```

**Cause:** System bash is too old (common on macOS)

**Solution:**
```bash
# macOS - install newer bash
brew install bash

# Update shell
sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'
chsh -s /usr/local/bin/bash

# Verify version
bash --version
```

---

### Issue 4: Installation Succeeds but Tests Fail

**Symptom:**
```
Installation complete but some tests failed
```

**Diagnostic:**
```bash
# Run tests individually to identify failing module
bash tests/test-state-manager.sh
bash tests/test-config-loader.sh
bash tests/test-session-manager.sh
# etc.
```

**Solution:** See [Testing Issues](#testing-issues) section

---

## Runtime Issues

### Issue 5: "Module Already Loaded" Errors

**Symptom:**
```
Error: Attempting to redefine readonly variable
```

**Cause:** Module sourced multiple times without double-sourcing protection

**Solution:**
```bash
# Ensure all modules have double-sourcing protection
[[ -n "${MODULE_NAME_LOADED:-}" ]] && return 0
readonly MODULE_NAME_LOADED=1
```

**Verification:**
```bash
# Check module for protection
grep "readonly.*LOADED" src/handlers/bash-handler.sh
```

---

### Issue 6: State Not Persisting

**Symptom:** Metrics reset between operations or sessions

**Cause:** State not being saved or loaded properly

**Diagnostic:**
```bash
# Check state directory
ls -la /tmp/wow-state-* 2>/dev/null

# Check state save/load
source src/core/state-manager.sh
state_init
state_set "test_key" "test_value"
state_save
# Should create file in /tmp/

# In new shell
source src/core/state-manager.sh
state_init
state_load
state_get "test_key"
# Should output: test_value
```

**Solution:**
```bash
# Ensure state_save is called
session_end() {
  state_save  # Add this
  # ... other cleanup
}

# Ensure state_load is called
session_start() {
  state_load  # Add this
  # ... other initialization
}
```

---

### Issue 7: JSON Parsing Errors

**Symptom:**
```
jq: parse error: Invalid numeric literal at line 1, column 5
```

**Cause:** Malformed JSON or special characters

**Diagnostic:**
```bash
# Validate JSON
echo "$json_params" | jq '.'

# Check for special characters
echo "$json_params" | od -c

# Pretty print
echo "$json_params" | jq -r '.'
```

**Solution:**
```bash
# Properly escape JSON
json_params=$(jq -n \
  --arg cmd "$command" \
  '{command: $cmd}')

# Not:
json_params="{\"command\": \"$command\"}"  # Can break with special chars
```

---

### Issue 8: Handlers Not Being Called

**Symptom:** Operations proceed without security checks

**Diagnostic:**
```bash
# Check handler registration
source src/infrastructure/orchestrator.sh
orchestrator_init
handler_list

# Should show:
# Bash -> /path/to/bash-handler.sh
# Write -> /path/to/write-handler.sh
# etc.
```

**Solution:**
```bash
# Ensure handlers are registered in handler-router.sh
handler_register "Bash" "${handler_dir}/bash-handler.sh"
handler_register "Write" "${handler_dir}/write-handler.sh"
# etc.

# Ensure handler-router is initialized
orchestrator_init  # Should initialize router
```

---

## Handler Issues

### Issue 9: Handler Blocks Safe Operations

**Symptom:** Valid operations are being blocked incorrectly

**Diagnostic:**
```bash
# Enable debug logging
export WOW_LOG_LEVEL="DEBUG"

# Run operation
handle_bash '{"command": "ls -la"}'

# Check logs
tail -f /tmp/wow-system.log

# Check block reason
echo "Block reason: $WOW_BLOCK_REASON"
echo "Risk level: $WOW_RISK_LEVEL"
```

**Solution:**
```bash
# Review handler logic
# Adjust patterns to be less restrictive
# Example: In bash-handler.sh

# Too restrictive:
if [[ "$cmd" =~ rm ]]; then
  block  # Blocks ALL rm commands
fi

# Better:
if [[ "$cmd" =~ rm.*-rf.*/ ]]; then
  block  # Only blocks dangerous rm -rf /
fi
```

---

### Issue 10: Handler Allows Dangerous Operations

**Symptom:** Dangerous operations not being blocked

**Diagnostic:**
```bash
# Test specific dangerous operation
handle_bash '{"command": "rm -rf /"}'

# Should return 1 (blocked)
echo $?  # Check return code

# Check handler logic
grep "rm.*-rf" src/handlers/bash-handler.sh
```

**Solution:**
```bash
# Add missing pattern to handler
# In bash-handler.sh

readonly DANGEROUS_COMMANDS=(
  "rm -rf /"
  "sudo rm -rf"
  # Add new patterns
  "dd if=/dev/zero"
  "mkfs.*"
  # etc.
)
```

**Testing:**
```bash
# Add test case
# In tests/test-bash-handler.sh

handle_bash '{"command": "new_dangerous_command"}'
assert_failure $? "Should block new_dangerous_command"
```

---

### Issue 11: Rate Limiting Not Working

**Symptom:** Rate limits not being enforced

**Diagnostic:**
```bash
# Check rate limit counter
source src/core/state-manager.sh
state_init
state_load

# Check count
state_get "bash_count"
state_get "operations"
```

**Solution:**
```bash
# Ensure counter is incremented
handle_bash() {
  # ... validation logic ...

  # Increment counter (make sure this exists)
  state_increment "bash_count"
  state_increment "operations"

  # Check rate limit
  local count=$(state_get "bash_count")
  if [[ $count -gt $MAX_BASH_OPS ]]; then
    block "Rate limit exceeded"
  fi
}
```

---

## Integration Issues

### Issue 12: Claude Code Hook Not Triggering

**Symptom:** WoW System not intercepting Claude Code operations

**Diagnostic:**
```bash
# Check hook location
ls -la ~/.claude/hooks/user-prompt-submit.sh

# Check hook permissions
stat ~/.claude/hooks/user-prompt-submit.sh

# Check Claude Code config
cat ~/.claude/config.json | jq '.hooks'
```

**Solution:**
```bash
# Ensure hook is executable
chmod +x ~/.claude/hooks/user-prompt-submit.sh

# Verify hook path in config
{
  "hooks": {
    "user_prompt_submit": "~/.claude/hooks/user-prompt-submit.sh"
  }
}

# Test hook manually
bash ~/.claude/hooks/user-prompt-submit.sh "Bash" '{"command": "ls"}'
```

---

### Issue 13: Hook Blocks All Operations

**Symptom:** All Claude Code operations blocked, even safe ones

**Diagnostic:**
```bash
# Check hook exit codes
bash -x ~/.claude/hooks/user-prompt-submit.sh "Bash" '{"command": "ls"}'

# Should show:
# + handler_route Bash {"command": "ls"}
# + return 0
# + exit 0
```

**Solution:**
```bash
# Ensure hook exits with correct code
# In user-prompt-submit.sh

if handler_route "$tool_name" "$json_params"; then
  exit 0  # Allow operation
else
  echo "Blocked: $WOW_BLOCK_REASON"
  exit 1  # Block operation
fi

# Not:
exit 1  # Always blocks!
```

---

### Issue 14: Hook Errors Not Visible

**Symptom:** Hook failing silently, no error messages

**Diagnostic:**
```bash
# Redirect errors to file
bash ~/.claude/hooks/user-prompt-submit.sh "Bash" '{"command": "ls"}' 2>/tmp/hook-errors.log

# Check errors
cat /tmp/hook-errors.log
```

**Solution:**
```bash
# Add error handling to hook
# In user-prompt-submit.sh

exec 2>/tmp/wow-hook-errors.log  # Log errors

set -e  # Exit on error
set -u  # Exit on undefined variable

# Add error checks
if [[ ! -f "$WOW_DIR/src/infrastructure/orchestrator.sh" ]]; then
  echo "ERROR: WoW System not found at $WOW_DIR" >&2
  exit 1
fi
```

---

## Performance Issues

### Issue 15: Slow Handler Response

**Symptom:** Operations take too long (>1 second)

**Diagnostic:**
```bash
# Measure handler time
time handle_bash '{"command": "ls"}'

# Profile specific functions
PS4='+ $(date "+%s.%N")\011 '
set -x
handle_bash '{"command": "ls"}'
set +x
```

**Solution:**
```bash
# Optimize slow operations

# Bad: Multiple jq calls
param1=$(echo "$json" | jq -r '.param1')
param2=$(echo "$json" | jq -r '.param2')
param3=$(echo "$json" | jq -r '.param3')

# Good: Single jq call
read -r param1 param2 param3 < <(echo "$json" | jq -r '.param1, .param2, .param3')

# Bad: Repeated grep in loop
for pattern in "${patterns[@]}"; do
  echo "$text" | grep "$pattern"  # Slow
done

# Good: Single grep with alternation
echo "$text" | grep -E "pattern1|pattern2|pattern3"

# Cache frequently accessed values
if [[ -z "${CACHED_CONFIG:-}" ]]; then
  CACHED_CONFIG=$(config_get "enforcement.strict_mode")
fi
```

---

### Issue 16: High Memory Usage

**Symptom:** WoW System consuming excessive memory

**Diagnostic:**
```bash
# Check memory usage
ps aux | grep "wow\|bash.*handler"

# Check state file sizes
du -sh /tmp/wow-state-*
```

**Solution:**
```bash
# Clean up old state files
find /tmp -name "wow-state-*" -mtime +7 -delete

# Limit history size
# In state-manager.sh
readonly MAX_HISTORY_SIZE=100

state_add_history() {
  # ... add entry ...

  # Trim if too large
  local count=$(state_get "history_count")
  if [[ $count -gt $MAX_HISTORY_SIZE ]]; then
    # Remove oldest entries
    state_trim_history
  fi
}
```

---

## Configuration Issues

### Issue 17: Configuration Not Loaded

**Symptom:** Default values used instead of configured values

**Diagnostic:**
```bash
# Check config file
cat config/wow-config.json | jq '.'

# Check if config is loaded
source src/core/config-loader.sh
config_init "config/wow-config.json"

# Get specific value
config_get "enforcement.strict_mode"
```

**Solution:**
```bash
# Ensure config_init is called
# In orchestrator.sh

orchestrator_init() {
  # ... other initialization ...

  # Load configuration
  config_init "${module_dir}/config/wow-config.json"

  # ... rest of initialization ...
}
```

---

### Issue 18: Invalid Configuration JSON

**Symptom:**
```
jq: parse error: Expected separator between values
```

**Diagnostic:**
```bash
# Validate JSON syntax
jq '.' config/wow-config.json

# Find syntax errors
jq -e '.' config/wow-config.json || echo "Invalid JSON at line $?"
```

**Solution:**
```bash
# Fix JSON syntax errors

# Bad:
{
  "key1": "value1"
  "key2": "value2"  # Missing comma
}

# Good:
{
  "key1": "value1",
  "key2": "value2"
}

# Validate after fixing
jq '.' config/wow-config.json
```

---

## Testing Issues

### Issue 19: Tests Fail with "Command Not Found"

**Symptom:**
```
bash: assert_equals: command not found
```

**Cause:** Test framework not sourced

**Solution:**
```bash
# Ensure test framework is sourced first
source "$(dirname "${BASH_SOURCE[0]}")/test-framework.sh"

# Then source module under test
source "$(dirname "${BASH_SOURCE[0]}")/../src/handlers/bash-handler.sh"
```

---

### Issue 20: Tests Pass Individually but Fail Together

**Symptom:** Running all tests fails, but individual tests pass

**Cause:** Test interdependencies, shared state

**Diagnostic:**
```bash
# Run tests individually
bash tests/test-bash-handler.sh  # Passes
bash tests/test-write-handler.sh  # Passes

# Run together
bash tests/test-framework.sh tests/test-*.sh  # Fails
```

**Solution:**
```bash
# Reset state between tests
# In each test file

# Before tests
state_init
score_init

# Between tests (if needed)
reset_state() {
  rm -f /tmp/wow-state-*
  state_init
  score_init
}
```

---

### Issue 21: Assertion Failures Not Clear

**Symptom:** Test fails but message doesn't explain why

**Diagnostic:**
```bash
# Review assertion message
assert_equals "expected" "actual" "Should match"
# vs
assert_equals "expected" "actual" ""  # Bad: no message
```

**Solution:**
```bash
# Always provide clear assertion messages

# Bad:
assert_equals "$expected" "$actual" ""

# Good:
assert_equals "$expected" "$actual" "Command should match expected pattern"

# Even better:
assert_equals "$expected" "$actual" \
  "Command should be 'ls -la' but got '$actual'"
```

---

## Recovery Procedures

### Procedure 1: Complete Reset

If system is in bad state, perform complete reset:

```bash
#!/bin/bash
# reset-wow-system.sh

echo "Resetting WoW System..."

# Stop all WoW processes
pkill -f "wow-system"

# Clear state
rm -f /tmp/wow-state-*
rm -f /tmp/wow-system.log

# Clear session data
rm -f /tmp/wow-session-*

# Reinitialize
source src/infrastructure/orchestrator.sh
orchestrator_init "$(pwd)"

# Verify
if handler_list >/dev/null 2>&1; then
  echo "✓ Reset successful"
else
  echo "❌ Reset failed"
  exit 1
fi
```

---

### Procedure 2: Recover Lost State

If state is lost or corrupted:

```bash
#!/bin/bash
# recover-state.sh

echo "Recovering state..."

# Backup corrupted state
mkdir -p backups
cp /tmp/wow-state-* backups/ 2>/dev/null || true

# Remove corrupted state
rm -f /tmp/wow-state-*

# Reinitialize with defaults
source src/core/state-manager.sh
state_init

# Set default values
state_set "wow_score" "100"
state_set "wow_status" "excellent"
state_set "violations" "0"
state_set "warnings" "0"
state_set "operations" "0"

# Save
state_save

echo "✓ State recovered with defaults"
```

---

### Procedure 3: Rebuild Handler Registry

If handlers not registering:

```bash
#!/bin/bash
# rebuild-handlers.sh

echo "Rebuilding handler registry..."

source src/infrastructure/handler-router.sh

# Re-register all handlers
handler_dir="$(pwd)/src/handlers"

handler_register "Bash" "${handler_dir}/bash-handler.sh"
handler_register "Write" "${handler_dir}/write-handler.sh"
handler_register "Edit" "${handler_dir}/edit-handler.sh"
handler_register "Read" "${handler_dir}/read-handler.sh"
handler_register "Glob" "${handler_dir}/glob-handler.sh"
handler_register "Grep" "${handler_dir}/grep-handler.sh"
handler_register "Task" "${handler_dir}/task-handler.sh"
handler_register "WebFetch" "${handler_dir}/webfetch-handler.sh"

# Verify
echo "Registered handlers:"
handler_list

echo "✓ Handlers rebuilt"
```

---

## Getting Help

### Debug Information to Collect

When reporting issues, provide:

```bash
# System information
uname -a
bash --version
jq --version

# WoW System version
cat config/wow-config.json | jq -r '.version'

# Handler status
source src/infrastructure/orchestrator.sh
orchestrator_init
handler_list

# Recent logs
tail -100 /tmp/wow-system.log

# State information
source src/core/state-manager.sh
state_init
state_load
echo "Score: $(state_get wow_score)"
echo "Violations: $(state_get violations)"
echo "Operations: $(state_get operations)"

# Test results
bash tests/test-framework.sh tests/test-*.sh 2>&1 | tee test-results.log
```

### Creating Minimal Reproduction

```bash
#!/bin/bash
# minimal-repro.sh - Minimal script to reproduce issue

# Initialize system
source src/infrastructure/orchestrator.sh
orchestrator_init "$(pwd)"

# Reproduce issue
handle_bash '{"command": "problematic_command"}'

# Show result
echo "Exit code: $?"
echo "Block reason: $WOW_BLOCK_REASON"
echo "Warn reason: $WOW_WARN_REASON"
echo "Risk level: $WOW_RISK_LEVEL"
```

### Support Channels

- **Author**: Chude <chude@emeke.org>
- **Repository Issues**: (pending GitHub setup)
- **Documentation**: See [API Reference](./API-REFERENCE.md) and [Developer Guide](./DEVELOPER-GUIDE.md)

---

## Common Error Messages

### Error Message Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `jq: command not found` | jq not installed | Install jq: `apt-get install jq` or `brew install jq` |
| `Permission denied` | Script not executable | `chmod +x script.sh` |
| `Bash 4.0+ required` | Old bash version | Upgrade bash: `brew install bash` |
| `Module already loaded` | Double-sourcing without protection | Add sourcing protection |
| `Invalid JSON` | Malformed JSON | Validate with `jq '.'` |
| `Handler not found` | Handler not registered | Check `handler_register` call |
| `State file not found` | State not initialized | Call `state_init` and `state_load` |
| `Config file not found` | Missing configuration | Copy from `config/wow-config.json` |
| `Rate limit exceeded` | Too many operations | Wait or adjust rate limits |
| `Operation blocked` | Security policy violation | Check `$WOW_BLOCK_REASON` for details |

---

Last Updated: 2025-10-02
