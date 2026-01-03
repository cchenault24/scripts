# macOS Cleanup Utility - Manual Test Plan

## Overview

This document provides a comprehensive manual testing plan for the macOS Cleanup Utility. All tests should be performed before any production release.

## Prerequisites

- macOS 10.15 or later
- Terminal access
- Test user account (recommended: use a non-production account)
- Backup of important data (always test in safe environment)

## Test Environment Setup

1. Create a test backup directory: `mkdir -p ~/test-mac-cleanup-backups`
2. Set environment variable: `export MC_BACKUP_DIR=~/test-mac-cleanup-backups`
3. Ensure script is executable: `chmod +x mac-cleanup.sh`

---

## Section 1: Basic Operations

### Test 1.1: Help Display
**Objective:** Verify help text displays correctly

**Steps:**
1. Run: `./mac-cleanup.sh --help`
2. Run: `./mac-cleanup.sh -h`

**Expected Results:**
- Help text displays with all available options
- No errors or warnings
- All command-line options are documented

**Status:** [ ] PASS [ ] FAIL

---

### Test 1.2: Dry-Run Mode
**Objective:** Verify dry-run shows operations without executing them

**Steps:**
1. Run: `./mac-cleanup.sh --dry-run`
2. Select a category (e.g., "browsers")
3. Review the output

**Expected Results:**
- Script shows what would be cleaned
- No actual files are deleted
- No backup is created
- Size calculations are shown
- Clear indication that this is a dry-run

**Status:** [ ] PASS [ ] FAIL

---

### Test 1.3: Interactive Cleanup
**Objective:** Verify interactive mode works correctly

**Steps:**
1. Run: `./mac-cleanup.sh`
2. Select one category using fzf
3. Confirm the cleanup
4. Observe the progress

**Expected Results:**
- fzf interface appears for category selection
- Selected category is highlighted
- Confirmation prompt appears
- Cleanup executes with progress updates
- Backup is created before deletion
- Space saved is reported

**Status:** [ ] PASS [ ] FAIL

---

### Test 1.4: Undo Functionality
**Objective:** Verify backup restore works

**Steps:**
1. Run a cleanup operation (Test 1.3)
2. Note the backup directory created
3. Run: `./mac-cleanup.sh --undo`
4. Select the backup to restore
5. Confirm restoration

**Expected Results:**
- List of backups is displayed
- Backup selection works
- Files are restored to original locations
- Restored files are accessible
- Manifest is validated before restore

**Status:** [ ] PASS [ ] FAIL

---

### Test 1.5: Schedule Feature
**Objective:** Verify LaunchAgent creation

**Steps:**
1. Run: `./mac-cleanup.sh --schedule`
2. Follow the prompts
3. Check: `ls ~/Library/LaunchAgents/ | grep mac-cleanup`

**Expected Results:**
- LaunchAgent plist file is created
- File is in correct location
- File has correct permissions
- Schedule options are clear

**Status:** [ ] PASS [ ] FAIL

---

## Section 2: Safety Tests

### Test 2.1: Interrupt Handling (CTRL-C)
**Objective:** Verify script handles interrupts gracefully

**Steps:**
1. Run: `./mac-cleanup.sh`
2. Select a category
3. During cleanup, press CTRL-C
4. Check backup directory

**Expected Results:**
- Script exits cleanly
- No corrupted files
- Partial backup is preserved (if any)
- Progress file is cleaned up
- No orphaned lock files

**Status:** [ ] PASS [ ] FAIL

---

### Test 2.2: No Disk Space Scenario
**Objective:** Verify graceful failure when disk is full

**Steps:**
1. Fill disk to near capacity (use `dd` or similar)
2. Run: `./mac-cleanup.sh`
3. Attempt cleanup

**Expected Results:**
- Script detects insufficient space
- Clear error message displayed
- No partial/corrupted backups created
- Script exits with non-zero code
- Helpful guidance provided

**Status:** [ ] PASS [ ] FAIL

---

### Test 2.3: Concurrent Execution (File Locking)
**Objective:** Verify file locking prevents conflicts

**Steps:**
1. Run: `./mac-cleanup.sh` in terminal 1
2. Immediately run: `./mac-cleanup.sh` in terminal 2
3. Observe both processes

**Expected Results:**
- Second instance detects lock
- Clear message about another instance running
- First instance completes normally
- No file corruption
- Both instances exit cleanly

**Status:** [ ] PASS [ ] FAIL

---

### Test 2.4: Missing Backup Directory Recovery
**Objective:** Verify script recreates deleted backup directory

**Steps:**
1. Run a cleanup (creates backup dir)
2. Delete backup directory: `rm -rf ~/.mac-cleanup-backups`
3. Run cleanup again

**Expected Results:**
- Script detects missing directory
- Creates new backup directory
- Continues normally
- No errors about missing directory

**Status:** [ ] PASS [ ] FAIL

