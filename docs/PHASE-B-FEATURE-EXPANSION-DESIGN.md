# Phase B: Feature Expansion - Design Document

**Version**: WoW System v5.3.0 → v5.4.0
**Date**: 2025-10-18
**Status**: Design Phase
**Author**: Chude

---

## Executive Summary

Phase B extends the WoW System from MVP (v5.3.0) to feature-complete production system (v5.4.0) by adding medium-priority handlers, advanced analytics, and extensibility features. This phase builds on the exceptional foundation from Phase E (production hardening) and Phase UX (user experience).

**Design Principle**: Maximize user value while maintaining the production-ready quality established in Phase E (13ms P95 latency, zero memory leaks, 100% success rate).

---

## Current State Analysis (v5.3.0 MVP)

### What We Have (Production Ready)

**Core Infrastructure**:
- 8 handlers: Bash, Write, Edit, Read, Glob, Grep, Task, WebFetch
- Scoring engine with behavioral tracking
- Risk assessment with multi-factor analysis
- Session management with persistence
- Capture engine with frustration detection
- Email alerts with secure credential storage
- Real-time credential detection and redaction
- docTruth integration for documentation automation

**UX Layer** (v5.3.0):
- Score display on violations with visual gauge
- Session banner showing system status
- Unknown tool tracking with auto-discovery
- Benchmark framework for performance validation

**Production Metrics** (Phase E Validated):
- P95 latency: 13ms (74% better than 50ms target)
- Memory growth: 0 KB per 1K operations
- Success rate: 100% across 10,000+ operations
- Concurrent capacity: 50 parallel workers, zero data corruption

### What's Missing (Gaps Analysis)

**Handlers** (from README roadmap):
- NotebookEdit handler (Jupyter notebook safety)
- WebSearch handler (search query validation) - partially complete

**Analytics**:
- Multi-session trend analysis (currently single-session only)
- Historical comparisons and benchmarking
- Pattern recognition (repeated violations, learning opportunities)

**Extensibility**:
- Custom rule DSL (user-defined patterns)
- Plugin architecture for third-party handlers
- Handler composition (chain multiple validators)

**Advanced Features**:
- ML-based anomaly detection (behavioral modeling)
- Web dashboard (metrics visualization)
- Team features (multi-user scoring, leaderboards)

---

## Phase B Feature Selection

### Selection Criteria

1. **User Value**: Directly improves safety or user experience
2. **Implementation Feasibility**: Can be completed in 10-15 hours with TDD
3. **Architectural Fit**: Leverages existing patterns and infrastructure
4. **Security Impact**: Enhances defensive posture
5. **Foundation for Future**: Enables Phase A optimization or Phase D features

### Recommended Features for Phase B

**Priority 1 (Must-Have)**:
1. **NotebookEdit Handler** - Critical for Jupyter notebook users
2. **Multi-Session Analytics** - Unlock historical insights
3. **Pattern Recognition Engine** - Learning from repeated violations

**Priority 2 (Should-Have)**:
4. **Custom Rule DSL** - Extensibility for power users
5. **WebSearch Handler Completion** - Already partially implemented

**Deferred to Future Phases**:
- ML Anomaly Detection (requires training data corpus - defer to v6.0)
- Web Dashboard (requires Phase B analytics foundation - defer to Phase D)
- Team Features (requires multi-user infrastructure - defer to v6.0)

---

## Feature 1: NotebookEdit Handler

### Problem Statement

Jupyter notebooks (.ipynb files) contain executable code cells that can be modified via NotebookEdit tool. Current system has no validation, allowing:
- Malicious code injection into notebooks
- Credential embedding in output cells
- Execution of dangerous commands via magic commands
- Path traversal in notebook file paths

### Architecture

**Handler Pattern Integration**:
```
NotebookEdit Tool Call → Handler Router → NotebookEdit Handler → Validation → Allow/Warn/Block
```

**Components**:
1. **NotebookEdit Handler** (`src/handlers/notebookedit-handler.sh`)
   - JSON structure validation (notebooks are JSON files)
   - Cell content scanning (code cells, markdown cells)
   - Magic command validation (%bash, !shell, etc.)
   - Output cell inspection (prevent credential leakage)
   - File path validation (prevent system notebook overwrites)

2. **Notebook Parser** (`src/parsers/notebook-parser.sh` - NEW)
   - Extract cells from .ipynb JSON structure
   - Parse cell metadata (execution counts, outputs)
   - Handle cell types (code, markdown, raw)
   - Validate notebook schema version

