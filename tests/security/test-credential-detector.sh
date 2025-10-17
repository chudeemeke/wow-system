#!/bin/bash
# WoW System - Credential Detector Test Suite
# Comprehensive tests with 30+ credential samples
# Author: Chude <chude@emeke.org>

set -uo pipefail

# ============================================================================
# Test Setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source the credential detector
source "${PROJECT_ROOT}/src/security/credential-detector.sh"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Framework
# ============================================================================

assert_detects() {
    local test_name="$1"
    local input="$2"
    local expected_type="$3"

    (( TESTS_RUN++ )) || true

    local result
    if result=$(detect_in_string "$input"); then
        local detected_type
        detected_type=$(echo "$result" | jq -r '.type')

        if [[ "$detected_type" == "$expected_type" ]]; then
            echo "  PASS: $test_name"
            (( TESTS_PASSED++ )) || true
        else
            echo "  FAIL: $test_name (expected: $expected_type, got: $detected_type)"
            (( TESTS_FAILED++ )) || true
        fi
    else
        echo "  FAIL: $test_name (no detection)"
        (( TESTS_FAILED++ )) || true
    fi
}

assert_no_detection() {
    local test_name="$1"
    local input="$2"

    (( TESTS_RUN++ )) || true

    local result
    if result=$(detect_in_string "$input"); then
        echo "  FAIL: $test_name (false positive detected)"
        (( TESTS_FAILED++ )) || true
    else
        echo "  PASS: $test_name"
        (( TESTS_PASSED++ )) || true
    fi
}

# ============================================================================
# Test Cases - HIGH Severity
# ============================================================================

test_github_tokens() {
    echo "=== Testing GitHub Tokens ==="

    assert_detects "GitHub PAT" \
        "export GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuv123456" \
        "github_pat"

    assert_detects "GitHub OAuth" \
        "token = gho_1234567890abcdefghijklmnopqrstuv123456" \
        "github_oauth"

    assert_detects "GitHub App token" \
        "Authorization: Bearer ghu_1234567890abcdefghijklmnopqrstuv123456" \
        "github_app"

    assert_detects "GitHub Server token" \
        "GH_TOKEN=ghs_1234567890abcdefghijklmnopqrstuv123456" \
        "github_app"

    assert_detects "GitHub Refresh token" \
        "refresh_token=ghr_1234567890abcdefghijklmnopqrstuv123456" \
        "github_refresh"
}

test_npm_tokens() {
    echo "=== Testing NPM Tokens ==="

    assert_detects "NPM token (36 chars)" \
        "//registry.npmjs.org/:_authToken=npm_1234567890abcdefghijklmnopqrstuvwxyz" \
        "npm_token"

    assert_detects "NPM token (40 chars)" \
        "NPM_TOKEN=npm_abcdefghijklmnopqrstuvwxyz0123456789ABCD" \
        "npm_token"
}

test_gitlab_tokens() {
    echo "=== Testing GitLab Tokens ==="

    assert_detects "GitLab PAT" \
        "GITLAB_TOKEN=glpat-abcdefghijklmnopqrstuvwxyz" \
        "gitlab_pat"

    assert_detects "GitLab Runner token" \
        "CI_JOB_TOKEN=GR1348941abcdefghijklmnopqrstuvwxyz" \
        "gitlab_runner"
}

test_openai_keys() {
    echo "=== Testing OpenAI API Keys ==="

    assert_detects "OpenAI API key (48 chars)" \
        "OPENAI_API_KEY=sk-1234567890abcdefghijklmnopqrstuvwxyzABCDEFGH" \
        "openai_api"

    assert_detects "OpenAI API key in code" \
        "const apiKey = 'sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJK';" \
        "openai_api"
}

test_anthropic_keys() {
    echo "=== Testing Anthropic API Keys ==="

    assert_detects "Anthropic API key" \
        "ANTHROPIC_API_KEY=sk-ant-api03-1234567890abcdefghijklmnopqrstuvwxyz" \
        "anthropic_api"

    assert_detects "Anthropic key with underscores" \
        "api_key = sk-ant-api03-abc_def_ghi_jkl_mno_pqr_stu_vwx_yz" \
        "anthropic_api"
}

test_aws_keys() {
    echo "=== Testing AWS Keys ==="

    assert_detects "AWS Access Key" \
        "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE" \
        "aws_access_key"

    assert_detects "AWS Access Key in config" \
        "aws_access_key_id = AKIAI44QH8DHBEXAMPLE" \
        "aws_access_key"
}

test_slack_tokens() {
    echo "=== Testing Slack Tokens ==="

    assert_detects "Slack Bot token" \
        "SLACK_BOT_TOKEN=xoxb-XXXXXXXXXXXX-XXXXXXXXXXXX-XXXXXXXXXXXXXXXXXXXXXXXX" \
        "slack_token"

    assert_detects "Slack Webhook URL" \
        "webhook_url=https://hooks.slack.com/services/TXXXXXXXX/BXXXXXXXX/XXXXXXXXXXXXXXXXXXXX" \
        "slack_webhook"
}

