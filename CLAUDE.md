# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**WoW System v5.4.2** - Ways of Working Enforcement for Claude Code

A production-grade defensive security framework that intercepts Claude Code tool calls to prevent dangerous operations, enforce best practices, and maintain behavioral scoring.

**CRITICAL**: This codebase implements defensive security controls. All changes must maintain security guarantees and pass comprehensive testing.

## Architecture

### Hook-Based Interception System

The core workflow is:
1. Claude Code prepares a tool call (Bash, Write, Edit, Read, Glob, Grep, Task, WebFetch)
2. hooks/user-prompt-submit.sh intercepts via PreToolUse hook (exit 0 = allow, non-zero = block)
3. src/core/orchestrator.sh initializes system using Facade pattern
4. src/handlers/handler-router.sh routes to appropriate handler via Strategy pattern
5. Handler validates, modifies, or blocks operation
6. Response flows back to Claude Code in hookSpecificOutput JSON format

### Module Loading & Dependency Order

The orchestrator loads modules in strict dependency order:

1. Design Patterns (v5.0+): DI Container, Event Bus, Handler Factory
2. Core Foundation: utils.sh → file-storage.sh → state-manager.sh → config-loader.sh → session-manager.sh
3. Security Constants (v5.4.2+): security-constants.sh (shared SSRF patterns, Single Source of Truth)
4. Handlers: Loaded on-demand by handler-router.sh
5. Engines: scoring-engine.sh, risk-assessor.sh, capture-engine.sh (v5.0+)
6. Security: credential-detector.sh, credential-storage.sh (v5.0+)

**Double-sourcing protection**: All modules check WOW_*_LOADED guards to prevent re-initialization.

### Handler Contract

All handlers must implement this interface:

```bash
handle_<tool>() {
    local tool_input="$1"  # JSON from Claude Code
    
    # 1. Extract parameters using jq or regex fallback
    # 2. Validate operation (path, content, patterns)
    # 3. Track metrics: session_increment_metric "<tool>_count"
    # 4. Apply security checks (return 2 to BLOCK)
    # 5. Update WoW score if violations detected
    # 6. Return original or modified tool_input JSON
    
    echo "${tool_input}"  # Allow
    return 0
}
```

**Return Codes**:
- `0` = ALLOW (echo modified/original JSON)
- `1` = WARN (non-blocking, logs warning)
- `2` = BLOCK (operation prevented, Claude Code sees error)

**Exit Code Mapping** (hooks/user-prompt-submit.sh:237-241):
- Handler returns 0 → Hook exits 0 (allow)
- Handler returns 2 → Hook exits 1 (block)
- Handler returns 1 → Hook exits 0 but logs warning

## CRITICAL: Test-Driven Development (TDD)

**MANDATORY FOR ALL CODING TASKS:**

This project follows STRICT TDD methodology:

1. **RED**: Write failing test first (defines expected behavior)
2. **GREEN**: Write minimal code to make test pass
3. **REFACTOR**: Improve code while keeping tests green

**TDD Rules:**
- ❌ NEVER write production code without a failing test
- ✅ ALWAYS write tests before implementation
- ✅ Tests define the API/interface contract
- ✅ Each test should test ONE thing
- ✅ Keep tests simple, readable, and maintainable

**If you skip TDD, STOP and restart properly.**

See global `~/.claude/CLAUDE.md` for detailed TDD workflow.

## Development Commands

### Running Tests

```bash
# Run all test suites (23 total, 283+ tests)
for test in tests/test-*.sh; do bash "$test"; done

# Run specific handler test (24 tests each)
bash tests/test-bash-handler.sh
bash tests/test-write-handler.sh
bash tests/test-edit-handler.sh
bash tests/test-read-handler.sh
bash tests/test-glob-handler.sh
bash tests/test-grep-handler.sh
bash tests/test-task-handler.sh
bash tests/test-webfetch-handler.sh

# Run core infrastructure tests
bash tests/test-orchestrator.sh
bash tests/test-state-manager.sh
bash tests/test-session-manager.sh
```

### Installation & Setup

```bash
# Install WoW System
bash install.sh

# Manual initialization (for testing)
source src/core/orchestrator.sh
wow_init
wow_status

# Verify installation
bash install.sh  # Runs self-tests automatically
```

