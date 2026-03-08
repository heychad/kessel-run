#!/usr/bin/env bats
# Tests for format_duration helper

load test_helpers

setup() {
    setup_temp_project
    source_loop_functions
}

teardown() {
    teardown_temp_project
}

@test "format_duration: seconds only" {
    result=$(format_duration 45)
    [ "$result" = "45s" ]
}

@test "format_duration: zero seconds" {
    result=$(format_duration 0)
    [ "$result" = "0s" ]
}

@test "format_duration: exactly 60 seconds → minutes" {
    result=$(format_duration 60)
    [ "$result" = "1m 0s" ]
}

@test "format_duration: minutes and seconds" {
    result=$(format_duration 125)
    [ "$result" = "2m 5s" ]
}

@test "format_duration: exactly 1 hour" {
    result=$(format_duration 3600)
    [ "$result" = "1h 0m" ]
}

@test "format_duration: hours and minutes" {
    result=$(format_duration 3725)
    [ "$result" = "1h 2m" ]
}

@test "format_duration: large value" {
    result=$(format_duration 7380)
    [ "$result" = "2h 3m" ]
}

@test "format_duration: 59 seconds stays in seconds" {
    result=$(format_duration 59)
    [ "$result" = "59s" ]
}

@test "format_duration: 3599 seconds stays in minutes" {
    result=$(format_duration 3599)
    [ "$result" = "59m 59s" ]
}