3. **Integration Points**:
   - Register in `handler-router.sh`
   - Use existing credential detector for output scanning
   - Leverage file-storage.sh for parsed notebook cache

### Validation Rules

**Path Validation** (Block):
- System directories: `/etc`, `/usr`, `/bin`, `/boot`
- User config notebooks: `~/.jupyter`, `~/.ipython`
- Root notebooks: `/root/*.ipynb`

**Content Validation** (Warn/Block):
- Magic commands: `%bash`, `!rm`, `!curl | sh` (Block)
- Credential patterns in code cells (Warn)
- Imports: `os.system`, `subprocess.run` with dangerous args (Warn)
- Output cells containing credentials (Block write)

**Structure Validation** (Block):
- Invalid JSON structure
- Missing required fields (cells, metadata)
- Unsupported notebook version (>= v4.0 only)

### Test Coverage (TDD)

**Test Suite**: `tests/test-notebookedit-handler.sh` (24 tests minimum)

**Categories**:
1. Path validation (6 tests): system notebooks, user config, path traversal
2. Magic command blocking (6 tests): %bash, !shell, dangerous commands
3. Content scanning (6 tests): credentials, imports, dangerous code
4. Structure validation (3 tests): invalid JSON, missing fields, version
5. Output inspection (3 tests): credential leakage, error outputs

**Success Criteria**:
- All 24 tests pass
- Integration test with real .ipynb file
- Performance: < 20ms overhead (notebooks are larger files)

### Configuration

```json
{
  "handlers": {
    "notebookedit": {
      "enabled": true,
      "validate_structure": true,
      "scan_code_cells": true,
      "scan_output_cells": true,
      "block_magic_commands": true,
      "allowed_magic_commands": ["%matplotlib", "%time", "%timeit"],
      "max_notebook_size_mb": 10
    }
  }
}
```

### Implementation Estimate

**Time**: 3-4 hours (TDD approach)
1. Write tests (RED): 1 hour
2. Implement handler (GREEN): 1.5 hours
3. Implement notebook parser (GREEN): 1 hour
4. Integration + refactor: 0.5 hours

**LOC Estimate**:
- `notebookedit-handler.sh`: 320 LOC
- `notebook-parser.sh`: 180 LOC
- `test-notebookedit-handler.sh`: 380 LOC
- **Total**: 880 LOC

---

## Feature 2: Multi-Session Analytics

### Problem Statement

Current system tracks metrics per session only. Users cannot:
- See trends across sessions (score improvement over time)
- Compare sessions (which day had most violations?)
- Identify patterns (always violate on Fridays?)
- Benchmark progress (am I getting better?)

### Architecture

**Observer Pattern with Aggregation**:
```
Session Events → Analytics Collector → Aggregation Engine → Trend Calculator → Report Generator
```

**Components**:
1. **Analytics Collector** (`src/analytics/analytics-collector.sh` - NEW)
   - Subscribe to session lifecycle events (start, end, violation)
   - Collect cross-session metrics
   - Persist to analytics database (JSON files in `~/.wow-data/analytics/`)

2. **Aggregation Engine** (`src/analytics/aggregation-engine.sh` - NEW)
   - Daily aggregates: violations/day, avg score, tools used
   - Weekly aggregates: trends, patterns, anomalies
   - Monthly summaries: overall progress, milestones

3. **Trend Calculator** (`src/analytics/trend-calculator.sh` - NEW)
   - Score trends: improving, stable, declining
   - Violation trends: by handler, by day of week, by time of day
   - Statistical significance testing (is improvement real or random?)

4. **Report Generator** (`src/ui/analytics-display.sh` - NEW)
   - Weekly summary display
   - Trend visualization (ASCII charts)
   - Milestone achievements (100 sessions, 1000 operations, etc.)

### Data Model

**Session Summary** (persisted after each session):
```json
{
  "session_id": "session_20251018_143022",
  "start_time": "2025-10-18T14:30:22Z",
  "end_time": "2025-10-18T15:45:33Z",
  "duration_seconds": 4511,
  "final_score": 75,
  "score_changes": 5,
  "violations": 3,
  "operations": {
    "bash": 45,
    "write": 12,
    "read": 23,
    "total": 80
  },
  "handlers_triggered": ["bash-handler", "write-handler"],
  "location": "/home/user/projects/my-app"
}
```

