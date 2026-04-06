#!/bin/zsh

TEST_FILE="/tmp/test_owner_$$.txt"
echo "5" > "$TEST_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
export MC_LOG_FILE="/tmp/test_log_$$.txt"
export MC_COLOR_OUTPUT=false
source "$SCRIPT_DIR/lib/utils.sh"

echo "My PID: $$"

# Do a read
val=$(_read_progress_file "$TEST_FILE")
echo "Read value: $val"

# Check lock ownership
lock_dir="$TEST_FILE.lock"
if [[ -d "$lock_dir" ]]; then
  echo "Lock directory exists"
  owner_file="$lock_dir/owner"
  if [[ -f "$owner_file" ]]; then
    owner=$(cat "$owner_file")
    echo "Lock owner file contains: $owner"
  else
    echo "Lock owner file doesn't exist"
  fi
else
  echo "Lock directory doesn't exist"
fi

# Now try to write
_write_progress_file "$TEST_FILE" "6"

# Check if lock was released
if [[ -d "$lock_dir" ]]; then
  echo "ERROR: Lock still exists after write"
else
  echo "Lock successfully released"
fi

rm -f "$TEST_FILE"* /tmp/test_log_$$.txt
