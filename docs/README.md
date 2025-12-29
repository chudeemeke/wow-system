# WoW System Documentation

Welcome to the WoW System documentation! This guide helps you navigate our comprehensive documentation library.

## Quick Start

- **New Users**: Start with [Installation Guide](../README.md) → [CLI Usage](guides/CLI-USAGE.md) → [Developer Guide](guides/DEVELOPER-GUIDE.md)
- **Developers**: See [Architecture Overview](architecture/ARCHITECTURE.md) → [API Reference](reference/API-REFERENCE.md)
- **Troubleshooting**: Check [Troubleshooting Guide](guides/TROUBLESHOOTING.md)
- **Migration**: Upgrading from v5.x? See [Migration Guide](guides/MIGRATION-v6.0.0.md)

---

## Documentation Structure

### 📐 Architecture (`architecture/`)
Deep-dive into system design, patterns, and technical architecture.

- [**ARCHITECTURE.md**](architecture/ARCHITECTURE.md) - Core system architecture and design patterns
- [**ANALYTICS-ARCHITECTURE.md**](architecture/ANALYTICS-ARCHITECTURE.md) - Multi-session analytics system design
- [**FAST-PATH-ARCHITECTURE.md**](architecture/FAST-PATH-ARCHITECTURE.md) - Performance optimization architecture
- [**INSTALLATION-ARCHITECTURE.md**](architecture/INSTALLATION-ARCHITECTURE.md) - Installation and deployment architecture
- [**STRESS-TEST-ARCHITECTURE.md**](architecture/STRESS-TEST-ARCHITECTURE.md) - Stress testing framework design
- [**STRUCTURE_STANDARD.md**](architecture/STRUCTURE_STANDARD.md) - Project structure standards

### ✨ Features (`features/`)
Documentation for specific features and capabilities.

- [**CAPTURE-ENGINE.md**](features/CAPTURE-ENGINE.md) - Frustration detection and capture engine
- [**CREDENTIAL-SECURITY.md**](features/CREDENTIAL-SECURITY.md) - Credential detection, redaction, and secure storage
- [**DOCTRUTH-INTEGRATION-COMPLETE.md**](features/DOCTRUTH-INTEGRATION-COMPLETE.md) - Automated documentation synchronization
- [**EMAIL-IMPLEMENTATION-SUMMARY.md**](features/EMAIL-IMPLEMENTATION-SUMMARY.md) - Email alert implementation details
- [**EMAIL-QUICK-REFERENCE.md**](features/EMAIL-QUICK-REFERENCE.md) - Email configuration quick reference
- [**EMAIL-SETUP-GUIDE.md**](features/EMAIL-SETUP-GUIDE.md) - Email alert setup guide
- [**capture-engine-delivery.md**](features/capture-engine-delivery.md) - Capture engine delivery documentation
- [**capture-engine-integration.md**](features/capture-engine-integration.md) - Capture engine integration guide
- [**wow-capture-delivery.md**](features/wow-capture-delivery.md) - WoW capture system delivery notes

### 📖 Guides (`guides/`)
Step-by-step guides and tutorials for users and developers.

- [**DEVELOPER-GUIDE.md**](guides/DEVELOPER-GUIDE.md) - Comprehensive developer guide
- [**CLI-USAGE.md**](guides/CLI-USAGE.md) - Command-line interface usage
- [**TROUBLESHOOTING.md**](guides/TROUBLESHOOTING.md) - Common issues and solutions
- [**FOR_FUTURE_CLAUDE.md**](guides/FOR_FUTURE_CLAUDE.md) - Context for future Claude sessions
- [**MIGRATION-v6.0.0.md**](guides/MIGRATION-v6.0.0.md) - Migration guide from v5.x to v6.0.0

### 📚 Reference (`reference/`)
API documentation, configuration references, and technical specifications.

- [**API-REFERENCE.md**](reference/API-REFERENCE.md) - Complete API reference for all modules

### 🔒 Security (`security/`)
Security-focused documentation, threat models, and security best practices.

