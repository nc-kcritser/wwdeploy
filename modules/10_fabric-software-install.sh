#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.
# 'common.sh' should contain the color variables and helper functions.
# If common.sh is not found, the script will exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common.sh" ]; then
    source "${SCRIPT_DIR}/../common.sh"
else
    echo "Error: common.sh not found in parent directory."
    exit 1
fi

# --- Fabric Software Installation Functions ---

install_doca_online() {
    option_picked "Install DOCA from Online Repository"

    console_info_msg "Adding DOCA online repository..."
    cat << EOF > /etc/yum.repos.d/doca.repo
[doca]
name=DOCA Online Repo
baseurl=https://linux.mellanox.com/public/repo/doca/${DOCA_VER}/rhel${os_version_major}/x86_64/
enabled=1
gpgcheck=0
EOF

    console_taskcomplete_msg "DOCA repository added."
    console_info_msg "Installing DOCA host packages from online repository..."

    if dnf install -y doca-host; then
        console_taskcomplete_msg "DOCA host installation from online repository complete."
    else
        console_fail_msg "Failed to install DOCA from online repository. Check your network and repository access."
        pause_for_review
        return 1
    fi

    pause_for_review
}

install_doca_rpm() {
    option_picked "Install DOCA from Downloaded RPM"

    # --- Find Downloaded RPM ---
    local FILENAME="doca-host-3.0.0*.rpm"
    local found_file
    found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
    if [ -z "${found_file}" ]; then
        console_fail_msg "RPM matching '$FILENAME' not found in /root."
        console_info_msg "Attempting to download DOCA Host RPM..."
        if ! wget -nc "$MLNX_DOCA_OFED_3_DL_URL"; then
            console_fail_msg "Download failed. Check URL and network."
            pause_for_review
            return 1
        fi
        found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
        if [ -z "${found_file}" ]; then
            console_fail_msg "RPM still not found after download attempt."
            pause_for_review
            return 1
        fi
    fi

    # --- Install RPM using DNF ---
    console_info_msg "Installing DOCA from RPM: ${found_file}..."
    if ! dnf localinstall -y "${found_file}"; then
        console_fail_msg "DNF command failed to install DOCA RPM. See errors above."
        pause_for_review
        return 1
    fi

    console_taskcomplete_msg "DOCA RPM installation complete."
    pause_for_review
}

