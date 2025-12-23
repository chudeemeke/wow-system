# Changelog

All notable changes to WoW System (Ways of Working Enforcement) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added - WoW Security v7.0 (Phase 1)

**Exit Code 4 (SUPERADMIN-REQUIRED) and Bootstrap Security**

#### Security Tier System

- **TIER CRITICAL** (Exit 3): Operations that can NEVER be bypassed
  - SSRF/Cloud metadata attacks
  - System destruction commands
  - Fork bombs
  - System authentication files (/etc/shadow, /etc/sudoers)
  - **NEW: Hook self-protection** (bootstrap security)

- **TIER SUPERADMIN** (Exit 4): Operations requiring fingerprint authentication
  - WoW bypass system files
  - Security policy files
  - SuperAdmin gate files
  - Can be unlocked with `wow superadmin unlock` + fingerprint

- **TIER HIGH** (Exit 2): Bypassable with `wow bypass`
  - Protected system paths
  - Sensitive directories
  - Credential patterns

#### Bootstrap Security (Hook Self-Protection)

**Problem Solved**: AI could previously disable WoW by moving/renaming the hook file.

**Solution**: Hook file added to CRITICAL tier (cannot be bypassed, even with SuperAdmin)
- Patterns blocked: `.claude/hooks/user-prompt-submit.sh`, `.bak`, `.dev`, `.disabled` variants
- Defense-in-depth: Combined with `chattr +i` for kernel-level protection

#### Immutable File Protection

- **`bin/wow-immutable`** - Helper script for `chattr +i` protection
  - Commands: `lock`, `unlock`, `status`
  - Requires sudo for lock/unlock
  - Provides kernel-level protection AI cannot circumvent
  - Works on Linux/WSL2 native filesystems

- **`docs/IMMUTABLE-PROTECTION.md`** - Comprehensive guide
  - Setup instructions
  - WSL considerations
  - Helper functions for .bashrc
  - Troubleshooting guide

#### Security Policy Updates

- **`src/security/security-policies.sh`**:
  - Added exit code constants: `EXIT_ALLOW=0`, `EXIT_WARN=1`, `EXIT_BLOCK=2`, `EXIT_CRITICAL=3`, `EXIT_SUPERADMIN=4`
  - Added `POLICY_HOOK_PROTECTION` array for bootstrap security
  - Added `POLICY_SUPERADMIN_REQUIRED` array for SuperAdmin-tier operations
  - Added `policy_check_superadmin()` function
  - Added `policy_is_superadmin_unlockable()` function
  - Updated `policy_get_reason()` for all tiers

#### Handler Router Updates

- **`src/handlers/handler-router.sh`**:
  - CRITICAL patterns checked FIRST (before bypass check)
  - SUPERADMIN patterns checked after CRITICAL
  - SuperAdmin mode integration (checks `superadmin_is_active()`)
  - Exit code 4 propagation to hook

#### Hook Updates

- **`hooks/user-prompt-submit.sh`**:
  - Exit code 4 handling with proper user messaging
  - Guidance to run `wow superadmin unlock` for SuperAdmin-tier blocks
  - **Session startup warning** if hook file is not protected with `chattr +i`
  - Reminds AI and user to run `sudo wow-immutable lock` for production protection

#### Test Coverage

- **`tests/test-exit-codes.sh`** (17 tests, 100% passing)
  - Exit code constant tests
  - SUPERADMIN tier function tests
  - CRITICAL vs SUPERADMIN separation tests
  - Hook protection tests (5 new tests)
  - Bootstrap security verification

#### Messaging Framework (SOLID-Compliant)

**New unified messaging system following SOLID principles and Apple-style design:**

- **`src/ui/messaging/message-types.sh`** (SSOT)
  - Single Source of Truth for colors, icons, prefixes
  - Semantic color aliases (success=green, warning=yellow, etc.)
  - 9 built-in message types: info, success, warning, error, security, debug, blocked, allowed, score
  - Type registration API for extensibility (OCP)

- **`src/ui/messaging/message-formatter.sh`** (Strategy Pattern)
  - 4 formatters: terminal (colored), json, log (timestamped), plain
  - Auto-detection based on environment (TTY, explicit setting)
  - Formatter registration for custom outputs
  - Apple-style visual hierarchy (consistent 2-space indent)

- **`src/ui/messaging/messages.sh`** (Facade Pattern)
  - Simple public API: `wow_msg "type" "message" "details"`
  - Convenience functions: `wow_msg_info()`, `wow_msg_error()`, etc.
  - Block messages: `wow_msg_block "type" "title" "line1" "line2"`
  - Level filtering (debug < info < warning < error)
  - Global enable/disable
  - Color exports for inline use: `${WOW_C_CYAN}text${WOW_C_RESET}`

