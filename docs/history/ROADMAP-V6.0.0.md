# WoW System v6.0.0 Roadmap

**Created**: 2025-11-28
**Target**: Production-ready architectural refactor with SOLID compliance
**Estimated Effort**: 15-20 hours total

---

## Executive Summary

v6.0.0 is a major architectural refactor to address SOLID principle violations in the current domain/URL validation system. The current design has hardcoded domain lists in handlers, violating Open/Closed Principle (OCP) and Single Responsibility Principle (SRP). This refactor creates a dedicated security module with three-tier validation and interactive prompts.

---

## Current State (v5.4.4)

### What's Working
- 10 security handlers fully implemented
- Multi-session analytics operational
- Pattern recognition and custom rule DSL
- Behavioral scoring and risk assessment
- Hook-based interception system

### What Needs Fixing
1. **Hardcoded domain lists** in `webfetch-handler.sh` and `websearch-handler.sh`
2. **Dead code**: `_is_safe_domain()` function exists but wasn't being called (fixed in v5.4.1)
3. **No user customization**: Users can't add their own safe domains without editing code
4. **Version inconsistencies**: README.md (v5.4.0), CLAUDE.md (v5.0.1) don't match utils.sh (v5.4.4)
5. **Documentation disorganization**: 29 files in `docs/` root instead of subdirectories
6. **Missing tests**: 9 modules lack dedicated test files

---

## Architecture Design

### Three-Tier Domain Validation System

```
TIER 1: Critical Security (Hardcoded - IMMUTABLE)
├── Cannot be overridden by users
├── Protects against SSRF, metadata attacks
└── Examples: 127.0.0.1, localhost, 169.254.169.254, metadata.google.internal

TIER 2: System Defaults (Config - APPEND-ONLY)
├── Shipped with WoW System
├── Users can ADD to this via custom config
├── System defaults cannot be REMOVED
└── Examples: docs.claude.com, github.com, stackoverflow.com

TIER 3: User Custom (Config - FULLY EDITABLE)
├── User's personal/company domains
├── Clear warning that this is user's responsibility
├── No system guarantee of safety
└── Examples: internal.company.com, myproject.dev
```

### New File Structure

```
src/
├── security/
│   ├── security-constants.sh      # EXISTING - SSRF patterns (TIER 1)
│   ├── domain-validator.sh        # NEW - Core validation logic
│   ├── domain-lists.sh            # NEW - List management
│   ├── credential-detector.sh     # EXISTING
│   ├── credential-redactor.sh     # EXISTING
│   └── credential-scanner.sh      # EXISTING

config/
├── security/
│   ├── system-safe-domains.conf       # NEW - TIER 2 defaults
│   ├── system-blocked-domains.conf    # NEW - TIER 2 blocks
│   ├── custom-safe-domains.conf       # NEW - TIER 3 user additions
│   └── custom-blocked-domains.conf    # NEW - TIER 3 user blocks
└── wow-config.json                    # EXISTING
```

### Module Contracts

#### domain-validator.sh (NEW - ~500 LOC)

```bash
# Public API
domain_validate() {
    local domain="$1"
    local context="$2"  # "webfetch", "websearch", "task"

    # Returns: 0=ALLOW, 1=WARN, 2=BLOCK
    # Side effects: May prompt user for unknown domains
}

domain_is_safe() {
    local domain="$1"
    # Returns: 0=safe, 1=not in safe list
}

domain_is_blocked() {
    local domain="$1"
    # Returns: 0=blocked, 1=not blocked
}

domain_prompt_user() {
    local domain="$1"
    # Interactive prompt: Block/Allow once/Add to safe/Always block
}

domain_add_custom() {
    local domain="$1"
    local list="$2"  # "safe" or "blocked"
    # Adds to custom config file
}
```

#### domain-lists.sh (NEW - ~200 LOC)

```bash
# Public API
domain_lists_init() {
    # Load all config files, merge with hardcoded
}

domain_lists_reload() {
    # Reload config files without restart
}

domain_is_critical_blocked() {
    local domain="$1"
    # TIER 1 check - hardcoded, immutable
}

domain_is_system_safe() {
    local domain="$1"
    # TIER 2 check - from system config
}

domain_is_user_safe() {
    local domain="$1"
    # TIER 3 check - from user config
}
```