install_mellanox_ofed() {
    option_picked "Install Mellanox OFED"

    # Get the OS minor version (e.g., 4 from 9.4)
    local os_version_minor
    os_version_minor=$(echo "$os_version_full" | cut -d'.' -f2)

    # --- Build the dynamic menu for OFED versions ---
    local PS3="Please choose an OFED version to install: "
    local options=()

    if (( os_version_minor <= 4 )); then
        options+=("OFED 23.10 (for RHEL/Rocky <= 9.4)")
    fi
    if (( os_version_minor >= 5 )); then
        options+=("OFED 24.10 (for RHEL/Rocky 9.5+)")
    fi
    options+=("Quit")

    # --- Get user's choice ---
    local DOWNLOAD_URL=""
    local FILENAME=""
    select choice in "${options[@]}"; do
        case $choice in
            "OFED 23.10"*)
                DOWNLOAD_URL="$MLNX_OFED_2310_DL_URL"
                FILENAME="MLNX_OFED_LINUX-23.10*.tgz"
                break
                ;;
            "OFED 24.10"*)
                DOWNLOAD_URL="$MLNX_OFED_2410_DL_URL"
                FILENAME="MLNX_OFED_LINUX-24.10*.tgz"
                break
                ;;
            "Quit")
                console_info_msg "Aborting installation."
                return 0
                ;;
            *)
                console_fail_msg "Invalid option. Please try again."
                ;;
        esac
    done

    # --- Download and Install Selected OFED Version ---
    console_taskstart_msg "Attempting to download file - $DOWNLOAD_URL"
    if ! wget -nc -P /root "$DOWNLOAD_URL"; then
        console_fail_msg "Download failed. Check URL and network."
        pause_for_review
        return 1
    fi

    local found_file
    found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
    if [ -z "${found_file}" ]; then
        console_fail_msg "Tarball matching '$FILENAME' not found in /root."
        pause_for_review
        return 1
    fi

    console_info_msg "Installing OFED from Tarball: ${found_file}..."

	# Extract the tarball to /tmp
    tar zxf "${found_file}" -C /tmp

	local dir_count
	dir_count=$(find /tmp -maxdepth 1 -type d -name 'MLNX_OFED_LINUX*' | wc -l)

	if [ "$dir_count" -ne 1 ]; then
		console_fail_msg "Found $dir_count directories matching 'MLNX_OFED_LINUX*' in /tmp."
		console_info_msg "Please clean up /tmp so there is only 0 or 1 OFED directories and run this again."
		console_info_msg "---> There's probably a leftover log directory from a previous install. Clean that up first."
		pause_for_review
		# Exit the function if there are multiple directories
		return 2
	else
		# This command is now safe because we know the wildcard will only match one directory
		console_info_msg "Found one OFED directory, changing directory..."
		cd /tmp/MLNX_OFED_LINUX* || return 1
	fi
    ./mlnxofedinstall --skip-distro-check --without-32bit --without-fw-update --kmp --enable-opensm -q
	pause_for_review

	# Prompt the user to see if they want to enable OpenSM service
	console_info_msg "Do you want to enable the OpenSM service? (y/n)"
	read -r enable_opensm
	if [[ "$enable_opensm" =~ ^[Yy]$ ]]; then
		console_info_msg "Enabling OpenSM service..."
		systemctl enable --now opensmd
		if systemctl is-active --quiet opensmd; then
			console_taskcomplete_msg "OpenSM service is now enabled and running."
		else
			console_fail_msg "Failed to enable OpenSM service. Please check the service status."
			pause_for_review
			return 1
		fi
	else
		console_info_msg "OpenSM service will not be enabled. You can enable it later with 'systemctl enable --now opensmd'."
	fi

	# Clean up the installation files
    cd /tmp || return 1
    rm -rf MLNX_OFED_LINUX* ofed.conf.save ofed.conf

    console_taskcomplete_msg "Mellanox OFED installation complete."
    pause_for_review
}

install_omnipath() {
    option_picked "Install Cornelis Networks Omni-Path"
	mkdir -p /opt/ohpc/pub/apps/cornelis/{RPM,firmware}
	cornelis_file=$(find /root -maxdepth 1 -name 'CornelisOPX*.tgz' -print -quit)
	if [ -z "${cornelis_file}" ];then
		console_fail_msg "Cornelis Networks Omni-Path tarball not found in /root. Please download the file and run this again."
		pause_for_review
		return 1
	fi

	# Install prerequisite RPMs
	dnf install -y kernel-abi-stablelists atlas

    cd /tmp || return 1
	tar zxf "${cornelis_file}"
    cornelis_working_dir=$(basename "${cornelis_file}" .tgz)
	cd "${cornelis_working_dir}" || return 1
    # Move firmware RPMs before install, if they exist
    mv hfi1*.rpm /opt/ohpc/pub/apps/cornelis/RPM/ 2>/dev/null
	./INSTALL -a
	cd /tmp || return 1
	rm -rf "${cornelis_working_dir}"

	# Install firmware RPMs if any were found
    if ls /opt/ohpc/pub/apps/cornelis/RPM/*.rpm 1> /dev/null 2>&1; then
	    dnf localinstall -y /opt/ohpc/pub/apps/cornelis/RPM/*.rpm
    fi
    console_taskcomplete_msg "Cornelis Omni-Path installation complete."
	pause_for_review
}

# --- Sub-Menu for this script ---
show_fabric_software_menu() {
    while true; do
        clear
        echo_menu_header "Fabric Software Installation Menu"
        echo -e "  ${YELLOW}1)${BLUE} DOCA (Online Repository) ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} DOCA (Downloaded RPM) ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Mellanox OFED ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Cornelis Omni-Path ${RESET}"
        echo -e "  ${YELLOW}0)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}*************************************************${RESET}"
        read -p "Enter your choice: " fabric_choice

        case $fabric_choice in
            1) install_doca_online ;;
            2) install_doca_rpm ;;
            3) install_mellanox_ofed ;;
            4) install_omnipath ;;
            0) break ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script Execution Starts Here ---
show_fabric_software_menu
