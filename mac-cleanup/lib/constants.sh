#!/bin/zsh
#
# lib/constants.sh - Constants and configuration values for mac-cleanup
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Size constants (in bytes)
MC_BYTES_PER_KB=1024
MC_BYTES_PER_MB=1048576
MC_BYTES_PER_GB=1073741824
MC_BYTES_PER_TB=1099511627776

# Size thresholds
MC_MIN_BACKUP_SIZE=$MC_BYTES_PER_MB  # Skip backup for directories smaller than 1MB
MC_MIN_DIR_SIZE=4096  # Minimum directory size to consider (4KB overhead)

# Temporary file patterns
MC_TEMP_DIR="/tmp"
MC_TEMP_PREFIX="mac-cleanup"
MC_TEMP_OUTPUT_PATTERN="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-output-$$.tmp"
MC_TEMP_PROGRESS_PATTERN="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-progress-$$.tmp"
MC_TEMP_SPACE_PATTERN="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-space-$$.tmp"
MC_TEMP_SWEEP_PATTERN="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-sweep-$$.tmp"
MC_TEMP_SIZE_PATTERN="${MC_TEMP_DIR}/${MC_TEMP_PREFIX}-size-$$.tmp"

# Backup directory fallback
MC_BACKUP_FALLBACK_DIR="${MC_TEMP_DIR}/mac-cleanup-backups"

# Lock file timeout (in attempts, each 0.1 seconds)
MC_LOCK_TIMEOUT_ATTEMPTS=50

# Log levels (standardized)
MC_LOG_LEVEL_DEBUG="DEBUG"
MC_LOG_LEVEL_INFO="INFO"
MC_LOG_LEVEL_WARNING="WARNING"
MC_LOG_LEVEL_ERROR="ERROR"
MC_LOG_LEVEL_SUCCESS="SUCCESS"
MC_LOG_LEVEL_DRY_RUN="DRY_RUN"

# Phase 5: Platform Compatibility Constants
# Minimum required macOS version (10.15 = Catalina)
MC_MIN_MACOS_MAJOR=10
MC_MIN_MACOS_MINOR=15

# Minimum required zsh version (5.0+)
MC_MIN_ZSH_MAJOR=5
MC_MIN_ZSH_MINOR=0

# Supported architectures
MC_ARCH_INTEL="intel"
MC_ARCH_APPLE_SILICON="apple_silicon"

# Supported file systems
MC_FS_APFS="apfs"
MC_FS_HFS_PLUS="hfs+"
