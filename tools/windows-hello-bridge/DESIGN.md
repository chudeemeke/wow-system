# WoW Windows Hello Bridge - Design Document

## History and Rationale

### The Problem (December 2024)

WoW Security v7.0 Phase 4 introduced SuperAdmin mode - a higher privilege tier than bypass that requires biometric authentication. The initial implementation detected biometric hardware using Linux's `fprintd` (fingerprint daemon).

**Issue discovered**: On a Dell Latitude 7400 with a working fingerprint reader and Windows Hello configured, the system reported "No fingerprint reader detected."

**Root cause**: WoW runs in WSL2 (Windows Subsystem for Linux), which is a virtualized Linux environment. WSL2 does NOT have direct access to Windows hardware:

```
┌─────────────────────────────────────────────────────────────┐
│  Windows 11                                                 │
│  ├── Windows Hello (fingerprint works)                      │
│  ├── Dell drivers (direct hardware access)                  │
│  │                                                          │
│  └── WSL2 (Linux VM) ◄── Claude Code runs here              │
│      └── fprintd sees NOTHING (no hardware passthrough)     │
└─────────────────────────────────────────────────────────────┘
```

This is a fundamental WSL2 architectural limitation, not a bug in WoW.

### Options Evaluated

#### Option A: Use WSL-Hello-sudo (Existing Solution)

