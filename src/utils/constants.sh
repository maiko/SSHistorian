#!/usr/bin/env bash
#
# SSHistorian - Constants and Global Variables
# Central location for all constants used across the application

# Set up strict error handling
set -o errexit
set -o nounset
set -o pipefail

# ========================================================================
# VERSION INFORMATION
# ========================================================================
export VERSION="2025.03.RC1"
export DB_VERSION="1"

# ========================================================================
# CONFIGURATION FLAGS
# ========================================================================
export DEBUG="${DEBUG:-false}"

# ========================================================================
# DIRECTORY PATHS
# ========================================================================
# Detect base directory based on script location
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT_DIR
export SRC_DIR="${ROOT_DIR}/src"
export BIN_DIR="${ROOT_DIR}/bin"
export DATA_DIR="${ROOT_DIR}/data"
export LOG_DIR="${DATA_DIR}/logs"
export DB_FILE="${DATA_DIR}/sshistorian.db"
export PLUGINS_DIR="${ROOT_DIR}/src/plugins"
export PLUGINS_DB_FILE="${DATA_DIR}/plugins.db"

# Ensure essential directories exist
mkdir -p "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
# Set secure permissions for directories (0700: only owner can read/write/execute)
chmod 700 "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true

# ========================================================================
# ENCRYPTION KEYS DIRECTORY
# ========================================================================
# Directory for storing encryption keys (the only configuration kept as files)
export KEYS_DIR="${HOME}/.config/sshistorian/keys"

# ========================================================================
# DEFAULT CONFIGURATION VALUES
# ========================================================================
# These are used when initializing the config database
export DEFAULT_LOG_BASE_DIR="${HOME}/sshistorian_logs"
export DEFAULT_LOG_PERMISSIONS="0600"
export DEFAULT_DIR_PERMISSIONS="0700"
export DEFAULT_SSH_BINARY="/usr/bin/ssh"
export DEFAULT_SCP_BINARY="/usr/bin/scp" 
export DEFAULT_SFTP_BINARY="/usr/bin/sftp"
export DEFAULT_MAX_LOG_AGE_DAYS=7
export DEFAULT_ASYNC_CLEANUP="true"
export DEFAULT_ENABLE_ENCRYPTION="false"
export DEFAULT_ENCRYPTION_METHOD="asymmetric"
export DEFAULT_OPENSSL_PUBLIC_KEY="${KEYS_DIR}/public.pem"
export DEFAULT_OPENSSL_PRIVATE_KEY="${KEYS_DIR}/private.pem"
export DEFAULT_COMPRESSION_TOOL="gzip"
export DEFAULT_COMPRESSION_LEVEL=9
export DEFAULT_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"

# ========================================================================
# COLOR DEFINITIONS
# ========================================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'  # Same as MAGENTA
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export GRAY='\033[0;90m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# Determine if colors should be used
if [[ -t 1 ]]; then
    # stdout is a terminal - use colors unless disabled
    export USE_COLORS="true"
else
    # stdout is not a terminal (e.g., being piped) - don't use colors
    export USE_COLORS="false"
fi

# ========================================================================
# TEMPORARY FILE MANAGEMENT
# ========================================================================
# Global array to track temporary files for cleanup on exit
export TEMP_FILES=()

# Ensure temporary files are cleaned up on exit
cleanup_temp_files() {
    if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
        for file in "${TEMP_FILES[@]}"; do
            [[ -e "$file" ]] && rm -f "$file" >/dev/null 2>&1
        done
    fi
}

# Register the cleanup function to run on exit
trap cleanup_temp_files EXIT

# Export functions
export -f cleanup_temp_files