**Daily Aggregate**:
```json
{
  "date": "2025-10-18",
  "sessions": 3,
  "total_operations": 240,
  "avg_score": 72.3,
  "violations": 8,
  "top_violation_type": "path_traversal",
  "trend": "improving"
}
```

### Display Format

**Weekly Summary** (shown on session start, configurable):
```
╔══════════════════════════════════════════════════════════╗
║  📊 WEEKLY ANALYTICS SUMMARY                             ║
╠══════════════════════════════════════════════════════════╣
║  Week of Oct 12-18, 2025                                 ║
║                                                          ║
║  Score Trend: ▲ IMPROVING (+8 points this week)          ║
║  [══════════▲══════════▲══════════▲═══] 70 → 78          ║
║        Mon    Wed        Fri       Sun                   ║
║                                                          ║
║  Sessions This Week: 12                                  ║
║  Total Operations: 1,450                                 ║
║  Violations: 18 (↓ 40% vs last week)                     ║
║                                                          ║
║  Most Common Violation: Path traversal (8 occurrences)   ║
║  Biggest Improvement: Fewer bash violations (-60%)       ║
║                                                          ║
║  Milestone: 🎉 100 sessions completed!                   ║
╚══════════════════════════════════════════════════════════╝
```

### Test Coverage (TDD)

**Test Suite**: `tests/test-analytics-collector.sh` (24 tests)

**Categories**:
1. Session tracking (6 tests): capture, persist, retrieve
2. Aggregation (6 tests): daily, weekly, monthly calculations
3. Trend calculation (6 tests): improving/stable/declining detection
4. Report generation (6 tests): formatting, edge cases

**Additional Suites**:
- `tests/test-aggregation-engine.sh` (18 tests)
- `tests/test-trend-calculator.sh` (18 tests)

**Success Criteria**:
- 60+ tests passing
- Integration with existing session-manager
- Performance: < 5ms overhead per operation
- Multi-session data integrity validated

### Configuration

```json
{
  "analytics": {
    "enabled": true,
    "track_sessions": true,
    "daily_aggregates": true,
    "weekly_summaries": true,
    "show_summary_on_start": true,
    "retention_days": 90,
    "milestone_notifications": true
  }
}
```

### Implementation Estimate

**Time**: 4-5 hours (TDD approach)
1. Write tests (RED): 1.5 hours
2. Implement collector (GREEN): 1 hour
3. Implement aggregation + trends (GREEN): 1.5 hours
4. Implement display (GREEN): 0.5 hours
5. Integration + refactor: 0.5 hours

**LOC Estimate**:
- `analytics-collector.sh`: 280 LOC
- `aggregation-engine.sh`: 320 LOC
- `trend-calculator.sh`: 250 LOC
- `analytics-display.sh`: 200 LOC
- Test suites: 900 LOC (60 tests)
- **Total**: 1,950 LOC

---

## Feature 3: Pattern Recognition Engine

### Problem Statement

Users repeat same mistakes (violations) without learning. System should:
- Detect repeated violations (same handler, same pattern)
- Suggest fixes or best practices
- Offer proactive guidance before violations occur
- Identify learning opportunities

### Architecture

**Strategy Pattern with Learning**:
```
Violation Event → Pattern Detector → Learning Suggestions → User Notification
```

**Components**:
1. **Pattern Detector** (`src/engines/pattern-detector.sh` - NEW)
   - Track violation history with context
   - Detect repetition (3+ same violations in 7 days)
   - Identify anti-patterns (always violate after certain operations)

2. **Suggestion Engine** (`src/engines/suggestion-engine.sh` - NEW)
   - Map violation types to suggestions
   - Context-aware recommendations (based on location, tools used)
   - Progressive hints (start gentle, escalate if repeated)

3. **Learning Database** (`~/.wow-data/learning/patterns.json`)
   - Violation patterns tracked
   - Suggestions shown (avoid repeating)
   - User responses (ignored, followed, dismissed)

### Pattern Detection Rules

**Repetition Detection**:
- Same handler + same violation type (3+ times in 7 days)
- Same file path (2+ times in session)
- Same command pattern (e.g., always try `rm -rf`)

**Anti-Pattern Detection**:
- Always violate after git commit (forgot to remove debug code?)
- Violations cluster on specific weekday (tired on Fridays?)
- Violations after long idle periods (rusty after break?)