---

## Implementation Phases

### Phase 1: Security Module Foundation (5 hours)

**Deliverables:**
- [ ] `src/security/domain-validator.sh` (500 LOC)
- [ ] `src/security/domain-lists.sh` (200 LOC)
- [ ] `tests/test-domain-validator.sh` (30 tests)
- [ ] `tests/test-domain-lists.sh` (20 tests)

**TDD Approach:**
1. Write tests for TIER 1 critical blocks first
2. Write tests for TIER 2 system defaults
3. Write tests for TIER 3 user custom
4. Write tests for validation flow
5. Implement minimal code to pass each test
6. Refactor while keeping tests green

**Test Cases (domain-validator.sh):**
```
1. TIER 1 blocks localhost
2. TIER 1 blocks 127.0.0.1
3. TIER 1 blocks 169.254.169.254 (AWS metadata)
4. TIER 1 blocks metadata.google.internal
5. TIER 1 blocks kubernetes.default
6. TIER 1 cannot be overridden by user config
7. TIER 2 allows docs.claude.com
8. TIER 2 allows github.com
9. TIER 2 user can add custom domain
10. TIER 2 user cannot remove system default
11. TIER 3 loads user config file
12. TIER 3 respects user safe list
13. TIER 3 respects user block list
14. Unknown domain triggers prompt (if interactive)
15. Unknown domain warns (if non-interactive)
16. Validation caches results for performance
17. Config reload works without restart
18. Invalid config file handled gracefully
19. Missing config file uses defaults
20. Empty domain returns BLOCK
21. Malformed domain returns BLOCK
22. Port in domain handled correctly
23. Subdomain matching works (*.github.com)
24. Case-insensitive matching
25. Trailing slash stripped
26. Protocol stripped before validation
27. IPv4 address passed to IP validator
28. IPv6 address passed to IP validator
29. Unicode/IDN domains handled
30. Performance: <5ms for validation
```

### Phase 2: Three-Tier Validation Logic (3 hours)

**Deliverables:**
- [ ] TIER 1 hardcoded patterns in `domain-lists.sh`
- [ ] TIER 2 config files created and populated
- [ ] TIER 3 empty config files with comments
- [ ] Merge logic (TIER 1 > TIER 2 > TIER 3)
- [ ] Integration tests

**Config File Format:**
```conf
# config/security/system-safe-domains.conf
# WoW System - Safe Domains (TIER 2)
# These are trusted domains for documentation and development
# Users can ADD to this list via custom-safe-domains.conf
# Users CANNOT remove entries from this file

# Anthropic Documentation
docs.claude.com
docs.anthropic.com

# Development Platforms
github.com
gitlab.com
bitbucket.org

# Documentation Sites
stackoverflow.com
stackexchange.com
developer.mozilla.org
docs.python.org
nodejs.org

# Package Registries
npmjs.com
pypi.org
crates.io

# Reference Sites
wikipedia.org
w3.org
```

### Phase 3: Interactive Prompt System (2 hours)

**Deliverables:**
- [ ] `domain_prompt_user()` function
- [ ] Claude Code hookSpecificOutput integration
- [ ] Temporary allow/block tracking
- [ ] Persistent config updates
- [ ] Tests for prompt flow

**Prompt Design (Claude Code UX):**
```
═══════════════════════════════════════════════════════════════
  WoW Security: Unknown Domain Detected
═══════════════════════════════════════════════════════════════

  Domain: internal.company.com
  Context: WebFetch request

  This domain is not in the safe list. What should I do?

  [1] Block this request
  [2] Allow this time only
  [3] Add to my safe list (persists)
  [4] Always block this domain (persists)

═══════════════════════════════════════════════════════════════
```

**Implementation Notes:**
- Use `wow_prompt_user()` from display.sh
- Store temporary decisions in session state
- Write persistent decisions to custom config
- Respect `config.security.prompt_on_unknown` setting
- Fallback to WARN if non-interactive

