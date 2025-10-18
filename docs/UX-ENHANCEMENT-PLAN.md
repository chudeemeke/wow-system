# WoW System v5.1.0 → v5.2.0: UX Enhancement Implementation Plan

## Executive Summary

Complete the UX layer for WoW System with four critical enhancements: score display on violations, session banner, unknown tool tracking, and performance benchmarking framework.

---

## Design Philosophy

**System Thinking Approach:**
- Observer Pattern for event-driven UX updates
- Facade Pattern for simplified UX API
- Strategy Pattern for pluggable display modes
- Decorator Pattern for enhanced functionality without core changes

**Architectural Principles:**
- Non-invasive: UX layer doesn't alter core security logic
- Performance-conscious: Minimal overhead (<5ms per operation)
- Fail-silent: UX errors don't break operations
- Configurable: All features can be enabled/disabled
- Testable: Complete TDD coverage

---

## Feature 1: Score Display on Violations

### Problem Statement
Users don't see their WoW score or know when violations occur, reducing awareness and learning opportunities.

### Architecture

**Observer Pattern Implementation:**
```
Violation Event → Event Bus → Score Display Subscriber → UI Renderer
```

**Components:**
1. **Event Subscription** (src/ui/score-display.sh)
   - Subscribe to: `security_violation`, `score_updated`, `threshold_crossed`
   - Render score gauge when triggered
   - Display violation details

2. **Score Gauge Renderer** (src/ui/display.sh - extend)
   - ASCII art gauge (0-100 scale)
   - Color-coded status (excellent/good/warn/critical/blocked)
   - Violation summary
   - Recent history (last 3 violations)

3. **Integration Point** (hooks/user-prompt-submit.sh)
   - After handler returns exit code 2 (block)
   - Call score_display_on_violation()

**Display Format:**
```
╔══════════════════════════════════════╗
║  ⚠️  SECURITY VIOLATION DETECTED     ║
╠══════════════════════════════════════╣
║  WoW Score: 60/100 (▼10)             ║
║  Status: ⚠️  WARNING                  ║
║                                      ║
║  Score Gauge:                        ║
║  [████████████░░░░░░░░] 60%          ║
║                                      ║
║  Violation: Path traversal detected  ║
║  Path: ../../etc/passwd              ║
║  Handler: read-handler               ║
║                                      ║
║  Recent Violations: 3 (last hour)    ║
╚══════════════════════════════════════╝
```

### Configuration
```json
{
  "ui": {
    "score_display": {
      "enabled": true,
      "show_on_violation": true,
      "show_gauge": true,
      "show_history": true,
      "max_history_items": 3
    }
  }
}
```

### Test Coverage
- Violation triggers display (24 test cases)
- Score calculation correct
- Color coding matches thresholds
- History tracking accurate
- Configuration flags respected
- Edge cases: no violations, score at extremes (0, 100)

---

## Feature 2: Session Start Banner

### Problem Statement
Users don't know if WoW system is active or what version is running.

### Architecture

**Initialization Hook:**
```
Hook First Invocation → Session Init → Display Banner → Continue
```

**Components:**
1. **Banner Generator** (src/ui/display.sh - extend)
   - System info (version, status)
   - Configuration summary (enforcement mode, fast path status)
   - Quick stats (handlers loaded, session start time)

2. **First-Run Detection** (hooks/user-prompt-submit.sh)
   - Check for session marker file
   - If missing: first run → display banner
   - Create marker to prevent repeat

3. **Session Lifecycle Integration** (src/core/session-manager.sh)
   - on_session_start() callback
   - Register banner display as subscriber

