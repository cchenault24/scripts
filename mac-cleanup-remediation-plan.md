# mac-cleanup Remediation Plan

## Goal
Address all critical security vulnerabilities, implement high-impact performance optimizations, and improve code quality based on comprehensive review findings. Transform the codebase from B+ to A- rating while maintaining excellent safety characteristics.

---

## Phase 1: Critical Security Fixes (Branch: `security/critical-fixes`)

**Priority:** CRITICAL - Must complete before any other work
**Duration:** 3-5 days
**Risk Level:** HIGH (touching sensitive code paths)

### Tasks

- [ ] **SEC-1: Remove eval in error_handler.sh** → Verify: `grep -r "eval" lib/` returns no results
  - Replace `eval "$command"` with direct execution or whitelisting
  - Update all callers to use structured command arrays
  - Test: Run error scenarios without eval

- [ ] **SEC-2: Fix sudo command injection in admin.sh** → Verify: `shellcheck lib/admin.sh` passes
  - Replace `sh -c` pattern with direct sudo execution
  - Use `sudo -- "${cmd_array[@]}"` instead of `sudo sh -c "$escaped_command"`
  - Add input validation for all sudo commands
  - Test: Attempt injection with `; id` in command

- [ ] **SEC-3: Eliminate unsafe sudo usage in plugins** → Verify: `grep -r "sudo sh -c" plugins/` returns empty
  - Refactor system_cache.sh lines 18, 53, 80
  - Refactor logs.sh lines 96, 130
  - Use direct sudo commands without shell interpretation
  - Test: Each system plugin with admin privileges

- [ ] **SEC-4: Implement proper file locking with flock** → Verify: Lock race condition test passes
  - Replace custom lock logic with `flock` or atomic `mkdir`
  - Update _write_progress_file in utils.sh:46-73
  - Update _read_progress_file in utils.sh:101-124
  - Update _write_space_tracking_file in plugins/base.sh:74-88
  - Test: Parallel execution of 50 lock attempts

- [ ] **SEC-5: Fix symlink attack in safe_clean_dir** → Verify: Symlink test case passes
  - Remove `rm -rf` fallback at lines 744-763
  - Use only `find -delete` which doesn't follow symlinks
  - Add explicit symlink detection and safe removal
  - Test: Create symlink to /etc/passwd in cache dir, attempt cleanup

- [ ] **SEC-6: Secure temp file creation with mktemp** → Verify: No predictable temp files exist
  - Replace all `${MC_TEMP_PREFIX}-$$` patterns in constants.sh
  - Create `create_secure_temp_file()` function
  - Use `mktemp -t` for all temporary files
  - Set chmod 600 on all temp files
  - Test: Check /tmp for predictable filenames

- [ ] **SEC-7: Add path canonicalization and validation** → Verify: Path traversal test fails safely
  - Create `validate_and_canonicalize_path()` function
  - Use in all backup operations
  - Use in all cleanup operations
  - Whitelist only $HOME and safe subdirectories
  - Test: Attempt backup of "../../../../etc/passwd"

- [ ] **SEC-8: Add set -euo pipefail to main script** → Verify: Script exits on undefined variable
  - Add to line 1 of mac-cleanup.sh
  - Test all error paths to ensure proper handling
  - Test: Reference undefined variable, verify exit

- [ ] **SEC-9: Set restrictive backup directory permissions** → Verify: `ls -la ~/.mac-cleanup-backups` shows drwx------
  - Update _create_backup_dir() to use umask 077
  - Add chmod 700 after directory creation
  - Test: Create backup as user A, attempt access as user B

- [ ] **SEC-10: Add input validation to plugin registration** → Verify: Malicious function name rejected
  - Validate function names match `^[a-zA-Z_][a-zA-Z0-9_]*$`
  - Verify function exists and is actually a function
  - Test: Register plugin with function name containing semicolon

### Verification Checklist
- [ ] All shellcheck warnings resolved
- [ ] Security test suite passes (create test_security.sh)
- [ ] No eval usage remains
- [ ] No sudo sh -c patterns remain
- [ ] Temp files created securely
- [ ] Path traversal blocked
- [ ] Backup permissions verified

---

## Phase 2: High-Impact Performance Optimizations (Branch: `perf/high-impact`)

**Priority:** HIGH - 2-2.5× speedup potential
**Duration:** 4-6 days
**Depends On:** Phase 1 complete

### Tasks

