#!/bin/bash
# event-bus.sh - Observer pattern for event-driven architecture
# Author: Chude <chude@emeke.org>
#
# Design Pattern: Observer (Publish-Subscribe)
# Purpose: Decouple components via events

# Double-sourcing protection
[[ -n "${WOW_EVENT_BUS_LOADED:-}" ]] && return 0
readonly WOW_EVENT_BUS_LOADED=1

# Event subscribers: event_name => "callback1 callback2 ..."
declare -gA _EVENT_BUS_SUBSCRIBERS
_EVENT_BUS_INITIALIZED=false

# Initialize event bus
event_bus_init() {
    [[ "${_EVENT_BUS_INITIALIZED}" == "true" ]] && return 0

    if ! declare -p _EVENT_BUS_SUBSCRIBERS &>/dev/null; then
        declare -gA _EVENT_BUS_SUBSCRIBERS
    fi

    _EVENT_BUS_INITIALIZED=true
    return 0
}

# Subscribe to event
event_bus_subscribe() {
    local event_name="$1"
    local callback="$2"

    [[ -z "$event_name" ]] && return 1
    [[ -z "$callback" ]] && return 1

    local current="${_EVENT_BUS_SUBSCRIBERS[$event_name]:-}"
    if [[ -z "$current" ]]; then
        _EVENT_BUS_SUBSCRIBERS["$event_name"]="$callback"
    else
        _EVENT_BUS_SUBSCRIBERS["$event_name"]="$current $callback"
    fi

    return 0
}

# Unsubscribe from event
event_bus_unsubscribe() {
    local event_name="$1"
    local callback="$2"

    [[ -z "${_EVENT_BUS_SUBSCRIBERS[$event_name]:-}" ]] && return 0

    local current="${_EVENT_BUS_SUBSCRIBERS[$event_name]}"
    local new_list=""

    for cb in $current; do
        if [[ "$cb" != "$callback" ]]; then
            new_list="$new_list $cb"
        fi
    done

    _EVENT_BUS_SUBSCRIBERS["$event_name"]="${new_list# }"
    return 0
}

# Publish event
event_bus_publish() {
    local event_name="$1"
    shift
    local event_data="$@"

    [[ -z "${_EVENT_BUS_SUBSCRIBERS[$event_name]:-}" ]] && return 0

    local callbacks="${_EVENT_BUS_SUBSCRIBERS[$event_name]}"

    for callback in $callbacks; do
        if type "$callback" &>/dev/null; then
            "$callback" "$event_data" 2>/dev/null || true
        fi
    done

    return 0
}

# Clear subscribers for event
event_bus_clear() {
    local event_name="$1"
    unset "_EVENT_BUS_SUBSCRIBERS[$event_name]"
    return 0
}

# Clear all subscribers
event_bus_clear_all() {
    for event_name in "${!_EVENT_BUS_SUBSCRIBERS[@]}"; do
        unset "_EVENT_BUS_SUBSCRIBERS[$event_name]"
    done
    return 0
}

# List all events
event_bus_list_events() {
    for event_name in "${!_EVENT_BUS_SUBSCRIBERS[@]}"; do
        local count=$(echo "${_EVENT_BUS_SUBSCRIBERS[$event_name]}" | wc -w)
        echo "$event_name ($count subscribers)"
    done | sort
}

