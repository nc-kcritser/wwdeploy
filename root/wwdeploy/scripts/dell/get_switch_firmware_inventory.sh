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

# Function to execute SSH command and retrieve output
execute_ssh_command() {
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$HOSTNAME" "$1" 2>/dev/null
}

# Get inventory information from the switch via SSH
inventory_output=$(execute_ssh_command "show inventory")

# Check if the command was successful
if [ -z "$inventory_output" ]; then
    echo "Failed to retrieve inventory information from $HOSTNAME"
    exit 1
fi

# Extract firmware version and service tag from the inventory output and then output.
firmware_version=$(echo "$inventory_output" | grep 'Software version' | awk -F: '{print $2}' | xargs)
service_tag=$(echo "$inventory_output" | grep -A 2 'Unit Type' | grep '*' | awk '{print $7}' | xargs)

# Output the results to screen. 
echo "Host/IP    : $HOSTNAME"
echo "OS Version : $firmware_version"
echo "Service Tag: $service_tag"