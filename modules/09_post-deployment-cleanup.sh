#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common.sh" ]; then
    source "${SCRIPT_DIR}/../common.sh"
else
    echo "Error: common.sh not found in parent directory."
    exit 1
fi

# --- Main Cleanup Function ---

run_cleanup() {
    option_picked "Post-Deployment Cleanup"
    echo -e "${YELLOW}This will remove all downloaded tarballs, ISOs, and runfiles from /root.${RESET}"
    read -p "Are you absolutely sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "Cleanup cancelled by user."
        pause_for_review
        return
    fi

    console_info_msg "Cleaning up installation files from /root..."
    
    # Remove the extracted dell directory if it exists
    if [ -d "/root/dell" ]; then
        rm -rf /root/dell
        console_taskcomplete_msg "Removed /root/dell directory."
    fi

    # Remove downloaded artifacts using a glob pattern
    rm -f /root/dell_bright_*.tgz /root/l_*.sh /root/intel-oneapi*.sh /root/cuda_*.run /root/hpcx*.tbz /root/MLNX_OFED*.tgz /root/CornelisOPX*.tgz /root/OM-SrvAdmin-Dell*.gz /root/R*.iso
    
    console_taskcomplete_msg "Cleanup of /root directory is complete."
    pause_for_review
}

# --- Script execution starts here ---
run_cleanup
