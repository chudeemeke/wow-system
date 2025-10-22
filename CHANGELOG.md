# Changelog

All notable changes to WoW System (Ways of Working Enforcement) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.4.0] - 2025-10-22 (In Progress)

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
