#!/bin/bash
# WoW System - Bypass Always-Block Definitions
# Provides: Operations blocked EVEN when bypass is active
# Author: Chude <chude@emeke.org>

# Prevent double-sourcing
if [[ -n "${WOW_BYPASS_ALWAYS_BLOCK_LOADED:-}" ]]; then
  return 0
fi
readonly WOW_BYPASS_ALWAYS_BLOCK_LOADED=1

# Source dependencies
_ALWAYS_BLOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ALWAYS_BLOCK_DIR}/../core/utils.sh" 2>/dev/null || true

set -uo pipefail

# CATEGORY 1: System Destruction
# Note: Patterns anchor to end-of-string or whitespace to allow subdirectory deletions
# e.g., "rm -rf /home" is blocked but "rm -rf /home/user/project" is allowed
readonly -a ALWAYS_BLOCK_DESTRUCTIVE=(
	'rm[[:space:]]+-rf[[:space:]]+/$'
	'rm[[:space:]]+-rf[[:space:]]+/\*'
	'rm[[:space:]]+-rf[[:space:]]+--no-preserve-root'
	'rm[[:space:]]+-rf[[:space:]]+/bin([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/lib([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/lib64([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/usr([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/var([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/home([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/root([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/etc([[:space:]]|/?$)'
	'rm[[:space:]]+-rf[[:space:]]+/sbin([[:space:]]|/?$)'
)

# CATEGORY 2: Boot/Disk Operations
readonly -a ALWAYS_BLOCK_BOOT=(
  'dd[[:space:]].*of=/dev/[sh]da'
  'dd[[:space:]].*of=/dev/nvme'
  'mkfs\.[[:alnum:]]+[[:space:]]+/dev/'
)

# CATEGORY 3: Fork Bombs
readonly -a ALWAYS_BLOCK_FORK_BOMBS=(
  ':\(\)[[:space:]]*\{[[:space:]]*:'
)

# CATEGORY 4: SSRF
readonly -a ALWAYS_BLOCK_SSRF=(
  '169\.254\.169\.254'
  'metadata\.google\.internal'
  '100\.100\.100\.200'
)

# CATEGORY 5: Bypass Self-Protection
readonly -a ALWAYS_BLOCK_BYPASS_SELF=(
  '\.wow-data/bypass'
  'passphrase\.hash'
  'active\.token'
  'bypass-core\.sh'
  'bypass-always-block\.sh'
  'wow-bypass-setup'
  'wow-bypass[^-]'
  'wow-bypass$'
  'failures\.json'
)

# CATEGORY 6: System Auth
readonly -a ALWAYS_BLOCK_AUTH=(
  '/etc/shadow'
  '/etc/sudoers'
)

# Check if operation matches always-block patterns
# Returns: 0=BLOCK, 1=ALLOW
bypass_check_always_block() {
  local operation="$1"
  local category="${2:-all}"

  _check_patterns() {
	  local -n patterns_ref=$1
	  local pattern
	  for pattern in "${patterns_ref[@]}"; do
		  if [[ "${operation}" =~ ${pattern} ]]; then
			  return 0
		  fi
	  done
	  return 1
  }

  case "${category}" in
	  all|*)
		  _check_patterns ALWAYS_BLOCK_DESTRUCTIVE && return 0
		  _check_patterns ALWAYS_BLOCK_BOOT && return 0
		  _check_patterns ALWAYS_BLOCK_FORK_BOMBS && return 0
		  _check_patterns ALWAYS_BLOCK_SSRF && return 0
		  _check_patterns ALWAYS_BLOCK_BYPASS_SELF && return 0
		  _check_patterns ALWAYS_BLOCK_AUTH && return 0
		  return 1
		  ;;
  esac
}

bypass_get_block_reason() {
  local operation="$1"
  for p in "${ALWAYS_BLOCK_DESTRUCTIVE[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "System destruction" && return; done
  for p in "${ALWAYS_BLOCK_BOOT[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "Boot/disk corruption" && return; done
  for p in "${ALWAYS_BLOCK_FORK_BOMBS[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "Fork bomb" && return; done
  for p in "${ALWAYS_BLOCK_SSRF[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "Cloud credential theft (SSRF)" && return; done
  for p in "${ALWAYS_BLOCK_BYPASS_SELF[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "Bypass self-protection" && return; done
  for p in "${ALWAYS_BLOCK_AUTH[@]}"; do [[ "${operation}" =~ ${p} ]] && echo "System auth file" && return; done
  echo "Unknown"
}
