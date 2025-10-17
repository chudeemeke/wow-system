#!/bin/bash
# WoW System - Credential Detection Integration Example
# Shows how to integrate credential detection into handlers
# Author: Chude <chude@emeke.org>

# ============================================================================
# Example 1: Integration with Bash Handler
# ============================================================================

# Add credential scanning to bash handler by modifying handle_bash function:

example_bash_handler_integration() {
    cat <<'EOF'
# In src/handlers/bash-handler.sh, add after line 21:

# Source credential scanner (optional - won't fail if not available)
if [[ -f "${_BASH_HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${_BASH_HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# In handle_bash function, add after command extraction (around line 217):

    # ========================================================================
    # SECURITY CHECK: Credential Detection
    # ========================================================================

    if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
        if scanner_scan_command "${command}"; then
            # Credential detected and user alerted
            wow_warn "SECURITY: Credential detected in bash command"

            # Log the event
            session_track_event "credential_detected" "bash:${command:0:50}" 2>/dev/null || true

            # Ask user if they want to proceed
            echo ""
            echo "Do you want to:"
            echo "  1. Redact and continue"
            echo "  2. Block this command"
            echo "  3. Continue anyway (NOT RECOMMENDED)"
            echo ""
            echo -n "Choice (1/2/3): "
            read -r choice

            case "$choice" in
                1)
                    # Redact the command
                    command=$(scanner_auto_redact "${command}")
                    wow_info "Command redacted, proceeding..."
                    ;;
                2)
                    # Block
                    wow_error "Command blocked by user"
                    return 2
                    ;;
                3)
                    # Continue anyway
                    wow_warn "User chose to proceed with credential in command"
                    ;;
                *)
                    # Default: block
                    wow_error "Invalid choice, blocking command"
                    return 2
                    ;;
            esac
        fi
    fi
EOF
}

# ============================================================================
# Example 2: Integration with Write Handler
# ============================================================================

example_write_handler_integration() {
    cat <<'EOF'
# In src/handlers/write-handler.sh:

# Source credential scanner
if [[ -f "${_WRITE_HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${_WRITE_HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# In handle_write function, before writing the file:

    # ========================================================================
    # SECURITY CHECK: Credential Detection in File Content
    # ========================================================================

    if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
        # Check if content contains credentials
        if scanner_has_credentials "${content}"; then
            wow_warn "SECURITY: Credentials detected in file content"

            # Show preview
            echo ""
            echo "File would contain credentials. Preview:"
            echo "----------------------------------------"
            echo "${content}" | head -20
            echo "----------------------------------------"
            echo ""

            echo "Do you want to:"
            echo "  1. Redact credentials and write"
            echo "  2. Cancel write operation"
            echo "  3. Write anyway (NOT RECOMMENDED)"
            echo ""
            echo -n "Choice (1/2/3): "
            read -r choice

            case "$choice" in
                1)
                    # Redact content
                    content=$(scanner_auto_redact "${content}")
                    wow_info "Credentials redacted, writing file..."
                    ;;
                2)
                    # Cancel
                    wow_error "Write operation cancelled by user"
                    return 2
                    ;;
                3)
                    # Write anyway
                    wow_warn "User chose to write file with credentials"
                    ;;
                *)
                    # Default: cancel
                    wow_error "Invalid choice, cancelling write"
                    return 2
                    ;;
            esac
        fi
    fi
EOF
}

# ============================================================================
# Example 3: Integration with Edit Handler
# ============================================================================

example_edit_handler_integration() {
    cat <<'EOF'
# In src/handlers/edit-handler.sh:

# Source credential scanner
if [[ -f "${_EDIT_HANDLER_DIR}/../security/credential-scanner.sh" ]]; then
    source "${_EDIT_HANDLER_DIR}/../security/credential-scanner.sh"
    _CREDENTIAL_SCAN_ENABLED=true
else
    _CREDENTIAL_SCAN_ENABLED=false
fi

# In handle_edit function, after getting new_string:

    # ========================================================================
    # SECURITY CHECK: Credential Detection in Edit
    # ========================================================================

    if [[ "${_CREDENTIAL_SCAN_ENABLED}" == "true" ]]; then
        # Check if new content contains credentials
        if scanner_has_credentials "${new_string}"; then
            wow_warn "SECURITY: Credentials detected in edit content"

            # Show what would be added
            echo ""
            echo "Edit would introduce credentials:"
            echo "New content: ${new_string:0:100}..."
            echo ""

            echo "Do you want to:"
            echo "  1. Redact credentials in edit"
            echo "  2. Cancel edit operation"
            echo "  3. Apply edit anyway (NOT RECOMMENDED)"
            echo ""
            echo -n "Choice (1/2/3): "
            read -r choice

            case "$choice" in
                1)
                    # Redact
                    new_string=$(scanner_auto_redact "${new_string}")
                    wow_info "Edit content redacted..."
                    ;;
                2)
                    # Cancel
                    wow_error "Edit operation cancelled by user"
                    return 2
                    ;;
                3)
                    # Apply anyway
                    wow_warn "User chose to apply edit with credentials"
                    ;;
                *)
                    # Default: cancel
                    wow_error "Invalid choice, cancelling edit"
                    return 2
                    ;;
            esac
        fi
    fi