---

## Section 3: Edge Cases

### Test 3.1: Empty Cache Directories
**Objective:** Verify script handles empty directories gracefully

**Steps:**
1. Ensure a cache directory is empty (e.g., `~/Library/Caches/SomeApp`)
2. Run cleanup for that category
3. Observe output

**Expected Results:**
- Script detects empty directory
- Skips with informative message
- No errors or warnings
- Continues to next operation

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.2: Missing Browsers/Tools
**Objective:** Verify script skips missing dependencies

**Steps:**
1. Ensure a browser is not installed (e.g., Chrome)
2. Run cleanup for browsers category
3. Observe output

**Expected Results:**
- Script detects missing browser
- Skips with clear message
- No errors
- Continues with available browsers

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.3: Corrupted Manifest
**Objective:** Verify script handles corrupted backup manifests

**Steps:**
1. Create a backup (Test 1.3)
2. Manually corrupt manifest: `echo "invalid json" > ~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/manifest.json`
3. Attempt restore: `./mac-cleanup.sh --undo`

**Expected Results:**
- Script detects corrupted manifest
- Clear error message
- Option to skip or attempt recovery
- No script crash

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.4: Symlink Safety
**Objective:** Verify symlinks are not followed destructively

**Steps:**
1. Create test symlink: `ln -s /tmp/test-symlink ~/Library/Caches/test-symlink`
2. Run cleanup
3. Verify `/tmp/test-symlink` still exists

**Expected Results:**
- Symlink is removed (if in cleanup path)
- Target of symlink is NOT deleted
- No errors about following symlinks

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.5: Files in Use
**Objective:** Verify script handles locked files gracefully

**Steps:**
1. Open a file in an application
2. Run cleanup that would target that file's directory
3. Observe behavior

**Expected Results:**
- Script attempts cleanup
- Locked files are skipped
- Warning message for skipped files
- Other files are cleaned successfully

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.6: Permissions Denied
**Objective:** Verify script handles permission errors

**Steps:**
1. Create a directory with restricted permissions: `chmod 000 ~/test-restricted`
2. Attempt cleanup that targets this directory
3. Observe behavior

**Expected Results:**
- Script detects permission issue
- Skips with clear message
- No script crash
- Continues with other operations

**Status:** [ ] PASS [ ] FAIL

---

### Test 3.7: Missing Dependencies (fzf, brew, etc.)
**Objective:** Verify script handles missing optional tools

**Steps:**
1. Temporarily rename fzf: `mv /usr/local/bin/fzf /usr/local/bin/fzf.bak`
2. Run: `./mac-cleanup.sh`
3. Observe behavior

**Expected Results:**
- Script detects missing fzf
- Offers to install or provides alternative
- Clear instructions provided
- Script doesn't crash

**Status:** [ ] PASS [ ] FAIL

---

## Section 4: Plugin-Specific Tests

### Test 4.1: Browser Plugins
**Test each browser plugin individually:**

- [ ] Chrome Cache cleanup
- [ ] Firefox Cache cleanup
- [ ] Safari Cache cleanup
- [ ] Edge Cache cleanup

**For each:**
1. Verify cache directory exists
2. Run cleanup for that browser only
3. Verify files are backed up
4. Verify files are deleted
5. Verify space calculation is accurate

**Status:** [ ] PASS [ ] FAIL

---

### Test 4.2: Package Manager Plugins
**Test each package manager:**

- [ ] npm Cache
- [ ] Homebrew Cache
- [ ] pip Cache
- [ ] Gradle Cache
- [ ] Maven Cache

**For each:**
1. Verify tool is installed
2. Run cleanup
3. Verify backup created
4. Verify cache cleared
5. Verify tool still works after cleanup

**Status:** [ ] PASS [ ] FAIL

---

### Test 4.3: Development Plugins
**Test each development tool:**

- [ ] Docker Cache
- [ ] Xcode Data
- [ ] Node Modules
- [ ] Developer Tool Temp Files

**For each:**
1. Verify tool/data exists
2. Run cleanup
3. Verify backup
4. Verify cleanup
5. Verify tool functionality after cleanup

**Status:** [ ] PASS [ ] FAIL

---

### Test 4.4: System Plugins
**Test each system plugin:**

- [ ] System Cache (requires admin)
- [ ] User Cache
- [ ] Application Logs
- [ ] System Logs (requires admin)
- [ ] Temporary Files
- [ ] Container Caches
- [ ] Saved Application States

**For each:**
1. Verify data exists
2. Run cleanup (with sudo if needed)
3. Verify backup
4. Verify cleanup
5. Verify system stability

**Status:** [ ] PASS [ ] FAIL

---

### Test 4.5: Maintenance Plugins
**Test each maintenance plugin:**

- [ ] Empty Trash
- [ ] Flush DNS Cache (requires admin)
- [ ] Corrupted Preference Lockfiles

