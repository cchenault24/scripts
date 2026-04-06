#!/bin/zsh
#
# Test script to verify race condition fixes (SEC-4)
# This script spawns 50 parallel processes that attempt to acquire locks
# and verifies no race conditions occur
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/mac-cleanup-race-test-$$"
TEST_FILE="$TEST_DIR/test_file.txt"
NUM_PROCESSES=50
WRITES_PER_PROCESS=10

echo "========================================="
echo "SEC-4: Race Condition Test"
echo "========================================="
echo ""

# Create test directory
mkdir -p "$TEST_DIR" || {
  echo "${RED}ERROR: Failed to create test directory${NC}"
  exit 1
}

# Cleanup function
cleanup() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Source the utils.sh to get the locking functions
SCRIPT_DIR=$(dirname "$0")
source "$SCRIPT_DIR/lib/utils.sh" 2>/dev/null || {
  echo "${RED}ERROR: Failed to source lib/utils.sh${NC}"
  exit 1
}

# Initialize test file
echo "0" > "$TEST_FILE"

echo "Test 1: Testing _write_progress_file with $NUM_PROCESSES parallel writers..."
echo "  Each process will write $WRITES_PER_PROCESS times"
echo ""

# Test 1: Parallel writes using _write_progress_file
test_write_progress() {
  local process_id=$1
  local test_file=$2
  local num_writes=$3

  for i in $(seq 1 $num_writes); do
    # Read current value
    local current_value=$(_read_progress_file "$test_file" 2>/dev/null || echo "0")
    if [[ -z "$current_value" ]]; then
      current_value=0
    fi

    # Increment and write back
    local new_value=$((current_value + 1))
    _write_progress_file "$test_file" "$new_value" 2>/dev/null || true

    # Small random delay to increase chance of race condition
    sleep 0.00$((RANDOM % 5))
  done
}

# Spawn parallel processes
pids=()
for i in $(seq 1 $NUM_PROCESSES); do
  test_write_progress $i "$TEST_FILE" $WRITES_PER_PROCESS &
  pids+=($!)
done

# Wait for all processes to complete
echo -n "  Waiting for processes to complete... "
for pid in "${pids[@]}"; do
  wait $pid 2>/dev/null || true
done
echo "done"

# Verify result
expected_value=$((NUM_PROCESSES * WRITES_PER_PROCESS))
actual_value=$(cat "$TEST_FILE" 2>/dev/null || echo "0")

echo ""
echo "Results:"
echo "  Expected final value: $expected_value"
echo "  Actual final value:   $actual_value"
echo ""

if [[ "$actual_value" -eq "$expected_value" ]]; then
  echo "${GREEN}✓ Test 1 PASSED: No race condition detected${NC}"
  test1_passed=true
else
  echo "${RED}✗ Test 1 FAILED: Race condition detected!${NC}"
  echo "  Lost updates: $((expected_value - actual_value))"
  test1_passed=false
fi

echo ""
echo "========================================="
echo ""

# Test 2: Test mkdir-based locking directly
echo "Test 2: Testing atomic mkdir locking with $NUM_PROCESSES parallel processes..."
echo ""

# Reset test file
echo "0" > "$TEST_FILE"
rm -rf "$TEST_FILE".lock* 2>/dev/null || true

# Test function using mkdir directly
test_mkdir_lock() {
  local process_id=$1
  local test_file=$2
  local num_writes=$3
  local lock_dir="${test_file}.lock.d"

  for i in $(seq 1 $num_writes); do
    local attempts=0
    local max_attempts=100

    # Try to acquire lock with mkdir
    while [[ $attempts -lt $max_attempts ]]; do
      if mkdir "$lock_dir" 2>/dev/null; then
        # Got lock - read, increment, write
        local current_value=$(cat "$test_file" 2>/dev/null || echo "0")
        if [[ -z "$current_value" ]]; then
          current_value=0
        fi
        local new_value=$((current_value + 1))
        echo "$new_value" > "$test_file"

        # Release lock
        rmdir "$lock_dir" 2>/dev/null || true
        break
      fi

      # Wait and retry
      sleep 0.001
      attempts=$((attempts + 1))
    done

    # Small random delay
    sleep 0.00$((RANDOM % 5))
  done
}