- **`src/ui/messaging/startup-checks.sh`** (Registry Pattern)
  - Extensible startup check system
  - Priority-based execution (1=first, 99=last)
  - Built-in checks: bypass_active, superadmin_active, hook_immutable, low_score
  - Easy custom check registration
  - Enable/disable individual checks

**Design Patterns Applied:**
- **SSOT**: All colors/icons defined once in message-types.sh
- **Strategy**: Swap formatters without changing client code
- **Facade**: Simple `wow_msg()` hides complex subsystem
- **Registry**: Add checks without modifying existing code
- **Template Method**: Standard check interface, custom implementations

**Apple-Style Design:**
- Clean, aligned output with consistent 2-space indent
- Dimmed details for visual hierarchy
- Minimal but informative messages
- "It just works" - auto-detects terminal vs non-TTY

### Added - WoW Security v7.0 (Phase 2)

**Heuristic Evasion Detection - Catches AI attempts to bypass security through obfuscation**

#### Detection Categories

- **Encoding Evasion**
  - Base64 decode piped to shell
  - Hex decode execution
  - Octal escape sequences piped to shell

- **Variable Substitution Attacks**
  - Variable-built dangerous commands
  - Array expansion execution
  - Indirect variable execution via eval

- **Command Obfuscation**
  - Quote insertion obfuscation
  - Backslash obfuscation
  - String concatenation
  - Null byte escape sequences
  - Case variation

- **Indirect Execution**
  - eval commands
  - bash -c / sh -c execution
  - Backtick command execution
  - source/dot from temp directories

- **Network Evasion**
  - Curl piped to shell
  - Wget piped to bash
  - URL-encoded IP addresses (SSRF obfuscation)

#### Confidence Scoring System

- **Block threshold**: >= 70% confidence
- **Warn threshold**: >= 40% confidence
- **Allow**: < 40% confidence

Each detection assigns a confidence score based on the evasion technique severity.

#### New Files

- **`src/security/heuristics/detector.sh`** (430 LOC)
  - Detection functions for each category
  - Confidence scoring and reason tracking
  - Public API: `heuristic_check()`, `heuristic_get_confidence()`, `heuristic_get_reason()`
  - Self-test validation

- **`tests/test-heuristics.sh`** (29 tests, 100% passing)
  - Encoding evasion tests (5)
  - Variable substitution tests (4)
  - Command obfuscation tests (5)
  - Indirect execution tests (6)
  - Network evasion tests (3)
  - Confidence scoring tests (3)
  - Reason reporting tests (1)
  - Function existence tests (2)

- **`tests/test-heuristic-integration.sh`** (6 tests)
  - Handler router integration tests
  - Block/allow verification

#### Handler Router Integration

- **`src/handlers/handler-router.sh`**:
  - Sources `src/security/heuristics/detector.sh`
  - Heuristic check runs AFTER bypass check (can be bypassed)
  - Heuristic check runs BEFORE individual handlers
  - Exit code 2 (BLOCK) on high confidence evasion
  - Warning logged on medium confidence

#### Design Principles

- **Defense in Depth**: Multiple detection layers work together
- **Confidence Scoring**: Graduated response, not binary
- **Extensible**: Add new patterns without modifying core
- **Low False Positives**: Legitimate use cases allowed
- **Bypassable**: Can be disabled with `wow bypass` for legitimate testing

### Added - WoW Security v7.0 (Phase 3)

**Content Correlator - Detects split attacks across multiple operations**

#### Attack Patterns Detected

- **Write-then-Execute**
  - Write script to temp directory, then execute it
  - Write script, chmod +x, then run
  - Dot-source or source from temp paths

- **Download-then-Execute**
  - Curl/wget file to disk, then execute
  - Fetch remote script, then source it

- **Staged Building**
  - Build command across multiple variable assignments
  - Array construction followed by execution
  - Piece-by-piece command assembly

- **Config Poisoning**
  - Modifications to .bashrc, .profile, .zshrc
  - SSH config changes (ProxyCommand injection)
  - PATH manipulation in shell configs

#### Sliding Window Tracking

- Tracks last 50 operations (configurable)
- 30-minute TTL for operation history
- Automatic expiry of old operations
- Redirect detection (tracks `>` as implicit Write)

#### Risk Scoring

- **Block threshold**: >= 70% risk
- **Warn threshold**: >= 40% risk
- System binaries: Low risk (10%)
- Recently written temp files: High risk (90%)
- Downloaded then executed: Very high risk (95%)

