#!/usr/bin/env bash

# Modify these Variables if Needed for the environment
USERNAME="admin"
PASSWORD="admin"

# Check to see if we have a single argument (the hostname or IP)
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

HOSTNAME="$1"

# This function does the heavy lifting to execute SSH command and retrieve output
execute_ssh_command() {
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$HOSTNAME" "$1" 2>/dev/null
}

# Capture the output of the running config command
timestamp=$(date +"%Y%m%d_%H%M%S")
running_config=$(execute_ssh_command "show running-configuration | no-more")
output_file="${HOSTNAME}_os10_runningconfig_${timestamp}.txt"

# Save the running configuration to the file
echo "$running_config" > "$output_file"

# Finished .... 
echo "Running configuration saved to $output_file"
