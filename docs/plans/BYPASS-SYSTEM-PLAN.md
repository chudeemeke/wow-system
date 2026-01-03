 Executive Summary

  This document provides a comprehensive implementation plan for a "sudo-style" bypass system that allows the WoW System owner to
   temporarily disable security blocking. The system ensures that only an interactive human user can activate bypass mode through
   passphrase authentication, making it impossible for Claude or any automated process to circumvent the protection.

  Key Design Principles

  1. Human-Only Activation: TTY enforcement ensures only interactive terminal sessions can activate bypass
  2. Defense in Depth: Multiple security layers (TTY + passphrase + HMAC tokens + checksums)
  3. Fail-Secure: Any error or missing component keeps protection ON
  4. Always-Block Safety Net: Catastrophic operations blocked even in bypass mode
  5. iOS-Style Rate Limiting: Exponential backoff prevents brute force attacks

  ---
  Table of Contents

  1. #1-goals--requirements
  2. #2-security-model
  3. #3-architecture-overview
  4. #4-file-structure
  5. #5-commands--usage
  6. #6-implementation-details
  7. #7-security-hardening
  8. #8-attack-vectors--mitigations
  9. #9-always-block-list
  10. #10-ios-style-rate-limiting
  11. #11-handler-integration
  12. #12-claude-behavior-integration
  13. #13-testing-strategy
  14. #14-future-enhancements

  ---
  1. Goals & Requirements

  1.1 Functional Requirements

  | ID   | Requirement                                            | Priority |
  |------|--------------------------------------------------------|----------|
  | FR-1 | User can set up a passphrase for bypass authentication | MUST     |
  | FR-2 | User can activate bypass mode with correct passphrase  | MUST     |
  | FR-3 | User can manually re-enable protection at any time     | MUST     |
  | FR-4 | User can check current bypass/protection status        | MUST     |
  | FR-5 | Bypass stays active until explicitly disabled          | MUST     |
  | FR-6 | All handlers respect bypass status                     | MUST     |
  | FR-7 | Claude receives helpful guidance when blocked          | SHOULD   |

  1.2 Security Requirements

  | ID   | Requirement                                        | Priority |
  |------|----------------------------------------------------|----------|
  | SR-1 | Only interactive TTY sessions can activate bypass  | MUST     |
  | SR-2 | Passphrase never visible during entry (like sudo)  | MUST     |
  | SR-3 | Passphrase stored as salted hash, never plaintext  | MUST     |
  | SR-4 | Token validation uses HMAC to prevent forgery      | MUST     |
  | SR-5 | Rate limiting prevents brute force attacks         | MUST     |
  | SR-6 | Script integrity verified via checksums            | MUST     |
  | SR-7 | Always-block list prevents catastrophic operations | MUST     |
  | SR-8 | Fail-secure on any error                           | MUST     |

  1.3 Usability Requirements

  | ID   | Requirement                                        | Priority |
  |------|----------------------------------------------------|----------|
  | UR-1 | Simple command interface (wow-bypass, wow-protect) | MUST     |
  | UR-2 | Clear status messages                              | MUST     |
  | UR-3 | Helpful error messages with guidance               | SHOULD   |
  | UR-4 | No passphrase recovery (security over convenience) | MUST     |

  ---
  2. Security Model

  2.1 Trust Boundaries

  ┌─────────────────────────────────────────────────────────────┐
  │                    UNTRUSTED ZONE                           │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │              Claude / AI Process                     │   │
  │  │  - Cannot access /dev/tty                           │   │
  │  │  - Cannot type interactively                        │   │
  │  │  - Can execute bash commands                        │   │
  │  │  - Can read files (with WoW restrictions)           │   │
  │  │  - Can write files (with WoW restrictions)          │   │
  │  └─────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────┘
                                │
                      TTY BOUNDARY (Cannot Cross)
                                │
  ┌─────────────────────────────────────────────────────────────┐
  │                     TRUSTED ZONE                            │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │              Human User Terminal                     │   │
  │  │  - Has TTY access                                   │   │
  │  │  - Can type passphrase interactively                │   │
  │  │  - Owns the passphrase                              │   │
  │  └─────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────┘

  2.2 Threat Model

  | Threat                    | Attacker              | Mitigation                               |
  |---------------------------|-----------------------|------------------------------------------|
  | Brute force passphrase    | Claude/Script         | iOS-style rate limiting                  |
  | Read passphrase hash      | Claude                | File permissions (600), WoW blocks reads |
  | Create fake token         | Claude                | HMAC verification requires hash          |
  | Modify bypass scripts     | Claude                | Checksum verification, WoW blocks writes |
  | Symlink attacks           | Claude                | Path canonicalization                    |
  | Pipe passphrase to stdin  | Script                | TTY enforcement, /dev/tty read           |
  | Encoded commands          | base64 -d             | Pattern detection for encoding           |
  | Environment injection     | Export passphrase var | No environment passphrase                |
  | Script sourcing attack    | source wow-bypass     | Scripts verify own integrity             |
  | Indirect token creation   | Construct valid HMAC  | Requires passphrase hash knowledge       |
  | Fork script               | Copy and modify       | Checksums tied to specific paths         |
  | Time-of-check-time-of-use | Race condition        | Atomic file operations                   |

  2.3 Security Invariants

  These must ALWAYS hold true:

  1. Passphrase is never stored in plaintext - Only salted SHA256 hash
  2. Passphrase entry is invisible - read -s flag, /dev/tty
  3. Token cannot be forged - HMAC requires passphrase hash knowledge
  4. Scripts cannot be modified - Checksum verification at runtime
  5. Bypass files cannot be read by Claude - WoW read-handler blocks
  6. Bypass files cannot be written by Claude - WoW write-handler blocks
  7. Catastrophic operations always blocked - Always-block list
  8. Errors keep protection ON - Fail-secure design

  ---
  3. Architecture Overview

  3.1 Component Diagram

  ┌─────────────────────────────────────────────────────────────────────┐
  │                        USER INTERFACE LAYER                         │
  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐│
  │  │wow-bypass    │ │wow-protect   │ │wow-bypass    │ │wow-bypass   ││
  │  │-setup        │ │              │ │              │ │-status      ││
  │  │              │ │              │ │              │ │             ││
  │  │Initial setup │ │Re-enable     │ │Activate      │ │Show current ││
  │  │passphrase    │ │protection    │ │bypass mode   │ │status       ││
  │  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬──────┘│
  └─────────┼────────────────┼────────────────┼────────────────┼────────┘
            │                │                │                │
            ▼                ▼                ▼                ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     CORE BYPASS LIBRARY                             │
  │                    src/security/bypass-core.sh                      │
  │  ┌─────────────────────────────────────────────────────────────┐   │
  │  │ bypass_check_tty()        - Verify interactive terminal     │   │
  │  │ bypass_read_passphrase()  - Read from /dev/tty with -s      │   │
  │  │ bypass_hash_passphrase()  - Salt + SHA256                   │   │
  │  │ bypass_verify_passphrase()- Constant-time comparison        │   │
  │  │ bypass_create_token()     - timestamp:HMAC format           │   │
  │  │ bypass_verify_token()     - Validate HMAC                   │   │
  │  │ bypass_is_active()        - Check if bypass active          │   │
  │  │ bypass_record_failure()   - iOS-style rate limiting         │   │
  │  │ bypass_check_rate_limit() - Check if locked out             │   │
  │  │ bypass_verify_checksums() - Script integrity check          │   │
  │  └─────────────────────────────────────────────────────────────┘   │
  │                                                                     │
  │                  src/security/bypass-always-block.sh                │
  │  ┌─────────────────────────────────────────────────────────────┐   │
  │  │ ALWAYS_BLOCK_PATTERNS[]   - Regex patterns always blocked   │   │
  │  │ ALWAYS_BLOCK_PATHS[]      - Paths always protected          │   │
  │  │ ALWAYS_BLOCK_DOMAINS[]    - Domains always blocked          │   │
  │  │ bypass_check_always_block() - Check against all lists       │   │
  │  └─────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────┘
            │                │                │                │
            ▼                ▼                ▼                ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │                      DATA STORAGE LAYER                             │
  │                      ~/.wow-data/bypass/                            │
  │  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐    │
  │  │ passphrase.hash  │ │ active.token     │ │ failures.json    │    │
  │  │ (mode 600)       │ │ (exists=active)  │ │ (rate limiting)  │    │
  │  │                  │ │                  │ │                  │    │
  │  │ salt:hash        │ │ timestamp:hmac   │ │ {count,last_ts}  │    │
  │  └──────────────────┘ └──────────────────┘ └──────────────────┘    │
  │                                                                     │
  │  ┌──────────────────────────────────────────────────────────────┐  │
  │  │ checksums.sha256 - SHA256 hashes of all bypass scripts       │  │
  │  └──────────────────────────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────────┘

  3.2 Data Flow: Bypass Activation

  User types: wow-bypass
          │
          ▼
  ┌───────────────────────┐
  │ 1. Verify checksums   │──── FAIL ──► Exit 1 (tampering detected)
  │    of bypass scripts  │
  └───────────┬───────────┘
              │ PASS
              ▼
  ┌───────────────────────┐
  │ 2. Check TTY          │──── FAIL ──► Exit 2 (not interactive)
  │    [ -t 0 ]           │
  └───────────┬───────────┘
              │ PASS
              ▼
  ┌───────────────────────┐
  │ 3. Check rate limit   │──── LOCKED ──► Exit 3 (try again later)
  │    iOS-style backoff  │
  └───────────┬───────────┘
              │ OK
              ▼
  ┌───────────────────────┐
  │ 4. Read passphrase    │
  │    from /dev/tty -s   │
  └───────────┬───────────┘
              │
              ▼
  ┌───────────────────────┐
  │ 5. Verify passphrase  │──── FAIL ──► Record failure, Exit 4
  │    constant-time cmp  │
  └───────────┬───────────┘
              │ PASS
              ▼
  ┌───────────────────────┐
  │ 6. Create HMAC token  │
  │    timestamp:hmac     │
  └───────────┬───────────┘
              │
              ▼
  ┌───────────────────────┐
  │ 7. Write active.token │
  │    Reset failures     │
  └───────────┬───────────┘
              │
              ▼
      Exit 0 (success)
      "Bypass mode active"

  3.3 Data Flow: Handler Check

  Claude tool call (e.g., Bash "rm -rf /tmp/test")
          │
          ▼
  ┌───────────────────────┐
  │ 1. Check always-block │──── MATCH ──► BLOCK (even in bypass)
  │    list               │
  └───────────┬───────────┘
              │ NO MATCH
              ▼
  ┌───────────────────────┐
  │ 2. Check bypass_is    │──── ACTIVE ──► ALLOW (skip other checks)
  │    _active()          │
  └───────────┬───────────┘
              │ NOT ACTIVE
              ▼
  ┌───────────────────────┐
  │ 3. Normal handler     │──── VIOLATION ──► BLOCK with guidance
  │    security checks    │
  └───────────┬───────────┘
              │ PASS
              ▼
          ALLOW

  ---
  4. File Structure

  4.1 Source Files (in wow-system repo)

  wow-system/
  ├── bin/
  │   ├── wow-bypass-setup      # Initial passphrase configuration
  │   ├── wow-bypass            # Activate bypass mode
  │   ├── wow-protect           # Re-enable protection
  │   └── wow-bypass-status     # Check current status
  │
  ├── src/security/
  │   ├── bypass-core.sh        # Core library (~300 LOC)
  │   └── bypass-always-block.sh # Always-block definitions
  │
  └── tests/
      ├── test-bypass-core.sh   # Unit tests for core library
      └── test-bypass-integration.sh # Integration tests

  4.2 Deployed Files (after install.sh)

  ~/.claude/wow-system/
  ├── bin/
  │   ├── wow-bypass-setup
  │   ├── wow-bypass
  │   ├── wow-protect
  │   └── wow-bypass-status
  │
  └── src/security/
      ├── bypass-core.sh
      └── bypass-always-block.sh

  4.3 Runtime Data Files

  ~/.wow-data/
  └── bypass/
      ├── passphrase.hash       # Salt:SHA256 hash (mode 600)
      ├── active.token          # Timestamp:HMAC (exists = bypass active)
      ├── failures.json         # Rate limiting state
      └── checksums.sha256      # Script integrity hashes

  ---
  5. Commands & Usage

  5.1 wow-bypass-setup

  Purpose: Initial one-time setup of bypass passphrase

  Usage:
  wow-bypass-setup

  Interactive Flow:
  WoW Bypass System Setup
  =======================

  This will configure a passphrase for temporarily disabling WoW blocking.
  The passphrase will be stored as a salted hash (never plaintext).

  IMPORTANT:
  - There is NO recovery option if you forget the passphrase
  - You will need to delete and re-setup if forgotten
  - Choose something memorable but not guessable

  Enter passphrase: ********
  Confirm passphrase: ********

  Passphrase configured successfully.
  Use 'wow-bypass' to activate bypass mode.
  Use 'wow-protect' to re-enable protection.

  Exit Codes:
  | Code | Meaning                                         |
  |------|-------------------------------------------------|
  | 0    | Success                                         |
  | 1    | Passphrase mismatch                             |
  | 2    | Not running in TTY                              |
  | 3    | Already configured (use --reset to reconfigure) |

  5.2 wow-bypass

  Purpose: Activate bypass mode (disable most blocking)

  Usage:
  wow-bypass

  Interactive Flow:
  WoW Bypass Mode
  ===============

  Enter passphrase: ********

  Bypass mode activated.
  WoW blocking is now disabled (except always-block operations).
  Use 'wow-protect' to re-enable protection when done.

  Exit Codes:
  | Code | Meaning                                     |
  |------|---------------------------------------------|
  | 0    | Success - bypass active                     |
  | 1    | Script tampering detected                   |
  | 2    | Not running in TTY                          |
  | 3    | Rate limited (locked out)                   |
  | 4    | Wrong passphrase                            |
  | 5    | Not configured (run wow-bypass-setup first) |

  5.3 wow-protect

  Purpose: Re-enable protection (deactivate bypass)

  Usage:
  wow-protect

  Output:
  WoW protection re-enabled.
  All security blocking is now active.

  Exit Codes:
  | Code | Meaning                        |
  |------|--------------------------------|
  | 0    | Success - protection enabled   |
  | 1    | Was not in bypass mode (no-op) |

  5.4 wow-bypass-status

  Purpose: Check current bypass/protection status

  Usage:
  wow-bypass-status

  Output (Protected):
  WoW Status: PROTECTED
  All security blocking is active.

  Output (Bypass):
  WoW Status: BYPASS ACTIVE
  Security blocking is disabled (except always-block operations).
  Use 'wow-protect' to re-enable protection.

  ---
  6. Implementation Details

  6.1 src/security/bypass-core.sh

  #!/usr/bin/env bash
  # bypass-core.sh - Core bypass system library
  # Part of WoW System v6.1.0
  #
  # SECURITY CRITICAL: This file implements the bypass authentication system.
  # Any modifications require security review.

  # Double-sourcing protection
  if [[ -n "${WOW_BYPASS_CORE_LOADED:-}" ]]; then
      return 0
  fi
  readonly WOW_BYPASS_CORE_LOADED=1

  # Constants
  readonly BYPASS_DATA_DIR="${HOME}/.wow-data/bypass"
  readonly BYPASS_HASH_FILE="${BYPASS_DATA_DIR}/passphrase.hash"
  readonly BYPASS_TOKEN_FILE="${BYPASS_DATA_DIR}/active.token"
  readonly BYPASS_FAILURES_FILE="${BYPASS_DATA_DIR}/failures.json"
  readonly BYPASS_CHECKSUMS_FILE="${BYPASS_DATA_DIR}/checksums.sha256"

  # Token validity period (not used for expiry, but for HMAC input)
  readonly BYPASS_TOKEN_VERSION="1"

  #######################################
  # Initialize bypass data directory
  # Globals:
  #   BYPASS_DATA_DIR
  # Returns:
  #   0 on success
  #######################################
  bypass_init() {
      if [[ ! -d "${BYPASS_DATA_DIR}" ]]; then
          mkdir -p "${BYPASS_DATA_DIR}"
          chmod 700 "${BYPASS_DATA_DIR}"
      fi
  }

  #######################################
  # Check if running in interactive TTY
  # Arguments:
  #   None
  # Returns:
  #   0 if TTY available, 1 otherwise
  #######################################
  bypass_check_tty() {
      # Must have stdin as TTY
      if [[ ! -t 0 ]]; then
          return 1
      fi

      # Must be able to read from /dev/tty
      if [[ ! -r /dev/tty ]]; then
          return 1
      fi

      # Additional check: ensure not in a pipe or subshell
      if [[ -p /dev/stdin ]]; then
          return 1
      fi

      return 0
  }

  #######################################
  # Read passphrase from TTY (invisible)
  # Arguments:
  #   $1 - Prompt message
  # Outputs:
  #   Passphrase to stdout
  # Returns:
  #   0 on success, 1 on failure
  #######################################
  bypass_read_passphrase() {
      local prompt="${1:-Enter passphrase: }"
      local passphrase

      # CRITICAL: Read directly from /dev/tty with -s (silent)
      # This prevents any piping or scripting attacks
      if ! IFS= read -rs -p "${prompt}" passphrase < /dev/tty 2>/dev/null; then
          return 1
      fi

      # Print newline after hidden input
      echo "" > /dev/tty

      # Output passphrase (caller captures)
      printf '%s' "${passphrase}"
      return 0
  }

  #######################################
  # Generate salted hash of passphrase
  # Arguments:
  #   $1 - Passphrase (plaintext)
  # Outputs:
  #   salt:hash to stdout
  # Returns:
  #   0 on success
  #######################################
  bypass_hash_passphrase() {
      local passphrase="$1"
      local salt
      local hash

      # Generate random salt (32 hex chars)
      salt=$(head -c 16 /dev/urandom | xxd -p)

      # Create SHA256 hash of salt+passphrase
      hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha256sum | cut -d' ' -f1)

      printf '%s:%s' "${salt}" "${hash}"
  }

  #######################################
  # Verify passphrase against stored hash
  # Arguments:
  #   $1 - Passphrase to verify
  # Returns:
  #   0 if correct, 1 if wrong, 2 if not configured
  #######################################
  bypass_verify_passphrase() {
      local passphrase="$1"
      local stored_hash
      local salt
      local expected_hash
      local computed_hash

      # Check if configured
      if [[ ! -f "${BYPASS_HASH_FILE}" ]]; then
          return 2
      fi

      # Read stored salt:hash
      stored_hash=$(cat "${BYPASS_HASH_FILE}")
      salt="${stored_hash%%:*}"
      expected_hash="${stored_hash#*:}"

      # Compute hash of provided passphrase
      computed_hash=$(printf '%s%s' "${salt}" "${passphrase}" | sha256sum | cut -d' ' -f1)

      # Constant-time comparison (prevent timing attacks)
      # Compare character by character, always checking all chars
      local match=0
      local i
      for ((i=0; i<${#expected_hash}; i++)); do
          if [[ "${expected_hash:$i:1}" != "${computed_hash:$i:1}" ]]; then
              match=1
          fi
      done

      return ${match}
  }

  #######################################
  # Create HMAC-verified token
  # Arguments:
  #   None (reads from BYPASS_HASH_FILE)
  # Outputs:
  #   Token to stdout
  # Returns:
  #   0 on success
  #######################################
  bypass_create_token() {
      local timestamp
      local stored_hash
      local hmac

      timestamp=$(date +%s)
      stored_hash=$(cat "${BYPASS_HASH_FILE}")

      # HMAC-SHA256 of version:timestamp using passphrase hash as key
      hmac=$(printf '%s:%s' "${BYPASS_TOKEN_VERSION}" "${timestamp}" | \
             openssl dgst -sha256 -hmac "${stored_hash}" | \
             sed 's/^.* //')

      printf '%s:%s:%s' "${BYPASS_TOKEN_VERSION}" "${timestamp}" "${hmac}"
  }

  #######################################
  # Verify token is valid (not forged)
  # Arguments:
  #   None (reads from token file)
  # Returns:
  #   0 if valid, 1 if invalid/missing
  #######################################
  bypass_verify_token() {
      local token
      local version
      local timestamp
      local stored_hmac
      local stored_hash
      local expected_hmac

      # Check token file exists
      if [[ ! -f "${BYPASS_TOKEN_FILE}" ]]; then
          return 1
      fi

      # Check hash file exists
      if [[ ! -f "${BYPASS_HASH_FILE}" ]]; then
          return 1
      fi

      # Read token
      token=$(cat "${BYPASS_TOKEN_FILE}")
      version="${token%%:*}"
      token="${token#*:}"
      timestamp="${token%%:*}"
      stored_hmac="${token#*:}"

      # Read stored passphrase hash
      stored_hash=$(cat "${BYPASS_HASH_FILE}")

      # Compute expected HMAC
      expected_hmac=$(printf '%s:%s' "${version}" "${timestamp}" | \
                     openssl dgst -sha256 -hmac "${stored_hash}" | \
                     sed 's/^.* //')

      # Constant-time comparison
      if [[ "${stored_hmac}" != "${expected_hmac}" ]]; then
          return 1
      fi

      return 0
  }

  #######################################
  # Check if bypass mode is currently active
  # Arguments:
  #   None
  # Returns:
  #   0 if active (bypass on), 1 if not (protection on)
  #######################################
  bypass_is_active() {
      # Token file must exist AND be valid
      if [[ ! -f "${BYPASS_TOKEN_FILE}" ]]; then
          return 1
      fi

      # Verify token is not forged
      if ! bypass_verify_token; then
          # Invalid token - remove it
          rm -f "${BYPASS_TOKEN_FILE}" 2>/dev/null
          return 1
      fi

      return 0
  }

  #######################################
  # Record authentication failure (rate limiting)
  # Arguments:
  #   None
  # Returns:
  #   0
  #######################################
  bypass_record_failure() {
      local failures_json
      local count
      local last_time
      local now

      now=$(date +%s)

      if [[ -f "${BYPASS_FAILURES_FILE}" ]]; then
          failures_json=$(cat "${BYPASS_FAILURES_FILE}")
          count=$(echo "${failures_json}" | grep -o '"count":[0-9]*' | cut -d: -f2)
          count=$((count + 1))
      else
          count=1
      fi

      # Write updated failures
      cat > "${BYPASS_FAILURES_FILE}" << EOF
  {"count":${count},"last_failure":${now}}
  EOF
      chmod 600 "${BYPASS_FAILURES_FILE}"
  }

  #######################################
  # Reset failure counter (on successful auth)
  # Arguments:
  #   None
  # Returns:
  #   0
  #######################################
  bypass_reset_failures() {
      rm -f "${BYPASS_FAILURES_FILE}" 2>/dev/null
      return 0
  }

  #######################################
  # Check if currently rate limited
  # Arguments:
  #   None
  # Outputs:
  #   Lockout message if locked
  # Returns:
  #   0 if allowed, 1 if locked out
  #######################################
  bypass_check_rate_limit() {
      local failures_json
      local count
      local last_failure
      local now
      local lockout_duration
      local unlock_time
      local remaining

      # No failures file = no lockout
      if [[ ! -f "${BYPASS_FAILURES_FILE}" ]]; then
          return 0
      fi

      failures_json=$(cat "${BYPASS_FAILURES_FILE}")
      count=$(echo "${failures_json}" | grep -o '"count":[0-9]*' | cut -d: -f2)
      last_failure=$(echo "${failures_json}" | grep -o '"last_failure":[0-9]*' | cut -d: -f2)
      now=$(date +%s)

      # iOS-style exponential backoff
      case ${count} in
          0|1|2) lockout_duration=0 ;;        # No lockout
          3)     lockout_duration=60 ;;       # 1 minute
          4)     lockout_duration=300 ;;      # 5 minutes
          5)     lockout_duration=900 ;;      # 15 minutes
          6|7|8|9) lockout_duration=3600 ;;   # 1 hour
          *)     lockout_duration=999999 ;;   # Permanent (manual reset)
      esac

      if [[ ${lockout_duration} -eq 0 ]]; then
          return 0
      fi

      unlock_time=$((last_failure + lockout_duration))

      if [[ ${now} -lt ${unlock_time} ]]; then
          remaining=$((unlock_time - now))
          if [[ ${lockout_duration} -eq 999999 ]]; then
              echo "Account locked. Too many failed attempts."
              echo "Manual reset required: rm ~/.wow-data/bypass/failures.json"
          else
              echo "Rate limited. Try again in ${remaining} seconds."
          fi
          return 1
      fi

      return 0
  }

  #######################################
  # Verify script checksums
  # Arguments:
  #   None
  # Returns:
  #   0 if all match, 1 if tampering detected
  #######################################
  bypass_verify_checksums() {
      local checksums_file="${BYPASS_CHECKSUMS_FILE}"

      # If no checksums file, skip verification (first run)
      if [[ ! -f "${checksums_file}" ]]; then
          return 0
      fi

      # Verify each checksum
      if ! sha256sum -c "${checksums_file}" --quiet 2>/dev/null; then
          return 1
      fi

      return 0
  }

  #######################################
  # Generate checksums for bypass scripts
  # Arguments:
  #   $1 - WoW installation directory
  # Returns:
  #   0 on success
  #######################################
  bypass_generate_checksums() {
      local wow_dir="$1"
      local checksums_file="${BYPASS_CHECKSUMS_FILE}"

      bypass_init

      # Generate checksums for all bypass-related scripts
      {
          sha256sum "${wow_dir}/bin/wow-bypass-setup"
          sha256sum "${wow_dir}/bin/wow-bypass"
          sha256sum "${wow_dir}/bin/wow-protect"
          sha256sum "${wow_dir}/bin/wow-bypass-status"
          sha256sum "${wow_dir}/src/security/bypass-core.sh"
          sha256sum "${wow_dir}/src/security/bypass-always-block.sh"
      } > "${checksums_file}"

      chmod 600 "${checksums_file}"
  }

  #######################################
  # Store passphrase hash
  # Arguments:
  #   $1 - Salted hash (salt:hash format)
  # Returns:
  #   0 on success
  #######################################
  bypass_store_hash() {
      local hash="$1"

      bypass_init

      echo "${hash}" > "${BYPASS_HASH_FILE}"
      chmod 600 "${BYPASS_HASH_FILE}"
  }

  #######################################
  # Activate bypass mode
  # Arguments:
  #   None
  # Returns:
  #   0 on success
  #######################################
  bypass_activate() {
      local token

      token=$(bypass_create_token)
      echo "${token}" > "${BYPASS_TOKEN_FILE}"
      chmod 600 "${BYPASS_TOKEN_FILE}"
      bypass_reset_failures
  }

  #######################################
  # Deactivate bypass mode
  # Arguments:
  #   None
  # Returns:
  #   0 on success
  #######################################
  bypass_deactivate() {
      rm -f "${BYPASS_TOKEN_FILE}" 2>/dev/null
      return 0
  }

  #######################################
  # Check if bypass is configured
  # Arguments:
  #   None
  # Returns:
  #   0 if configured, 1 if not
  #######################################
  bypass_is_configured() {
      [[ -f "${BYPASS_HASH_FILE}" ]]
  }

  6.2 src/security/bypass-always-block.sh

  #!/usr/bin/env bash
  # bypass-always-block.sh - Operations blocked even in bypass mode
  # Part of WoW System v6.1.0
  #
  # SECURITY CRITICAL: These patterns protect against catastrophic operations.
  # Modification requires security review.

  # Double-sourcing protection
  if [[ -n "${WOW_BYPASS_ALWAYS_BLOCK_LOADED:-}" ]]; then
      return 0
  fi
  readonly WOW_BYPASS_ALWAYS_BLOCK_LOADED=1

  # CATEGORY 1: System Destruction
  # Operations that could destroy the entire system
  readonly -a ALWAYS_BLOCK_DESTRUCTIVE=(
      'rm[[:space:]]+-rf[[:space:]]+/'
      'rm[[:space:]]+-rf[[:space:]]+/\*'
      'rm[[:space:]]+-rf[[:space:]]+--no-preserve-root'
      'rm[[:space:]]+-fr[[:space:]]+/'
      'rm[[:space:]].*[[:space:]]+/'$
      'rm[[:space:]]+-rf[[:space:]]+/bin'
      'rm[[:space:]]+-rf[[:space:]]+/lib'
      'rm[[:space:]]+-rf[[:space:]]+/lib64'
      'rm[[:space:]]+-rf[[:space:]]+/usr'
      'rm[[:space:]]+-rf[[:space:]]+/var'
      'rm[[:space:]]+-rf[[:space:]]+/home'
      'rm[[:space:]]+-rf[[:space:]]+/root'
  )

  # CATEGORY 2: Boot/Kernel Corruption
  # Operations that could make system unbootable
  readonly -a ALWAYS_BLOCK_BOOT=(
      'rm[[:space:]].*[[:space:]]+/boot'
      'rm[[:space:]].*[[:space:]]+/boot/vmlinuz'
      'rm[[:space:]].*[[:space:]]+/boot/initrd'
      'rm[[:space:]].*[[:space:]]+/boot/grub'
      'dd[[:space:]].*[[:space:]]of=/dev/[sh]da$'
      'dd[[:space:]].*[[:space:]]of=/dev/[sh]da[0-9]'
      'dd[[:space:]].*[[:space:]]of=/dev/nvme'
      'mkfs[[:space:]].*[[:space:]]/dev/[sh]da'
      'mkfs[[:space:]].*[[:space:]]/dev/nvme'
  )

  # CATEGORY 3: Fork Bombs / Resource Exhaustion
  # Operations that could freeze the system
  readonly -a ALWAYS_BLOCK_FORK_BOMBS=(
      ':\(\)[[:space:]]*{[[:space:]]*:|:'
      ':\(\){:|:&};:'
      'fork[[:space:]]*while'
      '\$0[[:space:]]*&[[:space:]]*\$0'
  )

  # CATEGORY 4: Disk Destruction
  # Direct disk writes that bypass filesystem
  readonly -a ALWAYS_BLOCK_DISK=(
      'dd[[:space:]].*if=/dev/zero.*of=/dev/'
      'dd[[:space:]].*if=/dev/urandom.*of=/dev/'
      'shred[[:space:]].*[[:space:]]/dev/'
      'wipefs[[:space:]].*[[:space:]]/dev/'
  )

  # CATEGORY 5: Cloud Credential Theft (SSRF)
  # Metadata endpoints for credential theft
  readonly -a ALWAYS_BLOCK_SSRF=(
      '169\.254\.169\.254'
      'metadata\.google\.internal'
      'metadata\.gke\.internal'
      '100\.100\.100\.200'
      'fd00:ec2::254'
  )

  # CATEGORY 6: Bypass System Self-Protection
  # Cannot modify the bypass system itself
  readonly -a ALWAYS_BLOCK_BYPASS_SELF=(
      '\.wow-data/bypass'
      'passphrase\.hash'
      'active\.token'
      'failures\.json'
      'checksums\.sha256'
      'bypass-core\.sh'
      'bypass-always-block\.sh'
      'wow-bypass-setup'
      'wow-bypass[^-]'
      'wow-protect'
  )

  # CATEGORY 7: System Authentication
  # Credential files that should never be touched
  readonly -a ALWAYS_BLOCK_AUTH=(
      '/etc/shadow'
      '/etc/gshadow'
      '/etc/master\.passwd'
      '/etc/sudoers'
      '/etc/pam\.d/'
  )

  #######################################
  # Check if operation matches always-block patterns
  # Arguments:
  #   $1 - Operation string (command, path, etc.)
  #   $2 - Category to check (optional, "all" for all categories)
  # Returns:
  #   0 if should block, 1 if allowed
  #######################################
  bypass_check_always_block() {
      local operation="$1"
      local category="${2:-all}"
      local pattern

      # Helper to check against array
      _check_patterns() {
          local -n patterns=$1
          for pattern in "${patterns[@]}"; do
              if [[ "${operation}" =~ ${pattern} ]]; then
                  return 0
              fi
          done
          return 1
      }

      case "${category}" in
          destructive)
              _check_patterns ALWAYS_BLOCK_DESTRUCTIVE
              ;;
          boot)
              _check_patterns ALWAYS_BLOCK_BOOT
              ;;
          fork)
              _check_patterns ALWAYS_BLOCK_FORK_BOMBS
              ;;
          disk)
              _check_patterns ALWAYS_BLOCK_DISK
              ;;
          ssrf)
              _check_patterns ALWAYS_BLOCK_SSRF
              ;;
          self)
              _check_patterns ALWAYS_BLOCK_BYPASS_SELF
              ;;
          auth)
              _check_patterns ALWAYS_BLOCK_AUTH
              ;;
          all|*)
              _check_patterns ALWAYS_BLOCK_DESTRUCTIVE && return 0
              _check_patterns ALWAYS_BLOCK_BOOT && return 0
              _check_patterns ALWAYS_BLOCK_FORK_BOMBS && return 0
              _check_patterns ALWAYS_BLOCK_DISK && return 0
              _check_patterns ALWAYS_BLOCK_SSRF && return 0
              _check_patterns ALWAYS_BLOCK_BYPASS_SELF && return 0
              _check_patterns ALWAYS_BLOCK_AUTH && return 0
              return 1
              ;;
      esac
  }

  #######################################
  # Get human-readable reason for block
  # Arguments:
  #   $1 - Operation string
  # Outputs:
  #   Reason string
  # Returns:
  #   0
  #######################################
  bypass_get_block_reason() {
      local operation="$1"

      local -n arr
      for arr in ALWAYS_BLOCK_DESTRUCTIVE ALWAYS_BLOCK_BOOT \
                 ALWAYS_BLOCK_FORK_BOMBS ALWAYS_BLOCK_DISK \
                 ALWAYS_BLOCK_SSRF ALWAYS_BLOCK_BYPASS_SELF \
                 ALWAYS_BLOCK_AUTH; do
          for pattern in "${arr[@]}"; do
              if [[ "${operation}" =~ ${pattern} ]]; then
                  case "${arr}" in
                      ALWAYS_BLOCK_DESTRUCTIVE) echo "System destruction command" ;;
                      ALWAYS_BLOCK_BOOT) echo "Boot/kernel corruption risk" ;;
                      ALWAYS_BLOCK_FORK_BOMBS) echo "Fork bomb / resource exhaustion" ;;
                      ALWAYS_BLOCK_DISK) echo "Direct disk destruction" ;;
                      ALWAYS_BLOCK_SSRF) echo "Cloud credential theft (SSRF)" ;;
                      ALWAYS_BLOCK_BYPASS_SELF) echo "Bypass system self-protection" ;;
                      ALWAYS_BLOCK_AUTH) echo "System authentication file" ;;
                  esac
                  return 0
              fi
          done
      done

      echo "Unknown"
  }

  6.3 bin/wow-bypass-setup

  #!/usr/bin/env bash
  # wow-bypass-setup - Configure bypass passphrase
  # Part of WoW System v6.1.0

  set -euo pipefail

  # Find WoW installation
  WOW_HOME="${WOW_HOME:-${HOME}/.claude/wow-system}"
  source "${WOW_HOME}/src/security/bypass-core.sh"

  main() {
      echo "WoW Bypass System Setup"
      echo "======================="
      echo ""

      # Check TTY
      if ! bypass_check_tty; then
          echo "ERROR: This command must be run in an interactive terminal."
          echo "It cannot be run from scripts or piped input."
          exit 2
      fi

      # Check if already configured
      if bypass_is_configured; then
          echo "Bypass is already configured."
          echo "To reconfigure, first run: rm ~/.wow-data/bypass/passphrase.hash"
          exit 3
      fi

      echo "This will configure a passphrase for temporarily disabling WoW blocking."
      echo "The passphrase will be stored as a salted hash (never plaintext)."
      echo ""
      echo "IMPORTANT:"
      echo "- There is NO recovery option if you forget the passphrase"
      echo "- You will need to delete and re-setup if forgotten"
      echo "- Choose something memorable but not guessable"
      echo ""

      # Read passphrase
      local passphrase1
      local passphrase2

      passphrase1=$(bypass_read_passphrase "Enter passphrase: ")
      passphrase2=$(bypass_read_passphrase "Confirm passphrase: ")

      # Check match
      if [[ "${passphrase1}" != "${passphrase2}" ]]; then
          echo "ERROR: Passphrases do not match."
          exit 1
      fi

      # Check minimum length
      if [[ ${#passphrase1} -lt 8 ]]; then
          echo "ERROR: Passphrase must be at least 8 characters."
          exit 1
      fi

      # Hash and store
      local hash
      hash=$(bypass_hash_passphrase "${passphrase1}")
      bypass_store_hash "${hash}"

      # Generate checksums
      bypass_generate_checksums "${WOW_HOME}"

      echo ""
      echo "Passphrase configured successfully."
      echo ""
      echo "Usage:"
      echo "  wow-bypass  - Activate bypass mode (disable blocking)"
      echo "  wow-protect - Re-enable protection"
      echo "  wow-bypass-status - Check current status"

      exit 0
  }

  main "$@"

  6.4 bin/wow-bypass

  #!/usr/bin/env bash
  # wow-bypass - Activate bypass mode
  # Part of WoW System v6.1.0

  set -euo pipefail

  # Find WoW installation
  WOW_HOME="${WOW_HOME:-${HOME}/.claude/wow-system}"
  source "${WOW_HOME}/src/security/bypass-core.sh"

  main() {
      echo "WoW Bypass Mode"
      echo "==============="
      echo ""

      # Step 1: Verify script integrity
      if ! bypass_verify_checksums; then
          echo "ERROR: Script tampering detected!"
          echo "The bypass scripts have been modified."
          echo "Please reinstall WoW System."
          exit 1
      fi

      # Step 2: Check TTY
      if ! bypass_check_tty; then
          echo "ERROR: This command must be run in an interactive terminal."
          echo "It cannot be run from scripts or piped input."
          exit 2
      fi

      # Step 3: Check configuration
      if ! bypass_is_configured; then
          echo "ERROR: Bypass not configured."
          echo "Please run 'wow-bypass-setup' first."
          exit 5
      fi

      # Step 4: Check rate limiting
      if ! bypass_check_rate_limit; then
          exit 3
      fi

      # Step 5: Read and verify passphrase
      local passphrase
      passphrase=$(bypass_read_passphrase "Enter passphrase: ")

      if ! bypass_verify_passphrase "${passphrase}"; then
          bypass_record_failure
          echo "ERROR: Incorrect passphrase."
          exit 4
      fi

      # Step 6: Activate bypass
      bypass_activate

      echo ""
      echo "Bypass mode activated."
      echo "WoW blocking is now disabled (except always-block operations)."
      echo ""
      echo "Use 'wow-protect' to re-enable protection when done."

      exit 0
  }

  main "$@"

  6.5 bin/wow-protect

  #!/usr/bin/env bash
  # wow-protect - Re-enable WoW protection
  # Part of WoW System v6.1.0

  set -euo pipefail

  # Find WoW installation
  WOW_HOME="${WOW_HOME:-${HOME}/.claude/wow-system}"
  source "${WOW_HOME}/src/security/bypass-core.sh"

  main() {
      if bypass_is_active; then
          bypass_deactivate
          echo "WoW protection re-enabled."
          echo "All security blocking is now active."
          exit 0
      else
          echo "WoW protection was already enabled."
          exit 1
      fi
  }

  main "$@"

  6.6 bin/wow-bypass-status

  #!/usr/bin/env bash
  # wow-bypass-status - Check bypass/protection status
  # Part of WoW System v6.1.0

  set -euo pipefail

  # Find WoW installation
  WOW_HOME="${WOW_HOME:-${HOME}/.claude/wow-system}"
  source "${WOW_HOME}/src/security/bypass-core.sh"

  main() {
      if ! bypass_is_configured; then
          echo "WoW Status: NOT CONFIGURED"
          echo ""
          echo "Bypass system is not set up."
          echo "Run 'wow-bypass-setup' to configure."
          exit 0
      fi

      if bypass_is_active; then
          echo "WoW Status: BYPASS ACTIVE"
          echo ""
          echo "Security blocking is disabled (except always-block operations)."
          echo "Use 'wow-protect' to re-enable protection."
      else
          echo "WoW Status: PROTECTED"
          echo ""
          echo "All security blocking is active."
      fi

      exit 0
  }

  main "$@"

  ---
  7. Security Hardening

  7.1 Path Protection

  All bypass-related paths are protected by WoW handlers:

  # In read-handler.sh, add:
  readonly -a BYPASS_PROTECTED_PATHS=(
      "${HOME}/.wow-data/bypass"
      "passphrase.hash"
      "active.token"
      "failures.json"
      "checksums.sha256"
  )

  # Block reads of these paths
  for protected in "${BYPASS_PROTECTED_PATHS[@]}"; do
      if [[ "${file_path}" == *"${protected}"* ]]; then
          echo "BLOCKED: Cannot read bypass system files" >&2
          return 2
      fi
  done

  7.2 Symlink Attack Prevention

  # Before any path check, canonicalize:
  _canonicalize_path() {
      local path="$1"
      # Resolve all symlinks
      if command -v realpath &>/dev/null; then
          realpath -m "${path}" 2>/dev/null || echo "${path}"
      elif command -v readlink &>/dev/null; then
          readlink -f "${path}" 2>/dev/null || echo "${path}"
      else
          echo "${path}"
      fi
  }

  # Use in checks:
  local canonical_path
  canonical_path=$(_canonicalize_path "${file_path}")

  7.3 Encoded Command Detection

  # Add to bash-handler.sh always-block checks:
  _detect_encoded_commands() {
      local cmd="$1"

      # Base64 patterns
      if [[ "${cmd}" =~ base64[[:space:]]+-d ]]; then
          return 0  # Suspicious
      fi

      # Hex decoding
      if [[ "${cmd}" =~ xxd[[:space:]]+-r ]]; then
          return 0  # Suspicious
      fi

      # Perl/Python eval
      if [[ "${cmd}" =~ (perl|python).*-e.*(eval|exec) ]]; then
          return 0  # Suspicious
      fi

      return 1
  }

  ---
  8. Attack Vectors & Mitigations

  8.1 Attack Vector Analysis

  | #   | Attack Vector             | Method                   | Mitigation                              | Status    |
  |-----|---------------------------|--------------------------|-----------------------------------------|-----------|
  | 1   | Brute force passphrase    | Repeated guessing        | iOS-style rate limiting                 | MITIGATED |
  | 2   | Read passphrase.hash      | Direct file read         | WoW read-handler blocks, file mode 600  | MITIGATED |
  | 3   | Create fake token         | Write to active.token    | HMAC verification (needs hash)          | MITIGATED |
  | 4   | Modify bypass scripts     | Edit/overwrite           | Checksum verification, WoW write blocks | MITIGATED |
  | 5   | Symlink redirection       | ln -s attack             | Path canonicalization before checks     | MITIGATED |
  | 6   | Pipe passphrase           | echo "pass" | wow-bypass | TTY enforcement, /dev/tty read          | MITIGATED |
  | 7   | Encoded commands          | base64 -d                | Pattern detection for encoding          | MITIGATED |
  | 8   | Environment injection     | Export passphrase var    | No env variable passphrase              | MITIGATED |
  | 9   | Script sourcing attack    | source wow-bypass        | Scripts verify own integrity            | MITIGATED |
  | 10  | Indirect token creation   | Construct valid HMAC     | Requires passphrase hash knowledge      | MITIGATED |
  | 11  | Fork script               | Copy and modify          | Checksums tied to specific paths        | MITIGATED |
  | 12  | Time-of-check-time-of-use | Race condition           | Atomic file operations                  | MITIGATED |

  8.2 Defense Matrix

                      ┌─────────────────────────────────────────┐
                      │           DEFENSE LAYERS                │
                      └─────────────────────────────────────────┘
                                        │
          ┌─────────────┬───────────────┼───────────────┬─────────────┐
          │             │               │               │             │
          ▼             ▼               ▼               ▼             ▼
     ┌─────────┐  ┌──────────┐  ┌─────────────┐  ┌──────────┐  ┌──────────┐
     │   TTY   │  │Passphrase│  │    HMAC     │  │Checksums │  │  Always  │
     │  Check  │  │   Auth   │  │   Tokens    │  │Integrity │  │  Block   │
     └────┬────┘  └────┬─────┘  └──────┬──────┘  └────┬─────┘  └────┬─────┘
          │            │               │              │              │
     Blocks:      Blocks:         Blocks:        Blocks:        Blocks:
     - Scripts    - Wrong pass    - Fake tokens  - Modified     - rm -rf /
     - Pipes      - Brute force   - Direct       scripts        - Fork bombs
     - SSH cmd    (rate limit)    token writes   - Backdoors    - dd to disk
                                                                - SSRF

  ---
  9. Always-Block List

  9.1 Categories

  Operations that are blocked EVEN WHEN BYPASS IS ACTIVE:

  | Category            | Examples                      | Rationale                     |
  |---------------------|-------------------------------|-------------------------------|
  | System Destruction  | rm -rf /, rm -rf /*           | Irreversible system loss      |
  | Boot Corruption     | rm /boot/*, dd of=/dev/sda    | Makes system unbootable       |
  | Fork Bombs          | `:(){ :                       | :& };:`                       |
  | Disk Destruction    | dd if=/dev/zero of=/dev/sda   | Data loss                     |
  | SSRF/Cloud Creds    | 169.254.169.254, AWS metadata | Credential theft              |
  | Bypass Self-Protect | ~/.wow-data/bypass/*          | Prevents disabling protection |
  | System Auth         | /etc/shadow, /etc/sudoers     | Privilege escalation          |

  9.2 Rationale

  The always-block list exists because:

  1. Catastrophic operations cannot be undone - Even a trusted user running with bypass shouldn't accidentally destroy their
  system
  2. Defense against social engineering - If someone tricks you into enabling bypass, they still can't destroy everything
  3. Bypass system integrity - The bypass system must protect itself to remain trustworthy
  4. Cloud security - SSRF attacks can compromise entire cloud accounts

  ---
  10. iOS-Style Rate Limiting

  10.1 Lockout Progression

  | Failures | Lockout Duration | Cumulative Wait |
  |----------|------------------|-----------------|
  | 1-2      | None             | 0               |
  | 3        | 1 minute         | 1 min           |
  | 4        | 5 minutes        | 6 min           |
  | 5        | 15 minutes       | 21 min          |
  | 6-9      | 1 hour           | 1-4 hours       |
  | 10+      | Permanent*       | Manual reset    |

  *Permanent lockout requires: rm ~/.wow-data/bypass/failures.json

  10.2 Implementation

  # iOS-style exponential backoff
  case ${count} in
      0|1|2) lockout_duration=0 ;;        # No lockout
      3)     lockout_duration=60 ;;       # 1 minute
      4)     lockout_duration=300 ;;      # 5 minutes
      5)     lockout_duration=900 ;;      # 15 minutes
      6|7|8|9) lockout_duration=3600 ;;   # 1 hour
      *)     lockout_duration=999999 ;;   # Permanent
  esac

  10.3 Reset on Success

  Successful authentication immediately resets the failure counter:

  bypass_activate() {
      local token
      token=$(bypass_create_token)
      echo "${token}" > "${BYPASS_TOKEN_FILE}"
      bypass_reset_failures  # Clear failure count
  }

  ---
  11. Handler Integration

  11.1 Integration Pattern

  Each handler must be modified to check bypass status:

  handle_<tool>() {
      local tool_input="$1"

      # Extract parameters...

      # STEP 1: Always check always-block list FIRST
      source "${WOW_HOME}/src/security/bypass-always-block.sh"
      if bypass_check_always_block "${operation}"; then
          local reason
          reason=$(bypass_get_block_reason "${operation}")
          log_warn "ALWAYS-BLOCKED: ${reason}"
          _output_block_guidance "This operation is blocked for safety: ${reason}"
          return 2
      fi

      # STEP 2: Check if bypass is active
      source "${WOW_HOME}/src/security/bypass-core.sh"
      if bypass_is_active; then
          # Bypass active - allow operation (skip other checks)
          log_info "Bypass active - allowing operation"
          echo "${tool_input}"
          return 0
      fi

      # STEP 3: Normal security checks (only when not bypassed)
      # ... existing handler logic ...
  }

  11.2 Handlers to Modify

  | Handler   | File                 | Changes                                   |
  |-----------|----------------------|-------------------------------------------|
  | Bash      | bash-handler.sh      | Add bypass check after always-block       |
  | Write     | write-handler.sh     | Add bypass check after always-block       |
  | Edit      | edit-handler.sh      | Add bypass check after always-block       |
  | Read      | read-handler.sh      | Add bypass path protection + bypass check |
  | Glob      | glob-handler.sh      | Add bypass check                          |
  | Grep      | grep-handler.sh      | Add bypass check                          |
  | Task      | task-handler.sh      | Add bypass check                          |
  | WebFetch  | webfetch-handler.sh  | Add bypass check (keep SSRF always-block) |
  | WebSearch | websearch-handler.sh | Add bypass check                          |

  11.3 Block Message Format

  When blocking (bypass NOT active), provide guidance:

  _output_block_guidance() {
      local reason="$1"
      local message="BLOCKED: ${reason}

  To perform this operation:
  1. Open a new terminal
  2. Run: wow-bypass
  3. Enter your passphrase
  4. Retry the operation
  5. Run: wow-protect (when done)

  Note: The user must manually enable bypass mode."

      echo "${message}" >&2
  }

  ---
  12. Claude Behavior Integration

  12.1 CLAUDE.md Addition

  Add to project CLAUDE.md:

  ## Bypass System Behavior

  When WoW blocks an operation with a message containing "wow-bypass", DO NOT:
  - Try alternative approaches to achieve the same goal
  - Attempt to work around the restriction
  - Repeatedly retry the blocked operation

  Instead, DO:
  - Inform the user that the operation was blocked
  - Ask the user if they want to enable bypass mode
  - Wait for the user to confirm they have enabled bypass
  - Only then retry the operation

  Example interaction:
  Claude: I tried to [operation] but it was blocked by WoW System.
          Would you like me to proceed? If so, please:
          1. Run wow-bypass in a terminal
          2. Enter your passphrase
          3. Tell me when ready

  User: Ready

  Claude: [Retries operation]


  12.2 Handler Output Format

  Structure block messages to trigger correct Claude behavior:

  {
    "blocked": true,
    "reason": "Operation blocked by WoW System",
    "action_required": "user_bypass",
    "instructions": [
      "Run wow-bypass in terminal",
      "Enter passphrase when prompted",
      "Inform Claude when ready"
    ]
  }

  ---
  13. Testing Strategy

  13.1 Unit Tests (test-bypass-core.sh)

  test_suite "Bypass Core Tests"

  # TTY Tests
  test_case "should detect non-TTY environment" test_non_tty
  test_case "should detect piped input" test_piped_input

  # Hash Tests
  test_case "should generate salted hash" test_hash_generation
  test_case "should produce different hashes for same input" test_hash_salt
  test_case "should verify correct passphrase" test_verify_correct
  test_case "should reject wrong passphrase" test_verify_wrong

  # Token Tests
  test_case "should create valid HMAC token" test_token_creation
  test_case "should verify valid token" test_token_verify
  test_case "should reject forged token" test_token_forge_reject
  test_case "should reject tampered token" test_token_tamper_reject

  # Rate Limiting Tests
  test_case "should allow first two attempts" test_rate_no_lockout
  test_case "should lock after 3 failures" test_rate_lock_3
  test_case "should increase lockout duration" test_rate_escalation
  test_case "should reset on success" test_rate_reset

  # Checksum Tests
  test_case "should generate checksums" test_checksum_generate
  test_case "should verify intact scripts" test_checksum_verify
  test_case "should detect tampered scripts" test_checksum_tamper

  13.2 Integration Tests (test-bypass-integration.sh)

  test_suite "Bypass Integration Tests"

  # Full Flow Tests
  test_case "should complete setup flow" test_full_setup
  test_case "should complete bypass flow" test_full_bypass
  test_case "should complete protect flow" test_full_protect

  # Handler Integration Tests
  test_case "should allow operation when bypass active" test_handler_bypass_allow
  test_case "should block operation when not bypassed" test_handler_no_bypass_block
  test_case "should always block catastrophic operations" test_always_block_active

  13.3 Security Tests

  test_suite "Bypass Security Tests"

  # Attack Simulation
  test_case "should block piped passphrase" test_attack_pipe
  test_case "should block script passphrase" test_attack_script
  test_case "should block direct token creation" test_attack_token_create
  test_case "should block hash file read" test_attack_hash_read
  test_case "should block script modification" test_attack_script_mod
  test_case "should detect symlink attacks" test_attack_symlink

  ---
  14. Future Enhancements

  14.1 v6.2.0: Per-Handler Bypass

  Allow bypassing specific handlers while keeping others active:

  wow-bypass --handler bash      # Only bypass bash checks
  wow-bypass --handler write     # Only bypass write checks
  wow-bypass --all               # Current behavior (all handlers)

  14.2 v6.3.0: Audit Logging

  Log all bypass activations for security review:

  # ~/.wow-data/bypass/audit.log
  2024-01-15T10:30:00Z SETUP user=destiny tty=/dev/pts/0
  2024-01-15T11:45:00Z BYPASS user=destiny tty=/dev/pts/0 duration=15m
  2024-01-15T12:00:00Z PROTECT user=destiny

  14.3 v6.4.0: Time-Limited Bypass

  Auto-expire bypass after configurable duration:

  wow-bypass --duration 30m   # Auto-protect after 30 minutes
  wow-bypass --duration 1h    # Auto-protect after 1 hour
  wow-bypass                  # No timeout (current behavior)

  ---
  Appendix A: File Permissions

  | File                | Mode | Owner | Rationale                      |
  |---------------------|------|-------|--------------------------------|
  | ~/.wow-data/bypass/ | 700  | user  | Directory only user-accessible |
  | passphrase.hash     | 600  | user  | Sensitive credential data      |
  | active.token        | 600  | user  | Auth state                     |
  | failures.json       | 600  | user  | Rate limiting state            |
  | checksums.sha256    | 600  | user  | Integrity data                 |

  Appendix B: Error Messages

  | Exit Code | Message                   | User Action                 |
  |-----------|---------------------------|-----------------------------|
  | 1         | Script tampering detected | Reinstall WoW               |
  | 2         | Not interactive terminal  | Use terminal directly       |
  | 3         | Rate limited              | Wait for lockout to expire  |
  | 4         | Wrong passphrase          | Re-enter correct passphrase |
  | 5         | Not configured            | Run wow-bypass-setup        |

  Appendix C: Glossary

  | Term          | Definition                                          |
  |---------------|-----------------------------------------------------|
  | TTY           | Terminal device allowing interactive input          |
  | HMAC          | Hash-based Message Authentication Code              |
  | Salt          | Random data added before hashing                    |
  | Constant-time | Comparison that takes same time regardless of match |
  | Always-block  | Operations blocked even in bypass mode              |
  | Fail-secure   | Errors result in protective (locked) state          |

  ---
  Document History

  | Version | Date       | Changes                    |
  |---------|------------|----------------------------|
  | 1.0     | 2024-12-22 | Initial comprehensive plan |

  ---