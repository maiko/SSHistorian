#!/usr/bin/env bash
#
# SSHistorian - Auto Tag Plugin
# Automatically tags SSH sessions based on configurable rules

# Define plugin metadata
PLUGIN_ID="autotag"
PLUGIN_NAME="Auto Tag"
PLUGIN_VERSION="1.0.0"
PLUGIN_DESCRIPTION="Automatically tags SSH sessions based on configurable rules"

# Initialize plugin settings with defaults
initialize_autotag_settings() {
    # Settings for user-based tagging
    set_plugin_setting "$PLUGIN_ID" "tag_root_user" "true" "Automatically tag sessions with root user"
    set_plugin_setting "$PLUGIN_ID" "user_root_tag" "user_root" "Tag to apply for root user sessions"
    
    # Settings for hostname pattern matching
    set_plugin_setting "$PLUGIN_ID" "tag_by_environment" "true" "Tag sessions based on hostname environment patterns"
    set_plugin_setting "$PLUGIN_ID" "prod_patterns" "prod,production" "Comma-separated list of patterns for production environments"
    set_plugin_setting "$PLUGIN_ID" "dev_patterns" "dev,development" "Comma-separated list of patterns for development environments"
    set_plugin_setting "$PLUGIN_ID" "staging_patterns" "staging,stage,uat,test" "Comma-separated list of patterns for staging environments"
    
    # Settings for regex-based tagging
    set_plugin_setting "$PLUGIN_ID" "enable_regex" "false" "Enable regex-based pattern matching for tagging"
    set_plugin_setting "$PLUGIN_ID" "regex_patterns" "" "JSON-formatted regex patterns and associated tags"
    
    # Settings for custom tagging rules
    set_plugin_setting "$PLUGIN_ID" "enable_custom_rules" "false" "Enable custom tagging rules from rules.sh file"
    set_plugin_setting "$PLUGIN_ID" "rules_file_path" "${HOME}/.config/sshistorian/autotag_rules.sh" "Path to custom rules file"
    
    return 0
}

# Tag session based on remote user
tag_by_remote_user() {
    local session_id="$1"
    local remote_user="$2"
    
    # Check if user tagging is enabled
    local tag_root_enabled
    tag_root_enabled=$(get_plugin_setting "$PLUGIN_ID" "tag_root_user" "true")
    
    if [[ "$tag_root_enabled" != "true" ]]; then
        log_debug "User tagging disabled, skipping"
        return 0
    fi
    
    # Tag root user sessions
    if [[ "$remote_user" == "root" ]]; then
        local root_tag
        root_tag=$(get_plugin_setting "$PLUGIN_ID" "user_root_tag" "user_root")
        
        log_debug "Tagging root user session: $session_id with tag: $root_tag"
        add_session_tag "$session_id" "$root_tag"
    elif [[ -n "$remote_user" ]]; then
        # Tag with user_NAME for other users (if remote user is known)
        log_debug "Tagging user session: $session_id with tag: user_${remote_user}"
        add_session_tag "$session_id" "user_${remote_user}"
    fi
    
    return 0
}

# Tag session based on environment patterns in hostname
tag_by_environment() {
    local session_id="$1"
    local hostname="$2"
    
    # Check if environment tagging is enabled
    local tag_env_enabled
    tag_env_enabled=$(get_plugin_setting "$PLUGIN_ID" "tag_by_environment" "true")
    
    if [[ "$tag_env_enabled" != "true" ]]; then
        log_debug "Environment tagging disabled, skipping"
        return 0
    fi
    
    # Get environment patterns
    local prod_patterns dev_patterns staging_patterns
    prod_patterns=$(get_plugin_setting "$PLUGIN_ID" "prod_patterns" "prod,production")
    dev_patterns=$(get_plugin_setting "$PLUGIN_ID" "dev_patterns" "dev,development")
    staging_patterns=$(get_plugin_setting "$PLUGIN_ID" "staging_patterns" "staging,stage,uat,test")
    
    # Check against production patterns
    local pattern
    IFS=',' read -ra PATTERNS <<< "$prod_patterns"
    for pattern in "${PATTERNS[@]}"; do
        if [[ "$hostname" == *"$pattern"* ]]; then
            log_debug "Tagging production environment: $session_id"
            add_session_tag "$session_id" "env_production"
            return 0
        fi
    done
    
    # Check against development patterns
    IFS=',' read -ra PATTERNS <<< "$dev_patterns"
    for pattern in "${PATTERNS[@]}"; do
        if [[ "$hostname" == *"$pattern"* ]]; then
            log_debug "Tagging development environment: $session_id"
            add_session_tag "$session_id" "env_development"
            return 0
        fi
    done
    
    # Check against staging patterns
    IFS=',' read -ra PATTERNS <<< "$staging_patterns"
    for pattern in "${PATTERNS[@]}"; do
        if [[ "$hostname" == *"$pattern"* ]]; then
            log_debug "Tagging staging environment: $session_id"
            add_session_tag "$session_id" "env_staging"
            return 0
        fi
    done
    
    # No environment matched
    log_debug "No environment pattern matched for: $hostname"
    add_session_tag "$session_id" "env_unknown"
    
    return 0
}