**Display Format:**
```
╔══════════════════════════════════════════════════════════╗
║  WoW System v5.1.0 - Ways of Working Enforcement         ║
║  Status: ✅ Active                                        ║
╠══════════════════════════════════════════════════════════╣
║  Configuration:                                          ║
║  • Enforcement: Enabled                                  ║
║  • Fast Path: Enabled (70-80% faster)                    ║
║  • Handlers: 8 loaded (Bash, Write, Edit, Read, Glob,   ║
║              Grep, Task, WebFetch)                       ║
║  • Scoring: Enabled (threshold: warn=50, block=30)       ║
║                                                          ║
║  Session Info:                                           ║
║  • Started: 2025-10-17 14:23:05                          ║
║  • Location: ~/Projects/wow-system                       ║
║  • Initial Score: 70/100                                 ║
╚══════════════════════════════════════════════════════════╝
```

### Configuration
```json
{
  "ui": {
    "session_banner": {
      "enabled": true,
      "show_on_start": true,
      "show_config": true,
      "show_handlers": true
    }
  }
}
```

### Test Coverage
- Banner displays on first tool call
- Banner not repeated on subsequent calls
- All info sections render correctly
- Configuration flags control content
- Edge cases: missing config, handler load failures

---

## Feature 3: Unknown Tool Tracking

### Problem Statement
New tools (MCPs, Anthropic additions, custom tools) pass through silently. No visibility, can't add handlers proactively.

### Architecture

**Registry Pattern with Notification:**
```
Unknown Tool → Handler Router (miss) → Registry Logger → User Notification
```

**Components:**
1. **Tool Registry** (src/core/tool-registry.sh - NEW)
   - Known tools: List of registered handlers
   - Unknown tools: Track first seen, frequency
   - Tool metadata: name, first_seen, count, last_seen
   - Persistence: Store in state-manager

2. **Unknown Tool Detector** (src/handlers/handler-router.sh - extend)
   - On handler_route() miss
   - Log to registry
   - Emit event: `unknown_tool_detected`

3. **Notification System** (src/ui/tool-tracking.sh - NEW)
   - Subscribe to unknown_tool events
   - Display notification (first occurrence only)
   - Weekly summary option

**Display Format (First Occurrence):**
```
╔══════════════════════════════════════╗
║  ℹ️  NEW TOOL DETECTED                ║
╠══════════════════════════════════════╣
║  Tool: NotebookEdit                  ║
║  First seen: 2025-10-17 14:30:12     ║
║  Status: Passing through (no handler)║
║                                      ║
║  Action: Consider adding handler     ║
║  Security: Auto-allowed (fail-open)  ║
╚══════════════════════════════════════╝
```

**Summary Format (Weekly):**
```
╔══════════════════════════════════════╗
║  📊 UNKNOWN TOOLS SUMMARY (7 days)   ║
╠══════════════════════════════════════╣
║  NotebookEdit:     42 uses           ║
║  CustomMCP:        15 uses           ║
║  WebSearch:         8 uses           ║
║                                      ║
║  Recommendation: Add handlers for    ║
║  high-frequency tools (>20 uses)     ║
╚══════════════════════════════════════╝
```

### Configuration
```json
{
  "tool_tracking": {
    "enabled": true,
    "notify_on_first_use": true,
    "track_frequency": true,
    "weekly_summary": true
  }
}
```

### Test Coverage
- Unknown tool detection (24 test cases)
- Registry persistence
- Notification on first use only
- Frequency tracking accurate
- Summary generation
- Edge cases: empty registry, malformed tool names

---

## Feature 4: Performance Benchmark Framework

### Problem Statement
Need reproducible performance tests to prove fast path optimization claims (70-80% reduction).

### Architecture

**Benchmark Harness:**
```
Test Suite → Warmup → Timed Operations → Statistics → Report
```

**Components:**
1. **Benchmark Framework** (tests/benchmark-framework.sh - NEW)
   - Time measurement utilities
   - Statistical analysis (mean, median, p95, p99)
   - Comparison tools (before/after)
   - Report generation

2. **Fast Path Benchmarks** (tests/benchmark-fast-path.sh - NEW)
   - Measure: Read/Glob/Grep operations
   - Scenarios:
     - Safe files (should fast-path)
     - Suspicious files (should deep check)
     - Dangerous files (should block fast)
   - Compare: With/without fast path