### Hook Testing

```bash
# Test hook directly (requires JSON input)
echo '{"tool_name":"Bash","tool_input":{"command":"echo test"}}' | bash hooks/user-prompt-submit.sh

# Enable debug logging
WOW_DEBUG=1 WOW_DEBUG_LOG=/tmp/wow-debug.log bash hooks/user-prompt-submit.sh
```

## Test-Driven Development (TDD) Workflow

This project follows strict TDD:

1. **RED**: Write failing test first
2. **GREEN**: Implement minimal code to pass
3. **REFACTOR**: Improve design while keeping tests green

### Test Framework Usage

```bash
# tests/test-new-feature.sh
source tests/test-framework.sh

test_suite "Feature Name Tests"

test_case "should do something" your_test_function
test_case "should handle edge case" edge_case_test

test_summary  # Returns 0 if all pass, 1 if any fail
```

### Assertions Available

- `assert_equals expected actual [message]`
- `assert_contains haystack needle [message]`
- `assert_file_exists path [message]`
- `assert_success [message]` (checks $?)
- See `tests/test-framework.sh` for full list

## Adding a New Handler

1. **Create test first** (TDD RED phase):
```bash
# tests/test-newtool-handler.sh
source tests/test-framework.sh
test_suite "NewTool Handler Tests"

test_case "should block dangerous operation" test_block_dangerous
test_case "should allow safe operation" test_allow_safe
# ... 24 tests minimum for comprehensive coverage

test_summary
```

2. **Create handler skeleton** (TDD GREEN phase):
```bash
# src/handlers/newtool-handler.sh
if [[ -n "${WOW_NEWTOOL_HANDLER_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_NEWTOOL_HANDLER_LOADED=1

handle_newtool() {
    local input="$1"
    # Extract params, validate, return exit code
}
```

3. **Register in handler-router.sh**:
```bash
handler_register "NewTool" "${handler_dir}/newtool-handler.sh"
```

4. **Run tests until green**, then refactor

## Configuration Management

### Config Hierarchy

1. `~/.claude/wow-config.json` (user-specific)
2. `${WOW_HOME}/config/wow-config.json` (installation default)
3. Hard-coded defaults in `config-loader.sh`

### Key Configuration Points

- `enforcement.enabled`: Master kill switch
- `enforcement.strict_mode`: Warnings become blocks
- `scoring.threshold_block`: Score below this blocks all operations (default: 30)
- `capture.email_alerts.enabled`: Frustration detection alerts (v5.0+)

## Security-Critical Patterns

### What Must NEVER Change

1. **Path traversal detection** (`../../` patterns) - prevents privilege escalation
2. **System directory blocks** (`/etc`, `/bin`, `/usr`, `/boot`, `/sys`, `/proc`, `/dev`) - prevents system corruption
3. **Credential detection patterns** - prevents secret leakage
4. **SSRF prevention** (private IPs, localhost) - prevents network attacks
5. **Hook fail-open behavior** - errors must not block legitimate operations

### Security Validation Checklist

Before merging security-sensitive changes:
- [ ] All existing tests pass (283+ tests)
- [ ] New tests cover attack vectors
- [ ] Credential patterns tested with real examples
- [ ] Path traversal tested with `../` variants
- [ ] Handler fails safely (exits 0 on error)
- [ ] No plaintext credential storage
- [ ] OS keychain integration tested (Linux Secret Service, macOS Keychain)

## Documentation Automation (v5.0.1+)

WoW uses **docTruth** for automated documentation synchronization:

```bash
# Generate/update CURRENT_TRUTH.md
doctruth

# Check if docs are outdated
doctruth --check

# Watch mode (auto-regenerate on changes)
doctruth --watch
```

Configuration in `.doctruth.yml`:
- 40+ truth sources (version, handlers, metrics, tests)
- 5 validations (version consistency, handler coverage, core modules, hooks, config)
- Integrated with capture-engine.sh for automatic updates

## v5.0+ Advanced Features

### Event Bus (Publish/Subscribe)
```bash
event_bus_publish "event_name" '{"key":"value"}'
event_bus_subscribe "event_name" callback_function
```

