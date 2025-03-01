#!/usr/bin/env bash
#
# SSHistorian - Session Model
# Integrates all session model components
#

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${SCRIPT_DIR}/../utils/constants.sh"
fi

# Source session model components
# shellcheck source=./session/session_model.sh
source "${SCRIPT_DIR}/session/session_model.sh"

# shellcheck source=./session/session_tags.sh
source "${SCRIPT_DIR}/session/session_tags.sh"

# No additional exports needed as they're all exported from their respective modules