3. **Handler Benchmarks** (tests/benchmark-handlers.sh - NEW)
   - Measure all 8 handlers
   - Baseline performance
   - Regression detection

**Benchmark Output:**
```
╔══════════════════════════════════════════════════════════╗
║  WoW System Performance Benchmarks                       ║
╠══════════════════════════════════════════════════════════╣
║  Fast Path Optimization - Read Handler                   ║
║                                                          ║
║  Scenario: Safe Files (package.json, src/*.ts)           ║
║  ├─ Without Fast Path: 68ms (mean), 72ms (p95)          ║
║  ├─ With Fast Path:     12ms (mean), 15ms (p95)         ║
║  └─ Improvement:        82% reduction ✅                  ║
║                                                          ║
║  Scenario: Suspicious Files (.env, credentials.json)     ║
║  ├─ Without Fast Path: 75ms (mean), 80ms (p95)          ║
║  ├─ With Fast Path:     45ms (mean), 50ms (p95)         ║
║  └─ Improvement:        40% reduction ✅                  ║
║                                                          ║
║  Scenario: Dangerous Files (/etc/passwd, ~/.ssh/id_rsa) ║
║  ├─ Without Fast Path: 70ms (mean), 75ms (p95)          ║
║  ├─ With Fast Path:     18ms (mean), 22ms (p95)         ║
║  └─ Improvement:        74% reduction ✅ (faster block)  ║
║                                                          ║
║  Parallel Operations (10 concurrent Reads):              ║
║  ├─ Without Fast Path: 685ms (causes API errors)        ║
║  ├─ With Fast Path:     125ms (no errors) ✅              ║
║  └─ Improvement:        82% reduction                    ║
╚══════════════════════════════════════════════════════════╝
```

### Configuration
```json
{
  "benchmarks": {
    "enabled": true,
    "iterations": 100,
    "warmup_runs": 10,
    "parallel_tests": true
  }
}
```

### Test Coverage
- Timing accuracy (±5ms tolerance)
- Statistical calculations correct
- Comparison logic sound
- Report formatting
- Regression detection
- Edge cases: zero operations, single operation

---

## Implementation Phases

### Phase 1: Core Infrastructure (TDD)
**Duration: 2-3 hours**
1. Create tool-registry.sh (TDD)
2. Create benchmark-framework.sh (TDD)
3. Extend display.sh with new renderers (TDD)
4. Update config schema

### Phase 2: Feature Implementation (TDD)
**Duration: 3-4 hours**
1. Score display on violations
   - Write tests (RED)
   - Implement (GREEN)
   - Integrate into hook
   - Refactor

2. Session start banner
   - Write tests (RED)
   - Implement (GREEN)
   - Integrate into session-manager
   - Refactor

3. Unknown tool tracking
   - Write tests (RED)
   - Implement tool-registry
   - Integrate into handler-router
   - Implement notifications
   - Refactor

4. Performance benchmarks
   - Write benchmark tests
   - Implement framework
   - Run baselines
   - Document results

### Phase 3: Integration & Testing
**Duration: 2-3 hours**
1. Integration testing
   - All features work together
   - No conflicts
   - Performance impact <5ms

2. Edge case testing
   - Error conditions
   - Boundary values
   - Concurrent access

3. Security validation
   - UI doesn't leak sensitive info
   - Display errors don't block operations
   - No injection vulnerabilities

4. Regression testing
   - All existing tests pass
   - Fast path still optimal
   - Handlers unchanged

### Phase 4: Documentation & Release
**Duration: 1 hour**
1. Update README.md
2. Update CLAUDE.md
3. Update wow-config.json
4. Version bump (5.1.0 → 5.2.0)
5. Git commit
6. Release notes

---

## Success Criteria

### Functional
- ✅ Score displays on every violation
- ✅ Banner shows on session start (once)
- ✅ Unknown tools tracked and notified
- ✅ Benchmarks run and report accurately

