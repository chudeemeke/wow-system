# Migration Guide: v5.x → v6.0.0

**Target Audience**: Existing WoW System users upgrading from v5.0.0 - v5.4.4
**Migration Complexity**: Low - No breaking changes, config additions only
**Estimated Time**: 5-10 minutes
**Rollback**: Easy - disable new features via config

---

## Executive Summary

v6.0.0 introduces a **three-tier domain validation system** with interactive prompts. This is a **non-breaking upgrade** - your existing configuration and workflows continue to work unchanged.

**What's New:**
- 🔒 TIER 1: Immutable critical security blocks (36+ SSRF patterns)
- 🔧 TIER 2: System safe/blocked domain lists (config-based)
- ✏️ TIER 3: User custom domain lists (your preferences)
- 💬 Interactive prompts for unknown domains
- 📁 Reorganized documentation structure

**What's Changed:**
- WebFetch handler delegates to domain-validator module
- WebSearch handler delegates to domain-validator module
- New config files in `config/security/`

**What's Removed:**
- Nothing! All v5.x features are preserved

---

## Pre-Migration Checklist

Before upgrading, ensure:

- [ ] You're running v5.0.0 or later (check `src/core/utils.sh` for `WOW_VERSION`)
- [ ] All tests pass in your current version
- [ ] You have a backup of `~/.claude/wow-system/` (optional but recommended)
- [ ] You have 5-10 minutes for the upgrade

---

## Migration Steps

### Step 1: Backup Configuration (Optional)

```bash
# Backup your current WoW configuration
cp -r ~/.claude/wow-system ~/.claude/wow-system.backup-v5
```

### Step 2: Pull v6.0.0 Changes

```bash
cd /path/to/wow-system  # Your WoW System repository
git fetch origin
git checkout main
git pull origin main
```

Verify version:
```bash
grep "readonly WOW_VERSION" src/core/utils.sh
# Should output: readonly WOW_VERSION="6.0.0"
```

### Step 3: Run Installation Script

The installation script will:
- Create new `config/security/` directory structure
- Populate system domain lists (TIER 2)
- Create empty user custom lists (TIER 3)
- Symlink to `~/.claude/wow-system/`

```bash
bash install.sh
```

**Expected Output:**
```
WoW System Installation
=======================
✓ Created directory: ~/.claude/wow-system
✓ Created directory: ~/.claude/wow-system/config/security
✓ Installed system-safe-domains.conf
✓ Installed system-blocked-domains.conf
✓ Created custom-safe-domains.conf
✓ Created custom-blocked-domains.conf
✓ Installation complete!
```

### Step 4: Verify New Configuration Files

Check that security config files were created:

```bash
ls -1 ~/.claude/wow-system/config/security/
```

**Expected Output:**
```
custom-blocked-domains.conf
custom-safe-domains.conf
system-blocked-domains.conf
system-safe-domains.conf
```

### Step 5: Test Domain Validation

Test the new domain validation system:

```bash
# Test TIER 1 critical block
source src/security/domain-validator.sh
domain_validate "127.0.0.1" "test"
echo $?  # Should output: 2 (BLOCK)

# Test TIER 2 safe domain
domain_validate "github.com" "test"
echo $?  # Should output: 0 (ALLOW)

# Test unknown domain (will prompt in interactive mode)
domain_validate "example.com" "test"
# In non-interactive mode, should output: 1 (WARN)
```

### Step 6: Run Test Suite

Verify all tests pass:

```bash
# Run domain validation tests
bash tests/test-domain-validator.sh

# Run domain lists tests
bash tests/test-domain-lists.sh

# Run handler tests
bash tests/test-webfetch-handler.sh
bash tests/test-websearch-handler.sh
```

**Expected Output:** All tests should pass (100% pass rate)

### Step 7: Optional - Add Custom Domains

If you have internal/company domains you trust, add them to your custom safe list:

```bash
# Edit your custom safe domains
nano ~/.claude/wow-system/config/security/custom-safe-domains.conf
```

**Example custom-safe-domains.conf:**
```conf
# My Custom Safe Domains (TIER 3)
# These are domains I personally trust

# My Company
internal.company.com
docs.company.com
api.company.com

# My Projects
myproject.dev
staging.myapp.io
```

Changes take effect immediately - no restart needed!

---

