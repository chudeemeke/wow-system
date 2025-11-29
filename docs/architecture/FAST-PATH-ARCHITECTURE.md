# Fast Path Validation Architecture

## Problem Statement

Current handler implementation runs full validation on EVERY file operation, even for obviously safe files (package.json, src/app.ts, etc.). This causes:
- 50-80ms overhead per operation
- API concurrency errors when multiple operations run in parallel
- Poor user experience (strangling effect)

## Solution: Three-Layer Validation with Early Exit

### Design Patterns Applied

**1. Chain of Responsibility Pattern**
- Each validation layer can handle request or pass to next layer
- Early exit when conditions met (performance optimization)
- Progressive deepening of security checks

**2. Strategy Pattern**
- Different validation strategies for different file types
- Pluggable validators (extensible)

**3. Template Method Pattern**
- Common validation flow, specific implementations vary

### SOLID Principles

**Single Responsibility Principle (SRP)**
- Each validator has ONE job (e.g., check safe extensions)
- Fast path validator only handles pre-filtering
- Deep validators only handle security checks

**Open/Closed Principle (OCP)**
- Open for extension (add new validators)
- Closed for modification (existing validators don't change)

**Liskov Substitution Principle (LSP)**
- All validators implement same interface contract
- Validators are interchangeable

**Interface Segregation Principle (ISP)**
- Validators only implement what they need
- No forced dependencies

**Dependency Inversion Principle (DIP)**
- Handlers depend on validator abstraction, not concrete implementations
- Easy to swap validators for testing

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: FAST PATH (5-15ms)                             │
│                                                          │
│ Validators (run in order, exit on first match):         │
│ 1. Current Directory Validator (5ms)                    │
│    - Files in current project directory                 │
│    - No path traversal (../)                            │
│    - Not absolute paths to sensitive dirs               │
│                                                          │
│ 2. Safe Extension Validator (5ms)                       │
│    - Whitelisted extensions (.js, .ts, .md, .json)      │
│    - Known safe file types                              │
│                                                          │
│ 3. Non-System Path Validator (5ms)                      │
│    - Quick regex check for /etc, /root, /sys            │
│    - Early blocking of obviously dangerous paths        │
│                                                          │
│ Result: 90% of operations exit here                     │
│ Exit codes: 0 = safe (allow), 1 = needs deep check      │
└────────────────────┬────────────────────────────────────┘
                     ↓ (only if Layer 1 returns 1)
┌─────────────────────────────────────────────────────────┐
│ Layer 2: PATTERN MATCHING (20-40ms)                     │
│                                                          │
│ - Credential pattern detection                          │
│ - Browser data detection                                │
│ - Private key detection                                 │
│ - Path traversal targeting sensitive files              │
│                                                          │
│ Result: 9% of operations exit here                      │
│ Exit codes: 0 = safe, 2 = block                         │
└────────────────────┬────────────────────────────────────┘
                     ↓ (only if Layer 2 returns 0)
┌─────────────────────────────────────────────────────────┐
│ Layer 3: DEEP ANALYSIS (40-80ms)                        │
│                                                          │
│ - Path resolution and normalization                     │
│ - Rate limiting checks (anti-exfiltration)              │
│ - Score updates                                         │
│ - Metrics tracking                                      │
│                                                          │
│ Result: 1% of operations (truly suspicious)             │
│ Exit codes: 0 = safe, 2 = block                         │
└─────────────────────────────────────────────────────────┘
```

## Implementation Structure

### New Module: `src/core/fast-path-validator.sh`

```bash
# Public API:
fast_path_validate() {
    local file_path="$1"
    local operation_type="${2:-read}"  # read, write, edit

    # Returns:
    # 0 = ALLOW (safe, skip deep validation)
    # 1 = CONTINUE (needs deep validation)
    # 2 = BLOCK (obviously dangerous)
}

# Private validators (Chain of Responsibility):
_fast_path_current_directory() { ... }  # 5ms
_fast_path_safe_extension() { ... }     # 5ms
_fast_path_not_system_path() { ... }    # 5ms
```

### Handler Integration

```bash
# Example: read-handler.sh
handle_read() {
    local tool_input="$1"
    local file_path=$(extract_file_path "${tool_input}")

    # NEW: Fast path check
    case $(fast_path_validate "${file_path}" "read") in
        0)  # ALLOW - safe, skip deep validation
            session_increment_metric "file_reads"
            echo "${tool_input}"
            return 0
            ;;
        2)  # BLOCK - obviously dangerous
            wow_error "Fast path blocked: ${file_path}"
            return 2
            ;;
        1)  # CONTINUE - needs deep validation
            # Fall through to existing validation logic
            ;;
    esac

    # Existing deep validation...
}
```

## Performance Characteristics

### Before Optimization
- Every operation: 50-80ms
- 10 parallel Reads: 500-800ms (API timeout risk)

### After Optimization
- Safe files (90%): 10-15ms (75% reduction)
- Suspicious files (9%): 30-50ms (40% reduction)
- Dangerous files (1%): 50-80ms (same, but blocked faster)
- 10 parallel Reads: 100-150ms (80% reduction)

## Security Guarantees

**No security compromise:**
1. Dangerous paths still blocked (even faster)
2. All existing security checks remain
3. Fast path only optimizes SAFE cases
4. Conservative approach: when in doubt, run deep checks

**Fail-safe design:**
- Fast path errors → fall through to deep validation
- Unknown patterns → deep validation
- Edge cases → deep validation

## Extensibility

### Adding New Validators

```bash
# Add to fast-path-validator.sh
_fast_path_your_new_check() {
    local file_path="$1"

    # Your check logic
    if [[ condition ]]; then
        return 0  # Safe
    fi

    return 1  # Needs more checks
}

# Register in fast_path_validate()
_fast_path_your_new_check "${file_path}" || return $?
```

### Adding New File Types

```bash
# Update SAFE_EXTENSIONS in fast-path-validator.sh
readonly -a FAST_PATH_SAFE_EXTENSIONS=(
    "\.js$" "\.ts$" "\.md$"
    "\.your_new_ext$"  # Add here
)
```

## Testing Strategy

### Unit Tests
- Each validator tested independently
- Edge cases covered
- Performance benchmarks

### Integration Tests
- Handler integration with fast path
- Fallback to deep validation
- End-to-end flow

### Performance Tests
- Measure overhead reduction
- Verify 70-80% improvement target
- Test parallel operation handling

## Migration Plan

1. **Phase 1:** Implement fast path validator (TDD)
2. **Phase 2:** Integrate into Read handler (with tests)
3. **Phase 3:** Integrate into Glob handler (with tests)
4. **Phase 4:** Integrate into Grep handler (with tests)
5. **Phase 5:** Performance benchmarking
6. **Phase 6:** Production deployment

## Rollback Plan

If issues arise:
1. Disable fast path via config flag
2. Revert to deep validation only
3. Zero data loss, zero security impact

## Configuration

```json
{
  "performance": {
    "fast_path_enabled": true,
    "fast_path_validators": [
      "current_directory",
      "safe_extension",
      "non_system_path"
    ]
  }
}
```

## Metrics to Track

- Fast path hit rate (target: 90%)
- Average operation time (target: <20ms)
- Deep validation rate (target: <10%)
- Block rate (should remain constant)
- False negative rate (target: 0%)

## Success Criteria

1. 70-80% reduction in average operation time
2. Zero increase in security violations
3. API concurrency errors eliminated
4. All existing tests pass
5. New tests achieve 100% coverage