#### New Files

- **`src/security/correlator/correlator.sh`** (450 LOC)
  - Operation tracking with sliding window
  - Pattern detection functions
  - Risk scoring engine
  - Public API: `correlator_track()`, `correlator_check()`, `correlator_get_risk()`

- **`tests/test-correlator.sh`** (24 tests, 100% passing)
  - Write-then-execute tests (5)
  - Download-then-execute tests (3)
  - Staged building tests (2)
  - Config poisoning tests (3)
  - Temporal correlation tests (2)
  - Sliding window tests (2)
  - Risk scoring tests (3)
  - Function existence tests (4)

#### Handler Router Integration

- **`src/handlers/handler-router.sh`**:
  - Sources `src/security/correlator/correlator.sh`
  - Correlator check runs AFTER heuristic check
  - All operations tracked for future correlation
  - Exit code 2 (BLOCK) on high-risk patterns

#### Design Principles

- **Defense in Depth**: Works alongside heuristic detector
- **Temporal Awareness**: Considers operation timing and sequence
- **Low False Positives**: Normal workflows allowed
- **Bypassable**: Can be disabled with `wow bypass`

### Added - WoW Security v7.0 (Phase 4)

**SuperAdmin Biometric Authentication - Fingerprint unlock for high-privilege operations**

#### Authentication Methods

- **Primary: Fingerprint Authentication**
  - Linux: Uses `fprintd-verify` (Fingerprint daemon)
  - macOS: Uses Touch ID via security framework
  - Automatic detection of biometric hardware

- **Fallback: Strong Passphrase**
  - Minimum 12 characters (vs 8 for bypass)
  - Salted SHA512 hashing
  - Stored separately from bypass passphrase
  - Setup via `wow superadmin setup`

#### Safety Features (Shorter Than Bypass)

- **Maximum Duration**: 15 minutes (vs 4 hours for bypass)
- **Inactivity Timeout**: 5 minutes (vs 30 minutes for bypass)
- **TTY Enforcement**: Cannot be activated from scripts or AI
- **Rate Limiting**: Exponential backoff on failed attempts

#### Token Security

- **HMAC-SHA512 Verification**: Tamper-proof tokens
- **Expiry Timestamp**: Built into token, protected by HMAC
- **Activity Tracking**: Updates on each SuperAdmin operation
- **Automatic Cleanup**: Expired tokens rejected

#### CLI Commands

- **`wow superadmin unlock`** - Authenticate with fingerprint/passphrase
  - Pre-flight checks (TTY, rate limit, configuration)
  - Biometric detection and fallback
  - Token creation with HMAC protection

- **`wow superadmin lock`** - Re-lock immediately
  - Idempotent (safe to run multiple times)
  - Clears token and activity tracking

- **`wow superadmin status`** - Check current state
  - Three states: NOT_CONFIGURED, LOCKED, UNLOCKED
  - Shows biometric availability
  - Shows remaining time when unlocked

- **`wow superadmin setup`** - Configure fallback passphrase
  - TTY required
  - Passphrase confirmation
  - Secure hash storage

#### Security Tier Integration

- **SUPERADMIN tier (Exit 4)** operations require fingerprint
- **CRITICAL tier (Exit 3)** still blocked even with SuperAdmin
- Handler router checks SuperAdmin status before allowing SUPERADMIN-tier operations
- Clear user messaging on what's required

#### New Files

- **`src/security/superadmin/superadmin-core.sh`** (500 LOC)
  - Core authentication and token management
  - Fingerprint and passphrase verification
  - Activity tracking and expiry logic
  - Rate limiting with exponential backoff

- **`bin/wow-superadmin`** (345 LOC)
  - CLI command with unlock/lock/status/setup
  - Color-coded terminal output
  - Help documentation

- **`tests/test-superadmin.sh`** (27 tests, 100% passing)
  - Function existence tests (6)
  - State management tests (5)
  - TTY enforcement tests (2)
  - Biometric detection tests (2)
  - Token security tests (3)
  - Inactivity timeout tests (3)
  - Security policy integration tests (2)
  - Status/display tests (2)
  - Rate limiting tests (2)

#### Modified Files

- **`bin/wow`**: Added `superadmin|sa` command routing
- **`src/handlers/handler-router.sh`**: Sources superadmin-core.sh for status checks

#### Design Principles

