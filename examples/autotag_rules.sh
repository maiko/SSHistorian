#!/usr/bin/env bash
#
# SSHistorian - Auto Tag Plugin Custom Rules Example
# Custom tagging rules for the Auto Tag plugin
#
# This file is sourced by the Auto Tag plugin when custom rules are enabled.
# It has access to the following variables:
#   - SESSION_ID: The UUID of the current session
#   - HOSTNAME: The hostname of the SSH target
#   - REMOTE_USER: The remote username (if available)
#   - COMMAND: The full SSH command
#
# The apply_tag function is available to add tags:
#   apply_tag <tag_name> <reason>
#
# NOTE: This file is executed in a subshell, so any variables or functions
# defined here are not available outside this file.

# Tag based on hostname patterns

# Database servers
if [[ "$HOSTNAME" == *"db"* || "$HOSTNAME" == *"database"* || "$HOSTNAME" == *"mysql"* || "$HOSTNAME" == *"postgres"* ]]; then
    apply_tag "server_database" "Hostname contains database indicator"
fi

# Web servers
if [[ "$HOSTNAME" == *"web"* || "$HOSTNAME" == *"www"* || "$HOSTNAME" == *"nginx"* || "$HOSTNAME" == *"apache"* ]]; then
    apply_tag "server_web" "Hostname contains web server indicator"
fi

# Application servers
if [[ "$HOSTNAME" == *"app"* || "$HOSTNAME" == *"application"* ]]; then
    apply_tag "server_application" "Hostname contains application server indicator"
fi

# Tag based on IP address ranges
if [[ "$HOSTNAME" =~ ^10\.0\.[0-9]+\.[0-9]+$ ]]; then
    apply_tag "network_internal" "IP in 10.0.x.x range (internal network)"
fi

if [[ "$HOSTNAME" =~ ^192\.168\.[0-9]+\.[0-9]+$ ]]; then
    apply_tag "network_local" "IP in 192.168.x.x range (local network)"
fi

# Tag based on command parameters
if [[ "$COMMAND" == *"-p 2222"* ]]; then
    apply_tag "custom_port" "Using non-standard SSH port"
fi

if [[ "$COMMAND" == *"-i"* && "$COMMAND" == *".pem"* ]]; then
    apply_tag "key_authentication" "Using PEM key authentication"
fi

# Tag based on remote user and specific hostname combinations
if [[ "$REMOTE_USER" == "admin" && "$HOSTNAME" == *"prod"* ]]; then
    apply_tag "admin_production" "Admin user on production server"
fi

# Example of more complex logic
if [[ "$REMOTE_USER" == "deploy" ]]; then
    # Deployment user typically means a deployment operation
    apply_tag "operation_deployment" "Using deployment user"
    
    # Check if this is for a specific project based on hostname
    if [[ "$HOSTNAME" == *"project-x"* ]]; then
        apply_tag "project_x" "Deployment to Project X server"
    elif [[ "$HOSTNAME" == *"project-y"* ]]; then
        apply_tag "project_y" "Deployment to Project Y server"
    fi
fi

# Tag based on day of week (weekend operations often need special attention)
current_day=$(date +%u)  # 1-7, where 1 is Monday
if [[ "$current_day" -ge 6 ]]; then
    apply_tag "time_weekend" "Operation performed on weekend"
fi

# Tag based on time of day
current_hour=$(date +%H)  # 00-23
if [[ "$current_hour" -ge 22 || "$current_hour" -le 6 ]]; then
    apply_tag "time_night" "Operation performed during night hours"
fi