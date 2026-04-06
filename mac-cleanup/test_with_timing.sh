#!/bin/zsh

TEST_FILE="/tmp/test_timing_$$.txt"
LOG_FILE="/tmp/test_timing_$$.log"
echo "0" > "$TEST_FILE"
> "$LOG_FILE"

SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
export MC_LOG_FILE="/tmp/mc_log_$$.txt"
export MC_COLOR_OUTPUT=false
source "$SCRIPT_DIR/lib/utils.sh"

test_process() {
  local pid=$1
  local start=$(date +%s.%N)
  
  for i in {1..2}; do
    local read_start=$(date +%s.%N)
    val=$(_read_progress_file "$TEST_FILE" 2>/dev/null || echo "0")
    local read_end=$(date +%s.%N)
    
    [[ -z "$val" ]] && val=0
    new_val=$((val + 1))
    
    local write_start=$(date +%s.%N)
    _write_progress_file "$TEST_FILE" "$new_val" 2>/dev/null || echo "P$pid: write failed" >> "$LOG_FILE"
    local write_end=$(date +%s.%N)
    
    local read_time=$(echo "$read_end - $read_start" | bc)
    local write_time=$(echo "$write_end - $write_start" | bc)
    echo "P$pid iter$i: read=${read_time}s write=${write_time}s" >> "$LOG_FILE"
  done
}

# Test with 10 processes
for i in {1..10}; do
  test_process $i &
done

wait

result=$(cat "$TEST_FILE")
echo "Expected: 20, Got: $result"
echo "Log:"
cat "$LOG_FILE"

rm -f "$TEST_FILE"* "$LOG_FILE" /tmp/mc_log_$$.txt