test_google_keys() {
    echo "=== Testing Google API Keys ==="

    assert_detects "Google API key" \
        "GOOGLE_API_KEY=AIzaSyAbcDefGhIjKlMnOpQrStUvWxYz1234567" \
        "google_api"
}

test_stripe_keys() {
    echo "=== Testing Stripe Keys ==="

    assert_detects "Stripe Live key" \
        "STRIPE_SECRET_KEY=sk_live_FAKE_TEST_CREDENTIAL_NOT_REAL" \
        "stripe_live"

    assert_detects "Stripe Test key" \
        "stripe_key = sk_test_FAKE_TEST_CREDENTIAL_NOT_REAL" \
        "stripe_test"
}

test_twilio_keys() {
    echo "=== Testing Twilio Keys ==="

    assert_detects "Twilio Account SID" \
        "TWILIO_ACCOUNT_SID=ACabcdefghijklmnopqrstuvwxyz123456" \
        "twilio_account"

    assert_detects "Twilio Auth Token" \
        "TWILIO_AUTH_TOKEN=SKabcdefghijklmnopqrstuvwxyz123456" \
        "twilio_auth"
}

test_sendgrid_keys() {
    echo "=== Testing SendGrid Keys ==="

    assert_detects "SendGrid API key" \
        "SENDGRID_API_KEY=SG.abcdefghijklmnopqrstuv.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop" \
        "sendgrid_api"
}

test_mailgun_keys() {
    echo "=== Testing Mailgun Keys ==="

    assert_detects "Mailgun API key" \
        "MAILGUN_API_KEY=key-1234567890abcdefghijklmnopqrstuv" \
        "mailgun_api"
}

test_jwt_tokens() {
    echo "=== Testing JWT Tokens ==="

    assert_detects "JWT token" \
        "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
        "jwt_token"
}

test_pypi_tokens() {
    echo "=== Testing PyPI Tokens ==="

    assert_detects "PyPI token" \
        "PYPI_TOKEN=pypi-AgEIcHlwaS5vcmcCJGFiY2RlZi0xMjM0LTU2NzgtOTBhYi1jZGVmMTIzNDU2Nzg" \
        "pypi_token"
}

test_docker_tokens() {
    echo "=== Testing Docker Tokens ==="

    assert_detects "Docker PAT" \
        "DOCKER_TOKEN=dckr_pat_abcdefghijklmnopqrstuvwxyz1234567890" \
        "docker_token"
}

# ============================================================================
# Test Cases - MEDIUM Severity
# ============================================================================

test_generic_api_keys() {
    echo "=== Testing Generic API Keys ==="

    assert_detects "Generic API key (snake_case)" \
        "api_key = abcdefghijklmnopqrstuvwxyz1234567890" \
        "generic_api_key"

    assert_detects "Generic API key (camelCase)" \
        "apiKey: 1234567890abcdefghijklmnopqrstuvwxyz" \
        "generic_api_key"

    assert_detects "Generic API key (kebab-case)" \
        "api-key=ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890" \
        "generic_api_key"
}

test_generic_tokens() {
    echo "=== Testing Generic Tokens ==="

    assert_detects "Generic token" \
        "token = abcdefghijklmnopqrstuvwxyz1234567890ABCD" \
        "generic_token"

    assert_detects "Auth token" \
        "auth_token: 1234567890abcdefghijklmnopqrstuvwxyz" \
        "generic_token"
}

test_generic_secrets() {
    echo "=== Testing Generic Secrets ==="

    assert_detects "Generic secret" \
        "secret = my-super-secret-key-12345678901234567890" \
        "generic_secret"

    assert_detects "API secret" \
        "api_secret: ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890" \
        "generic_secret"
}

test_generic_passwords() {
    echo "=== Testing Generic Passwords ==="

    assert_detects "Password" \
        "password = MyP@ssw0rd123!" \
        "generic_password"

    assert_detects "Passwd" \
        "passwd: SuperSecret123$" \
        "generic_password"
}

test_bearer_tokens() {
    echo "=== Testing Bearer Tokens ==="

    assert_detects "Bearer token" \
        "Authorization: Bearer abcdefghijklmnopqrstuvwxyz1234567890" \
        "bearer_token"
}

test_basic_auth() {
    echo "=== Testing Basic Auth ==="

    assert_detects "Basic auth" \
        "Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQxMjM0NTY3ODkwYWJjZGVm" \
        "basic_auth"
}

test_connection_strings() {
    echo "=== Testing Connection Strings ==="

    assert_detects "MongoDB connection string" \
        "MONGO_URL=mongodb://admin:password123@localhost:27017/mydb" \
        "connection_string"

    assert_detects "PostgreSQL connection string" \
        "DATABASE_URL=postgres://user:pass123@localhost:5432/db" \
        "connection_string"

    assert_detects "MySQL connection string" \
        "DB_URL=mysql://root:secret@127.0.0.1:3306/database" \
        "connection_string"

    assert_detects "Redis connection string" \
        "REDIS_URL=redis://user:password@localhost:6379" \
        "connection_string"
}

