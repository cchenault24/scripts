#!/bin/zsh

TEST_FILE="/tmp/test_locks_$$.txt"
echo "0" > "$TEST_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
export MC_LOG_FILE="/tmp/mc_log_$$.txt"
export MC_COLOR_OUTPUT=false
source "$SCRIPT_DIR/lib/utils.sh"

# Test with 5 processes
for i in {1..5}; do
  (
    for j in {1..1}; do
      val=$(_read_progress_file "$TEST_FILE")
      [[ -z "$val" ]] && val=0
      new_val=$((val + 1))
      _write_progress_file "$TEST_FILE" "$new_val"
    done
  ) &
done

wait

result=$(cat "$TEST_FILE")
echo "Expected: 5, Got: $result"

# Check if lock dir still exists
if [[ -d "$TEST_FILE.lock" ]]; then
  echo "WARNING: Lock directory still exists!"
  ls -la "$TEST_FILE.lock/"
else
  echo "Lock directory properly cleaned up"
fi

rm -rf "$TEST_FILE"* /tmp/mc_log_$$.txt