## New Features Walkthrough

### Feature 1: Three-Tier Domain Validation

**TIER 1: Critical Security (Immutable)**

Hardcoded patterns that **cannot be overridden**. Protects against:
- SSRF attacks (localhost, 127.0.0.1, ::1)
- Cloud metadata endpoints (169.254.169.254, metadata.google.internal)
- Kubernetes internal services (kubernetes.default)
- Private network ranges (10.0.0.0/8, 192.168.0.0/16)

**TIER 2: System Defaults (Config - Append-Only)**

System-provided safe domains (shipped with WoW):
- Anthropic docs (docs.claude.com, docs.anthropic.com)
- Development platforms (github.com, gitlab.com, stackoverflow.com)
- Package registries (npmjs.com, pypi.org, crates.io)

You can **add** to this list via `custom-safe-domains.conf`, but cannot remove system defaults.

**TIER 3: User Custom (Config - Fully Editable)**

Your personal safe/blocked domain lists:
- `custom-safe-domains.conf` - Domains you trust
- `custom-blocked-domains.conf` - Domains you want blocked

Full control - add, remove, edit as needed.

### Feature 2: Interactive Prompts

When Claude Code encounters an **unknown domain**, you'll see:

```
═══════════════════════════════════════════════════════════════
  WoW Security: Unknown Domain Detected
═══════════════════════════════════════════════════════════════

  Domain:  api.newservice.com
  Context: WebFetch request

  This domain is not in the safe list. What should I do?

  [1] Block this request
  [2] Allow this time only (session-based)
  [3] Add to my safe list (persistent)
  [4] Always block this domain (persistent)

═══════════════════════════════════════════════════════════════
Choice [1-4]:
```

**Options:**
1. **Block** - Reject this request (fail-safe default)
2. **Allow once** - Permit for this session only (stored in session state)
3. **Add to safe list** - Adds to `custom-safe-domains.conf` permanently
4. **Always block** - Adds to `custom-blocked-domains.conf` permanently

**Non-Interactive Mode:**
If running in a non-interactive environment (CI/CD, scripts), unknown domains default to **WARN** (logged but allowed).

### Feature 3: Session-Based Tracking

Temporary domain decisions are stored in:
```
~/.wow-data/sessions/latest/domain-decisions.json
```

Example:
```json
{
  "api.newservice.com": "allow",
  "suspicious.domain.com": "block"
}
```

This prevents re-prompting within the same session. Decisions are cleared when a new session starts.

---

## Configuration Changes

### New Configuration Files