- [ ] **PERF-1: Remove per-item size tracking in safe_clean_dir** → Verify: 10,000 file cleanup < 40 seconds
  - Replace per-item `du -sk` with directory diff (before/after)
  - Update lines 687-714 in utils.sh
  - Maintain total space freed tracking via directory size difference
  - Test: Cleanup large node_modules directory, measure time

- [ ] **PERF-2: Use find -delete for batch operations** → Verify: Deletion 5× faster
  - Replace loop-based deletion with single `find -delete`
  - Keep loop as fallback if find fails
  - Update lines 701-715 in utils.sh
  - Test: 1,000 files deleted in single operation

- [ ] **PERF-3: Export functions instead of re-sourcing in subshell** → Verify: No library sources in background process
  - Export all functions needed in cleanup subshell
  - Use `typeset -fx function_name` for zsh
  - Remove library sourcing from lines 1130-1156
  - Test: Cleanup subshell starts instantly

- [ ] **PERF-4: Implement selective cache invalidation** → Verify: 50% reduction in du calls
  - Track modified paths in MC_MODIFIED_PATHS array
  - Clear only modified paths instead of entire cache
  - Update cache clearing logic in line 1221
  - Add cache hit/miss logging for debugging
  - Test: Run cleanup, check log for cache statistics

- [ ] **PERF-5: Add process pooling for async sweep** → Verify: Memory usage < 100MB during sweep
  - Limit concurrent processes to 10 (configurable)
  - Wait for process slot before spawning new calculation
  - Update lines 131-221 in mac-cleanup.sh
  - Test: Spawn 100 plugins, verify max 10 concurrent

- [ ] **PERF-6: Reduce lock timeout and add exponential backoff** → Verify: Average lock wait < 100ms
  - Reduce attempts from 50 to 20
  - Implement exponential backoff with jitter
  - Start at 10ms, max 500ms
  - Update _write_progress_file in utils.sh
  - Test: Measure lock acquisition time under load

- [ ] **PERF-7: Optimize progress update throttling** → Verify: Progress overhead < 5% of runtime
  - Update every 5% or 50 items for large operations (>1000 items)
  - Keep 1% or 10 items for small operations
  - Update lines 143-161 in mac-cleanup.sh
  - Test: Process 10,000 items, count progress updates

### Performance Benchmarks
- [ ] Baseline benchmark: Current cleanup time with 23 plugins
- [ ] Post-optimization benchmark: Expect 2-2.5× speedup
- [ ] Memory usage: < 100MB peak during async sweep
- [ ] Large directory (10K files): < 40 seconds cleanup
- [ ] Lock contention: < 100ms average wait time

---

## Phase 3: Code Quality Improvements (Branch: `quality/refactoring`)

**Priority:** MEDIUM - Maintainability and technical debt
**Duration:** 5-7 days
**Depends On:** Phase 2 complete

### Tasks

- [ ] **QUAL-1: Refactor main() function** → Verify: Function < 200 lines
  - Extract `initialize_cleanup()` (args parsing, init)
  - Extract `select_plugins_interactive()` (UI flow)
  - Extract `execute_cleanup_with_progress()` (orchestration)
  - Extract `display_cleanup_summary()` (reporting)
  - Test: Full cleanup flow works identically

- [ ] **QUAL-2: Extract browser plugin base class** → Verify: Browser plugins < 50 lines each
  - Create `plugins/browsers/browser_base.sh`
  - Implement `clean_browser_cache_template()`
  - Implement `calculate_browser_size_template()`
  - Refactor chrome.sh, firefox.sh, edge.sh, safari.sh to use template
  - Test: All browser cleanups work

- [ ] **QUAL-3: Remove size calculation fallback case statement** → Verify: 338-line case deleted
  - Delete lines 243-563 from mac-cleanup.sh
  - Require all plugins to register size functions
  - Add error logging if size function missing
  - Test: All plugins have registered size functions

- [ ] **QUAL-4: Split core.sh by concern** → Verify: 3 focused modules instead of 1 monolith
  - Create `lib/plugins.sh` (plugin registry)
  - Create `lib/platform.sh` (compatibility checks)
  - Create `lib/lifecycle.sh` (traps, cleanup)
  - Move functions from core.sh to appropriate modules
  - Test: All functionality preserved

