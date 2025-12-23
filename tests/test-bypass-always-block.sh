#!/bin/bash
# WoW System - Bypass Always-Block Tests (Comprehensive)
# TDD test suite for always-block pattern matching
# Author: Chude <chude@emeke.org>
#
# Coverage: All 7 categories, edge cases, bypass scenarios, reason lookup

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test-framework.sh"

ALWAYS_BLOCK="${PROJECT_ROOT}/src/security/bypass-always-block.sh"

setup_test() {
  if [[ -f "${ALWAYS_BLOCK}" ]]; then
	  unset WOW_BYPASS_ALWAYS_BLOCK_LOADED
	  source "${ALWAYS_BLOCK}"
  fi
}

require_module() {
  [[ -f "${ALWAYS_BLOCK}" ]] || { echo "TDD RED - module not found"; return 1; }
}

# === CATEGORY 1: System Destruction ===
test_blocks_rm_rf_root() {
  setup_test; require_module || return 1
  bypass_check_always_block "rm -rf /" || { echo "Should block rm -rf /"; return 1; }
}

test_blocks_rm_rf_root_wildcard() {
  setup_test; require_module || return 1
  bypass_check_always_block "rm -rf /*" || { echo "Should block rm -rf /*"; return 1; }
}

test_blocks_rm_rf_no_preserve() {
  setup_test; require_module || return 1
  bypass_check_always_block "rm -rf --no-preserve-root /" || { echo "Should block --no-preserve-root"; return 1; }
}

test_blocks_rm_rf_system_dirs() {
  setup_test; require_module || return 1
  local dirs=("/bin" "/lib" "/lib64" "/usr" "/var" "/home" "/root" "/etc" "/sbin")
  for dir in "${dirs[@]}"; do
	  bypass_check_always_block "rm -rf ${dir}" || { echo "Should block rm -rf ${dir}"; return 1; }
  done
}

test_allows_rm_tmp() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "rm -rf /tmp/myfiles" || { echo "Should allow /tmp deletion"; return 1; }
}

test_allows_rm_user_dir() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "rm -rf /home/user/project" || { echo "Should allow user dir deletion"; return 1; }
}

# === CATEGORY 2: Boot/Disk Corruption ===
test_blocks_dd_to_sda() {
  setup_test; require_module || return 1
  bypass_check_always_block "dd if=/dev/zero of=/dev/sda" || { echo "Should block dd to sda"; return 1; }
}

test_blocks_dd_to_nvme() {
  setup_test; require_module || return 1
  bypass_check_always_block "dd if=/dev/urandom of=/dev/nvme0n1" || { echo "Should block dd to nvme"; return 1; }
}

test_blocks_mkfs() {
  setup_test; require_module || return 1
  bypass_check_always_block "mkfs.ext4 /dev/sda1" || { echo "Should block mkfs"; return 1; }
}

test_blocks_mkfs_xfs() {
  setup_test; require_module || return 1
  bypass_check_always_block "mkfs.xfs /dev/nvme0n1p1" || { echo "Should block mkfs.xfs"; return 1; }
}

test_allows_dd_to_file() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "dd if=/dev/zero of=/tmp/testfile bs=1M count=1" || { echo "Should allow dd to file"; return 1;
}
}

# === CATEGORY 3: Fork Bombs ===
test_blocks_fork_bomb_classic() {
  setup_test; require_module || return 1
  bypass_check_always_block ':(){ :|:& };:' || { echo "Should block classic fork bomb"; return 1; }
}

test_blocks_fork_bomb_variant() {
  setup_test; require_module || return 1
  bypass_check_always_block ':(){:|:&};:' || { echo "Should block fork bomb variant"; return 1; }
}

# === CATEGORY 4: SSRF/Cloud Credentials ===
test_blocks_aws_metadata() {
  setup_test; require_module || return 1
  bypass_check_always_block "curl http://169.254.169.254/latest/meta-data/" || { echo "Should block AWS metadata"; return 1;
}
}

test_blocks_aws_metadata_wget() {
  setup_test; require_module || return 1
  bypass_check_always_block "wget 169.254.169.254" || { echo "Should block AWS metadata wget"; return 1; }
}