### Phase 4: Handler Refactoring (4 hours)

**Handlers to Refactor:**
1. `webfetch-handler.sh` (~450 LOC → ~200 LOC)
2. `websearch-handler.sh` (~450 LOC → ~200 LOC)
3. `task-handler.sh` (URL validation only)

**Refactoring Pattern:**
```bash
# BEFORE (violates OCP, SRP)
handle_webfetch() {
    local url="$1"
    local domain=$(extract_domain "$url")

    # Hardcoded validation logic (~150 LOC)
    for pattern in "${BLOCKED_DOMAINS[@]}"; do
        if [[ "$domain" =~ $pattern ]]; then
            return 2
        fi
    done
    # ... more hardcoded logic
}

# AFTER (delegates to security module)
handle_webfetch() {
    local url="$1"
    local domain=$(extract_domain "$url")

    # Delegate to security module (3 LOC)
    domain_validate "$domain" "webfetch"
    local result=$?

    if [[ $result -eq 2 ]]; then
        return 2  # BLOCK
    fi

    # Continue with other checks...
}
```

**Deliverables:**
- [ ] Refactored `webfetch-handler.sh`
- [ ] Refactored `websearch-handler.sh`
- [ ] Refactored `task-handler.sh`
- [ ] All existing handler tests still pass
- [ ] Integration tests for new flow

### Phase 5: Comprehensive Testing (4 hours)

**Test Files to Create:**
- [ ] `tests/test-domain-validator.sh` (30 tests)
- [ ] `tests/test-domain-lists.sh` (20 tests)
- [ ] `tests/security/test-security-constants.sh` (20 tests)
- [ ] `tests/test-aggregator.sh` (15 tests)
- [ ] `tests/test-comparator.sh` (15 tests)
- [ ] `tests/test-trends.sh` (15 tests)
- [ ] `tests/test-patterns.sh` (15 tests)
- [ ] `tests/test-rule-dsl.sh` (15 tests)
- [ ] `tests/test-risk-assessor.sh` (15 tests)
- [ ] `tests/test-scoring-engine.sh` (15 tests)

**Test Coverage Goals:**
- Statement coverage: 95%+
- Branch coverage: 90%+
- All edge cases tested
- Performance benchmarks included

### Phase 6: Documentation & Migration (2 hours)

**Documentation Tasks:**
- [ ] Create `docs/architecture/` subdirectory
- [ ] Create `docs/features/` subdirectory
- [ ] Create `docs/security/` subdirectory
- [ ] Create `docs/guides/` subdirectory
- [ ] Create `docs/reference/` subdirectory
- [ ] Create `docs/history/` subdirectory
- [ ] Move 29 files to appropriate subdirectories
- [ ] Create `docs/README.md` navigation guide
- [ ] Update `CLAUDE.md` to v5.4.4
- [ ] Update `README.md` to v5.4.4
- [ ] Regenerate `CURRENT_TRUTH.md`

**Migration Tasks:**
- [ ] Update `install.sh` for new config/ structure
- [ ] Add migration script for existing users
- [ ] Test fresh install
- [ ] Test upgrade from v5.4.4

---

## SOLID Principles Compliance

### Single Responsibility Principle (SRP)
- **Before**: Handlers did validation AND list management
- **After**: `domain-validator.sh` handles validation, `domain-lists.sh` handles lists

### Open/Closed Principle (OCP)
- **Before**: Adding domains required editing handler source code
- **After**: Adding domains via config files, no code changes

### Liskov Substitution Principle (LSP)
- All validators follow same interface contract
- `domain_validate()` returns consistent codes (0/1/2)

### Interface Segregation Principle (ISP)
- Clean API: `validate`, `is_safe`, `is_blocked`, `add_custom`
- Handlers only use what they need

### Dependency Inversion Principle (DIP)
- Handlers depend on `domain_validate()` abstraction
- Don't depend on concrete list implementations

---

## Design Patterns Applied