- **Defense in Depth**: Biometric + passphrase + HMAC + expiry
- **Human-Only**: TTY enforcement prevents AI/script activation
- **Fail-Secure**: Errors keep protection ON
- **Shorter Timeouts**: More restrictive than bypass (safety)
- **Audit Trail**: All SuperAdmin events tracked in session metrics

---

### Added - WoW Structure Standard v1.0.0

**Single Source of Truth for Project Structure Across All Projects**

- **Structure Standard Config** (`config/wow-structure-standard.json`)
  - Comprehensive JSON schema defining universal project structure
  - Required folders: `src/`, `docs/`, `tests/`
  - Recommended folders: `scripts/`, `config/`, `assets/`
  - Optional folders: `public/`, `build/`, `dist/`, `lib/`
  - Root file whitelist by category (10 categories, 60+ file patterns)
  - Framework exceptions for Next.js, Python, Rust, Go, Node.js
  - Migration rules with classification priority
  - Validation rules with error/warning/info severity levels
  - **File size:** 450+ lines of structured configuration
  - **Version:** 1.0.0 (tracked in `STRUCTURE_STANDARD_VERSION`)

- **Documentation** (`docs/`)
  - `STRUCTURE_STANDARD.md` (600+ lines) - Complete usage guide
  - `FOR_FUTURE_CLAUDE.md` (500+ lines) - AI assistant onboarding guide
  - API reference with jq query examples
  - Integration patterns for tool developers
  - Troubleshooting guide
  - Update process documentation

- **Version Tracking**
  - `config/STRUCTURE_STANDARD_VERSION` - Independent version tracking
  - Compatible with wow-system >= 5.4.3
  - Semantic versioning for config schema changes

### Design Principles

**Single Source of Truth (SSOT):**
- No hardcoded structure rules in tools
- All projects and tools source from this config
- Change in one place → auto-updates everywhere

**Extensibility:**
- Framework exceptions defined in config (not hardcoded)
- Easy to add new frameworks without code changes
- Project-specific overrides via `.project.jsonl`

**Graceful Degradation:**
- Tools provide embedded fallbacks if config missing
- Version compatibility checks with warnings
- Non-blocking validation levels (error/warning/info)

**Maintainability:**
- JSON schema for validation
- Comprehensive comments explaining rationale
- Clear documentation for future maintainers
- Backward compatibility commitment

### Benefits

**For Tool Developers:**
- Query config instead of hardcoding rules
- Framework detection and exception handling
- Consistent validation across tools

**For Project Creators:**
- Clear structure expectations
- Framework-aware scaffolding
- Automated compliance checking

**For System Maintainers:**
- Single file to update for structure changes
- Version-tracked evolution
- Documented decision history

### Integration

**Consumed by:**
- ai-dev-environment validation tools
- ai-dev-environment migration tools
- ai-dev-environment project creation tools
- Future: IDE extensions, CI/CD pipelines

**Resolution path:**
1. `$WOW_STRUCTURE_CONFIG` environment variable
2. `~/Projects/wow-system/config/wow-structure-standard.json`
3. Embedded fallback in consuming tools

### Future Enhancements

**Planned for v1.1.0:**
- Custom project templates
- Auto-documentation generation
- Validation pre-commit hooks
- IDE integration

**Planned for v2.0.0:**
- Monorepo support
- Custom conventions per project
- Dependency coupling analysis
- Performance impact metrics

---

## [6.1.0] - 2025-12-22

### Added - Bypass System (TTY-Enforced Owner Override)

**Complete "sudo-style" bypass system for temporary security disabling**

This release introduces a comprehensive bypass system that allows the system owner to temporarily disable WoW protection while maintaining security for catastrophic operations.

#### Core Security Modules

- **`src/security/bypass-core.sh`** (600+ LOC)
  - TTY enforcement prevents AI/script activation (reads from `/dev/tty`)
  - Salted SHA512 passphrase hashing (format: `salt:hash`, 128 hex chars)
  - HMAC-SHA512 token verification (format: `version:created:expires:hmac`)
  - **Safety Dead-Bolt**: Auto-relock after max duration (4 hours) OR inactivity (30 minutes)
  - iOS-style exponential rate limiting (0, 0, 60s, 300s, 900s, 3600s, permanent)
  - Constant-time comparison for timing attack prevention
  - Script integrity verification via SHA256 checksums
  - Integration with WoW infrastructure (logging, paths, metrics)

- **`src/security/bypass-always-block.sh`** (120 LOC)
  - Operations blocked EVEN when bypass is active
  - 6 categories of always-blocked patterns:
    1. System Destruction (12 patterns)
    2. Boot/Disk Corruption (3 patterns)
    3. Fork Bombs (1 pattern)
    4. SSRF/Cloud Credentials (3 patterns)
    5. Bypass Self-Protection (9 patterns)
    6. System Authentication (2 patterns)
  - Pattern anchoring for precise matching (e.g., blocks `/home` but allows `/home/user/project`)