[WSL-Hello-sudo](https://github.com/nullpo-head/WSL-Hello-sudo) is an open-source project that bridges Windows Hello to WSL via a PAM module.

**Pros:**
- Battle-tested since 2020
- Handles edge cases across Windows versions
- Written in Rust (memory-safe)
- Open source - can audit code

**Cons:**
- Main repository abandoned (last commit: 2021)
- Pre-compiled binaries require trust
- Designed for PAM/sudo, not general CLI auth
- ~1,500 lines of code to audit
- Requires Rust toolchain to build from source
- If discontinued, dependent on community forks

**Security concern raised**: Pre-compiled binaries could theoretically contain malware or differ from published source code. Building from source mitigates this but requires trusting the Rust toolchain and all dependencies.

#### Option B: Build Custom Bridge

Create a minimal Windows Hello bridge specifically for WoW.

**Sub-options evaluated:**

| Approach | Lines of Code | Dependencies | Reliability |
|----------|---------------|--------------|-------------|
| PowerShell script | ~15 | None | Fragile (WinRT access is hacky) |
| C# console app | ~80-150 | .NET SDK | Solid |
| Rust executable | ~200 | Rust toolchain | Most robust |

**Pros:**
- 100% auditable - every line visible
- User compiles themselves (zero trust in pre-compiled)
- We control maintenance
- Simpler codebase (~150 LOC vs ~1,500 LOC)
- Can match WSL-Hello-sudo security model

**Cons:**
- Less battle-tested
- Development effort required
- Ongoing maintenance responsibility

### Decision: Option B (Custom C# Bridge)

**Rationale:**

1. **Trust**: Complete visibility into every line of code
2. **Maintenance**: Full control over updates and fixes
3. **Simplicity**: ~150 lines to audit vs ~1,500
4. **Security Model**: Matches WSL-Hello-sudo's cryptographic approach
5. **Dependencies**: .NET SDK is ubiquitous on Windows
6. **Longevity**: Windows Hello API stable since Windows 10 1607

**Trade-off accepted**: Less battle-tested, but:
- Our use case is well-defined
- We can add robustness iteratively
- Full understanding of behavior

---

## Architecture

### Security Model

We use **Windows Hello identity verification** via `UserConsentVerifier`:

```
┌──────────────────────────────────────────────────────────────────┐
│  Why UserConsentVerifier is Sufficient                           │
│                                                                  │
│  Use Case: Prevent AI/automation from unlocking SuperAdmin       │
│                                                                  │
│  Defense Layers:                                                 │
│  1. TTY Enforcement - AI cannot access /dev/tty                  │
│  2. Windows Hello - Biometric verification in Windows subsystem │
│  3. Short Timeouts - 15 min max, 5 min inactivity                │
│                                                                  │
│  The biometric verification happens INSIDE Windows, not in our   │
│  code. An attacker replacing the exe still can't bypass Windows  │
│  Hello's internal verification.                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Why We Chose UserConsentVerifier over KeyCredentialManager

Initially, we designed a challenge-response system using `KeyCredentialManager` for
TPM-backed asymmetric keys. However, this API requires **MSIX packaging** (app identity),
which adds significant deployment complexity for a CLI tool.

`UserConsentVerifier` provides the same user verification (fingerprint, face, PIN)
without the packaging requirement:

| API | Packaging Required | Cryptographic | Good Enough for WoW? |
|-----|-------------------|---------------|---------------------|
| `KeyCredentialManager` | MSIX required | Yes (TPM keys) | Overkill |
| `UserConsentVerifier` | No packaging | No (identity only) | Yes |

**Key insight**: Our threat model is "prevent AI bypass", not "prevent sophisticated
attackers with admin access". For this use case, identity verification is sufficient.

### Authentication Flow

```
┌─────────────────────┐     ┌─────────────────────┐
│  WSL2 (Linux)       │     │  Windows 11         │
│  superadmin-core.sh │     │  WoWHelloBridge.exe │
└─────────┬───────────┘     └──────────┬──────────┘
          │                            │
          │  1. Call bridge with       │
          │     --verify ──────────────▶
          │                            │
          │                   2. Check Windows Hello
          │                      availability
          │                            │
          │                   3. Request verification
          │                      (triggers Windows Hello
          │                       fingerprint/face/PIN)
          │                            │
          │                   4. Windows verifies
          │                      user identity
          │                            │
          │  5. Receive result ◀───────
          │     VERIFIED:OK or error   │
          │                            │
          │  6. If verified: ALLOW     │
          │     If failed: DENY        │
          │                            │
          ▼                            ▼
```

### State Management

| File | Location | Purpose |
|------|----------|---------|
| Enrollment marker | `~/.wow-data/superadmin/hello-pubkey.b64` | Indicates Windows Hello is configured |
| Token | `~/.wow-data/superadmin/active.token` | HMAC-verified session token |

### Enrollment vs Authentication

**First Run (Enrollment):**
1. User runs `wow superadmin setup --hello`
2. Bridge verifies Windows Hello is available and working
3. Enrollment marker stored in WSL
4. Future authentications know Hello is configured

**Subsequent Runs (Authentication):**
1. Check enrollment marker exists
2. Call bridge with --verify
3. Windows Hello prompts for fingerprint/face/PIN
4. If verified, SuperAdmin unlocks

---

## Windows Hello API Selection

### APIs Considered

| API | Purpose | Packaging Required | Security Level |
|-----|---------|-------------------|----------------|
| `UserConsentVerifier` | Identity verification | No | Medium (Windows Hello) |
| `KeyCredentialManager` | Asymmetric key operations | MSIX required | High (TPM-backed) |
| `Windows Hello for Business` | Enterprise identity | Domain joined | Overkill |

### Selected: UserConsentVerifier

**Why:**
- Works without MSIX packaging (simple .exe deployment)
- Uses full Windows Hello verification (fingerprint, face, PIN)
- Verification happens inside Windows security subsystem
- Sufficient for our threat model (prevent AI bypass)
- Simple API surface

**API Surface Used:**
```csharp
// Check if Windows Hello is available
UserConsentVerifier.CheckAvailabilityAsync()

// Request identity verification (triggers Windows Hello)
UserConsentVerifier.RequestVerificationAsync("WoW SuperAdmin Authentication")
```

### Why Not KeyCredentialManager?

`KeyCredentialManager` provides TPM-backed asymmetric keys for challenge-response
authentication. This is the approach used by WSL-Hello-sudo.

**However**, it requires the application to have a **package identity** (MSIX packaging).
Without this, `KeyCredentialManager.RequestCreateAsync()` throws a `COMException`.

For a CLI tool distributed as a simple .exe, MSIX adds significant complexity:
- Requires creating a package manifest
- Requires signing certificate
- More complex deployment

Since our threat model is "prevent AI bypass" (not "prevent attackers with admin access"),
the simpler `UserConsentVerifier` is sufficient

---

## Threat Model

### What We Protect Against

| Threat | Mitigation |
|--------|------------|
| AI attempting to bypass SuperAdmin | TTY enforcement + Windows Hello verification |
| Malicious script calling bridge | TTY enforcement in WSL (scripts can't access /dev/tty) |
| Replay of "verified" response | Short token expiry (15 min) + HMAC verification |

### What We Do NOT Protect Against

| Threat | Reason |
|--------|--------|
| Local admin replacing bridge exe | Admin already has full system access |
| Compromised Windows OS | Game over for all security |
| User sharing their fingerprint | Social/physical security, not software |
| Attacker with Windows admin | Can disable Windows Hello entirely |

### Threat Model: WoW vs Banking Apps

WoW's threat model is **intentionally simpler** than banking apps:

```
Banking App:
  Threat: Sophisticated remote attackers, malware, MITM
  Solution: TPM-backed keys, challenge-response, certificate pinning

WoW SuperAdmin:
  Threat: AI/automation attempting to bypass restrictions
  Solution: TTY enforcement + biometric verification

Key difference: We trust the local machine. Banking apps don't.
```

**Defense in depth for WoW:**
1. TTY enforcement (primary barrier) - AI cannot access /dev/tty
2. Windows Hello (secondary) - Biometric/PIN verification
3. Short timeouts (tertiary) - Limits exposure window
4. HMAC tokens (quaternary) - Prevents token forgery

---

## File Structure

```
tools/windows-hello-bridge/
├── DESIGN.md              # This document
├── README.md              # Build instructions, usage
├── src/
│   ├── WoWHelloBridge.csproj
│   └── Program.cs
├── build/                 # Compiled output (user generates)
│   └── WoWHelloBridge.exe
└── scripts/
    └── install.sh         # Copies exe to standard location
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-24 | Initial implementation with KeyCredentialManager (failed - requires MSIX) |
| 1.1.0 | 2024-12-24 | Switched to UserConsentVerifier (works without packaging) |

---

## References

- [WSL-Hello-sudo](https://github.com/nullpo-head/WSL-Hello-sudo) - Inspiration for architecture
- [KeyCredentialManager API](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredentialmanager)
- [UserConsentVerifier API](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier)
- [Windows Hello Architecture](https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/hello-how-it-works)

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2024-12-24 | Use custom C# bridge over WSL-Hello-sudo | Trust, maintainability, simplicity |
| 2024-12-24 | Initially chose KeyCredentialManager | Cryptographic security, TPM-backed keys |
| 2024-12-24 | Discovered MSIX requirement | KeyCredentialManager throws COMException without package identity |
| 2024-12-24 | Switched to UserConsentVerifier | Works without MSIX, sufficient for threat model |
| 2024-12-24 | Store enrollment marker in WSL | Simple flag indicating Hello is configured |