# Apply custom tagging rules from external file
apply_custom_rules() {
    local session_id="$1"
    local hostname="$2"
    local remote_user="$3"
    local command="$4"
    
    # Check if custom rules are enabled
    local custom_rules_enabled
    custom_rules_enabled=$(get_plugin_setting "$PLUGIN_ID" "enable_custom_rules" "false")
    
    if [[ "$custom_rules_enabled" != "true" ]]; then
        log_debug "Custom rules disabled, skipping"
        return 0
    fi
    
    # Get path to rules file
    local rules_file
    rules_file=$(get_plugin_setting "$PLUGIN_ID" "rules_file_path" "${HOME}/.config/sshistorian/autotag_rules.sh")
    
    # Validate path - prevent directory traversal
    if [[ "$rules_file" != /* ]]; then
        # If relative path, make it absolute relative to home
        rules_file="${HOME}/${rules_file}"
    fi
    
    # Normalize the path to remove ../ and ./ components
    rules_file=$(normalize_path "$rules_file")
    
    # Additional security: ensure it's in the expected location
    if [[ ! "$rules_file" =~ ^"${HOME}/.config/sshistorian" ]]; then
        log_error "Custom rules file path is outside of allowed directory: $rules_file"
        return 1
    fi
    
    # Check if rules file exists and is readable
    if [[ ! -f "$rules_file" || ! -r "$rules_file" ]]; then
        log_warning "Custom rules file not found or not readable: $rules_file"
        return 1
    fi
    
    # Source the rules file in a subshell to avoid polluting our environment
    (
        # Define the apply_tag function that the rules file can use
        apply_tag() {
            local tag="$1"
            local reason="$2"
            
            # Call back to our main process to add the tag
            add_session_tag "$session_id" "$tag"
            log_debug "Applied tag '$tag' from custom rule: $reason"
        }
        
        # Export variables for the rules file to use
        export SESSION_ID="$session_id"
        export HOSTNAME="$hostname"
        export REMOTE_USER="$remote_user"
        export COMMAND="$command"
        export -f apply_tag
        
        # Source the rules file
        # shellcheck disable=SC1090
        source "$rules_file"
    )
    
    return 0
}

# Process tag with capture groups
# Usage: process_tag_with_captures <tag_template> <captures_array>
process_tag_with_captures() {
    local tag_template="$1"
    shift
    local captures=("$@")
    local processed_tag="$tag_template"
    
    # Replace $1, $2, etc. with capture group values
    for i in "${!captures[@]}"; do
        local capture_index=$((i + 1))
        processed_tag="${processed_tag//\$$capture_index/${captures[$i]}}"
    done
    
    echo "$processed_tag"
}

# Tag session based on regex patterns
# Usage: tag_by_regex <session_id> <hostname> <command> <remote_user>
tag_by_regex() {
    local session_id="$1"
    local hostname="$2"
    local command="$3"
    local remote_user="$4"
    
    # Check if regex tagging is enabled
    local regex_enabled
    regex_enabled=$(get_plugin_setting "$PLUGIN_ID" "enable_regex" "false")
    
    if [[ "$regex_enabled" != "true" ]]; then
        log_debug "Regex tagging disabled, skipping"
        return 0
    fi
    
    # Get regex patterns from settings
    local patterns_json
    patterns_json=$(get_plugin_setting "$PLUGIN_ID" "regex_patterns" "")
    
    # Skip if no patterns defined
    if [[ -z "$patterns_json" ]]; then
        log_debug "No regex patterns defined, skipping"
        return 0
    fi
    
    log_debug "Processing regex patterns"
    
    # Parse the JSON patterns (basic parsing for simple JSON)
    # Format: [{"pattern":"regex1","tag":"tag1"},{"pattern":"regex2","tag":"tag2"}]
    # Trim brackets
    patterns_json="${patterns_json#[}"
    patterns_json="${patterns_json%]}"
    
    # Process each pattern entry by manually parsing JSON objects
    local remaining="$patterns_json"
    while [[ -n "$remaining" ]]; do
        # Find the end of the current object
        local obj_end
        if [[ "$remaining" == *"},"* ]]; then
            obj_end=$(echo "$remaining" | sed -n 's/^\(.*\)},.*$/\1}/p')
            remaining="${remaining#*},"
        else
            obj_end="$remaining"
            remaining=""
        fi
        
        # Extract pattern and tag
        local pattern_match tag_match
        pattern_match=$(echo "$obj_end" | grep -o '"pattern"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        tag_match=$(echo "$obj_end" | grep -o '"tag"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        
        if [[ -n "$pattern_match" && -n "$tag_match" ]]; then
            local regex="$pattern_match"
            local tag_template="$tag_match"
            local captures=()
            local matched_value=""
            local match_found=false
            
            log_debug "Checking regex: $regex for tag template: $tag_template"
            
            # Check against hostname
            if [[ "$hostname" =~ $regex ]]; then
                log_debug "Hostname '$hostname' matched regex '$regex'"
                match_found=true
                matched_value="$hostname"
                
                # Get all capture groups
                for i in $(seq 1 ${#BASH_REMATCH[@]}); do
                    if [[ $i -gt 0 ]]; then  # Skip first match (full string)
                        captures+=("${BASH_REMATCH[$i]}")
                    fi
                done
            fi
            
            # Check against command if no match found yet
            if [[ "$match_found" != "true" && "$command" =~ $regex ]]; then
                log_debug "Command '$command' matched regex '$regex'"
                match_found=true
                matched_value="$command"
                
                # Get all capture groups
                for i in $(seq 1 ${#BASH_REMATCH[@]}); do
                    if [[ $i -gt 0 ]]; then  # Skip first match (full string)
                        captures+=("${BASH_REMATCH[$i]}")
                    fi
                done
            fi
            
            # Check against remote user if provided and no match found yet
            if [[ "$match_found" != "true" && -n "$remote_user" && "$remote_user" =~ $regex ]]; then
                log_debug "Remote user '$remote_user' matched regex '$regex'"
                match_found=true
                matched_value="$remote_user"
                
                # Get all capture groups
                for i in $(seq 1 ${#BASH_REMATCH[@]}); do
                    if [[ $i -gt 0 ]]; then  # Skip first match (full string)
                        captures+=("${BASH_REMATCH[$i]}")
                    fi
                done
            fi
            
            # If a match was found, process the tag and apply it
            if [[ "$match_found" == "true" ]]; then
                local final_tag
                final_tag=$(process_tag_with_captures "$tag_template" "${captures[@]}")
                log_debug "Applying tag '$final_tag' from regex match on '$matched_value'"
                add_session_tag "$session_id" "$final_tag"
            fi
        fi
    done
    
    return 0
}

# Pre-session hook for Auto Tag plugin
# This function will be called before an SSH session starts
autotag_pre_session_hook() {
    local session_id="$1"
    local hostname="$2"
    local command="$3"
    local remote_user="$4"
    
    log_debug "Running Auto Tag pre-session hook for session: $session_id"
    
    # Apply tags based on remote user
    tag_by_remote_user "$session_id" "$remote_user"
    
    # Apply tags based on environment patterns in hostname
    tag_by_environment "$session_id" "$hostname"
    
    # Apply regex-based tags if enabled
    tag_by_regex "$session_id" "$hostname" "$command" "$remote_user"
    
    # Apply custom tagging rules if enabled
    apply_custom_rules "$session_id" "$hostname" "$remote_user" "$command"
    
    return 0
}

# Register the plugin with the plugin system
# Use a function to handle potential errors during registration
register_autotag_plugin() {
    # Check if plugin manager is loaded properly
    if ! command -v register_plugin &>/dev/null; then
        echo "Error: Plugin manager not properly loaded" >&2
        return 1
    fi

    # Validate required plugin metadata
    if [[ -z "$PLUGIN_ID" || -z "$PLUGIN_NAME" || -z "$PLUGIN_VERSION" ]]; then
        log_error "Missing required plugin metadata"
        return 1
    fi
    
    # Register the plugin
    register_plugin "$PLUGIN_ID" "$PLUGIN_NAME" "$PLUGIN_VERSION" "$PLUGIN_DESCRIPTION" 1 0
    local reg_status=$?
    
    # Only initialize settings if registration was successful
    if [[ $reg_status -eq 0 ]]; then
        # Initialize plugin settings with defaults
        initialize_autotag_settings
    else
        log_error "Failed to register autotag plugin, status: $reg_status"
    fi
    
    return $reg_status
}

# Call the registration function
register_autotag_plugin

# Export the plugin hook function
export -f autotag_pre_session_hook
export -f tag_by_remote_user
export -f tag_by_environment
export -f tag_by_regex
export -f process_tag_with_captures
export -f apply_custom_rules