#### CLI Commands

- **`bin/wow-bypass-setup`** - Initial passphrase configuration
  - TTY enforcement
  - Passphrase confirmation
  - Minimum length validation (8 chars)
  - Secure hash storage
  - Checksum generation

- **`bin/wow-bypass`** - Activate bypass mode
  - 5 pre-flight security checks (TTY, configured, already-active, rate-limit, checksums)
  - Color-coded UX with clear feedback
  - Rate limiting warnings
  - Immediate passphrase clearing from memory

- **`bin/wow-protect`** - Re-enable protection
  - Idempotent (safe to run multiple times)
  - No TTY requirement (scripts can re-enable protection)
  - Clear status feedback

- **`bin/wow-bypass-status`** - Check current state
  - Three states: NOT_CONFIGURED, PROTECTED, BYPASS_ACTIVE
  - Exit codes for scripting (0=protected, 1=bypass, 2=not-configured)
  - Failed attempt counter display

#### Handler Router Integration

- **Single integration point** in `handler-router.sh`
  - Bypass check at top of `handler_route()` function
  - Always-block patterns checked even in bypass mode
  - Pass-through for non-catastrophic operations when bypass active
  - Debug logging for bypass decisions

#### Test Suites

- **`tests/test-bypass-core.sh`** (71 tests)
  - TTY detection (4 tests)
  - Passphrase hashing basic (3 tests)
  - Passphrase hashing edge cases (5 tests)
  - Passphrase verification (6 tests)
  - Token tests basic (6 tests)
  - Token tests edge cases (3 tests)
  - Bypass state tests (4 tests)
  - Rate limiting tests (5 tests)
  - Activation/deactivation (4 tests)
  - Configuration state (4 tests)
  - Status helpers (3 tests)
  - **Safety Dead-Bolt expiry tests (15 tests)**
  - Security attack simulation (3 tests)
  - Script integrity tests (6 tests)

- **`tests/test-bypass-always-block.sh`** (40 tests)
  - All 6 categories tested
  - Edge cases (subdirectory vs root deletion)
  - Safe operations verification
  - Reason lookup validation

#### Safety Dead-Bolt (Auto-Relock Mechanism)

**Problem**: If user forgets to re-enable protection after bypass, system remains vulnerable indefinitely.

**Solution**: Hybrid expiry system with two independent kill switches:

1. **Maximum Duration** (default: 4 hours)
   - Absolute time limit from activation
   - Token v2 format includes expiry timestamp
   - HMAC protects against expiry tampering

2. **Inactivity Timeout** (default: 30 minutes)
   - Tracks last activity via `handler-router.sh`
   - Each bypassed operation updates timestamp
   - Auto-deactivates after 30 min of no activity

**Configurable via environment variables:**
- `BYPASS_MAX_DURATION`: Max bypass duration in seconds (default: 14400)
- `BYPASS_INACTIVITY_TIMEOUT`: Inactivity timeout in seconds (default: 1800)

#### Installer Updates

- Creates `~/.wow-data/bypass/` directory with 700 permissions
- Deploys `bin/` directory with executable permissions
- Tests bypass modules during installation
- Adds bypass setup instructions to "Next Steps"

### Security Design Principles

1. **Human-Only Activation**: TTY enforcement prevents AI/script bypass
2. **Defense in Depth**: Multiple security layers (TTY + passphrase + HMAC + checksums)
3. **Fail-Secure**: Errors keep protection ON
4. **Always-Block**: Catastrophic operations blocked even when bypassed
5. **Rate Limiting**: iOS-style exponential backoff prevents brute force
6. **Audit Trail**: All bypass events tracked in session metrics
7. **Safety Dead-Bolt**: Auto-relock on max duration OR inactivity

### Changed - Cryptographic Upgrade (SHA512)

**Breaking Change**: Upgraded from SHA256 to SHA512 for stronger security

- **Passphrase Hashing**: SHA512 (128 hex chars vs 64)
- **HMAC Tokens**: HMAC-SHA512 (128 hex chars)
- **Script Checksums**: Remain SHA256 (industry standard for integrity)

**Impact**: Existing v1 tokens (SHA256 HMAC) are no longer compatible. Users must re-authenticate after upgrade.

### Changed - Version Management (SSOT)

**VERSION file as Single Source of Truth**

