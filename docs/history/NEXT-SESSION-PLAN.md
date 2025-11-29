# Next Session: Phase B3 Implementation Plan

## Session Goals
Complete Enhanced Path 3: Phase B3 (Pattern Recognition) → Phase A (Performance) → Phase D (Documentation)

## Phase B3: Pattern Recognition & Custom Rule DSL

### Objective
Detect behavioral patterns across sessions and enable user-defined security rules.

### Modules to Implement

#### 1. Pattern Detector (src/analytics/patterns.sh)
**Purpose**: Identify repeated violations and behavioral patterns

**Features**:
- Track repeated violations (same pattern across multiple sessions)
- Frequency analysis (daily, weekly trends)
- Confidence scoring (high/medium/low)
- Pattern classification (critical/warning/info)

**API**:
```bash
analytics_pattern_init()
analytics_pattern_detect()                    # Scan for patterns
analytics_pattern_get_top(N)                  # Get top N patterns
analytics_pattern_get_recommendations()       # Suggest fixes
```

**Data Model** (patterns.json):
```json
{
  "version": "1.0",
  "patterns": [
    {
      "id": "pattern-001",
      "type": "repeated_violation",
      "signature": "BLOCKED_SYSTEM_FILE:/etc/passwd",
      "occurrences": 12,
      "first_seen": "2025-10-15T10:22:11Z",
      "last_seen": "2025-10-22T11:45:33Z",
      "confidence": "high",
      "recommendation": "Review file access patterns, use safer alternatives"
    }
  ]
}
```

**Estimated**: 250 LOC, ~3 hours

#### 2. Custom Rule DSL (src/rules/dsl.sh)
**Purpose**: Allow users to define custom security patterns

**Features**:
- Simple rule syntax (YAML-based)
- Pattern matching (regex, glob)
- Action specification (allow/warn/block)
- Priority ordering
- Rule validation

**Rule Format** (custom-rules.yml):
```yaml
rules:
  - name: "Block dangerous rm patterns"
    pattern: "rm.*-rf.*/(etc|usr|bin)"
    action: block
    severity: critical
    message: "Dangerous rm command detected"

  - name: "Warn on sudo without validation"
    pattern: "sudo.*eval"
    action: warn
    severity: high
    message: "sudo with eval is risky"
```

**API**:
```bash
rule_dsl_init()
rule_dsl_load_file(path)                     # Load custom rules
rule_dsl_validate(rule)                      # Validate rule syntax
rule_dsl_match(command, rules)               # Check if command matches
rule_dsl_get_action(match)                   # Get action (allow/warn/block)
```

**Estimated**: 280 LOC, ~4 hours

#### 3. Integration Points

**Handler Integration**:
- Check custom rules before default patterns
- Custom rules take precedence
- Log rule matches for analytics

**Analytics Integration**:
- Patterns feed from collector data
- Trends analysis considers patterns
- Comparator includes pattern frequency

**UX Integration**:
- Display top patterns in banner
- Show rule match explanations
- Provide pattern-based recommendations

**Estimated**: ~1 hour

### Testing Strategy
- Pattern detection: 15 tests
- DSL parser: 20 tests
- Integration: 10 tests
- **Total**: 45 new tests

### Success Criteria
- Patterns detected accurately (95%+ precision)
- Custom rules validated correctly
- Zero performance regression
- User-friendly error messages

---

## Phase A: Performance Optimization

### Objectives
1. Profile current performance
2. Optimize bottlenecks
3. Validate against Phase E benchmarks

### Tasks
1. **Profiling** (~30 min)
   - Measure handler latency
   - Identify slow paths
   - Benchmark analytics overhead

2. **Optimizations** (~1.5h)
   - Cache hot paths
   - Reduce unnecessary file I/O
   - Optimize regex patterns
   - Parallelize independent operations

3. **Validation** (~30 min)
   - Run performance tests
   - Compare vs Phase E baseline (13ms P95)
   - Document improvements

**Target**: Maintain <20ms P95 latency with all features

---

## Phase D: Documentation & Marketing

### Objectives
1. Complete user-facing documentation
2. Update technical docs
3. Prepare release announcement

### Tasks
1. **README Update** (~1h)
   - Feature showcase
   - Installation guide
   - Quick start
   - Architecture overview

2. **Architecture Docs** (~30 min)
   - Update diagrams for analytics
   - Document new patterns
   - Add decision records

3. **User Guide** (~1h)
   - Handler explanations
   - Analytics interpretation
   - Custom rules tutorial
   - Troubleshooting

4. **Release Notes** (~30 min)
   - Version 5.4.0 highlights
   - Breaking changes (none)
   - Migration guide (if needed)

---

## Pre-Session Checklist

Before starting Phase B3:
- [ ] Review this plan
- [ ] Check current codebase state (git status)
- [ ] Verify all Phase B2 commits
- [ ] Review CHANGELOG
- [ ] Set up test environment

## Commands to Run

```bash
# Verify current state
cd ~/Projects/wow-system
git log --oneline -10
git status

# Check test coverage
for test in tests/test-*.sh; do bash "$test" 2>&1 | tail -5; done

# Review analytics modules
ls -la src/analytics/
```

## Key Files to Review

- `src/analytics/collector.sh` - Session data collection
- `src/analytics/aggregator.sh` - Statistics
- `src/analytics/trends.sh` - Trend analysis
- `src/analytics/comparator.sh` - Performance comparison
- `src/ui/display.sh` - UX integration
- `CHANGELOG.md` - Current progress

## Estimated Timeline

- **Phase B3**: 6-8 hours
- **Phase A**: 2-3 hours
- **Phase D**: 2-3 hours
- **Total**: 10-14 hours

## Success Metrics

- All Enhanced Path 3 phases complete
- Version 5.4.0 production-ready
- 250+ tests passing
- <20ms P95 latency
- Zero security regressions
- Complete documentation

---

**Status**: Ready for Phase B3 implementation
**Version**: 5.4.0-rc (Release Candidate after Phase B3)
**Target**: 5.4.0 GA (General Availability after Phase D)