### Non-Functional
- ✅ UX overhead <5ms per operation
- ✅ All 108 existing tests still pass
- ✅ New features add 96+ tests (24 per feature)
- ✅ Zero security regressions
- ✅ Configuration backward compatible

### Quality
- ✅ 100% TDD coverage
- ✅ SOLID principles maintained
- ✅ Design patterns applied appropriately
- ✅ No code duplication
- ✅ Clear separation of concerns

---

## Risk Mitigation

**Risk 1: Display Overhead**
- Mitigation: Async rendering, caching
- Fallback: Disable UI via config

**Risk 2: Breaking Changes**
- Mitigation: Backward compatible config
- Fallback: Feature flags default to disabled

**Risk 3: Test Complexity**
- Mitigation: Reuse test-framework.sh
- Fallback: Manual validation protocol

**Risk 4: UI Injection**
- Mitigation: Sanitize all user input
- Fallback: Plain text mode (no colors/symbols)

---

## File Structure (New/Modified)

### New Files
```
src/
├── core/
│   └── tool-registry.sh           # Tool tracking (NEW)
├── ui/
│   ├── score-display.sh           # Violation display (NEW)
│   └── tool-tracking.sh           # Unknown tool notifications (NEW)
tests/
├── benchmark-framework.sh         # Benchmarking infrastructure (NEW)
├── benchmark-fast-path.sh         # Fast path benchmarks (NEW)
├── benchmark-handlers.sh          # Handler benchmarks (NEW)
├── test-tool-registry.sh          # Tool registry tests (NEW)
├── test-score-display.sh          # Score display tests (NEW)
└── test-tool-tracking.sh          # Tool tracking tests (NEW)
```

### Modified Files
```
src/
├── ui/
│   └── display.sh                 # Extend with new renderers
├── handlers/
│   └── handler-router.sh          # Add unknown tool detection
├── core/
│   └── session-manager.sh         # Add session start hook
hooks/
└── user-prompt-submit.sh          # Integrate score display + banner
config/
└── wow-config.json                # Add UI and tracking sections
```

---

## Performance Budget

**Per-Operation Overhead:**
- Score display: <2ms (only on violations)
- Tool tracking: <1ms (registry lookup)
- Session banner: <5ms (once per session)
- Benchmarking: N/A (testing only)

**Total UX Overhead: <3ms average per operation** (acceptable)

---

## Testing Strategy

### Unit Tests (96 new tests)
- Tool registry: 24 tests
- Score display: 24 tests
- Tool tracking: 24 tests
- Benchmark framework: 24 tests

### Integration Tests (20 tests)
- Score display + violation flow
- Banner + session start
- Tool tracking + handler router
- All features together

### Performance Tests (10 benchmarks)
- Fast path comparison
- Handler baselines
- Parallel operation stress test
- Memory usage

### Security Tests (10 tests)
- Display sanitization
- No sensitive data leaks
- Fail-silent behavior
- Configuration validation

---

## Rollout Plan

**Stage 1: Development (Current)**
- Implement features with TDD
- Local testing

**Stage 2: Alpha Testing**
- Enable in test environment
- Monitor for issues
- Collect feedback

**Stage 3: Beta Release (v5.2.0-beta)**
- Features disabled by default
- Opt-in via config
- Production validation

**Stage 4: Stable Release (v5.2.0)**
- Features enabled by default
- Full documentation
- Public availability

---

## Maintenance Plan

**Ongoing:**
- Performance monitoring
- User feedback integration
- Bug fixes within 48 hours

**Quarterly:**
- Benchmark regression testing
- Configuration tuning
- Feature enhancement review

**Annually:**
- Architecture review
- Refactoring sprints
- Major version planning

---

## Conclusion

This comprehensive plan ensures architectural soundness, complete test coverage, and zero security regressions while delivering critical UX enhancements. All features follow SOLID principles, use appropriate design patterns, and maintain the system's defensive security posture.

**Estimated Total Time: 8-11 hours**
**Estimated Test Coverage: 126+ new tests**
**Expected Version: 5.1.0 → 5.2.0**