- Created `VERSION` file at project root containing version number
- Updated `src/core/utils.sh` to read from VERSION file dynamically
- Lookup order: Project VERSION → WOW_HOME/VERSION → Fallback
- Config file now references VERSION file in `_version_note`
- Installer deploys VERSION file during installation
- **Benefit**: Change version in ONE place, propagates everywhere

### Files Added

```
VERSION                            # Single Source of Truth for version
src/security/bypass-core.sh        # Core library (500 LOC)
src/security/bypass-always-block.sh # Always-block patterns (120 LOC)
bin/wow-bypass-setup               # Setup command
bin/wow-bypass                     # Activation command
bin/wow-protect                    # Protection restore command
bin/wow-bypass-status              # Status command
tests/test-bypass-core.sh          # Core tests (50 tests)
tests/test-bypass-always-block.sh  # Pattern tests (40 tests)
```

### Files Modified

```
src/handlers/handler-router.sh     # Bypass integration
install.sh                         # Bypass deployment
config/wow-config.json             # Version 6.0.0
```

---

## [5.4.3] - 2025-10-31

### Fixed

**Display: ANSI Color Rendering in Claude Code**
- **Issue**: Banner displayed raw escape codes (`\033[0;36m`) instead of rendering colors
- **Root Cause**: Color constants used single quotes `'\033[...]'` which store literal backslash+digits
- **Solution**: Changed to ANSI-C quoting `$'\033[...]'` which stores actual ESC byte (0x1B)

**Technical Details**:
- Single quotes: `'\033'` = 4 literal chars (backslash, 0, 3, 3)
- ANSI-C quotes: `$'\033'` = 1 byte (0x1B ESC character)
- Terminal receives real control character → renders colors properly

**Files Changed**:
- `src/ui/display.sh` lines 43-54: All 10 color constants updated
- Added clarifying comment for future maintainers

**Platform Support**:
- ✅ WSL2 Ubuntu (tested)
- ✅ macOS (bash 2.04+)
- ✅ Native Linux (bash 2.04+)
- NOT WSL2-specific - standard bash behavior

**Visual Impact**:
- Banner now displays in cyan/bold as designed
- Status indicators render in proper colors (green, yellow, red)
- No more raw `\033[...]` codes visible

## [5.4.2] - 2025-10-31

### Fixed - Single Source of Truth (SSOT) Enforcement

**Design Principle Violations Eliminated:**

- **Version Synchronization** (CRITICAL - was fragmented across 5+ files)
  - Removed `ORCHESTRATOR_VERSION="5.0.0"` from orchestrator.sh (outdated by 4 releases)
  - Removed `ROUTER_VERSION="5.0.0"` from handler-router.sh (outdated by 4 releases)
  - Updated config version from 5.1.0 → 5.4.2 (synchronized with codebase)
  - Fixed display.sh hardcoded versions: "4.1.0" → `${WOW_VERSION}`, "5.3.0" → `${WOW_VERSION}`
  - **Result**: Single Source of Truth in `src/core/utils.sh:WOW_VERSION`

- **Code Duplication Eliminated** (SECURITY CRITICAL)
  - Created `src/security/security-constants.sh` for shared security patterns
  - Consolidated `BLOCKED_IP_PATTERNS` (9 identical patterns in 2 locations)
  - webfetch-handler.sh now sources from security-constants.sh
  - websearch-handler.sh now sources from security-constants.sh
  - **Security Benefit**: Bug fixes to SSRF patterns require 1 location update (was 2+)

### Changed