1. **Strategy Pattern**: TIER 1/2/3 validation strategies
2. **Facade Pattern**: `domain-validator.sh` provides simple interface
3. **Template Method**: Common validation flow, specific tier implementations
4. **Chain of Responsibility**: TIER 1 → TIER 2 → TIER 3 → Prompt
5. **Observer Pattern**: Config reload notifies validators

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Claude modifies config | write-handler.sh blocks ~/.claude/wow-system writes |
| User social-engineered | Clear warnings, tiered approach, critical tier immutable |
| Config file corruption | Fallback to hardcoded defaults, validation on load |
| Privilege escalation via config | Separate tiers, TIER 1 immutable |

### Security Principles

1. **Defense in Depth**: Multiple layers (hardcoded + config)
2. **Principle of Least Privilege**: User can only add, not remove critical blocks
3. **Fail-Safe Defaults**: If config missing/corrupt, use hardcoded
4. **Complete Mediation**: All domains checked against all tiers
5. **Separation of Privilege**: Different tiers for different trust levels

---

## Performance Requirements

- Domain validation: <5ms per check
- Config loading: <50ms on init
- Config reload: <20ms
- No impact on existing handler latency (<10ms total)

---

## Rollback Plan

If v6.0.0 introduces issues:

1. **Immediate**: Disable domain-validator via `config.security.use_domain_validator: false`
2. **Short-term**: Revert to v5.4.4 tag
3. **Long-term**: Address issues in v6.0.1 patch

---

## Success Criteria

1. All existing tests pass (283+)
2. New tests pass (175+ new)
3. SOLID principles verified
4. Performance targets met
5. Security guarantees maintained
6. Documentation complete and organized
7. Install/upgrade tested on fresh systems
8. User can add custom domains without code changes

---

## Timeline Summary

| Phase | Hours | Deliverables |
|-------|-------|--------------|
| Phase 1: Security Module | 5 | domain-validator.sh, domain-lists.sh, 50 tests |
| Phase 2: Three-Tier Logic | 3 | Config files, merge logic, integration |
| Phase 3: Interactive Prompts | 2 | User prompts, session tracking |
| Phase 4: Handler Refactoring | 4 | 3 handlers refactored, all tests pass |
| Phase 5: Testing | 4 | 175+ new tests, 95% coverage |
| Phase 6: Documentation | 2 | Reorg, migration, release notes |
| **Total** | **20** | Production-ready v6.0.0 |

---

## Appendix: Files to Create/Modify

### New Files
- `src/security/domain-validator.sh`
- `src/security/domain-lists.sh`
- `config/security/system-safe-domains.conf`
- `config/security/system-blocked-domains.conf`
- `config/security/custom-safe-domains.conf`
- `config/security/custom-blocked-domains.conf`
- `tests/test-domain-validator.sh`
- `tests/test-domain-lists.sh`
- `tests/security/test-security-constants.sh`
- `tests/test-aggregator.sh`
- `tests/test-comparator.sh`
- `tests/test-trends.sh`
- `tests/test-patterns.sh`
- `tests/test-rule-dsl.sh`
- `tests/test-risk-assessor.sh`
- `tests/test-scoring-engine.sh`
- `docs/README.md`
- `docs/architecture/` (subdirectory)
- `docs/features/` (subdirectory)
- `docs/security/` (subdirectory)
- `docs/guides/` (subdirectory)
- `docs/reference/` (subdirectory)
- `docs/history/` (subdirectory)

### Modified Files
- `src/handlers/webfetch-handler.sh` (refactor)
- `src/handlers/websearch-handler.sh` (refactor)
- `src/handlers/task-handler.sh` (refactor)
- `src/core/orchestrator.sh` (load new modules)
- `install.sh` (new config structure)
- `README.md` (version update)
- `CLAUDE.md` (version update)
- `CHANGELOG.md` (v6.0.0 release notes)

### Moved Files (29 docs)
- See Phase 6 documentation tasks

---

## Contact

- **Author**: Chude <chude@emeke.org>
- **Repository**: https://github.com/chudeemeke/wow-system
- **Current Version**: v5.4.4
- **Target Version**: v6.0.0
