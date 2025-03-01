#!/usr/bin/env bash
#
# SSHistorian - Command Line Interface
# Functions for handling command line arguments and showing help

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source utility functions if not already loaded
if [[ -z "$ROOT_DIR" ]]; then
    # shellcheck source=../utils/common.sh
    source "${SCRIPT_DIR}/../utils/common.sh"
fi

# Source dependencies if not already loaded
if ! command -v init_database &>/dev/null; then
    # shellcheck source=../db/database.sh
    source "${SCRIPT_DIR}/../db/database.sh"
fi

if ! command -v db_execute_params &>/dev/null; then
    # shellcheck source=../db/core/db_core.sh
    source "${SCRIPT_DIR}/../db/core/db_core.sh"
fi

if ! command -v list_sessions &>/dev/null; then
    # shellcheck source=../db/models/sessions.sh
    source "${SCRIPT_DIR}/../db/models/sessions.sh"
fi

if ! command -v handle_ssh &>/dev/null; then
    # shellcheck source=../core/ssh.sh
    source "${SCRIPT_DIR}/../core/ssh.sh"
fi

# Show help message
show_help() {
    cat << EOF
SSHistorian v${VERSION} - A tool to record and replay SSH sessions

USAGE:
  sshistorian [ssh-options] [user@]hostname [command]     Connect to a host and log the session
  sshistorian <command> [options]                        Run a specific command

COMMANDS:
  sessions ou list [options]                List recorded sessions
  replay <uuid> [--html]            Replay a recorded session
  tag <uuid> <tag>                  Add a tag to a session
  untag <uuid> <tag>                Remove a tag from a session
  generate-keys                     Generate RSA keys for encryption
  stats                             Show statistics about recorded sessions
  plugin list                       List available plugins
  plugin enable <id>                Enable a plugin
  plugin disable <id>               Disable a plugin
  plugin config <id> <key> <value>  Configure a plugin setting
  plugin get <id> <key>             Get a plugin setting
  plugin commands                   List all available plugin commands
  plugin command <id> <cmd> [args]  Run a plugin-specific command
  config                            Show current configuration
  config edit                       Edit configuration interactively
  config set <key> <value>          Set a configuration value
  config get <key>                  Get a configuration value
  help                              Show this help message
  version                           Show version information

SESSION OPTIONS:
  --limit N                         Limit to N results
  --host HOSTNAME                   Filter by hostname
  --tag TAG                         Filter by tag
  --days N                          Show sessions from the last N days
  --sort-field FIELD                Sort by field (created_at, timestamp, host)

ENCRYPTION:
  When encryption is enabled, all session logs are encrypted using your SSH key.
  To decrypt logs, your private key will be needed.
  Use 'generate-keys' to create dedicated keys for SSHistorian.

EXAMPLES:
  sshistorian user@example.com                      Connect and log SSH session
  sshistorian sessions --host example.com --limit 5 List recent sessions for a host
  sshistorian replay <uuid>                         Replay a session
  sshistorian tag <uuid> "important"                Tag a session
  sshistorian generate-keys                         Generate encryption keys
  sshistorian config set encryption.enabled true    Enable encryption

For more information, see README.md
EOF
}

# Show version information
show_version() {
    echo "SSHistorian v${VERSION}"
    echo "Database: ${DB_FILE}"
    echo "Logs directory: ${LOG_DIR}"
    echo ""
    
    # Add the schema version if database exists
    if [[ -f "$DB_FILE" && -s "$DB_FILE" ]]; then
        # Check if encryption is enabled
        local encryption_enabled
        encryption_enabled=$(get_config "encryption.enabled" "false")
        local key_path
        key_path=$(get_config "encryption.key_path" "${HOME}/.ssh/id_rsa.pub")
        
        if [[ "$encryption_enabled" == "true" ]]; then
            echo "Encryption: Enabled (using $key_path)"
        else
            echo "Encryption: Disabled"
        fi
    else
        echo "Database not initialized"
    fi
}