- **Maintainability**: Version changes now require editing 1 file (was 5+)
- **Security**: SSRF prevention patterns maintained in single authoritative location
- **Code Quality**: DRY (Don't Repeat Yourself) principle enforced

### Technical Debt Resolved

- Version drift across modules: **Eliminated**
- Duplicated security patterns: **Consolidated**
- Hardcoded fallback values: **Removed in favor of WOW_VERSION reference**

### Architectural Improvements

- **SOLID Compliance**: Single Responsibility Principle for security constants
- **Design Pattern**: Shared Constants pattern implemented
- **Maintainability**: Reduced by ~35% for version management tasks

## [5.4.1] - 2025-10-31

### Fixed
- **Hook Configuration**: Corrected PreToolUse hook path in settings.json from `/root/.claude/wow-system/hooks/user-prompt-submit.sh` to `/root/.claude/hooks/user-prompt-submit.sh`
  - Issue: Hook was not firing due to incorrect path (wow-system subdirectory doesn't exist in hooks/)
  - Result: WoW System now properly intercepts all tool calls

- **WebFetch Handler - Safe Domain Validation**: Fixed dead code issue where `_is_safe_domain()` function was never called
  - Added call to `_is_safe_domain()` in `_validate_url()` function
  - Now warns when domain not in safe list (monitoring approach, non-blocking)
  - Added `docs.claude.com` to SAFE_DOMAINS list (was missing, caused false positives)

### Technical Debt
- WebFetch handler still uses hardcoded domain lists (violates OCP/SRP)
- Planned architectural refactor in v6.0.0 with dedicated security module
- See [Architecture Refactor Plan](https://github.com/wow-system/issues/xxx) for details

## [5.4.0] - 2025-10-22

### Added - Phase B: Feature Expansion

#### Phase B1: Handler Expansion (Complete)
- **NotebookEdit Handler** (430 LOC, 24 tests)
  - Three-tier security for Jupyter notebook edits
  - Magic command validation (8 dangerous, 9 safe patterns)
  - Python code injection prevention (7 dangerous patterns)
  - Credential detection in notebook cells

- **WebSearch Handler** (450 LOC, 24 tests)
  - Three-tier security for web search operations
  - PII protection (email, SSN, credit cards, API keys)
  - SSRF prevention (private IPs in allowed domains)
  - Credential search detection
  - Injection pattern detection (SQL, command, XSS)
  - Rate limiting (warns at 50+ searches)

- **Handler Router Integration**
  - 10 handlers registered (was 8)
  - All handlers in local registry, factory, and tool registry

#### Phase B2: Multi-Session Analytics (Complete)
- **Semgrep Security Integration**
  - Custom .semgrep.yml with 9 bash-specific rules
  - Full codebase security scan
  - CRITICAL fix: eval replaced with declare in email-sender.sh
  - 12 false positives documented

- **Analytics Modules** (1175 LOC total)
  - **Collector** (345 LOC): Session data collection with caching
  - **Aggregator** (330 LOC): Statistical calculations (mean/median/percentiles)
  - **Trends** (290 LOC): Time-series analysis with confidence scoring
  - **Comparator** (210 LOC): Historical performance comparison

- **UX Integration**
  - Enhanced session banner with analytics insights
  - Trend indicators (↑/→/↓) in real-time display
  - Performance comparison at session start
  - Graceful fallback when analytics unavailable

- **Design Quality**
  - SOLID principles across all modules
  - Design patterns: Observer, Strategy, Facade
  - Performance: Efficient with result caching
  - Security: No sensitive data exposure

#### Phase B3: Pattern Recognition & Custom Rule DSL (Complete)
- **Pattern Detector** (src/analytics/patterns.sh - 450 LOC)
  - Detects repeated security violations across sessions
  - Minimum 3 occurrences to qualify as pattern
  - Confidence scoring: critical/high/medium/low
  - Pattern signatures for violation tracking
  - Generates actionable recommendations
  - API: analytics_pattern_detect, get_top, get_recommendations, get_summary

- **Custom Rule DSL** (src/rules/dsl.sh - 400 LOC)
  - Simple config format: rule name, pattern regex, action type
  - Supports allow/warn/block actions with severity levels
  - Rule validation before execution
  - Pattern matching with grep -E
  - Priority: Custom rules checked before built-in patterns
  - API: rule_dsl_load_file, match, get_action, get_message, get_severity
  - Example rules generator (5 sample rules)

- **Custom Rule Helper** (src/handlers/custom-rule-helper.sh - 150 LOC)
  - DRY principle: Single implementation for all handlers
  - Action codes: BLOCK=2, WARN=1, ALLOW=0, NO_MATCH=99
  - Score updates and metrics tracking
  - API: custom_rule_check, custom_rule_apply, custom_rule_available

- **Handler Integration** (7 handlers modified)
  - bash-handler.sh: Custom rules checked before built-in patterns
  - write-handler.sh: Path and content validation (first 1000 chars)
  - edit-handler.sh: Path, old_string, new_string validation
  - read-handler.sh: Custom rules before fast-path optimization
  - webfetch-handler.sh: URL and prompt validation
  - websearch-handler.sh: Query validation
  - handler-router.sh: Auto-load custom rules from WOW_HOME/custom-rules.conf

- **UX Integration**
  - display.sh: Pattern insights in enhanced session banner
  - Optional pattern summary line when patterns detected
  - Graceful fallback if patterns module unavailable

- **Integration Flow**
  1. handler-router.sh loads custom rules at startup
  2. Handlers call custom_rule_check() before built-in checks
  3. Custom rules can allow/warn/block operations
  4. Pattern detector analyzes violations across sessions
  5. UX displays pattern insights in session banner

- **Testing**
  - Pattern detection: 5 functions self-tested
  - Custom Rule DSL: 6 operations self-tested
  - Custom Rule Helper: 5 constants validated
  - All modules pass self-tests successfully

### Changed
- **Three-Tier Security Refactor** (read-handler.sh)
  - TIER 1 reduced to 3 truly critical files (was 15)
  - TIER 2 created with 26 sensitive patterns
  - Zero false positives on normal workflows
  - 25 tests passing (was 21)

### Fixed
- eval() usage in email-sender.sh (code injection risk eliminated)
- Path traversal detection false positives
- Handler double-sourcing protection verified

### Technical Debt
- Collector module test framework integration issue (implementation verified manually, to be resolved in future iteration)

### Performance (Phase A)
- **Operation Latency**: <10ms for core operations (target: <20ms) ✅
- **Analytics Overhead**: ~6ms for collector scan (minimal impact)
- **Custom Rule Matching**: <1ms per check (negligible overhead)
- **Overall Assessment**: Performance excellent, no optimization needed
- **Baseline Maintained**: Comparable to Phase E (13ms P95)

### Installation & Deployment (Phase D)
- **install.sh v5.4.0 Complete Rewrite** (462 LOC)
  - Windows filesystem deployment strategy for WSL2
  - Auto-detection of Windows user directory
  - Deploys to /mnt/c/Users/{USER}/.claude/wow-system/
  - Creates symlink: ~/.claude → Windows filesystem location
  - Automatic backup of existing installations
  - Interactive confirmation before overwrite
  - Claude Code settings.json configuration
  - Comprehensive testing: 10 handlers + analytics + patterns
  - Environment variable setup (.bashrc integration)
  - Clear post-installation instructions
  - Idempotent (safe to run multiple times)
  - **Dynamic Autodiscovery Pattern** (Single Source of Truth)
    - Version parsed from src/core/utils.sh (not hardcoded)
    - Handlers auto-discovered via find (no hardcoded list)
    - Analytics/rules/engines dynamically detected
    - Zero maintenance: Adding modules requires no install.sh changes
    - Industry standard: DRY principle implementation

### Release Summary
- **Total LOC Added**: ~4,850 (handlers, analytics, patterns, custom rules)
- **New Modules**: 11 (2 handlers, 4 analytics, 3 pattern/rule, 2 helper modules)
- **Tests**: 207+ total (100% pass rate)
- **Handlers**: 10 (covers all Claude Code tools)
- **Security**: Multi-layer validation, zero compromises
- **UX**: Enhanced with analytics insights and trend indicators
- **Customization**: User-defined rules with DSL
- **Intelligence**: Pattern recognition and behavioral learning

---

## [5.3.0] - 2025-10-22

### Added - Phase UX: User Experience Layer
- Complete UX infrastructure with handler integration
- Score display system with color-coded status
- Session banner with real-time metrics
- Hook integration for seamless operation

### Details
- handler-router.sh: UX display calls (lines 95-110)
- display.sh: Core UX rendering functions
- Session banner: Score, status, session ID display
- Color-coded feedback: Excellent(green), Good(cyan), Warning(yellow), Critical(red)

---

## [5.0.1] - 2025-10-21

### Added - Phase E: Production Hardening
- Event bus system (publish/subscribe pattern)
- DI container for service management
- Capture engine with frustration detection
- Credential security (OS keychain integration)
- docTruth integration for automated documentation

### Performance
- P95 latency: 13ms (exceptional)
- Memory: Zero leaks detected
- Success rate: 100% (2000 operations)

---

## [4.1.0] - 2025-09-30

### Added
- Initial production-ready system
- 8 core handlers (Bash, Write, Edit, Read, Glob, Grep, Task, WebFetch)
- Three-tier security classification
- Session management
- Scoring engine
- Risk assessment

### Technical Details
- 283 tests passing
- Handler-based architecture
- Fail-safe design
- WoW philosophy: "Intelligent, Not Paranoid"

---

## Historical Context

**v4.0.2** - Lost (accidentally deleted 2025-09-30)
**v3.5.0** - Previous major version
**v2.0** - Handler system introduced
**v1.0** - Initial hook-based concept

---

## Version Numbering

- **Major (X.0.0)**: Breaking changes, architecture overhaul
- **Minor (5.X.0)**: New features, handlers, modules
- **Patch (5.4.X)**: Bug fixes, refinements

## Links

- [Architecture Docs](docs/)
- [Test Reports](tests/)
- [Design Decisions](docs/principles/)