- [ ] **QUAL-5: Standardize error suppression patterns** → Verify: Consistent pattern throughout
  - Choose standard: `2>/dev/null || true`
  - Replace all variations: `2>&1 || true`, `2>/dev/null || echo "0"`
  - Update style guide
  - Test: Error paths still work

- [ ] **QUAL-6: Add readonly to constants** → Verify: Attempt to modify constant fails
  - Add `readonly` to all MC_* constants in constants.sh
  - Test: `MC_BYTES_PER_GB=0` should fail with error

- [ ] **QUAL-7: Extract magic numbers to constants** → Verify: No hardcoded numbers in logic
  - Identify all magic numbers (30, 50, 5, etc.)
  - Add to constants.sh with descriptive names
  - Replace hardcoded values with constant references
  - Test: Change constant, verify behavior changes

- [ ] **QUAL-8: Implement backup-clean-track wrapper** → Verify: 29 instances reduced to function calls
  - Create `backup_clean_and_track()` function
  - Encapsulates: size_before → backup → clean → size_after → track
  - Replace 29 duplicated patterns
  - Test: Wrapper function works for all use cases

- [ ] **QUAL-9: Standardize command paths** → Verify: All system commands use absolute paths
  - Use `/usr/bin/du` consistently
  - Use `/usr/bin/find` consistently
  - Use `/bin/rm` consistently
  - Document in style guide
  - Test: Cleanup with restricted PATH

- [ ] **QUAL-10: Add function name prefix consistency** → Verify: All private functions start with _
  - Rename `clear_size_cache()` → `_clear_size_cache()`
  - Rename `invalidate_size_cache()` → `_invalidate_size_cache()`
  - Update all callers
  - Test: Public API unchanged

### Code Quality Metrics
- [ ] Main script < 200 lines (from 1523)
- [ ] No functions > 100 lines
- [ ] Code duplication < 10% (from 20%)
- [ ] All constants use readonly
- [ ] Consistent naming conventions

---

## Phase 4: Security Enhancements (Branch: `security/enhancements`)

**Priority:** MEDIUM - Additional security layers
**Duration:** 3-4 days
**Depends On:** Phase 1 complete

### Tasks

- [ ] **SEC-ENH-1: Implement audit logging** → Verify: ~/.mac-cleanup-audit.log created
  - Create `lib/audit.sh` module
  - Implement `audit_log(event_type, details, severity)`
  - Log sudo executions, file deletions, backup failures
  - ISO8601 timestamps, structured format
  - Test: Audit log contains security events

- [ ] **SEC-ENH-2: Sanitize sensitive data in logs** → Verify: No credentials in logs
  - Create `sanitize_log_message()` function
  - Filter paths: ~/.ssh, ~/.aws, ~/.gnupg
  - Filter patterns: password=, token=, key=
  - Update all log_message() calls
  - Test: Log message with password=secret shows [REDACTED]

- [ ] **SEC-ENH-3: Improve JSON escaping in manifests** → Verify: Newlines in filenames handled
  - Create proper `json_escape()` function
  - Handle all control characters (0x00-0x1F)
  - Use jq if available
  - Update manifest.sh:72-74
  - Test: Filename with newline in manifest

- [ ] **SEC-ENH-4: Add SIP status verification** → Verify: SIP disabled warning shown
  - Implement `check_sip_enabled()` using csrutil
  - Check before assuming SIP protection
  - Warn user if SIP disabled
  - Test: csrutil status output parsing

- [ ] **SEC-ENH-5: Revoke sudo credentials on exit** → Verify: sudo requires password after cleanup
  - Add `sudo -k` to cleanup trap
  - Update mc_cleanup_script()
  - Test: Run cleanup, verify sudo -n fails afterward

- [ ] **SEC-ENH-6: Add process limit for DoS prevention** → Verify: Max 10 concurrent processes enforced
  - Implement MAX_PARALLEL_JOBS constant
  - Enforce in async sweep (already in PERF-5)
  - Add warning if plugin count > 150
  - Test: 200 plugins attempted, only 10 spawn

### Security Test Suite
- [ ] test_security_command_injection.sh
- [ ] test_security_path_traversal.sh
- [ ] test_security_symlink_attack.sh
- [ ] test_security_temp_files.sh
- [ ] test_security_permissions.sh
- [ ] All tests pass on security branches

---

## Phase 5: Documentation & Testing (Branch: `docs/comprehensive`)

**Priority:** MEDIUM - Knowledge transfer
**Duration:** 2-3 days
**Depends On:** Phases 1-4 complete

