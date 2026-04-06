#!/bin/zsh

TEST_FILE="/tmp/test_race_$$.txt"
echo "0" > "$TEST_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
export MC_LOG_FILE="/tmp/test_log_$$.txt"
export MC_COLOR_OUTPUT=false
source "$SCRIPT_DIR/lib/utils.sh"

# Simple test with just 5 processes, 2 writes each
for i in {1..5}; do
  (
    for j in {1..2}; do
      val=$(_read_progress_file "$TEST_FILE" 2>/dev/null || echo "0")
      [[ -z "$val" ]] && val=0
      new_val=$((val + 1))
      _write_progress_file "$TEST_FILE" "$new_val" 2>/dev/null || echo "P$i: write failed"
    done
  ) &
done

wait

result=$(cat "$TEST_FILE")
echo "Expected: 10, Got: $result"

rm -f "$TEST_FILE"* /tmp/test_log_$$.txt
