#!/bin/bash
# WoW System - Security Constants
# Shared security patterns and constants for all handlers
# Author: Chude <chude@emeke.org>
#
# Design Principle: Single Source of Truth for security patterns
# Used by: webfetch-handler, websearch-handler, and future security modules

# Prevent double-sourcing
if [[ -n "${WOW_SECURITY_CONSTANTS_LOADED:-}" ]]; then
    return 0
fi
readonly WOW_SECURITY_CONSTANTS_LOADED=1

# ============================================================================
# SSRF Prevention - Private/Internal IP Ranges
# ============================================================================

# CRITICAL: Private/internal IP ranges (SSRF prevention)
# These patterns block access to private networks and localhost
readonly -a BLOCKED_IP_PATTERNS=(
    "^127\."                    # 127.0.0.0/8 (loopback)
    "^10\."                     # 10.0.0.0/8 (private)
    "^172\.(1[6-9]|2[0-9]|3[01])\."  # 172.16.0.0/12 (private)
    "^192\.168\."               # 192.168.0.0/16 (private)
    "^169\.254\."               # 169.254.0.0/16 (link-local)
    "^::1$"                     # IPv6 loopback
    "^fe80:"                    # IPv6 link-local
    "^fc00:"                    # IPv6 unique local
    "^fd00:"                    # IPv6 unique local
)

# Export for handlers
export BLOCKED_IP_PATTERNS
