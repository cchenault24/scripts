#!/bin/zsh

TEST_FILE="/tmp/test_errors_$$.txt"
echo "0" > "$TEST_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
export MC_LOG_FILE="/tmp/mc_log_$$.txt"
export MC_COLOR_OUTPUT=false
source "$SCRIPT_DIR/lib/utils.sh"

# Test with just 3 processes, 2 writes each
for i in {1..3}; do
  (
    for j in {1..2}; do
      val=$(_read_progress_file "$TEST_FILE" 2>&1)
      rc_read=$?
      [[ -z "$val" ]] && val=0
      new_val=$((val + 1))
      
      if ! _write_progress_file "$TEST_FILE" "$new_val" 2>&1; then
        echo "P$i iter$j: write failed with rc=$?"
      fi
    done
  ) 2>&1 | sed "s/^/P$i: /"
done | sort

wait

result=$(cat "$TEST_FILE")
echo "Expected: 6, Got: $result"

rm -f "$TEST_FILE"* /tmp/mc_log_$$.txt