test_private_keys() {
    echo "=== Testing Private Keys ==="

    assert_detects "RSA private key header" \
        "-----BEGIN RSA PRIVATE KEY-----" \
        "private_key_header"

    assert_detects "Private key header" \
        "-----BEGIN PRIVATE KEY-----" \
        "private_key_header"
}

test_ssh_keys() {
    echo "=== Testing SSH Keys ==="

    assert_detects "SSH RSA key" \
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC1234567890abcdefghijk user@host" \
        "ssh_key"

    assert_detects "SSH Ed25519 key" \
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbcdefghijklmnopqrstuvwxyz user@host" \
        "ssh_key"
}

# ============================================================================
# Test Cases - False Positives (should NOT detect)
# ============================================================================

test_false_positives() {
    echo "=== Testing False Positives ==="

    assert_no_detection "Example placeholder" \
        "api_key = YOUR_API_KEY_HERE"

    assert_no_detection "Test placeholder" \
        "token = test_token_example"

    assert_no_detection "Sample placeholder" \
        "secret = sample_secret_key"

    assert_no_detection "Dummy value" \
        "password = dummy123"

    assert_no_detection "Fake value" \
        "api_key = fake_key_12345"

    assert_no_detection "Mock value" \
        "token = mock_token_abcdefg"

    assert_no_detection "Replace me placeholder" \
        "API_KEY=REPLACE_ME_WITH_ACTUAL_KEY"

    assert_no_detection "XXX placeholder" \
        "secret = xxxxxxxxxxxxxxxx"

    assert_no_detection "123 placeholder" \
        "password = 1234567890123456"

    assert_no_detection "ABC placeholder" \
        "api_key = abcabcabcabcabcabcabc"
}

# ============================================================================
# Test Cases - Severity Detection
# ============================================================================

test_severity_detection() {
    echo "=== Testing Severity Detection ==="

    local severity

    severity=$(detect_get_severity "github_pat")
    if [[ "$severity" == "HIGH" ]]; then
        echo "  PASS: GitHub PAT is HIGH severity"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: GitHub PAT severity (expected: HIGH, got: $severity)"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true

    severity=$(detect_get_severity "generic_api_key")
    if [[ "$severity" == "MEDIUM" ]]; then
        echo "  PASS: Generic API key is MEDIUM severity"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Generic API key severity (expected: MEDIUM, got: $severity)"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true

    severity=$(detect_get_severity "uuid")
    if [[ "$severity" == "LOW" ]]; then
        echo "  PASS: UUID is LOW severity"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: UUID severity (expected: LOW, got: $severity)"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true
}

# ============================================================================
# Test Cases - Alert Decision
# ============================================================================

test_alert_decision() {
    echo "=== Testing Alert Decision ==="

    if detect_should_alert "github_pat"; then
        echo "  PASS: Should alert for GitHub PAT"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Should alert for GitHub PAT"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true

    if detect_should_alert "generic_api_key"; then
        echo "  PASS: Should alert for generic API key"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Should alert for generic API key"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true

    if ! detect_should_alert "uuid"; then
        echo "  PASS: Should NOT alert for UUID"
        (( TESTS_PASSED++ )) || true
    else
        echo "  FAIL: Should NOT alert for UUID"
        (( TESTS_FAILED++ )) || true
    fi
    (( TESTS_RUN++ )) || true
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
    echo "=========================================="
    echo "WoW Credential Detector Test Suite"
    echo "=========================================="
    echo ""

    # Initialize
    detect_init
    detect_reset_stats

    # Run all test groups
    test_github_tokens
    echo ""
    test_npm_tokens
    echo ""
    test_gitlab_tokens
    echo ""
    test_openai_keys
    echo ""
    test_anthropic_keys
    echo ""
    test_aws_keys
    echo ""
    test_slack_tokens
    echo ""
    test_google_keys
    echo ""
    test_stripe_keys
    echo ""
    test_twilio_keys
    echo ""
    test_sendgrid_keys
    echo ""
    test_mailgun_keys
    echo ""
    test_jwt_tokens
    echo ""
    test_pypi_tokens
    echo ""
    test_docker_tokens
    echo ""
    test_generic_api_keys
    echo ""
    test_generic_tokens
    echo ""
    test_generic_secrets
    echo ""
    test_generic_passwords
    echo ""
    test_bearer_tokens
    echo ""
    test_basic_auth
    echo ""
    test_connection_strings
    echo ""
    test_private_keys
    echo ""
    test_ssh_keys
    echo ""
    test_false_positives
    echo ""
    test_severity_detection
    echo ""
    test_alert_decision

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total tests:  $TESTS_RUN"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"
    echo ""

    # Print detection statistics
    echo "Detection Statistics:"
    detect_get_stats
    echo ""

    # Exit with proper code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "All tests passed!"
        exit 0
    else
        echo "Some tests failed!"
        exit 1
    fi
}

main "$@"
