#!/usr/bin/env bash
#
# SSHistorian - SSH Module
# Main module that integrates all SSH functionality

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${SCRIPT_DIR}/../utils/common.sh"
fi

SSH_DIR="${SCRIPT_DIR}/ssh"

# Source SSH handler module if not already loaded
if ! command -v handle_ssh &>/dev/null; then
    # shellcheck source=./ssh/ssh_handler.sh
    source "${SSH_DIR}/ssh_handler.sh"
fi

# Source session recorder module if not already loaded
if ! command -v start_session_recording &>/dev/null; then
    # shellcheck source=./ssh/session_recorder.sh
    source "${SSH_DIR}/session_recorder.sh"
fi

# Source session replay module if not already loaded
if ! command -v replay_session &>/dev/null; then
    # shellcheck source=./ssh/session_replay.sh
    source "${SSH_DIR}/session_replay.sh"
fi

# Export functions
# No additional exports needed as they are all exported from their respective modules