**Context Patterns**:
- Violations in specific directories (production code vs test code)
- Violations with specific tools (always mess up with Edit?)

### Suggestion Examples

**For repeated path traversal**:
```
╔══════════════════════════════════════════════════════════╗
║  💡 LEARNING OPPORTUNITY                                 ║
╠══════════════════════════════════════════════════════════╣
║  Pattern Detected: Path traversal (3rd time this week)   ║
║                                                          ║
║  Suggestion: Use absolute paths instead of ../..        ║
║  Example:    /home/user/file.txt instead of ../../file  ║
║                                                          ║
║  Tip: Claude Code can resolve paths automatically if    ║
║       you provide the full path from project root.      ║
║                                                          ║
║  [Press Enter to dismiss, 's' to snooze pattern]        ║
╚══════════════════════════════════════════════════════════╝
```

**For repeated credential exposure**:
```
╔══════════════════════════════════════════════════════════╗
║  ⚠️  RECURRING SECURITY ISSUE                            ║
╠══════════════════════════════════════════════════════════╣
║  Pattern: Credentials in code (5th occurrence)           ║
║                                                          ║
║  Recommendation: Use environment variables instead       ║
║  1. Add to .env file (already gitignored)               ║
║  2. Load with process.env.API_KEY                       ║
║  3. Never hardcode secrets in source                    ║
║                                                          ║
║  WoW can help: Auto-detect .env usage and suggest       ║
║  migration from hardcoded values.                       ║
╚══════════════════════════════════════════════════════════╝
```

### Test Coverage (TDD)

**Test Suite**: `tests/test-pattern-detector.sh` (24 tests)

**Categories**:
1. Repetition detection (6 tests): same handler, same file, same pattern
2. Anti-pattern detection (6 tests): time-based, location-based, tool-based
3. Suggestion mapping (6 tests): correct suggestions for violation types
4. Context awareness (6 tests): adapt to user's environment

**Success Criteria**:
- All 24 tests pass
- No false positives (noise suggestions)
- Suggestions are actionable and relevant
- Performance: < 2ms overhead per violation

### Configuration

```json
{
  "pattern_recognition": {
    "enabled": true,
    "repetition_threshold": 3,
    "detection_window_days": 7,
    "show_suggestions": true,
    "suggestion_frequency": "on_third_occurrence",
    "track_user_responses": true,
    "snooze_duration_hours": 24
  }
}
```

### Implementation Estimate

**Time**: 3-4 hours (TDD approach)
1. Write tests (RED): 1 hour
2. Implement pattern detector (GREEN): 1.5 hours
3. Implement suggestion engine (GREEN): 1 hour
4. Integration + refactor: 0.5 hours

**LOC Estimate**:
- `pattern-detector.sh`: 300 LOC
- `suggestion-engine.sh`: 280 LOC
- `test-pattern-detector.sh`: 380 LOC
- **Total**: 960 LOC

---

## Feature 4: Custom Rule DSL (Extensibility)

### Problem Statement

Users have project-specific rules not covered by built-in handlers:
- Company-specific file naming conventions
- Project-specific dangerous patterns
- Custom validation logic for domain-specific files
- Team-agreed-upon best practices

### Architecture

**Interpreter Pattern**:
```
Rule Definition (YAML) → DSL Parser → Rule Engine → Validation → Allow/Warn/Block
```

**Components**:
1. **DSL Parser** (`src/dsl/rule-parser.sh` - NEW)
   - Parse YAML rule definitions
   - Validate rule syntax
   - Compile rules to executable validators

2. **Rule Engine** (`src/dsl/rule-engine.sh` - NEW)
   - Execute custom rules during validation
   - Integrate with existing handlers
   - Track custom rule violations separately

3. **Rule Library** (`~/.wow-data/rules/`)
   - User-defined rules in YAML format
   - Shared team rules (git-tracked)
   - Built-in rule templates

### DSL Syntax (YAML-based)