test_blocks_gcp_metadata() {
  setup_test; require_module || return 1
  bypass_check_always_block "curl metadata.google.internal" || { echo "Should block GCP metadata"; return 1; }
}

test_blocks_alibaba_metadata() {
  setup_test; require_module || return 1
  bypass_check_always_block "curl 100.100.100.200" || { echo "Should block Alibaba metadata"; return 1; }
}

test_allows_normal_ip() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "curl 8.8.8.8" || { echo "Should allow normal IP"; return 1; }
}

test_allows_normal_domain() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "curl github.com" || { echo "Should allow normal domain"; return 1; }
}

# === CATEGORY 5: Bypass Self-Protection ===
test_blocks_passphrase_hash_read() {
  setup_test; require_module || return 1
  bypass_check_always_block "cat ~/.wow-data/bypass/passphrase.hash" || { echo "Should block hash read"; return 1; }
}

test_blocks_active_token_write() {
  setup_test; require_module || return 1
  bypass_check_always_block "echo fake > active.token" || { echo "Should block token write"; return 1; }
}

test_blocks_bypass_core_edit() {
  setup_test; require_module || return 1
  bypass_check_always_block "vim bypass-core.sh" || { echo "Should block bypass-core edit"; return 1; }
}

test_blocks_bypass_always_block_edit() {
  setup_test; require_module || return 1
  bypass_check_always_block "nano bypass-always-block.sh" || { echo "Should block always-block edit"; return 1; }
}

test_blocks_wow_bypass_setup_edit() {
  setup_test; require_module || return 1
  bypass_check_always_block "sed -i 's/x/y/' wow-bypass-setup" || { echo "Should block setup edit"; return 1; }
}

test_blocks_wow_bypass_command_edit() {
  setup_test; require_module || return 1
  bypass_check_always_block "edit wow-bypass" || { echo "Should block wow-bypass edit"; return 1; }
}

test_blocks_failures_json_write() {
  setup_test; require_module || return 1
  bypass_check_always_block "echo {} > failures.json" || { echo "Should block failures.json write"; return 1; }
}

# === CATEGORY 6: System Authentication ===
test_blocks_etc_shadow_read() {
  setup_test; require_module || return 1
  bypass_check_always_block "cat /etc/shadow" || { echo "Should block /etc/shadow read"; return 1; }
}

test_blocks_etc_shadow_write() {
  setup_test; require_module || return 1
  bypass_check_always_block "echo root::0:0::: >> /etc/shadow" || { echo "Should block /etc/shadow write"; return 1; }
}

test_blocks_etc_sudoers() {
  setup_test; require_module || return 1
  bypass_check_always_block "echo 'ALL ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers" || { echo "Should block /etc/sudoers";
return 1; }
}

# === Safe Operations (should NOT block) ===
test_allows_ls() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "ls -la" || { echo "Should allow ls"; return 1; }
}

test_allows_git() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "git status" || { echo "Should allow git"; return 1; }
}

test_allows_npm() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "npm install lodash" || { echo "Should allow npm"; return 1; }
}

test_allows_python() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "python script.py" || { echo "Should allow python"; return 1; }
}

test_allows_mkdir() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "mkdir -p /home/user/project/src" || { echo "Should allow mkdir"; return 1; }
}

test_allows_cat_normal_file() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "cat /home/user/file.txt" || { echo "Should allow normal file read"; return 1; }
}

test_allows_rm_specific_file() {
  setup_test; require_module || return 1
  ! bypass_check_always_block "rm /tmp/test.txt" || { echo "Should allow specific file deletion"; return 1; }
}

