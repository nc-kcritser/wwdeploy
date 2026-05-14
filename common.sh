#!/usr/bin/env bash

# This script contains common variables and functions to be sourced by other scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DEPLOY_ROOT can be set by the caller; if not set, derive it from this script's location
if [ -z "$DEPLOY_ROOT" ]; then
    DEPLOY_ROOT="$SCRIPT_DIR"
fi
export DEPLOY_ROOT

if [ -f "${SCRIPT_DIR}/site-config.sh" ]; then
    source "${SCRIPT_DIR}/site-config.sh"
else
    echo "Warning: site-config.sh not found in ${SCRIPT_DIR}."
fi

if [ -f "${SCRIPT_DIR}/reference_external_downloads.config" ]; then
    source "${SCRIPT_DIR}/reference_external_downloads.config"
else
    echo "Warning: reference_external_downloads.config not found in ${SCRIPT_DIR}."
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
    os_version_update="${os_version_major}u${os_version_minor}"
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
	echo -e "           ${YELLOW}OS Distro is: $os_distro - Release $os_version_update             ${RESET}"
	echo -e "${BLUE}************************************************************************************************${RESET}"
}

# Displays a section header within a menu (e.g., to separate groups of options).
echo_section_header() {
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${YELLOW}=== ${MESSAGE} ===${RESET}"
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

# Displays command output with formatted header and footer.
show_command_output() {
	local command="$1"
	echo -e "${BLUE}*** Command Output: ${YELLOW}${command}${RESET}"
	echo -e "${BLUE}-----------------------------------------------------------------${RESET}"
	eval "$command"
	echo -e "${BLUE}-----------------------------------------------------------------${RESET}"
}

# Base packages for Warewulf container images
BASE_PACKAGES_CONTAINER="bash coreutils glibc-langpack-en ignition e2fsprogs xfsprogs parted gdisk bind-utils ethtool filesystem findutils gawk grep initscripts iproute iputils net-tools mtr nfs-utils pam psmisc rsync pdsh bc sed setup shadow-utils rsyslog chrony tzdata ntpstat words zlib tar less gzip which util-linux openssh-clients openssh-server dhclient pciutils vim-minimal strace cronie crontabs cpio wget ipmitool yum NetworkManager kernel kernel-devel perl libnl3 tcl tk lsof gcc-gfortran numactl-libs hwloc hwloc-libs lshw hostname dmidecode"
export BASE_PACKAGES_CONTAINER
OHPC_PACKAGES_CONTAINER="ohpc-base-compute ohpc-slurm-client nhc-ohpc lmod-ohpc"
export OHPC_PACKAGES_CONTAINER