**Example: Prevent production file modifications**:
```yaml
rules:
  - name: no_production_file_writes
    description: Block writes to production config files
    trigger: Write
    conditions:
      - path_matches: "config/production/*.{yml,json}"
      - not_path_matches: "config/production/README.md"
    action: block
    message: "Production config files must be modified via deployment pipeline"
    severity: critical

  - name: require_tests_for_handlers
    description: Warn if handler modified without test changes
    trigger: Edit
    conditions:
      - path_matches: "src/handlers/*.sh"
      - not_changed: "tests/test-*.sh"
    action: warn
    message: "Handler modified - did you update the tests?"
    severity: medium

  - name: no_console_log_in_production
    description: Block console.log in production source
    trigger: Write
    conditions:
      - path_matches: "src/**/*.{ts,js}"
      - content_contains: "console.log"
      - not_path_matches: "src/**/*.test.{ts,js}"
    action: warn
    message: "Remove console.log before production deployment"
    severity: low
```

### Rule Execution Flow

1. Handler triggered (e.g., Write tool)
2. Check for custom rules matching trigger type
3. Evaluate conditions in order (all must match)
4. Execute action (block/warn/allow)
5. Track custom rule metrics separately

### Test Coverage (TDD)

**Test Suite**: `tests/test-rule-parser.sh` (24 tests)

**Categories**:
1. YAML parsing (6 tests): valid syntax, invalid syntax, edge cases
2. Condition evaluation (6 tests): path matches, content matches, negations
3. Rule execution (6 tests): block, warn, allow actions
4. Integration (6 tests): custom rules + built-in handlers

**Additional Suite**: `tests/test-rule-engine.sh` (18 tests)

**Success Criteria**:
- 42+ tests passing
- Sample rules execute correctly
- Performance: < 10ms per rule evaluation
- No security bypass via malicious rules

### Configuration

```json
{
  "custom_rules": {
    "enabled": true,
    "rule_directory": "~/.wow-data/rules",
    "team_rules_directory": "./wow-rules",
    "allow_override": false,
    "max_rules": 50,
    "timeout_ms": 100
  }
}
```

### Implementation Estimate

**Time**: 4-5 hours (TDD approach)
1. Write tests (RED): 1.5 hours
2. Implement DSL parser (GREEN): 1.5 hours
3. Implement rule engine (GREEN): 1 hour
4. Sample rules + docs (GREEN): 0.5 hours
5. Integration + refactor: 0.5 hours

**LOC Estimate**:
- `rule-parser.sh`: 350 LOC
- `rule-engine.sh`: 300 LOC
- Test suites: 660 LOC (42 tests)
- **Total**: 1,310 LOC

---

## Feature 5: WebSearch Handler Completion

### Problem Statement

WebSearch handler exists but may be incomplete. Need to validate:
- All SSRF patterns blocked
- Search query sanitization
- Result validation (prevent injection attacks)

### Validation (Check Before Implementing)

**Steps**:
1. Read existing `src/handlers/websearch-handler.sh` (if exists)
2. Check test coverage in `tests/test-websearch-handler.sh`
3. Identify gaps in security validation

### If Incomplete: Implementation Plan

**Additional Security Checks**:
- Query injection patterns (SQL-like, command-like)
- Blacklisted search terms (credential harvesting patterns)
- Rate limiting (prevent search abuse)
- Result sanitization (strip executable content)

**Test Coverage**: Ensure 24 tests minimum

**Estimated Time**: 2-3 hours (if gaps found)

---

## Implementation Phases

### Phase B1: Handlers (4-5 hours)
1. NotebookEdit handler implementation (3-4 hours)
2. WebSearch handler validation/completion (1 hour)

### Phase B2: Analytics (4-5 hours)
1. Multi-session analytics implementation (4-5 hours)

### Phase B3: Intelligence (6-8 hours)
1. Pattern recognition engine (3-4 hours)
2. Custom rule DSL (4-5 hours)

### Total Estimated Time: 14-18 hours

---

## Success Criteria

### Functional
- All 5 features implemented and tested
- 150+ new tests passing
- Zero regression in existing tests
- Integration validated end-to-end

### Non-Functional
- Performance: P95 latency remains < 20ms
- Memory: Zero memory leaks validated
- Security: No new attack vectors introduced
- Quality: 100% TDD coverage maintained

### Quality
- SOLID principles maintained
- Design patterns applied appropriately
- No code duplication
- Clear separation of concerns
- Comprehensive documentation

---

## Risk Mitigation

**Risk 1: Feature Creep**
- Mitigation: Strict scope (5 features only)
- Fallback: Defer Feature 5 if timeline exceeds 18 hours

**Risk 2: Performance Degradation**
- Mitigation: Continuous benchmarking after each feature
- Fallback: Disable analytics by default if overhead > 5ms

