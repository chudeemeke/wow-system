#!/bin/bash
# WoW System - DI Container Integration Example
# Demonstrates how the orchestrator will use DI for handler creation
# Author: Chude <chude@emeke.org>

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source DI Container
source "${PROJECT_ROOT}/src/patterns/di-container.sh"

# ============================================================================
# Example: Mock Handlers and Dependencies
# ============================================================================

# Mock Storage Service (Singleton - shared across all handlers)
storage_service() {
    echo "StorageService[singleton]"
}

# Mock Logger Service (Singleton - shared logging instance)
logger_service() {
    echo "LoggerService[singleton]"
}

# Mock Configuration Service (Singleton - shared config)
config_service() {
    echo "ConfigService[singleton]"
}

# Mock Read Handler Factory (creates new handler instances with dependencies)
read_handler_factory() {
    local file_path="${1:-}"

    # Resolve dependencies from DI container
    local storage
    local logger
    storage=$(di_resolve "IStorageService")
    logger=$(di_resolve "ILoggerService")

    # Create handler instance with dependencies
    echo "ReadHandler{file='${file_path}', storage='${storage}', logger='${logger}'}"
}

# Mock Write Handler Factory
write_handler_factory() {
    local file_path="${1:-}"
    local content="${2:-}"

    # Resolve dependencies
    local storage
    local logger
    storage=$(di_resolve "IStorageService")
    logger=$(di_resolve "ILoggerService")

    echo "WriteHandler{file='${file_path}', content='${content}', storage='${storage}', logger='${logger}'}"
}

# Mock Grep Handler Factory
grep_handler_factory() {
    local pattern="${1:-}"

    # Resolve dependencies
    local config
    local logger
    config=$(di_resolve "IConfigService")
    logger=$(di_resolve "ILoggerService")

    echo "GrepHandler{pattern='${pattern}', config='${config}', logger='${logger}'}"
}

# Mock Session Manager (Transient - new instance each time)
session_manager() {
    local session_id="${RANDOM}"
    echo "SessionManager[transient-${session_id}]"
}

# ============================================================================
# Example: Orchestrator Integration
# ============================================================================

orchestrator_init_di() {
    echo "=== Orchestrator: Initializing DI Container ==="
    echo ""

    # Initialize DI Container
    di_init

    # Register core services as Singletons (shared instances)
    di_register_singleton "IStorageService" "storage_service"
    di_register_singleton "ILoggerService" "logger_service"
    di_register_singleton "IConfigService" "config_service"

    # Register handler factories (create new handlers with dependencies)
    di_register_factory "IReadHandler" "read_handler_factory"
    di_register_factory "IWriteHandler" "write_handler_factory"
    di_register_factory "IGrepHandler" "grep_handler_factory"

    # Register transient services (new instance each time)
    di_register_transient "ISessionManager" "session_manager"

    echo "✓ DI Container initialized with 7 services"
    echo ""
}

orchestrator_handle_tool_call() {
    local tool_name="$1"
    shift
    local params=("$@")

    echo "=== Orchestrator: Processing Tool Call ==="
    echo "Tool: ${tool_name}"
    echo "Params: ${params[*]}"
    echo ""

    # Resolve handler from DI container
    local handler
    case "${tool_name}" in
        "Read")
            handler=$(di_resolve "IReadHandler" "${params[@]}")
            echo "Handler Created: ${handler}"
            ;;
        "Write")
            handler=$(di_resolve "IWriteHandler" "${params[@]}")
            echo "Handler Created: ${handler}"
            ;;
        "Grep")
            handler=$(di_resolve "IGrepHandler" "${params[@]}")
            echo "Handler Created: ${handler}"
            ;;
        *)
            echo "ERROR: Unknown tool: ${tool_name}"
            return 1
            ;;
    esac

    echo ""
    return 0
}

demonstrate_singleton_sharing() {
    echo "=== Demonstrating Singleton Sharing ==="
    echo ""

    # Multiple handlers should share the same storage and logger instances
    echo "Creating multiple Read handlers..."
    local handler1
    local handler2
    handler1=$(di_resolve "IReadHandler" "/path/to/file1.txt")
    handler2=$(di_resolve "IReadHandler" "/path/to/file2.txt")

    echo "Handler 1: ${handler1}"
    echo "Handler 2: ${handler2}"
    echo ""
    echo "Note: Both handlers share the same StorageService and LoggerService instances"
    echo ""
}

demonstrate_transient_instances() {
    echo "=== Demonstrating Transient Instances ==="
    echo ""

    # Each session manager should be a new instance
    echo "Creating multiple SessionManager instances..."
    local session1
    local session2
    session1=$(di_resolve "ISessionManager")
    session2=$(di_resolve "ISessionManager")

    echo "Session 1: ${session1}"
    echo "Session 2: ${session2}"
    echo ""
    echo "Note: Each SessionManager is a different instance (different session IDs)"
    echo ""
}

demonstrate_di_benefits() {
    echo "=== Benefits of Dependency Injection ==="
    echo ""
    echo "1. Loose Coupling:"
    echo "   - Handlers don't know about concrete implementations"
    echo "   - Easy to swap implementations (e.g., FileStorage -> DatabaseStorage)"
    echo ""
    echo "2. Testability:"
    echo "   - Easy to mock dependencies in tests"
    echo "   - Example: di_register_singleton 'IStorageService' 'mock_storage'"
    echo ""
    echo "3. Lifecycle Management:"
    echo "   - Singleton: Shared instances (storage, config, logger)"
    echo "   - Factory: Create with parameters (handlers)"
    echo "   - Transient: New instance each time (sessions, requests)"
    echo ""
    echo "4. Centralized Configuration:"
    echo "   - All dependencies registered in one place"
    echo "   - Easy to understand system architecture"
    echo ""
    echo "5. Circular Dependency Detection:"
    echo "   - Container detects circular dependencies at runtime"
    echo "   - Prevents infinite loops"
    echo ""
}

show_container_stats() {
    echo "=== Container Statistics ==="
    echo ""
    di_stats
    echo ""
}

# ============================================================================
# Main Demonstration
# ============================================================================

main() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  WoW System - DI Container Integration Example                ║"
    echo "║  Demonstrates how orchestrator uses DI for handler creation    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Initialize DI
    orchestrator_init_di

    # Simulate handling tool calls
    orchestrator_handle_tool_call "Read" "/path/to/file.txt"
    orchestrator_handle_tool_call "Write" "/path/to/output.txt" "Hello, World!"
    orchestrator_handle_tool_call "Grep" "pattern.*search"

    # Demonstrate singleton behavior
    demonstrate_singleton_sharing

    # Demonstrate transient behavior
    demonstrate_transient_instances

    # Show benefits
    demonstrate_di_benefits

    # Show statistics
    show_container_stats

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Integration Example Complete                                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
}

# Run the demonstration
main