# Spawn parallel processes
pids=()
for i in $(seq 1 $NUM_PROCESSES); do
  test_mkdir_lock $i "$TEST_FILE" $WRITES_PER_PROCESS &
  pids+=($!)
done

# Wait for all processes
echo -n "  Waiting for processes to complete... "
for pid in "${pids[@]}"; do
  wait $pid 2>/dev/null || true
done
echo "done"

# Verify result
actual_value=$(cat "$TEST_FILE" 2>/dev/null || echo "0")

echo ""
echo "Results:"
echo "  Expected final value: $expected_value"
echo "  Actual final value:   $actual_value"
echo ""

if [[ "$actual_value" -eq "$expected_value" ]]; then
  echo "${GREEN}✓ Test 2 PASSED: mkdir-based locking works correctly${NC}"
  test2_passed=true
else
  echo "${RED}✗ Test 2 FAILED: mkdir-based locking has race condition!${NC}"
  echo "  Lost updates: $((expected_value - actual_value))"
  test2_passed=false
fi

echo ""
echo "========================================="
echo ""

# Test 3: Test lockf if available
if command -v lockf &>/dev/null; then
  echo "Test 3: Testing lockf-based locking with $NUM_PROCESSES parallel processes..."
  echo ""

  # Reset test file
  echo "0" > "$TEST_FILE"
  rm -rf "$TEST_FILE".lock* 2>/dev/null || true

  # Test function using lockf
  test_lockf_lock() {
    local process_id=$1
    local test_file=$2
    local num_writes=$3
    local lock_file="${test_file}.lock"

    # Create lock file if it doesn't exist
    touch "$lock_file" 2>/dev/null || return 1

    for i in $(seq 1 $num_writes); do
      # Use lockf to do atomic read-modify-write
      lockf -t 5 -k "$lock_file" sh -c "
        current_value=\$(cat '$test_file' 2>/dev/null || echo '0')
        if [[ -z \"\$current_value\" ]]; then
          current_value=0
        fi
        new_value=\$((current_value + 1))
        echo \"\$new_value\" > '$test_file'
      " 2>/dev/null || true

      # Small random delay
      sleep 0.00$((RANDOM % 5))
    done
  }

  # Spawn parallel processes
  pids=()
  for i in $(seq 1 $NUM_PROCESSES); do
    test_lockf_lock $i "$TEST_FILE" $WRITES_PER_PROCESS &
    pids+=($!)
  done

  # Wait for all processes
  echo -n "  Waiting for processes to complete... "
  for pid in "${pids[@]}"; do
    wait $pid 2>/dev/null || true
  done
  echo "done"

  # Verify result
  actual_value=$(cat "$TEST_FILE" 2>/dev/null || echo "0")

  echo ""
  echo "Results:"
  echo "  Expected final value: $expected_value"
  echo "  Actual final value:   $actual_value"
  echo ""

  if [[ "$actual_value" -eq "$expected_value" ]]; then
    echo "${GREEN}✓ Test 3 PASSED: lockf-based locking works correctly${NC}"
    test3_passed=true
  else
    echo "${RED}✗ Test 3 FAILED: lockf-based locking has race condition!${NC}"
    echo "  Lost updates: $((expected_value - actual_value))"
    test3_passed=false
  fi
else
  echo "Test 3: Skipped (lockf not available)"
  test3_passed=true
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""

all_passed=true
if $test1_passed; then
  echo "${GREEN}✓ _write_progress_file race condition test PASSED${NC}"
else
  echo "${RED}✗ _write_progress_file race condition test FAILED${NC}"
  all_passed=false
fi

if $test2_passed; then
  echo "${GREEN}✓ mkdir-based locking test PASSED${NC}"
else
  echo "${RED}✗ mkdir-based locking test FAILED${NC}"
  all_passed=false
fi

if $test3_passed; then
  echo "${GREEN}✓ lockf-based locking test PASSED${NC}"
else
  echo "${RED}✗ lockf-based locking test FAILED${NC}"
  all_passed=false
fi

echo ""
if $all_passed; then
  echo "${GREEN}All tests PASSED! No race conditions detected.${NC}"
  exit 0
else
  echo "${RED}Some tests FAILED! Race conditions detected.${NC}"
  exit 1
fi