# Show statistics about recorded sessions
show_stats() {
    # Get total session count
    local total_count
    total_count=$(db_execute -count "SELECT COUNT(*) FROM sessions;")
    
    # Get unique host count
    local host_count
    host_count=$(db_execute -count "SELECT COUNT(DISTINCT host) FROM sessions;")
    
    # Get total log size (in bytes)
    local total_size_bytes=0
    total_size_bytes=$(find "$LOG_DIR" -type f -size +0c | xargs du -c 2>/dev/null | tail -1 | cut -f1)
    
    # Convert to human-readable
    local total_size
    if [[ $total_size_bytes -ge 1073741824 ]]; then
        total_size=$(echo "scale=2; $total_size_bytes / 1073741824" | bc)" GB"
    elif [[ $total_size_bytes -ge 1048576 ]]; then
        total_size=$(echo "scale=2; $total_size_bytes / 1048576" | bc)" MB"
    elif [[ $total_size_bytes -ge 1024 ]]; then
        total_size=$(echo "scale=2; $total_size_bytes / 1024" | bc)" KB"
    else
        total_size="${total_size_bytes} bytes"
    fi
    
    # Get recent session count (last 7 days)
    local recent_count
    recent_count=$(db_execute -count "SELECT COUNT(*) FROM sessions WHERE created_at >= datetime('now', '-7 days');")
    
    # Get top hosts (with better delimiter for parsing)
    local top_hosts
    top_hosts=$(db_execute -csv "SELECT host || '|' || COUNT(*) as count FROM sessions GROUP BY host ORDER BY count DESC LIMIT 5;" | tail -n +2)
    
    # Get top tags (with better delimiter for parsing)
    local top_tags
    top_tags=$(db_execute -csv "SELECT tag || '|' || COUNT(*) as count FROM tags GROUP BY tag ORDER BY count DESC LIMIT 5;" | tail -n +2)
    
    # Get session count by month (with better delimiter for parsing)
    local monthly_stats
    monthly_stats=$(db_execute -csv "SELECT strftime('%Y-%m', created_at) || '|' || COUNT(*) FROM sessions GROUP BY strftime('%Y-%m', created_at) ORDER BY strftime('%Y-%m', created_at) DESC LIMIT 6;" | tail -n +2)
    
    # Display statistics
    echo -e "${YELLOW}SSHistorian Statistics${NC}"
    echo -e "${BLUE}====================${NC}"
    echo "Total sessions: $total_count"
    echo "Unique hosts: $host_count"
    echo "Total log size: $total_size"
    echo "Sessions in last 7 days: $recent_count"
    
    echo -e "\n${BLUE}Top Hosts:${NC}"
    if [[ -n "$top_hosts" ]]; then
        echo "$top_hosts" | while IFS='|' read -r host count; do
            echo "  ${host}: ${count} sessions"
        done
    else
        echo "  No hosts found"
    fi
    
    echo -e "\n${BLUE}Top Tags:${NC}"
    if [[ -n "$top_tags" ]]; then
        echo "$top_tags" | while IFS='|' read -r tag count; do
            echo "  ${tag}: ${count} sessions"
        done
    else
        echo "  No tags found"
    fi
    
    echo -e "\n${BLUE}Monthly Activity:${NC}"
    if [[ -n "$monthly_stats" ]]; then
        echo "$monthly_stats" | while IFS='|' read -r month count; do
            echo "  ${month}: ${count} sessions"
        done
    else
        echo "  No monthly data found"
    fi
    
    return 0
}