- *(Security documentation will be added here)*

### 📜 History (`history/`)
Historical records, session summaries, and archived documentation.

- [**SESSION-SUMMARY-2025-10-22.md**](history/SESSION-SUMMARY-2025-10-22.md) - Session summary from Oct 22, 2025
- [**AUDIT-SUMMARY-2025-11-28.md**](history/AUDIT-SUMMARY-2025-11-28.md) - Comprehensive audit summary
- [**DEPLOYMENT-SUMMARY.md**](history/DEPLOYMENT-SUMMARY.md) - Deployment history and notes
- [**PROGRESS-SUMMARY.md**](history/PROGRESS-SUMMARY.md) - Historical progress tracking
- [**PHASE-1-2-IMPLEMENTATION-COMPLETE.md**](history/PHASE-1-2-IMPLEMENTATION-COMPLETE.md) - Phase 1-2 completion summary
- [**PHASE-E-PRODUCTION-HARDENING-RESULTS.md**](history/PHASE-E-PRODUCTION-HARDENING-RESULTS.md) - Production hardening results
- [**NEXT-SESSION-PLAN.md**](history/NEXT-SESSION-PLAN.md) - Archived session planning

---

## Current Planning & Design

These documents represent active planning and design work:

- [**ROADMAP-V6.0.0.md**](ROADMAP-V6.0.0.md) - v6.0.0 roadmap and implementation plan
- [**IMPLEMENTATION-PLAN.md**](IMPLEMENTATION-PLAN.md) - Current implementation planning
- [**PHASE-B-FEATURE-EXPANSION-DESIGN.md**](PHASE-B-FEATURE-EXPANSION-DESIGN.md) - Feature expansion design docs
- [**UX-ENHANCEMENT-PLAN.md**](UX-ENHANCEMENT-PLAN.md) - UX enhancement planning

---

## Deprecated Documentation

Legacy documentation has been moved to [`deprecated/`](deprecated/) and is kept for historical reference only.

---

## Design Principles

See [`principles/`](principles/) directory for design principles and architectural decision records (ADRs).

---

## Contributing to Documentation

When adding new documentation:

1. **Choose the right category**:
   - `architecture/` - System design, patterns, technical architecture
   - `features/` - Feature-specific documentation
   - `guides/` - Tutorials, how-to guides, troubleshooting
   - `reference/` - API docs, configuration references
   - `security/` - Security documentation
   - `history/` - Historical records, session summaries

2. **Use clear, descriptive filenames**:
   - `FEATURE-NAME.md` for major topics
   - `feature-subtopic.md` for specific aspects

3. **Follow markdown conventions**:
   - Use H1 (`#`) for document title
   - Use H2 (`##`) for major sections
   - Include table of contents for long documents
   - Add code examples where relevant

4. **Keep docs synchronized**:
   - Update this README.md when adding new docs
   - Run `doctruth` to regenerate CURRENT_TRUTH.md
   - Update related guides when features change

---

## Version History

- **v7.0.0** (Current) - Zone-based filesystem security, biometric authentication, tiered access control
- **v6.0.0** - Three-tier domain validation system, interactive prompts, reorganized documentation
- **v5.4.4** - Security constants refactor, SSRF prevention enhancements
- **v5.0.1** - docTruth integration, automated documentation
- **v5.0.0** - Design patterns (DI, Event Bus), capture engine, credential security
- **v4.1** - Rebuilt after v4.0.2 loss
- See [CONTEXT.md](../CONTEXT.md) for complete version history

---

## Need Help?

- **Technical Issues**: See [Troubleshooting Guide](guides/TROUBLESHOOTING.md)
- **API Questions**: Check [API Reference](reference/API-REFERENCE.md)
- **Architecture Questions**: Read [Architecture Overview](architecture/ARCHITECTURE.md)
- **Feature Requests**: Review [Current Roadmap](ROADMAP-V6.0.0.md)

---

**Last Updated**: 2025-12-25 (v7.0.0 Zone-Based Security)