# === Reason Lookup Tests ===
test_reason_destruction() {
  setup_test; require_module || return 1
  local reason
  reason=$(bypass_get_block_reason "rm -rf /")
  [[ "${reason}" == *"estruction"* ]] || [[ "${reason}" == *"estroy"* ]] || { echo "Should provide destruction reason:
${reason}"; return 1; }
}

test_reason_ssrf() {
  setup_test; require_module || return 1
  local reason
  reason=$(bypass_get_block_reason "curl 169.254.169.254")
  [[ "${reason}" == *"SSRF"* ]] || [[ "${reason}" == *"credential"* ]] || [[ "${reason}" == *"loud"* ]] || { echo "Should
provide SSRF reason: ${reason}"; return 1; }
}

test_reason_self_protection() {
  setup_test; require_module || return 1
  local reason
  reason=$(bypass_get_block_reason "cat passphrase.hash")
  [[ "${reason}" == *"self"* ]] || [[ "${reason}" == *"rotection"* ]] || [[ "${reason}" == *"ypass"* ]] || { echo "Should
provide self-protection reason: ${reason}"; return 1; }
}

test_reason_auth() {
  setup_test; require_module || return 1
  local reason
  reason=$(bypass_get_block_reason "cat /etc/shadow")
  [[ "${reason}" == *"auth"* ]] || [[ "${reason}" == *"Auth"* ]] || [[ "${reason}" == *"shadow"* ]] || { echo "Should provide
auth reason: ${reason}"; return 1; }
}

# === Run Tests ===
test_suite "Bypass Always-Block Comprehensive Tests"

echo ""
echo "=== System Destruction Tests (6 tests) ==="
test_case "blocks rm -rf /" test_blocks_rm_rf_root
test_case "blocks rm -rf /*" test_blocks_rm_rf_root_wildcard
test_case "blocks --no-preserve-root" test_blocks_rm_rf_no_preserve
test_case "blocks rm -rf on system dirs" test_blocks_rm_rf_system_dirs
test_case "allows rm -rf /tmp" test_allows_rm_tmp
test_case "allows rm -rf user dir" test_allows_rm_user_dir

echo ""
echo "=== Boot/Disk Corruption Tests (5 tests) ==="
test_case "blocks dd to /dev/sda" test_blocks_dd_to_sda
test_case "blocks dd to /dev/nvme" test_blocks_dd_to_nvme
test_case "blocks mkfs.ext4" test_blocks_mkfs
test_case "blocks mkfs.xfs" test_blocks_mkfs_xfs
test_case "allows dd to regular file" test_allows_dd_to_file

echo ""
echo "=== Fork Bomb Tests (2 tests) ==="
test_case "blocks classic fork bomb" test_blocks_fork_bomb_classic
test_case "blocks fork bomb variant" test_blocks_fork_bomb_variant

echo ""
echo "=== SSRF/Cloud Credential Tests (6 tests) ==="
test_case "blocks AWS metadata curl" test_blocks_aws_metadata
test_case "blocks AWS metadata wget" test_blocks_aws_metadata_wget
test_case "blocks GCP metadata" test_blocks_gcp_metadata
test_case "blocks Alibaba metadata" test_blocks_alibaba_metadata
test_case "allows normal IP" test_allows_normal_ip
test_case "allows normal domain" test_allows_normal_domain

echo ""
echo "=== Bypass Self-Protection Tests (7 tests) ==="
test_case "blocks passphrase.hash read" test_blocks_passphrase_hash_read
test_case "blocks active.token write" test_blocks_active_token_write
test_case "blocks bypass-core.sh edit" test_blocks_bypass_core_edit
test_case "blocks bypass-always-block.sh edit" test_blocks_bypass_always_block_edit
test_case "blocks wow-bypass-setup edit" test_blocks_wow_bypass_setup_edit
test_case "blocks wow-bypass command edit" test_blocks_wow_bypass_command_edit
test_case "blocks failures.json write" test_blocks_failures_json_write

echo ""
echo "=== System Authentication Tests (3 tests) ==="
test_case "blocks /etc/shadow read" test_blocks_etc_shadow_read
test_case "blocks /etc/shadow write" test_blocks_etc_shadow_write
test_case "blocks /etc/sudoers modification" test_blocks_etc_sudoers

echo ""
echo "=== Safe Operations Tests (7 tests) ==="
test_case "allows ls command" test_allows_ls
test_case "allows git command" test_allows_git
test_case "allows npm command" test_allows_npm
test_case "allows python command" test_allows_python
test_case "allows mkdir command" test_allows_mkdir
test_case "allows cat normal file" test_allows_cat_normal_file
test_case "allows rm specific file" test_allows_rm_specific_file

echo ""
echo "=== Reason Lookup Tests (4 tests) ==="
test_case "provides destruction reason" test_reason_destruction
test_case "provides SSRF reason" test_reason_ssrf
test_case "provides self-protection reason" test_reason_self_protection
test_case "provides auth reason" test_reason_auth

echo ""
test_summary