### Dependency Injection
```bash
di_register_singleton "IServiceName" "initialization_function"
di_resolve "IServiceName"  # Returns service instance
```

### Capture Engine (Frustration Detection)
- Analyzes patterns of blocks, errors, retries
- Confidence scoring: CRITICAL, HIGH, MEDIUM, LOW
- Auto-generates context-aware prompts for user assistance
- Respects 5-minute cooldown between prompts

### Credential Security
- Real-time detection: passwords, API keys, tokens, private keys
- Automatic redaction in logs
- Secure storage via OS keychain (zero plaintext)

## Common Pitfalls

1. **Don't bypass double-sourcing guards** - causes readonly variable errors
2. **Don't modify handler exit codes** - breaks security contract (0=allow, 1=warn, 2=block)
3. **Don't add blocking operations to hook** - must complete in <100ms
4. **Don't use jq without `wow_has_jq()` check** - hook must work without jq
5. **Don't hardcode paths** - use `${WOW_HOME}` and auto-discovery
6. **Always fail open in hooks** - errors should not block legitimate operations

## Debug & Troubleshooting

### Enable Debug Logging
```bash
export WOW_DEBUG=1
export WOW_DEBUG_LOG=/tmp/wow-debug.log
tail -f /tmp/wow-debug.log
```

### Check Module Load Status
```bash
source src/core/orchestrator.sh
wow_init
wow_modules_list
wow_status
```

### Verify Handler Registration
```bash
source src/handlers/handler-router.sh
handler_init
handler_router_list
```

### Session Metrics
```bash
# View current session metrics
cat ~/.wow-data/sessions/latest/metrics.json

# Or via API
source src/core/session-manager.sh
session_info
session_stats
```

## Version & Release Management

Current version: **5.0.1** (in `src/core/utils.sh`)

Version bumps require:
1. Update `WOW_VERSION` in `src/core/utils.sh`
2. Update README.md header
3. Update RELEASE-NOTES.md
4. Update orchestrator.sh version constant
5. Run `doctruth` to regenerate CURRENT_TRUTH.md
6. Tag release: `git tag -a v5.0.1 -m "Release v5.0.1"`

## Git Commit Standards

Per global CLAUDE.md rules:
- Author: ALWAYS "Chude <chude@emeke.org>"
- NO AI tool attribution (Claude Code, etc.)
- NO emojis in commits
- Professional, descriptive messages
- Follow conventional commits format when applicable

## Key Files Reference

- `hooks/user-prompt-submit.sh` - Main integration point with Claude Code (hooks/user-prompt-submit.sh:1-150)
- `src/core/orchestrator.sh` - System initialization (Facade pattern) (src/core/orchestrator.sh:1-352)
- `src/handlers/handler-router.sh` - Tool routing (Strategy pattern)
- `src/core/utils.sh` - **Single Source of Truth for WOW_VERSION**, logging, validation utilities
- `src/security/security-constants.sh` - **Shared security patterns** (BLOCKED_IP_PATTERNS for SSRF prevention)
- `config/wow-config.json` - Default configuration (config/wow-config.json:1-49)
- `tests/test-framework.sh` - Testing infrastructure (tests/test-framework.sh:1-364)
- `.doctruth.yml` - Documentation automation config (.doctruth.yml:1-80)

## Historical Context

**CRITICAL**: This project was rebuilt from v4.1 after v4.0.2 was accidentally deleted on September 30, 2025 via `rm -rf /mnt/c/Users/Destiny/.claude/`. The current architecture (standalone project in /Projects/ with symlink deployment to .claude/) was specifically designed to prevent this from happening again.

See `CONTEXT.md` for complete history: v1.0 → v2.0 → v3.5.0 → v4.0 → v4.0.2 (lost) → v4.1 → v5.0 → v5.0.1 → v5.4.0 → v5.4.1 → v5.4.2

## Self-Documentation Paradox

**Known Issue**: The WoW system's security features can block attempts to update its own documentation when example commands contain patterns that trigger security checks (even in quoted strings). This is documented in `docs/principles/v5.0/scratch.md`.

**Workaround**: Manually edit documentation files or temporarily disable specific handlers when updating docs.