**For each:**
1. Verify data exists
2. Run cleanup
3. Verify backup (if applicable)
4. Verify cleanup
5. Verify functionality

**Status:** [ ] PASS [ ] FAIL

---

## Section 5: Platform Compatibility

### Test 5.1: macOS Version Compatibility
**Test on different macOS versions:**

- [ ] macOS 10.15 (Catalina)
- [ ] macOS 11 (Big Sur)
- [ ] macOS 12 (Monterey)
- [ ] macOS 13 (Ventura)
- [ ] macOS 14 (Sonoma)
- [ ] macOS 15 (Sequoia) - if available

**For each version:**
1. Run basic cleanup
2. Verify all plugins work
3. Verify no version-specific errors

**Status:** [ ] PASS [ ] FAIL

---

### Test 5.2: Architecture Compatibility
**Test on different architectures:**

- [ ] Intel (x86_64)
- [ ] Apple Silicon (arm64)

**For each:**
1. Run full cleanup
2. Verify all operations work
3. Verify performance is acceptable

**Status:** [ ] PASS [ ] FAIL

---

## Section 6: Error Handling

### Test 6.1: Invalid Command-Line Arguments
**Objective:** Verify script handles invalid arguments

**Steps:**
1. Run: `./mac-cleanup.sh --invalid-option`
2. Run: `./mac-cleanup.sh --dry-run --undo` (conflicting options)
3. Observe behavior

**Expected Results:**
- Clear error message
- Help text or usage information
- Script exits with non-zero code

**Status:** [ ] PASS [ ] FAIL

---

### Test 6.2: Non-Interactive Mode
**Objective:** Verify script works in non-interactive environments

**Steps:**
1. Set: `export MC_NON_INTERACTIVE=true`
2. Run: `./mac-cleanup.sh --dry-run`
3. Observe behavior

**Expected Results:**
- No prompts for user input
- Script runs automatically
- Clear output
- Appropriate defaults used

**Status:** [ ] PASS [ ] FAIL

---

### Test 6.3: Piped Input
**Objective:** Verify script handles piped input

**Steps:**
1. Run: `echo "y" | ./mac-cleanup.sh --dry-run`
2. Observe behavior

**Expected Results:**
- Script doesn't hang
- Handles input appropriately
- Completes successfully

**Status:** [ ] PASS [ ] FAIL

---

## Section 7: Backup System

### Test 7.1: Backup Creation
**Objective:** Verify backups are created correctly

**Steps:**
1. Run cleanup for a category
2. Check backup directory structure
3. Verify manifest.json exists
4. Verify files are in backup

**Expected Results:**
- Backup directory created with timestamp
- Manifest.json is valid JSON
- All files are present
- File permissions preserved

**Status:** [ ] PASS [ ] FAIL

---

### Test 7.2: Backup Verification
**Objective:** Verify backup integrity checking

**Steps:**
1. Create a backup
2. Run: `./mac-cleanup.sh --undo`
3. Select backup
4. Observe verification process

**Expected Results:**
- Manifest is validated
- File checksums verified (if implemented)
- Clear success/failure messages

**Status:** [ ] PASS [ ] FAIL

---

### Test 7.3: Backup Storage Management
**Objective:** Verify old backups are managed

**Steps:**
1. Create multiple backups (run cleanup several times)
2. Check backup directory
3. Verify old backups are retained or cleaned appropriately

**Expected Results:**
- Old backups are preserved (or cleaned per policy)
- Disk space is managed
- Clear retention policy

**Status:** [ ] PASS [ ] FAIL

---

## Section 8: Logging

### Test 8.1: Log File Creation
**Objective:** Verify logging works correctly

**Steps:**
1. Run cleanup
2. Check: `~/.mac-cleanup-backups/YYYY-MM-DD-HH-MM-SS/cleanup.log`
3. Review log contents

**Expected Results:**
- Log file is created
- Contains all operations
- Proper log levels used
- Timestamps present

**Status:** [ ] PASS [ ] FAIL

---

### Test 8.2: Log Compression
**Objective:** Verify logs are compressed after cleanup

**Steps:**
1. Run cleanup
2. Wait for completion
3. Check for `cleanup.log.gz`

**Expected Results:**
- Log is compressed after cleanup
- Original log removed
- Compressed log is readable

**Status:** [ ] PASS [ ] FAIL

---

## Test Summary

**Total Tests:** 40+
**Passed:** ___
**Failed:** ___
**Skipped:** ___

**Date Tested:** ___________
**Tester:** ___________
**macOS Version:** ___________
**Architecture:** ___________

## Notes

_Add any additional observations, issues, or recommendations here:_

---

## Sign-Off

**Ready for Production:** [ ] YES [ ] NO

**Blocking Issues:**
1. 
2. 
3. 

**Non-Blocking Issues:**
1. 
2. 
3. 