EOF
}

# ============================================================================
# Example 4: Standalone Scanning Scripts
# ============================================================================

example_scan_project() {
    cat <<'EOF'
#!/bin/bash
# Scan entire project for credentials

source "$(dirname "$0")/../src/security/credential-scanner.sh"

echo "Scanning project for credentials..."

# Find all source files
find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" \) | while read -r file; do
    if scanner_has_credentials "$(<"$file")"; then
        scanner_scan_file "$file"
    fi
done

echo ""
echo "Scan complete!"
scanner_get_stats
EOF
}

example_scan_conversation() {
    cat <<'EOF'
#!/bin/bash
# Scan conversation history for credentials

source "$(dirname "$0")/../src/security/credential-scanner.sh"

echo "Scanning conversation history..."
scanner_scan_conversation "$HOME/.claude/history.jsonl"

echo ""
echo "To redact detected credentials:"
echo "  redact_with_backup \"\$HOME/.claude/history.jsonl\""
EOF
}

# ============================================================================
# Example 5: Pre-commit Hook Integration
# ============================================================================

example_precommit_hook() {
    cat <<'EOF'
#!/bin/bash
# .git/hooks/pre-commit
# Scan staged files for credentials before commit

source "$(git rev-parse --show-toplevel)/src/security/credential-scanner.sh"

echo "Scanning staged files for credentials..."

# Get staged files
git diff --cached --name-only --diff-filter=ACM | while read -r file; do
    if [[ -f "$file" ]]; then
        # Get staged content
        content=$(git show ":$file")

        if scanner_has_credentials "$content"; then
            echo ""
            echo "ERROR: Credentials detected in staged file: $file"
            echo ""
            echo "Please remove credentials before committing."
            echo "Use: redact_with_backup \"$file\""
            exit 1
        fi
    fi
done

echo "No credentials detected. Safe to commit."
exit 0
EOF
}

# ============================================================================
# Example 6: CI/CD Integration
# ============================================================================

example_ci_integration() {
    cat <<'EOF'
# .github/workflows/credential-scan.yml

name: Credential Scan

on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Scan for credentials
        run: |
          bash ./src/security/credential-scanner.sh

          # Scan all files in PR
          for file in $(git diff --name-only origin/main...HEAD); do
            if [[ -f "$file" ]]; then
              if bash -c "source ./src/security/credential-scanner.sh && scanner_has_credentials \"\$(<\"$file\")\""; then
                echo "ERROR: Credentials detected in $file"
                exit 1
              fi
            fi
          done

          echo "No credentials detected!"
EOF
}

# ============================================================================
# Example 7: Interactive Scanning
# ============================================================================

example_interactive_scan() {
    cat <<'EOF'
#!/bin/bash
# Interactive credential scanner

source "$(dirname "$0")/../src/security/credential-scanner.sh"

while true; do
    echo ""
    echo "========================================"
    echo "WoW Credential Scanner"
    echo "========================================"
    echo "1. Scan file"
    echo "2. Scan directory (recursive)"
    echo "3. Scan conversation history"
    echo "4. Test string"
    echo "5. View statistics"
    echo "6. View alert log"
    echo "7. Exit"
    echo ""
    echo -n "Choice: "
    read -r choice

    case "$choice" in
        1)
            echo -n "File path: "
            read -r filepath
            scanner_scan_file "$filepath"
            ;;
        2)
            echo -n "Directory path: "
            read -r dirpath
            find "$dirpath" -type f | while read -r file; do
                if scanner_has_credentials "$(<"$file")"; then
                    scanner_scan_file "$file"
                fi
            done
            ;;
        3)
            scanner_scan_conversation
            ;;
        4)
            echo -n "Enter text to test: "
            read -r text
            if scanner_has_credentials "$text"; then
                scanner_scan_string "$text" "interactive_test"
            else
                echo "No credentials detected."
            fi
            ;;
        5)
            scanner_get_stats
            ;;
        6)
            scanner_view_alerts
            ;;
        7)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
done
EOF
}

# ============================================================================
# Main - Show All Examples
# ============================================================================

main() {
    echo "=========================================="
    echo "WoW Credential Detection Integration"
    echo "=========================================="
    echo ""

    echo "Example 1: Bash Handler Integration"
    echo "======================================"
    example_bash_handler_integration
    echo ""
    echo ""

    echo "Example 2: Write Handler Integration"
    echo "======================================"
    example_write_handler_integration
    echo ""
    echo ""

    echo "Example 3: Edit Handler Integration"
    echo "======================================"
    example_edit_handler_integration
    echo ""
    echo ""

    echo "Example 4: Project Scanner"
    echo "======================================"
    example_scan_project
    echo ""
    echo ""

    echo "Example 5: Conversation Scanner"
    echo "======================================"
    example_scan_conversation
    echo ""
    echo ""

    echo "Example 6: Pre-commit Hook"
    echo "======================================"
    example_precommit_hook
    echo ""
    echo ""

    echo "Example 7: CI/CD Integration"
    echo "======================================"
    example_ci_integration
    echo ""
    echo ""

    echo "Example 8: Interactive Scanner"
    echo "======================================"
    example_interactive_scan
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