### Tasks

- [ ] **DOC-1: Update README with security best practices** → Verify: Security section added
  - Document sudo usage guidelines
  - Document plugin security requirements
  - Document path validation requirements
  - Add security audit results summary

- [ ] **DOC-2: Create SECURITY.md** → Verify: File exists with CVE information
  - List all fixed vulnerabilities with CVSS scores
  - Document security model
  - Add responsible disclosure policy
  - Link to security test suite

- [ ] **DOC-3: Add function docstrings** → Verify: All public functions documented
  - Document parameters and return values
  - Add usage examples
  - Document side effects
  - Use consistent format

- [ ] **DOC-4: Create PERFORMANCE.md** → Verify: Optimization guide exists
  - Document performance optimizations
  - Include benchmarks (before/after)
  - Add scalability guidelines
  - Document when to optimize further

- [ ] **DOC-5: Update ARCHITECTURE.md** → Verify: Current architecture documented
  - Reflect new module structure
  - Document security model
  - Document performance characteristics
  - Add decision records for major changes

- [ ] **TEST-1: Create unit test framework** → Verify: tests/unit/ directory with tests
  - Set up shunit2 or similar
  - Write tests for utility functions
  - Write tests for validation functions
  - Test: `./run_tests.sh unit` passes

- [ ] **TEST-2: Create integration test suite** → Verify: tests/integration/ with tests
  - Test full cleanup flow
  - Test backup and restore
  - Test error scenarios
  - Test: `./run_tests.sh integration` passes

- [ ] **TEST-3: Create performance test suite** → Verify: tests/performance/ with benchmarks
  - Benchmark size calculation
  - Benchmark cleanup operations
  - Benchmark lock contention
  - Test: `./run_tests.sh perf` generates report

### Documentation Completeness
- [ ] All modules have file-level documentation
- [ ] All public functions documented
- [ ] Security model documented
- [ ] Performance characteristics documented
- [ ] Test coverage > 70%

---

## Phase 6: Validation & Deployment (Branch: `release/v2.0`)

**Priority:** HIGH - Final verification
**Duration:** 2-3 days
**Depends On:** All previous phases

### Tasks

- [ ] **VAL-1: Run complete test suite** → Verify: All tests pass
  - Security tests: 100% pass rate
  - Unit tests: 100% pass rate
  - Integration tests: 100% pass rate
  - Performance tests: Meet benchmarks

- [ ] **VAL-2: Run shellcheck on all scripts** → Verify: Zero warnings
  - Run on all .sh files
  - Fix any new warnings
  - Update CI to enforce

- [ ] **VAL-3: Manual regression testing** → Verify: Checklist complete
  - Test on macOS 13 (Ventura)
  - Test on macOS 14 (Sonoma)
  - Test on macOS 15 (Sequoia)
  - Test on Intel and Apple Silicon
  - Test with 5, 10, 23 plugins
  - Test with large directories (>10K files)
  - Test with network filesystem

- [ ] **VAL-4: Performance benchmarking** → Verify: 2× speedup achieved
  - Run baseline benchmark (saved from Phase 2)
  - Run optimized benchmark
  - Calculate improvement percentage
  - Document results in PERFORMANCE.md

- [ ] **VAL-5: Security audit verification** → Verify: No critical/high vulnerabilities
  - Re-run security test suite
  - Manual security review
  - Check for any new vulnerabilities introduced
  - Document remaining low-severity issues

- [ ] **VAL-6: Code quality verification** → Verify: A- rating achieved
  - Check main script < 200 lines
  - Check no functions > 100 lines
  - Check code duplication < 10%
  - Check consistent patterns
  - Run quality metrics tool

- [ ] **VAL-7: Create release notes** → Verify: CHANGELOG.md updated
  - List all security fixes
  - List all performance improvements
  - List all breaking changes
  - Add upgrade guide

- [ ] **VAL-8: Tag release v2.0.0** → Verify: Git tag exists
  - Create annotated tag
  - Push to repository
  - Create GitHub release if applicable

### Final Acceptance Criteria
- [ ] Zero critical security vulnerabilities
- [ ] Zero high security vulnerabilities
- [ ] 2-2.5× performance improvement achieved
- [ ] Code quality rating: A-
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Backward compatibility maintained (or documented)

---

## Branch Strategy

