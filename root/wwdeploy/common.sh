#!/usr/bin/env bash

# This script contains common variables and functions to be sourced by other scripts.

# Source OpenHPC and Warewulf variables so they are available to all scripts.
# Note: The paths to these files must be correct relative to the execution directory.
if [ -f /root/openhpc-set-vars.sh ]; then
    source /root/openhpc-set-vars.sh
else
    echo "Warning: /root/openhpc-set-vars.sh not found."
fi

if [ -f /root/warewulf-download-vars.sh ]; then
    source /root/warewulf-download-vars.sh
else
    echo "Warning: /root/warewulf-download-vars.sh not found."
fi


# --- ICONS & Color Palette Setup ---
CM="✔️ "
CROSS="✖️ "

BOLDRED='\033[01;31m' # bold red
RESET='\033[00;00m'   # normal white
BLUE='\033[36m'      # blue
YELLOW='\033[33m'    # yellow
RED_TEXT='\033[31m'  # red text
FGRED='\033[41m'     # red background
FGBLUE='\033[44m'    # blue background
BLARROW="${BLUE} → ${RESET}"
YELLOWCM="${YELLOW} ✔ ${RESET}"


# --- System Info Gathering ---
# This block determines the OS distribution and version.
if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_distro=$NAME
    case "$os_distro" in
        *"Red Hat"*)
            os_version_full=$VERSION_ID
            os_version_major=${VERSION_ID%%.*}
            os_version_minor=${VERSION_ID#*.}
            os_id=$ID
            ;;
        *"Rocky Linux"*)
            os_version_full=$VERSION_ID
            os_version_major=${VERSION_ID%%.*}
            os_version_minor=${VERSION_ID#*.}
            os_id=$ID
            ;;
        *)
            echo -e "${CROSS} Unsupported OS: $os_distro"
            exit 1
            ;;
    esac
else
    echo -e "${CROSS} Cannot determine OS version. /etc/os-release not found."
    exit 1
fi


# --- Supporting Functions for Menus ---

# Advises what option was picked by informational message.
option_picked() {
    MESSAGE=${@:-"${RESET}Error: No message passed"}
    echo -e "\n${BOLDRED}--- ${MESSAGE} ---${RESET}"
}

# Displays a standard informational message to the console.
console_info_msg() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${BLARROW} ${MESSAGE} ${RESET}"
}

# Displays a header for a menu.
echo_menu_header() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${BLUE}************************************************************************************************${RESET}"
	echo -e "           ${YELLOW}${MESSAGE}                                                           ${RESET}"
	echo -e "           ${YELLOW}OS Distro is: $os_distro - Major Release $os_version_major         ${RESET}"
	echo -e "${BLUE}************************************************************************************************${RESET}"
}

# Displays a success message for a completed task.
console_taskcomplete_msg() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${YELLOWCM} ${MESSAGE} ${RESET}"
}

# Displays a message indicating the start of a task.
console_taskstart_msg() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${YELLOW}- ${MESSAGE} ${RESET}"
}

# Displays a failure message and sends it to stderr.
console_fail_msg() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "\n${CROSS} ${FGRED}${MESSAGE} ${RESET}\n" >&2
}

# Pauses the script and waits for the user to press any key.
pause_for_review() {
    read -p "→ Press any key to continue..." fackAnyKey
}
