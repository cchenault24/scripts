#!/bin/zsh
# Test if our locking actually prevents concurrent access

TEST_DIR="/tmp/lock-test-$$"
TEST_FILE="$TEST_DIR/file.txt"
LOCK_DIR="$TEST_FILE.lock"

mkdir -p "$TEST_DIR"
echo "0" > "$TEST_FILE"

# Source the functions
SCRIPT_DIR="/Users/chenaultcp/Documents/scripts/mac-cleanup"
source "$SCRIPT_DIR/lib/utils.sh"

# Test function that should increment atomically
test_increment() {
  local id=$1
  local val=$(_read_progress_file "$TEST_FILE" 2>/dev/null || echo "0")
  [[ -z "$val" ]] && val=0
  
  # Add delay to increase race window
  sleep 0.01
  
  local new_val=$((val + 1))
  _write_progress_file "$TEST_FILE" "$new_val" 2>/dev/null || echo "Write failed for process $id"
}

# Run 10 concurrent increments
for i in {1..10}; do
  test_increment $i &
done

wait

result=$(cat "$TEST_FILE")
echo "Expected: 10, Got: $result"

rm -rf "$TEST_DIR"