# Interactive list sessions function
# Provides a user-friendly interface for session listing and management
# Usage: list_sessions [--limit N] [--host name] [--tag name] [--days N] [--sort-field field]
list_sessions() {
    # First check if database exists and is initialized
    if [[ ! -f "$DB_FILE" || ! -s "$DB_FILE" ]]; then
        log_error "Database not initialized. Run a command that creates sessions first."
        return 1
    fi

    local limit=10
    local where_clauses=""
    local order_by="s.timestamp DESC"
    local host_filter=""
    local tag_filter=""
    local days_filter=0
    local sort_field="created_at"
    local interactive=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                limit="$1"
                ;;
            --host)
                shift
                host_filter="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.host = '$1'"
                ;;
            --tag)
                shift
                tag_filter="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.id IN (
                    SELECT session_id FROM tags WHERE tag = '$1'
                )"
                ;;
            --days)
                shift
                days_filter="$1"
                where_clauses="${where_clauses:+$where_clauses AND }s.created_at >= datetime('now', '-$1 days')"
                ;;
            --exit-code)
                shift
                where_clauses="${where_clauses:+$where_clauses AND }s.exit_code = $1"
                ;;
            --sort-field)
                shift
                sort_field="$1"
                if [[ "$sort_field" == "created_at" || "$sort_field" == "timestamp" || "$sort_field" == "host" ]]; then
                    order_by="s.$sort_field DESC"
                fi
                ;;
            --no-interactive)
                interactive=false
                ;;
            *)
                log_warning "Unknown option: $1"
                ;;
        esac
        shift
    done
    
    # Construct the WHERE clause
    local where_sql=""
    if [[ -n "$where_clauses" ]]; then
        where_sql="WHERE $where_clauses"
    fi
    
    # If non-interactive, just show the raw data and return
    if [[ "$interactive" == "false" ]]; then
        # Use parameter binding for the LIMIT to avoid SQL injection
        log_debug "Executing SQL with LIMIT: $limit"
        db_execute_params -line "SELECT * FROM sessions s $where_sql ORDER BY $order_by LIMIT :limit;" \
            ":limit" "$limit"
        return 0
    fi
    
    # Main display loop - will loop for interactive commands
    local running=true
    
    while $running; do
        echo -e "\n${YELLOW}SSHistorian Session List${NC}"
        echo -e "${BLUE}================${NC}\n"
        
        # Show current filters
        if [[ -n "$host_filter" || -n "$tag_filter" || $days_filter -gt 0 ]]; then
            echo -e "${CYAN}Active Filters:${NC}"
            [[ -n "$host_filter" ]] && echo -e "  Host: ${GREEN}$host_filter${NC}"
            [[ -n "$tag_filter" ]] && echo -e "  Tag: ${GREEN}$tag_filter${NC}"
            [[ $days_filter -gt 0 ]] && echo -e "  Last: ${GREEN}$days_filter days${NC}"
            echo -e "  Sort: ${GREEN}$sort_field${NC}"
            echo
        fi
        
        # Query the database
        local sql
        sql=$(cat <<EOF
SELECT 
    s.id, s.host, s.timestamp, s.command, s.user, s.remote_user,
    s.exit_code, s.duration, s.created_at,
    (SELECT GROUP_CONCAT(tag, ', ') FROM tags WHERE session_id = s.id) AS tags
FROM sessions s
$where_sql
ORDER BY $order_by
LIMIT $limit;
EOF
        )
        
        # Execute the query and store results in arrays for interactive use
        local session_ids=()
        local session_hosts=()
        local session_dates=()
        local session_cmds=()
        local session_tags=()
        local session_durations=()
        local session_exit_codes=()
        local session_count=0
        
        # Use a while loop with read to process each line from SQLite
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*id\ =\ (.*)$ ]]; then
                session_ids+=("${BASH_REMATCH[1]}")
                ((session_count++))
            elif [[ "$line" =~ ^[[:space:]]*host\ =\ (.*)$ ]]; then
                session_hosts+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*timestamp\ =\ (.*)$ ]]; then
                session_dates+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*command\ =\ (.*)$ ]]; then
                session_cmds+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*tags\ =\ (.*)$ ]]; then
                session_tags+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*duration\ =\ (.*)$ ]]; then
                session_durations+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^[[:space:]]*exit_code\ =\ (.*)$ ]]; then
                session_exit_codes+=("${BASH_REMATCH[1]}")
            fi
        done < <(db_execute -line "$sql")
        
        # No sessions found? Show message and return
        if [[ $session_count -eq 0 ]]; then
            echo -e "  ${YELLOW}No sessions found matching your criteria.${NC}"
            echo
            
            # Show a prompt to modify filters
            echo -e "${BLUE}Options:${NC}"
            echo -e "${GREEN}f${NC} - Modify filters"
            echo -e "${GREEN}q${NC} - Quit"
            echo
            
            echo -ne "${YELLOW}Enter option:${NC} "
            local choice
            read -r choice
            
            case "$choice" in
                f)
                    # Show filter menu
                    show_filter_menu
                    ;;
                q)
                    running=false
                    ;;
                *)
                    log_error "Invalid option: $choice"
                    ;;
            esac
            
            continue
        fi
        
        # Display sessions in table format
        printf "${CYAN}%-4s | %-20s | %-19s | %-30s | %-8s${NC}\n" \
            "NUM" "HOST" "DATE" "TAGS" "DURATION"
        printf "${BLUE}%s+%s+%s+%s+%s${NC}\n" \
            "$(printf '%0.s-' {1..4})" "$(printf '%0.s-' {1..22})" "$(printf '%0.s-' {1..21})" \
            "$(printf '%0.s-' {1..32})" "$(printf '%0.s-' {1..10})"
        
        for i in "${!session_ids[@]}"; do
            local num="$((i+1))"
            local host="${session_hosts[$i]}"
            local date="${session_dates[$i]}"
            local tags="${session_tags[$i]:-None}"
            local duration="${session_durations[$i]:-N/A}"
            local exit_code="${session_exit_codes[$i]:-N/A}"
            
            # Format duration as human-readable time
            if [[ "$duration" =~ ^[0-9]+$ ]]; then
                if [[ $duration -ge 3600 ]]; then
                    duration="$(( duration / 3600 ))h$(( (duration % 3600) / 60 ))m"
                elif [[ $duration -ge 60 ]]; then
                    duration="$(( duration / 60 ))m$(( duration % 60 ))s"
                else
                    duration="${duration}s"
                fi
            fi
            
            # Format exit code with colors
            local formatted_exit
            if [[ "$exit_code" == "0" ]]; then
                formatted_exit="${GREEN}$exit_code${NC}"
            elif [[ "$exit_code" =~ ^[0-9]+$ ]]; then
                formatted_exit="${RED}$exit_code${NC}"
            else
                formatted_exit="$exit_code"
            fi
            
            # Truncate tags if too long
            if [[ ${#tags} -gt 30 ]]; then
                tags="${tags:0:27}..."
            fi
            
            # Colorize host
            local formatted_host="${CYAN}${host}${NC}"
            
            # Format exit code with colors
            local formatted_exit
            if [[ "$exit_code" == "0" ]]; then
                formatted_exit="${GREEN}$exit_code${NC}"
            elif [[ "$exit_code" =~ ^[0-9]+$ ]]; then
                formatted_exit="${RED}$exit_code${NC}"
            else
                formatted_exit="$exit_code"
            fi
            
            # Apply filters
            local show_row=true
            if [[ -n "$host_filter" && "$host" != "$host_filter" ]]; then
                show_row=false
            fi
            
            if $show_row; then
                # Print the session in a table row (without EXIT column)
                printf "${GREEN}%-4s${NC} | ${CYAN}%-20s${NC} | %-19s | %-30s | %-8s\n" \
                    "$num" "$host" "$date" "$tags" "$duration"
            fi
        done
        
        echo
        echo -e "${BLUE}Options:${NC}"
        echo -e "${GREEN}r <num>${NC} - Replay session (e.g. 'r 1')"
        echo -e "${GREEN}h <num>${NC} - HTML view (e.g. 'h 2')"
        echo -e "${GREEN}t <num> \"tag\"${NC} - Tag session (e.g. 't 3 \"important\"')"
        echo -e "${GREEN}u <num> \"tag\"${NC} - Remove tag (e.g. 'u 3 \"important\"')"
        echo -e "${GREEN}i <num>${NC} - Show session info (e.g. 'i 1')"
        echo -e "${GREEN}s${NC} - Toggle sort order (current: by $sort_field)"
        echo -e "${GREEN}f${NC} - Filter sessions"
        echo -e "${GREEN}q${NC} - Quit"
        echo
        
        # Handle user input
        echo -ne "${YELLOW}Enter option: ${NC}"
        local choice
        read -r choice
        
        # Process user choice
        if [[ "$choice" == "q" ]]; then
            running=false
        elif [[ "$choice" == "s" ]]; then
            # Toggle sort order
            case "$sort_field" in
                created_at)
                    sort_field="timestamp"
                    order_by="s.timestamp DESC"
                    ;;
                timestamp)
                    sort_field="host"
                    order_by="s.host ASC"
                    ;;
                host)
                    sort_field="created_at"
                    order_by="s.created_at DESC"
                    ;;
                *)
                    sort_field="created_at"
                    order_by="s.created_at DESC"
                    ;;
            esac
            log_info "Sorting by $sort_field"
        elif [[ "$choice" == "f" ]]; then
            show_filter_menu
        elif [[ "$choice" =~ ^r\ +([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            if [[ "$num" -le "${#session_ids[@]}" && "$num" -gt 0 ]]; then
                local idx=$((num-1))
                local session_id="${session_ids[$idx]}"
                echo -e "\n${GREEN}Replaying session ${num}...${NC}"
                replay_session "$session_id"
                
                # Wait for user input before redisplaying the menu
                echo 
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
            else
                log_error "Invalid session number: $num"
                sleep 1
            fi
        elif [[ "$choice" =~ ^h\ +([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            if [[ "$num" -le "${#session_ids[@]}" && "$num" -gt 0 ]]; then
                local idx=$((num-1))
                local session_id="${session_ids[$idx]}"
                echo -e "\n${GREEN}Generating HTML view for session ${num}...${NC}"
                replay_session "$session_id" "--html"
                
                # Wait for user input before redisplaying the menu
                echo 
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
            else
                log_error "Invalid session number: $num"
                sleep 1
            fi
        elif [[ "$choice" =~ ^i\ +([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            if [[ "$num" -le "${#session_ids[@]}" && "$num" -gt 0 ]]; then
                local idx=$((num-1))
                local session_id="${session_ids[$idx]}"
                get_session "$session_id"
                
                # Show tags separately in a nicer format
                local tags
                tags=$(get_session_tags "$session_id")
                if [[ -n "$tags" ]]; then
                    echo -e "\n${YELLOW}Session Tags:${NC}"
                    echo "$tags"
                fi
                
                # Wait for user input before redisplaying the menu
                echo 
                echo -e "${YELLOW}Press Enter to continue...${NC}"
                read -r
            else
                log_error "Invalid session number: $num"
                sleep 1
            fi
        elif [[ "$choice" =~ ^t\ +([0-9]+)\ +\"(.+)\"$ ]]; then
            local num="${BASH_REMATCH[1]}"
            local tag="${BASH_REMATCH[2]}"
            if [[ "$num" -le "${#session_ids[@]}" && "$num" -gt 0 ]]; then
                local idx=$((num-1))
                local session_id="${session_ids[$idx]}"
                echo -e "\n${GREEN}Tagging session ${num} with \"${tag}\"...${NC}"
                add_session_tag "$session_id" "$tag"
                
                # Short pause to see the message
                sleep 1
            else
                log_error "Invalid session number: $num"
                sleep 1
            fi
        elif [[ "$choice" =~ ^u\ +([0-9]+)\ +\"(.+)\"$ ]]; then
            local num="${BASH_REMATCH[1]}"
            local tag="${BASH_REMATCH[2]}"
            if [[ "$num" -le "${#session_ids[@]}" && "$num" -gt 0 ]]; then
                local idx=$((num-1))
                local session_id="${session_ids[$idx]}"
                echo -e "\n${GREEN}Removing tag \"${tag}\" from session ${num}...${NC}"
                remove_session_tag "$session_id" "$tag"
                
                # Short pause to see the message
                sleep 1
            else
                log_error "Invalid session number: $num"
                sleep 1
            fi
        else
            log_error "Invalid option: $choice"
            sleep 1
        fi
    done
    
    return 0
}

# Display a menu to set session filters
show_filter_menu() {
    echo -e "\n${YELLOW}Filter Sessions${NC}"
    echo -e "${BLUE}==============${NC}\n"
    
    echo -e "Current filters:"
    echo -e "  ${CYAN}Host:${NC} ${host_filter:-None}"
    echo -e "  ${CYAN}Tag:${NC} ${tag_filter:-None}"
    echo -e "  ${CYAN}Days:${NC} ${days_filter:-All}"
    echo -e "  ${CYAN}Limit:${NC} ${limit}"
    echo
    
    echo -e "${BLUE}Options:${NC}"
    echo -e "${GREEN}h${NC} - Set host filter"
    echo -e "${GREEN}t${NC} - Set tag filter"
    echo -e "${GREEN}d${NC} - Set days filter"
    echo -e "${GREEN}l${NC} - Set result limit"
    echo -e "${GREEN}c${NC} - Clear all filters"
    echo -e "${GREEN}r${NC} - Return to session list"
    echo
    
    local choice
    echo -ne "${YELLOW}Enter option: ${NC}"
    read -r choice
    
    case "$choice" in
        h)
            echo -ne "Enter hostname (or leave empty to clear): "
            read -r new_host_filter
            
            if [[ -n "$new_host_filter" ]]; then
                host_filter="$new_host_filter"
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.host = .*//g')
                where_clauses="${where_clauses:+$where_clauses AND }s.host = '$host_filter'"
            else
                # Remove host filter from where clause
                host_filter=""
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.host = .*//g')
            fi
            ;;
        t)
            echo -ne "Enter tag (or leave empty to clear): "
            read -r new_tag_filter
            
            if [[ -n "$new_tag_filter" ]]; then
                tag_filter="$new_tag_filter"
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.id IN \(.*\)//g')
                where_clauses="${where_clauses:+$where_clauses AND }s.id IN (
                    SELECT session_id FROM tags WHERE tag = '$tag_filter'
                )"
            else
                # Remove tag filter from where clause
                tag_filter=""
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.id IN \(.*\)//g')
            fi
            ;;
        d)
            echo -ne "Enter days to include (or 0 for all): "
            read -r new_days_filter
            
            if [[ "$new_days_filter" =~ ^[0-9]+$ && $new_days_filter -gt 0 ]]; then
                days_filter="$new_days_filter"
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.created_at >= datetime\(.*\)//g')
                where_clauses="${where_clauses:+$where_clauses AND }s.created_at >= datetime('now', '-$days_filter days')"
            else
                # Remove days filter from where clause
                days_filter=0
                where_clauses=$(echo "$where_clauses" | sed -E 's/ AND s\.created_at >= datetime\(.*\)//g')
            fi
            ;;
        l)
            echo -ne "Enter result limit: "
            read -r new_limit
            
            if [[ "$new_limit" =~ ^[0-9]+$ && $new_limit -gt 0 ]]; then
                limit=$new_limit
            else
                log_error "Invalid limit: $new_limit - must be a positive integer"
            fi
            ;;
        c)
            # Clear all filters
            where_clauses=""
            host_filter=""
            tag_filter=""
            days_filter=0
            limit=10
            ;;
        r)
            # Just return to the main menu
            ;;
        *)
            log_error "Invalid option: $choice"
            sleep 1
            show_filter_menu  # Call recursively
            ;;
    esac
}

# Process command line arguments
process_arguments() {
    # No arguments? Show help
    if [[ $# -eq 0 ]]; then
        show_help
        return 0
    fi
    
    # Handle plugin management commands
# Usage: handle_plugin_command [args...]
handle_plugin_command() {
    # Check if plugin system is available
    if ! command -v list_plugins &>/dev/null; then
        log_error "Plugin system not available"
        return 1
    fi
    
    # No arguments, list plugins
    if [[ $# -eq 0 ]]; then
        echo -e "${YELLOW}Available plugins:${NC}"
        list_plugins
        return 0
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        list|ls)
            echo -e "${YELLOW}Available plugins:${NC}"
            list_plugins
            ;;
        enable)
            if [[ $# -eq 0 ]]; then
                log_error "No plugin ID provided"
                echo "Usage: $(basename "$0") plugin enable <plugin-id>"
                return 1
            fi
            set_plugin_status "$1" 1
            ;;
        disable)
            if [[ $# -eq 0 ]]; then
                log_error "No plugin ID provided"
                echo "Usage: $(basename "$0") plugin disable <plugin-id>"
                return 1
            fi
            set_plugin_status "$1" 0
            ;;
        config|set)
            if [[ $# -lt 3 ]]; then
                log_error "Insufficient arguments for plugin config command"
                echo "Usage: $(basename "$0") plugin config <plugin-id> <key> <value>"
                return 1
            fi
            local plugin_id="$1"
            local key="$2"
            local value="$3"
            set_plugin_setting "$plugin_id" "$key" "$value"
            ;;
        get)
            if [[ $# -lt 2 ]]; then
                log_error "Insufficient arguments for plugin get command"
                echo "Usage: $(basename "$0") plugin get <plugin-id> <key>"
                return 1
            fi
            local plugin_id="$1"
            local key="$2"
            local value
            value=$(get_plugin_setting "$plugin_id" "$key")
            echo -e "${BLUE}${plugin_id}.${key}:${NC} ${GREEN}${value}${NC}"
            ;;
        command|cmd)
            if [[ $# -lt 2 ]]; then
                log_error "Insufficient arguments for plugin command"
                echo "Usage: $(basename "$0") plugin command <plugin-id> <command> [args...]"
                return 1
            fi
            
            local plugin_id="$1"
            local command="$2"
            shift 2
            
            # Check if plugin exists
            local plugin_exists
            plugin_exists=$(query_plugin_db_params -count "SELECT COUNT(*) FROM plugins WHERE id = :plugin_id;" \
                ":plugin_id" "$plugin_id")
            
            if [[ "$plugin_exists" -eq 0 ]]; then
                log_error "Plugin not found: $plugin_id"
                return 1
            fi
            
            # Check if plugin is enabled
            if ! is_plugin_enabled "$plugin_id"; then
                log_error "Plugin $plugin_id is disabled. Enable it first with 'plugin enable $plugin_id'"
                return 1
            fi
            
            # Check if plugin has CLI commands
            local has_cli
            has_cli=$(query_plugin_db_params -count "SELECT has_cli_commands FROM plugins WHERE id = :plugin_id;" \
                ":plugin_id" "$plugin_id")
            
            if [[ "$has_cli" -eq 0 ]]; then
                log_error "Plugin $plugin_id does not provide CLI commands"
                return 1
            fi
            
            # Run the plugin command handler
            run_cli_command_handler "$plugin_id" "$command" "$@"
            return $?
            ;;
        commands)
            # List all available commands from all plugins
            echo -e "${YELLOW}Available plugin commands:${NC}"
            echo
            
            # Get all registered commands
            local registered_commands
            registered_commands=$(get_registered_cli_commands)
            
            if [[ -z "$registered_commands" ]]; then
                echo -e "${GRAY}No plugin commands available${NC}"
                return 0
            fi
            
            # Print them in a table format
            echo -e "${BLUE}PLUGIN ID         COMMAND             DESCRIPTION${NC}"
            echo -e "${BLUE}----------------  ------------------  ------------------------------------------${NC}"
            
            echo "$registered_commands" | while IFS=':' read -r plugin_id cmd desc _; do
                # Format with column alignment
                printf "%-16s  %-18s  %s\n" "$plugin_id" "$cmd" "$desc"
            done
            
            echo
            echo -e "Run commands with: ${GREEN}sshistorian plugin command <plugin-id> <command> [args...]${NC}"
            ;;
        *)
            # Check if this might be a direct plugin command
            local cmd_exists=false
            local registered_commands 
            registered_commands=$(get_registered_cli_commands)
            
            if [[ -n "$registered_commands" ]]; then
                while IFS=':' read -r plugin_id cmd desc handler; do
                    if [[ "$plugin_id" == "$subcommand" && -n "$1" ]]; then
                        # This could be a direct plugin:command call
                        cmd_exists=true
                        run_cli_command_handler "$plugin_id" "$1" "${@:2}"
                        return $?
                    fi
                done <<< "$registered_commands"
            fi
            
            if [[ "$cmd_exists" == "false" ]]; then
                # Unknown subcommand
                log_error "Unknown plugin subcommand: $subcommand"
                echo "Usage: $(basename "$0") plugin [list|enable|disable|config|get|command|commands] [args...]"
                return 1
            fi
            ;;
    esac
    
    return $?
}

# Handle different commands
    case "$1" in
        help|--help|-h)
            show_help
            ;;
        version|--version|-v)
            show_version
            return 0
            ;;
        sessions|list)
            shift
            list_sessions "$@"
            ;;
        replay)
            shift
            if [[ $# -lt 1 ]]; then
                log_error "Missing session ID"
                echo "Usage: $(basename "$0") replay <uuid> [--html]"
                return 1
            fi
            replay_session "$@"
            ;;
        tag)
            shift
            if [[ $# -lt 2 ]]; then
                log_error "Missing arguments"
                echo "Usage: $(basename "$0") tag <uuid> <tag>"
                return 1
            fi
            add_session_tag "$1" "$2"
            ;;
        untag)
            shift
            if [[ $# -lt 2 ]]; then
                log_error "Missing arguments"
                echo "Usage: $(basename "$0") untag <uuid> <tag>"
                return 1
            fi
            remove_session_tag "$1" "$2"
            ;;
        generate-keys)
            # Call the function to generate encryption keys
            generate_encryption_keys
            ;;
        stats)
            show_stats
            ;;
        plugin|plugins)
            shift
            handle_plugin_command "$@"
            ;;
        config)
            shift
            case "${1:-}" in
                edit)
                    # Use preferred editor or fallback to vim/nano
                    local editor="${EDITOR:-}"
                    
                    # Create a temporary configuration file with secure permissions
                    local temp_config
                    temp_config=$(mktemp) || {
                        log_error "Failed to create temporary config file"
                        return 1
                    }
                    
                    # Set secure permissions (0600: only owner can read/write)
                    chmod 600 "$temp_config" || log_warning "Failed to set permissions on temporary config file"
                    
                    # Add to cleanup
                    TEMP_FILES+=("$temp_config")
                    
                    # Extract all configuration values to the temporary file
                    db_execute -csv "SELECT key || '=' || value || ' # ' || description FROM config ORDER BY key;" > "$temp_config"
                    
                    # Add header with instructions
                    {
                        echo "# SSHistorian Configuration"
                        echo "# Edit values after the '=' sign and save to update configuration"
                        echo "# Lines beginning with '#' are ignored"
                        echo
                        cat "$temp_config"
                    } > "${temp_config}.new"
                    mv "${temp_config}.new" "$temp_config"
                    
                    # Find available editor
                    if [[ -z "$editor" ]]; then
                        if command -v nano &>/dev/null; then
                            editor="nano"
                        elif command -v vim &>/dev/null; then
                            editor="vim"
                        elif command -v vi &>/dev/null; then
                            editor="vi"
                        else
                            log_error "No editor found. Please set EDITOR environment variable."
                            echo "Use 'config set <key> <value>' to modify configuration instead."
                            return 1
                        fi
                    fi
                    
                    log_info "Opening configuration in $editor..."
                    # Open the editor
                    "$editor" "$temp_config"
                    
                    # Apply changes if the file was modified
                    if [[ -f "$temp_config" ]]; then
                        log_info "Applying configuration changes..."
                        
                        # Read each line of the config file and apply changes
                        while IFS= read -r line; do
                            # Skip comments and empty lines
                            if [[ "$line" =~ ^[[:space:]]*# || -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
                                continue
                            fi
                            
                            # Extract key and value (ignore comments after the value)
                            local key value
                            key=$(echo "$line" | cut -d= -f1)
                            value=$(echo "$line" | cut -d= -f2- | cut -d'#' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            
                            # Skip if key or value is empty
                            if [[ -z "$key" || -z "$value" ]]; then
                                continue
                            fi
                            
                            # Update the config
                            log_debug "Setting $key=$value"
                            set_config "$key" "$value"
                        done < "$temp_config"
                        
                        log_success "Configuration updated successfully"
                    else
                        log_warning "Config file not found or was removed. No changes applied."
                    fi
                    ;;
                set)
                    shift
                    if [[ $# -lt 2 ]]; then
                        log_error "Missing arguments"
                        echo "Usage: $(basename "$0") config set <key> <value>"
                        return 1
                    fi
                    set_config "$1" "$2"
                    log_success "Configuration updated: $1 = $2"
                    ;;
                get)
                    shift
                    if [[ $# -lt 1 ]]; then
                        log_error "Missing key"
                        echo "Usage: $(basename "$0") config get <key>"
                        return 1
                    fi
                    
                    local key="$1"
                    local value description
                    
                    # Get both value and description for better output
                    value=$(get_config "$key")
                    
                    # If the key was found, fetch its description too
                    if [[ -n "$value" ]]; then
                        description=$(db_execute_params -count "SELECT description FROM config WHERE key = :key LIMIT 1;" \
                            ":key" "$key")
                        echo -e "${BLUE}${key}:${NC}"
                        echo -e "  ${GREEN}${value}${NC}"
                        if [[ -n "$description" ]]; then
                            echo -e "  ${GRAY}(${description})${NC}"
                        fi
                    else
                        log_error "Configuration key '$key' not found"
                        return 1
                    fi
                    ;;
                *)
                    # Show all config values in a well-organized format
                    echo -e "${YELLOW}SSHistorian Configuration${NC}"
                    echo -e "${BLUE}=======================${NC}"
                    echo
                    
                    # Get all configuration data
                    local config_data
                    config_data=$(db_execute -csv "SELECT key, value, description, type FROM config ORDER BY key;" | tr ',' '|')
                    
                    # Define sections and process config values by section
                    declare -a sections=("general" "ssh" "encryption" "compression" "ui")
                    
                    # Find the longest key for nice formatting
                    local max_key_length=0
                    while IFS='|' read -r key value description type; do
                        if (( ${#key} > max_key_length )); then
                            max_key_length=${#key}
                        fi
                    done <<< "$config_data"
                    
                    # Format padding with extra spaces for readability
                    max_key_length=$((max_key_length + 2))
                    
                    # Process each section
                    for section in "${sections[@]}"; do
                        # Print section header with capitalized first letter
                        # Using a more compatible method for capitalization
                        local section_title="$section"
                        section_title="$(tr '[:lower:]' '[:upper:]' <<< "${section_title:0:1}")${section_title:1}"
                        echo -e "${BLUE}● ${section_title} Configuration:${NC}"
                        
                        # Extract and display values for this section
                        local has_values=false
                        while IFS='|' read -r key value description type; do
                            # Check if key belongs to this section
                            if [[ "$key" == "${section}."* ]]; then
                                # Extract the actual setting name without section prefix
                                local setting="${key#${section}.}"
                                # Calculate padding
                                local padding_length=$((max_key_length - ${#setting}))
                                local padding=$(printf '%*s' "$padding_length" '')
                                
                                # Display with nice formatting
                                echo -e "  ${CYAN}${setting}${NC}${padding}${GREEN}${value}${NC} ${GRAY}(${description})${NC}"
                                has_values=true
                            fi
                        done <<< "$config_data"
                        
                        # Only add a newline if we had values in this section
                        if [[ "$has_values" == "true" ]]; then
                            echo
                        fi
                    done
                    ;;
            esac
            ;;
        *)
            # Assume it's an SSH command - Initialize database and pass args to SSH handler
            init_database || return $?
            handle_ssh "$@"
            ;;
    esac
    
    return 0
}

# Setup the cleanup function using trap
cleanup() {
    # Clean up any temporary files
    if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
        log_debug "Cleaning up temporary files"
        rm -f "${TEMP_FILES[@]}" 2>/dev/null || true
    fi
    
    # Exit with provided code or default
    exit "${1:-0}"
}

# Set up the trap for cleanup
trap 'cleanup $?' EXIT
trap 'cleanup 1' INT TERM

# Check dependencies before proceeding
check_dependencies || exit 1

# Export functions
export -f show_help
export -f show_version
export -f show_stats
export -f process_arguments
export -f cleanup