**Risk 3: Breaking Changes**
- Mitigation: Backward compatible configuration
- Fallback: Feature flags default to disabled

**Risk 4: Test Complexity**
- Mitigation: Reuse existing test-framework.sh
- Fallback: Manual validation protocol for complex scenarios

---

## File Structure (New Files)

### Handlers
```
src/handlers/
├── notebookedit-handler.sh       # Jupyter notebook validation (NEW)
└── websearch-handler.sh          # May exist, validate completeness
```

### Parsers
```
src/parsers/
└── notebook-parser.sh             # .ipynb JSON parser (NEW)
```

### Analytics
```
src/analytics/
├── analytics-collector.sh         # Cross-session tracking (NEW)
├── aggregation-engine.sh          # Daily/weekly aggregates (NEW)
└── trend-calculator.sh            # Trend analysis (NEW)
```

### Engines
```
src/engines/
├── pattern-detector.sh            # Repeated violation detection (NEW)
└── suggestion-engine.sh           # Learning recommendations (NEW)
```

### DSL
```
src/dsl/
├── rule-parser.sh                 # YAML rule parser (NEW)
└── rule-engine.sh                 # Custom rule execution (NEW)
```

### UI
```
src/ui/
└── analytics-display.sh           # Weekly summaries (NEW)
```

### Tests (New)
```
tests/
├── test-notebookedit-handler.sh   # 24 tests
├── test-analytics-collector.sh    # 24 tests
├── test-aggregation-engine.sh     # 18 tests
├── test-trend-calculator.sh       # 18 tests
├── test-pattern-detector.sh       # 24 tests
├── test-rule-parser.sh            # 24 tests
└── test-rule-engine.sh            # 18 tests
```

### Configuration
```
~/.wow-data/
├── analytics/                     # Analytics database (NEW)
│   ├── sessions/
│   ├── daily/
│   └── weekly/
├── learning/                      # Pattern tracking (NEW)
│   └── patterns.json
└── rules/                         # Custom rules (NEW)
    └── user-rules.yml
```

---

## Performance Budget

**Per-Operation Overhead**:
- NotebookEdit handler: < 20ms (larger files)
- Analytics collector: < 2ms (append-only writes)
- Pattern detector: < 2ms (on violations only)
- Rule engine: < 10ms per custom rule
- WebSearch handler: < 5ms

**Total Estimated Overhead: < 5ms average** (acceptable, within Phase E budget)

---

## Testing Strategy

### Unit Tests (150+ new tests)
- NotebookEdit: 24 tests
- Analytics: 60 tests (collector, aggregation, trends)
- Pattern detection: 24 tests
- Custom rules: 42 tests (parser, engine)
- WebSearch: validation only

### Integration Tests (30 tests)
- NotebookEdit + credential detector
- Analytics + session manager
- Pattern detector + handlers
- Custom rules + existing handlers
- All features together

### Performance Tests (10 benchmarks)
- Notebook parsing speed
- Analytics overhead measurement
- Pattern detection latency
- Rule evaluation performance
- Regression against Phase E baseline

### Security Tests (15 tests)
- Notebook injection attacks
- Analytics data sanitization
- Rule DSL security (malicious rules)
- No information leakage

---

## Version Progression

- **v5.3.0**: MVP (UX complete) - CURRENT
- **v5.4.0**: Feature-complete (Phase B) - TARGET

---

## Post-Phase B: Phase A & D Preview

**Phase A (Performance Optimization)**:
- Profile all new features
- Optimize slow paths in analytics
- Cache rule evaluations
- Parallel analytics aggregation

**Phase D (Documentation & Marketing)**:
- Update README with new features
- Create video demonstrations
- Write blog post: "Building Production-Ready AI Safety"
- GitHub release with changelog

---

## Conclusion

Phase B transforms WoW System from MVP to feature-complete production system by adding:
1. **NotebookEdit Handler** - Jupyter safety
2. **Multi-Session Analytics** - Historical insights
3. **Pattern Recognition** - Learning from mistakes
4. **Custom Rule DSL** - Extensibility for power users
5. **WebSearch Validation** - Complete handler coverage

All features maintain the exceptional quality standards from Phase E (13ms P95, zero leaks, 100% success) while adding significant user value through intelligence, extensibility, and insights.

**Estimated Time**: 14-18 hours
**Estimated LOC**: 5,100+ (including tests)
**Expected Test Coverage**: 150+ new tests
