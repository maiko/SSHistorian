#!/usr/bin/env bash
#
# SSHistorian - Database Module
# Integrates all database components for complete database management

# Source constants if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${VERSION:-}" ]]; then
    # shellcheck source=../utils/constants.sh
    source "${ROOT_DIR}/src/utils/constants.sh"
fi

# Source utility functions if not already loaded
if ! command -v log_debug &>/dev/null; then
    # shellcheck source=../utils/common.sh
    source "${ROOT_DIR}/src/utils/common.sh"
fi

# Source core database module
if ! command -v db_execute &>/dev/null; then
    # shellcheck source=./core/db_core.sh
    source "${ROOT_DIR}/src/db/core/db_core.sh"
fi

# Source migration module
if ! command -v run_migrations &>/dev/null; then
    # shellcheck source=./migration/migration.sh
    source "${ROOT_DIR}/src/db/migration/migration.sh"
fi

# Source configuration module (after database core is loaded)
if ! command -v get_config &>/dev/null && [[ -f "${ROOT_DIR}/src/config/config.sh" ]]; then
    # shellcheck source=../config/config.sh
    source "${ROOT_DIR}/src/config/config.sh"
fi

# Source any model dependencies
for model_file in "${ROOT_DIR}/src/db/models"/*.sh; do
    if [[ -f "$model_file" && "$model_file" != *"_test.sh" ]]; then
        # shellcheck disable=SC1090
        source "$model_file"
    fi
done

# Export functions - no additional exports needed as they are all exported from their respective modules