```
master
  ├── security/critical-fixes (Phase 1)
  │   └── merge → master
  │
  ├── perf/high-impact (Phase 2)
  │   └── merge → master
  │
  ├── quality/refactoring (Phase 3)
  │   └── merge → master
  │
  ├── security/enhancements (Phase 4)
  │   └── merge → master
  │
  ├── docs/comprehensive (Phase 5)
  │   └── merge → master
  │
  └── release/v2.0 (Phase 6)
      └── merge → master (tagged v2.0.0)
```

**Merge Strategy:**
- Each phase merges to master independently
- Run full test suite before each merge
- No phase blocks another (except dependencies noted)
- Can work on Phase 3-5 in parallel after Phase 1 complete

---

## Risk Mitigation

### High-Risk Changes
1. **Removing eval** - Could break error handling
   - Mitigation: Extensive error scenario testing
   - Rollback: Keep eval version in git history

2. **Changing sudo execution** - Could break admin operations
   - Mitigation: Test all admin plugins thoroughly
   - Rollback: Original sudo patterns documented

3. **Refactoring main()** - Could break orchestration
   - Mitigation: Integration tests for full flow
   - Rollback: Keep original main() in separate file temporarily

### Testing Strategy
- Test each phase independently before merge
- Maintain test system with fresh macOS install
- Test on multiple macOS versions
- Test with varying plugin counts
- Test with edge cases (empty dirs, permission denied, etc.)

### Rollback Plan
- Each phase on separate branch
- Can revert specific merges
- Keep original code in git history
- Document known issues in KNOWN_ISSUES.md

---

## Success Metrics

### Security (Must Achieve)
- [ ] 0 critical vulnerabilities (from 3)
- [ ] 0 high vulnerabilities (from 5)
- [ ] < 3 medium vulnerabilities (from 4)
- [ ] Security test suite passes 100%

### Performance (Target)
- [ ] 2-2.5× speedup in total runtime
- [ ] < 100MB peak memory (from 120MB)
- [ ] < 40s for 10K file cleanup (from 350s)
- [ ] < 100ms average lock wait (from 500ms)

### Code Quality (Target)
- [ ] Main script < 200 lines (from 1523)
- [ ] Code duplication < 10% (from 20%)
- [ ] All functions < 100 lines (from 4 functions > 200)
- [ ] Test coverage > 70%
- [ ] Overall rating: A- (from B+)

### Maintainability (Target)
- [ ] All functions documented
- [ ] Consistent coding patterns
- [ ] Clear module boundaries
- [ ] Comprehensive test suite

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Security Fixes | 3-5 days | None |
| Phase 2: Performance | 4-6 days | Phase 1 |
| Phase 3: Code Quality | 5-7 days | Phase 2 |
| Phase 4: Security Enhancements | 3-4 days | Phase 1 |
| Phase 5: Documentation | 2-3 days | Phases 1-4 |
| Phase 6: Validation | 2-3 days | All phases |
| **Total** | **19-28 days** | Sequential critical path |

**Parallel Work Opportunities:**
- Phase 4 can start after Phase 1 (parallel with Phase 2-3)
- Phase 5 can start after Phase 1 (parallel with others)
- Reduces total time to ~15-20 days with parallel execution

---

## Notes

### Critical Dependencies
- Phase 2 depends on Phase 1 (security fixes might affect performance code)
- Phase 3 depends on Phase 2 (refactoring stable, optimized code)
- Phase 6 depends on all previous phases

### Testing Infrastructure
- Create `tests/` directory structure
- Set up test runner script
- Add CI/CD integration if applicable
- Maintain test data sets

### Breaking Changes
- eval removal might break custom plugins using it
- sudo pattern change might break custom admin operations
- Document all breaking changes in upgrade guide

### Future Work (Out of Scope)
- Plugin marketplace support
- Remote plugin installation
- Distributed lock manager
- Progressive size estimation UI
- Plugin execution pooling (concurrent cleanup)

---

## Getting Started

1. **Create security branch:** `git checkout -b security/critical-fixes`
2. **Start with SEC-1:** Remove eval from error_handler.sh
3. **Test thoroughly:** Run security test after each fix
4. **Commit frequently:** Small, focused commits
5. **Document changes:** Update CHANGELOG as you go
6. **Merge when complete:** Full test suite must pass

**First Command:** `git checkout -b security/critical-fixes`

**Last Command:** `git tag -a v2.0.0 -m "Major security and performance improvements"`
