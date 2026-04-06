#!/bin/zsh
# Debug test

TEST_FILE="/tmp/test_debug_$$.txt"
echo "5" > "$TEST_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"

# Set required variables
export MC_LOG_FILE="/tmp/test_log_$$.txt"
export MC_COLOR_OUTPUT=false

source "$SCRIPT_DIR/lib/utils.sh"

# Test single read-write cycle
echo "Initial value: $(cat $TEST_FILE)"

val=$(_read_progress_file "$TEST_FILE")
echo "Read value: '$val'"
echo "Lock owner: '$MC_FILE_LOCK_OWNER'"

new_val=$((val + 1))
echo "New value: $new_val"

_write_progress_file "$TEST_FILE" "$new_val"
echo "After write, file contains: $(cat $TEST_FILE)"
echo "Lock owner after write: '$MC_FILE_LOCK_OWNER'"

rm -f "$TEST_FILE"* /tmp/test_log_$$.txt