**File:** `config/security/system-safe-domains.conf`
**Purpose:** System-provided safe domains (TIER 2)
**User Action:** Read-only (you can view but shouldn't modify)

**File:** `config/security/system-blocked-domains.conf`
**Purpose:** System-provided blocked domains (TIER 2)
**User Action:** Read-only (you can view but shouldn't modify)

**File:** `config/security/custom-safe-domains.conf`
**Purpose:** Your personal safe domains (TIER 3)
**User Action:** Edit freely to add your trusted domains

**File:** `config/security/custom-blocked-domains.conf`
**Purpose:** Your personal blocked domains (TIER 3)
**User Action:** Edit freely to add domains you want blocked

### Existing Configuration

Your existing `wow-config.json` continues to work unchanged. No modifications needed.

**Optional:** You can add these new settings:

```json
{
  "security": {
    "domain_validation": {
      "enabled": true,
      "prompt_on_unknown": true,
      "prompt_timeout_seconds": 30
    }
  }
}
```

**Settings:**
- `enabled` (default: `true`) - Enable/disable domain validation system
- `prompt_on_unknown` (default: `true`) - Prompt user for unknown domains
- `prompt_timeout_seconds` (default: `30`) - Timeout for user prompt (fail-safe to block)

---

## Backward Compatibility

### Deprecated Functions (Still Supported)

These functions are deprecated but **still work** for backward compatibility:

**webfetch-handler.sh:**
- `_is_safe_domain()` - Deprecated, use `domain_is_safe()` from domain-validator
- `_is_ssrf_target()` - Deprecated, use `domain_is_critical_blocked()`

**websearch-handler.sh:**
- `_is_blocked_domain()` - Deprecated, use `domain_is_critical_blocked()`

**Migration Path:**
If you've written custom handlers that call these functions, they'll continue to work. However, we recommend updating to the new API:

```bash
# Old (still works)
if _is_safe_domain "github.com"; then
    echo "Safe"
fi

# New (recommended)
source src/security/domain-validator.sh
if domain_is_safe "github.com"; then
    echo "Safe"
fi
```

### No Breaking Changes

- All v5.x handlers continue to work unchanged
- All v5.x hooks continue to work unchanged
- All v5.x tests continue to pass
- Configuration format unchanged (only additions)

---

## Testing Your Migration

### Quick Smoke Test

```bash
# 1. Test orchestrator loads new modules
source src/core/orchestrator.sh
wow_init
wow_modules_list | grep domain

# Expected output:
# domain-lists
# domain-validator

# 2. Test WebFetch handler uses new validation
echo '{"tool_name":"WebFetch","tool_input":{"url":"http://127.0.0.1/"}}' | \
  bash hooks/user-prompt-submit.sh
# Should block (SSRF protection)

# 3. Test safe domain
echo '{"tool_name":"WebFetch","tool_input":{"url":"https://github.com/"}}' | \
  bash hooks/user-prompt-submit.sh
# Should allow
```

### Full Test Suite

```bash
# Run all tests
for test in tests/test-*.sh; do
    echo "Running $test..."
    bash "$test" || echo "FAILED: $test"
done
```

---

## Troubleshooting

### Issue: "Module not found: domain-validator.sh"

**Cause:** Orchestrator can't find new security modules

**Fix:**
```bash
# Verify files exist
ls -la src/security/domain-validator.sh
ls -la src/security/domain-lists.sh

# Reinstall if missing
bash install.sh
```

### Issue: "Config files not found"

**Cause:** Security config directory not created

**Fix:**
```bash
# Create manually
mkdir -p ~/.claude/wow-system/config/security

# Reinstall
bash install.sh
```

### Issue: "Tests failing after upgrade"

**Cause:** Possibly conflicting changes or installation issue

**Fix:**
```bash
# Check which tests are failing
bash tests/test-domain-validator.sh
bash tests/test-webfetch-handler.sh

# If all tests fail, reinstall
bash install.sh

# If specific tests fail, check module loading
source src/core/orchestrator.sh
wow_init
wow_status
```

### Issue: "Prompts not appearing for unknown domains"

**Cause:** Running in non-interactive mode or prompts disabled

**Check:**
```bash
# Verify interactive mode
[[ -t 0 ]] && echo "Interactive" || echo "Non-interactive"

# Check config
grep -A5 "domain_validation" ~/.claude/wow-system/config/wow-config.json

# Test manually
source src/security/domain-validator.sh
domain_prompt_user "test.example.com" "manual_test"
```

### Issue: "Custom domains not being recognized"

**Cause:** Config file format error or not reloaded

**Fix:**
```bash
# Verify config syntax
cat ~/.claude/wow-system/config/security/custom-safe-domains.conf

# Should be one domain per line, no protocols:
# example.com
# subdomain.example.com
# NOT: https://example.com (wrong!)

# Force reload
source src/security/domain-lists.sh
domain_lists_reload
```

---

## Rollback Procedure

If you encounter issues and need to rollback to v5.4.4:

### Option 1: Disable New Features (Recommended)

Keep v6.0.0 but disable domain validation:

```bash
# Edit config
nano ~/.claude/wow-system/config/wow-config.json

# Add this section:
{
  "security": {
    "domain_validation": {
      "enabled": false
    }
  }
}
```

This makes v6.0.0 behave like v5.4.4.

### Option 2: Full Rollback to v5.4.4

```bash
# 1. Restore backup (if you created one)
rm -rf ~/.claude/wow-system
mv ~/.claude/wow-system.backup-v5 ~/.claude/wow-system

# 2. Checkout v5.4.4
cd /path/to/wow-system
git checkout v5.4.4  # Or the specific v5.x tag you were using

# 3. Reinstall
bash install.sh
```

---

## Performance Impact

The new domain validation system is designed for **zero performance impact**:

- **Validation time**: <5ms per domain check (in-memory lookups)
- **Config loading**: <50ms on init (one-time cost)
- **Config reload**: <20ms (only when manually triggered)
- **Handler overhead**: <10ms total (same as v5.x)

**Benchmarks:**
```bash
# Test validation performance
time bash -c 'source src/security/domain-validator.sh; \
  for i in {1..100}; do domain_validate "github.com" "test" >/dev/null; done'

# Expected: ~300-500ms for 100 validations = 3-5ms per validation
```

---

## Security Considerations

### What's Protected (No Changes from v5.x)

- ✅ SSRF attacks (localhost, metadata endpoints)
- ✅ Path traversal (../../etc/passwd)
- ✅ System directory writes (/etc, /bin, /usr)
- ✅ Credential detection and redaction
- ✅ Malicious command injection

### What's New in v6.0.0

- ✅ **User-controlled domain lists** - You can add trusted domains without code changes
- ✅ **Interactive decision-making** - You choose what to allow/block
- ✅ **Session-based tracking** - Temporary decisions don't persist forever
- ✅ **Three-tier architecture** - Critical blocks can't be bypassed, safe defaults provided

### Threat Model

**Threat:** Claude Code modifies your custom domain config to add malicious domains

**Mitigation:** The `write-handler` blocks writes to `~/.claude/wow-system/` (v5.x feature, still active)

**Threat:** User social-engineered into adding malicious domain to safe list

**Mitigation:** Clear warnings in prompts, TIER 1 (critical blocks) cannot be overridden

**Threat:** Config file corruption

**Mitigation:** Graceful fallback to hardcoded defaults if config files are missing/corrupt

---

## FAQ

### Q: Do I need to update my custom handlers?

**A:** No. Custom handlers continue to work unchanged. The new domain validation is used by WebFetch and WebSearch handlers only.

### Q: Can I disable the interactive prompts?

**A:** Yes. Set `prompt_on_unknown: false` in config, or run in non-interactive mode (prompts auto-disabled).

### Q: How do I add multiple domains at once?

**A:** Edit `custom-safe-domains.conf` directly:
```bash
nano ~/.claude/wow-system/config/security/custom-safe-domains.conf
# Add one domain per line
```

### Q: Can I override TIER 1 critical blocks?

**A:** No. TIER 1 blocks (localhost, metadata endpoints, etc.) are immutable for security. This is by design.

### Q: How do I block a domain permanently?

**A:** Use option [4] in the interactive prompt, or manually add to `custom-blocked-domains.conf`.

### Q: What happens if I have conflicting entries (same domain in safe and blocked)?

**A:** Blocked takes precedence. The validation order is: TIER 1 (critical blocks) → TIER 2/3 (blocked) → TIER 2/3 (safe).

### Q: Can I see what domains are in the system safe list?

**A:** Yes:
```bash
cat ~/.claude/wow-system/config/security/system-safe-domains.conf
```

### Q: How do I reset my custom domain lists?

**A:** Delete and recreate:
```bash
rm ~/.claude/wow-system/config/security/custom-*.conf
bash install.sh  # Recreates empty custom configs
```

---

## Post-Migration Checklist

After migration, verify:

- [ ] All tests pass (`bash tests/test-*.sh`)
- [ ] New config files exist in `~/.claude/wow-system/config/security/`
- [ ] WebFetch requests to github.com are allowed
- [ ] WebFetch requests to 127.0.0.1 are blocked
- [ ] Interactive prompts appear for unknown domains (if in interactive mode)
- [ ] Custom domains (if added) are recognized
- [ ] Documentation is accessible at `docs/README.md`

---

## Getting Help

If you encounter issues during migration:

1. **Check troubleshooting section** above
2. **Review test output** for specific errors
3. **Check logs**: `tail -f ~/.claude/wow-system/logs/wow.log`
4. **File an issue**: [GitHub Issues](https://github.com/chudeemeke/wow-system/issues)

---

## Next Steps

After successful migration:

1. **Add your custom domains** to `custom-safe-domains.conf`
2. **Explore new features** - Try the interactive prompts with an unknown domain
3. **Review documentation** - New docs organization at `docs/README.md`
4. **Read v6.0.0 features** - See [ROADMAP-V6.0.0.md](../ROADMAP-V6.0.0.md)

---

**Migration Complete!** 🎉

You're now running WoW System v6.0.0 with three-tier domain validation and interactive prompts.

**Author**: Chude <chude@emeke.org>
**Last Updated**: 2025-11-29
**Version**: 6.0.0
