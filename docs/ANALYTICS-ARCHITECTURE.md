# Analytics Architecture Design (Phase B2)

## Overview

Multi-session analytics layer for WoW System v5.4.0 providing historical insights, trend analysis, and performance comparisons.

## Module Structure (SOLID: Single Responsibility Principle)

```
src/analytics/
  collector.sh      - Session data collection from filesystem (150 LOC)
  aggregator.sh     - Cross-session metric aggregation (180 LOC)
  trends.sh         - Time-series trend analysis (160 LOC)
  comparator.sh     - Historical performance comparison (170 LOC)
```

**Total: ~660 LOC, 80 tests (20 per module)**

## Data Model

```
~/.wow-data/analytics/
  trends.json       - Time-series score/violation data
  aggregates.json   - Cross-session totals, averages, percentiles
  patterns.json     - Detected behavioral patterns
```

### trends.json Structure
```json
{
  "version": "1.0",
  "updated": "2025-10-22T12:34:56Z",
  "data_points": [
    {
      "session_id": "session-20251022-123456",
      "timestamp": "2025-10-22T12:34:56Z",
      "wow_score": 85,
      "violations": 2,
      "tool_count": 45
    }
  ],
  "trend_direction": "improving",
  "confidence": 0.85
}
```

### aggregates.json Structure
```json
{
  "version": "1.0",
  "updated": "2025-10-22T12:34:56Z",
  "total_sessions": 127,
  "metrics": {
    "wow_score": {
      "current": 85,
      "mean": 78.5,
      "median": 80,
      "p25": 70,
      "p75": 88,
      "p95": 92,
      "best": 95,
      "worst": 45
    },
    "violations": {
      "total": 234,
      "mean": 1.84,
      "current_session": 2
    }
  }
}
```

### patterns.json Structure
```json
{
  "version": "1.0",
  "updated": "2025-10-22T12:34:56Z",
  "patterns": [
    {
      "type": "repeated_violation",
      "pattern": "BLOCKED_SYSTEM_FILE",
      "occurrences": 12,
      "first_seen": "2025-10-15T10:22:11Z",
      "last_seen": "2025-10-22T11:45:33Z",
      "confidence": "high"
    }
  ]
}
```

## Design Patterns

### 1. Observer Pattern
Analytics modules observe session lifecycle events:
- `session_close` → Trigger analytics update
- `violation_detected` → Track for pattern detection

### 2. Strategy Pattern
Multiple analysis strategies:
- Linear trend (simple moving average)
- Exponential smoothing (weighted recent data)
- Percentile ranking (relative performance)

### 3. Facade Pattern
Simple interface for complex analytics:
```bash
analytics_get_insights()  # Returns: "↑ Improving (85th percentile)"
```

## API Design

### Collector Module (collector.sh)
```bash
analytics_collector_init()                    # Initialize collector
analytics_collector_scan()                    # Scan all sessions
analytics_collector_get_sessions()            # Get session list (sorted)
analytics_collector_get_session_data(id)     # Get single session metrics
```

### Aggregator Module (aggregator.sh)
```bash
analytics_aggregator_init()                   # Initialize aggregator
analytics_aggregate_metrics()                 # Compute cross-session aggregates
analytics_aggregate_percentile(metric, val)   # Calculate percentile rank
analytics_aggregate_get(metric, stat)         # Get aggregate (mean/median/p95)
```

### Trends Module (trends.sh)
```bash
analytics_trends_init()                       # Initialize trends
analytics_trends_calculate()                  # Calculate trend direction
analytics_trends_get_direction()              # Return: improving/stable/declining
analytics_trends_get_confidence()             # Return: 0.0-1.0
analytics_trends_get_indicator()              # Return: ↑/→/↓
```

### Comparator Module (comparator.sh)
```bash
analytics_comparator_init()                   # Initialize comparator
analytics_compare_to_average(metric, value)   # Compare vs mean
analytics_compare_to_best(metric, value)      # Compare vs personal best
analytics_compare_get_percentile(metric)      # Get percentile rank
analytics_compare_format_delta(delta)         # Format: +5/-3/±0
```

## Integration Points

### 1. Session Manager Integration
```bash
# In session_close()
if type analytics_collector_scan &>/dev/null; then
    analytics_collector_scan &>/dev/null || true
    analytics_aggregate_metrics &>/dev/null || true
    analytics_trends_calculate &>/dev/null || true
fi
```

### 2. Display/Banner Integration
```bash
# In display_banner()
local insights=""
if type analytics_get_insights &>/dev/null; then
    insights=$(analytics_get_insights)
    echo "  Performance: ${insights}"
fi
```

### 3. Hook Integration (Optional)
```bash
# In user-prompt-submit.sh
# Include analytics context in error messages
if [[ ${exit_code} -eq 1 ]]; then
    local context=$(analytics_get_insights 2>/dev/null || echo "")
    echo "Context: ${context}" >&2
fi
```

## Performance Considerations

- **Overhead Budget**: < 10ms per analytics update
- **Caching**: Aggregates cached, regenerated only on new session
- **Lazy Loading**: Modules loaded on-demand
- **Efficient Parsing**: jq for JSON, fallback to grep/sed

## Security Considerations

- **No Sensitive Data**: Analytics only stores metrics, not commands/paths
- **Access Control**: Analytics files inherit session data permissions (600)
- **Data Sanitization**: All string values truncated to 100 chars
- **Privacy**: No cross-user analytics (single-user system)

## Testing Strategy (80 tests)

### Collector Tests (20)
- Scan empty sessions directory
- Scan corrupted session files
- Handle missing metrics.json
- Sort sessions chronologically
- Limit to last N sessions

### Aggregator Tests (20)
- Calculate mean/median/percentile
- Handle single session
- Handle outliers
- Update on new session
- Cache invalidation

### Trends Tests (20)
- Detect improving trend
- Detect declining trend
- Detect stable trend
- Calculate confidence score
- Handle insufficient data (< 5 sessions)

### Comparator Tests (20)
- Compare to average
- Compare to personal best
- Calculate percentile rank
- Format positive/negative deltas
- Handle first session (no history)

## UX Enhancements

### Banner Display (Before)
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ WoW System v5.4.0               ┃
┃ Score: 85/100 (Good)            ┃
┃ Session: session-xxx            ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Banner Display (After)
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ WoW System v5.4.0               ┃
┃ Score: 85/100 (Good) ↑          ┃
┃ Performance: 85th percentile    ┃
┃ Trend: Improving (+7 vs avg)    ┃
┃ Session: session-xxx (127th)    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

## Backward Compatibility

- **Graceful Degradation**: If analytics fails, system works without it
- **Version Migration**: trends.json v1.0 format, upgradeable
- **Optional Feature**: Can be disabled via config.wow_analytics_enabled

## Success Criteria

1. **Functional**: All 80 tests passing
2. **Performance**: Analytics overhead < 10ms
3. **UX**: Insights visible in banner, helpful not cluttered
4. **Security**: No sensitive data exposure
5. **Quality**: Zero regressions in existing 159 tests

## Implementation Order

1. collector.sh (TDD RED → GREEN)
2. aggregator.sh (TDD RED → GREEN)
3. trends.sh (TDD RED → GREEN)
4. comparator.sh (TDD RED → GREEN)
5. UX integration (display.sh, banner updates)
6. Session manager integration
7. Final validation (239 tests total)
