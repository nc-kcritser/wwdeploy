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

    # --- Kernel Update Warning ---
    console_fail_msg "⚠️  WARNING: Kernel updates must be completed BEFORE installing DOCA."
    console_info_msg "If the kernel was recently updated, you MUST reboot before proceeding with DOCA installation."
    console_info_msg "Proceeding without a reboot after kernel updates will cause installation failures."
    read -p "Press Enter to continue, or Ctrl+C to cancel..."

    # --- Select DOCA version ---
    
    local PS3="Select DOCA version: "
    local doca_menu=("3.3" "3.2.2 (LTS)" "3.2.1 (LTS)" "3.2.0 (LTS)" "3.1.0" "3.0.0" "2.9.4 (LTS)" "Cancel")
    local DOCA_VER=""

    select choice in "${doca_menu[@]}"; do
        case $choice in
            "Cancel")
                console_info_msg "DOCA installation cancelled."
                return 0
                ;;
            *)
                # Extract version number only (e.g., "3.2.2" from "3.2.2 (LTS)")
                DOCA_VER=$(echo "$choice" | cut -d' ' -f1)
                break
                ;;
        esac
    done

    console_info_msg "Adding DOCA $DOCA_VER online repository..."
    export DOCA_VER os_version_major
    envsubst < "${DEPLOY_ROOT}/files/doca.repo.template" > /etc/yum.repos.d/doca.repo

    console_taskcomplete_msg "DOCA repository added."

    # --- Select DOCA package variant ---
    local PS3="Select DOCA package to install: "
    local doca_pkgs=("doca-basic" "doca-ofed" "doca-networking" "doca-roce" "doca-all" "Cancel")
    local DOCA_PKG=""

    select pkg_choice in "${doca_pkgs[@]}"; do
        case $pkg_choice in
            "Cancel")
                console_info_msg "DOCA package installation cancelled."
                return 0
                ;;
            *)
                DOCA_PKG="$pkg_choice"
                break
                ;;
        esac
    done

    console_info_msg "Installing $DOCA_PKG from online repository..."

    if dnf install -y "$DOCA_PKG"; then
        console_taskcomplete_msg "DOCA package installation from online repository complete."
    else
        console_fail_msg "Failed to install $DOCA_PKG from online repository. Check your network and repository access."
        pause_for_review
        return 1
    fi

    pause_for_review
}

install_doca_rpm() {
    option_picked "Install DOCA from Downloaded RPM"

    # --- Kernel Update Warning ---
    console_fail_msg "⚠️  WARNING: Kernel updates must be completed BEFORE installing DOCA."
    console_info_msg "If the kernel was recently updated, you MUST reboot before proceeding with DOCA installation."
    console_info_msg "Proceeding without a reboot after kernel updates will cause installation failures."
    read -p "Press Enter to continue, or Ctrl+C to cancel..."

    # --- Find Downloaded RPM ---
    local FILENAME="doca-*.rpm"
    local found_file
    found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
    if [ -z "${found_file}" ]; then
        console_fail_msg "RPM matching '$FILENAME' not found in /root. Please download the file and run this again."
        pause_for_review
        return 1
    fi

    # --- Install RPM using DNF ---
    console_info_msg "Installing DOCA base RPM: ${found_file}..."
    if ! dnf localinstall -y "${found_file}"; then
        console_fail_msg "DNF command failed to install DOCA RPM. See errors above."
        pause_for_review
        return 1
    fi

    console_taskcomplete_msg "DOCA base RPM installation complete."

    # --- Select DOCA package variant ---
    local PS3="Select DOCA package to install: "
    local doca_pkgs=("doca-basic" "doca-ofed" "doca-networking" "doca-roce" "doca-all" "Cancel")
    local DOCA_PKG=""

    select pkg_choice in "${doca_pkgs[@]}"; do
        case $pkg_choice in
            "Cancel")
                console_info_msg "DOCA package installation skipped."
                pause_for_review
                return 0
                ;;
            *)
                DOCA_PKG="$pkg_choice"
                break
                ;;
        esac
    done

    console_info_msg "Installing $DOCA_PKG from repository..."

    if dnf install -y "$DOCA_PKG"; then
        console_taskcomplete_msg "DOCA package installation complete."
    else
        console_fail_msg "Failed to install $DOCA_PKG from repository."
        pause_for_review
        return 1
    fi

    pause_for_review
}

install_mellanox_ofed() {
    option_picked "Install Mellanox OFED from Local Tarball"

    # --- Kernel Update Warning ---
    console_fail_msg "⚠️  WARNING: Kernel updates must be completed BEFORE installing Mellanox OFED."
    console_info_msg "If the kernel was recently updated, you MUST reboot before proceeding with OFED installation."
    console_info_msg "Proceeding without a reboot after kernel updates will cause installation failures."
    read -p "Press Enter to continue, or Ctrl+C to cancel..."

    # --- Find Downloaded OFED Tarball ---
    local FILENAME="MLNX_OFED_LINUX*.tgz"
    local found_file
    found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
    if [ -z "${found_file}" ]; then
        console_fail_msg "OFED tarball matching '$FILENAME' not found in /root. Please download the file and run this again."
        pause_for_review
        return 1
    fi

    # --- Ask about OpenSM ---
    console_info_msg "Do you want to enable OpenSM support? (y/n)"
    read -r enable_opensm_flag
    local opensm_flag=""
    if [[ "$enable_opensm_flag" =~ ^[Yy]$ ]]; then
        opensm_flag="--enable-opensm"
    fi

    console_info_msg "Extracting OFED from Tarball: ${found_file}..."
    tar zxf "${found_file}" -C /tmp

    local dir_count
    dir_count=$(find /tmp -maxdepth 1 -type d -name 'MLNX_OFED_LINUX*' | wc -l)

    if [ "$dir_count" -ne 1 ]; then
        console_fail_msg "Found $dir_count directories matching 'MLNX_OFED_LINUX*' in /tmp."
        console_info_msg "Please clean up /tmp so there is only 0 or 1 OFED directories and run this again."
        console_info_msg "---> There's probably a leftover log directory from a previous install. Clean that up first."
        pause_for_review
        return 2
    else
        console_info_msg "Found one OFED directory, changing directory..."
        cd /tmp/MLNX_OFED_LINUX* || return 1
    fi

    # --- Show the installer command ---
    local install_cmd="./mlnxofedinstall --skip-distro-check --without-32bit --without-fw-update --kmp $opensm_flag -q"
    console_info_msg "Running installer:"
    echo "  ${YELLOW}${install_cmd}${RESET}"
    read -p "Press Enter to proceed with installation, or Ctrl+C to cancel..."

    # --- Run the installer ---
    if ! $install_cmd; then
        console_fail_msg "OFED installation failed. See errors above."
        pause_for_review
        cd /tmp || return 1
        rm -rf MLNX_OFED_LINUX* ofed.conf.save ofed.conf
        return 1
    fi

    console_taskcomplete_msg "Mellanox OFED installation complete."

    # --- Handle OpenSM service if enabled ---
    if [[ "$enable_opensm_flag" =~ ^[Yy]$ ]]; then
        console_info_msg "Enabling OpenSM service..."
        if systemctl enable --now opensmd; then
            console_taskcomplete_msg "OpenSM service is now enabled and running."
        else
            console_fail_msg "Failed to enable OpenSM service. Please check the service status."
            pause_for_review
        fi
    fi

    # Clean up the installation files
    cd /tmp || return 1
    rm -rf MLNX_OFED_LINUX* ofed.conf.save ofed.conf

    pause_for_review
}

install_omnipath() {
    option_picked "Install Cornelis Networks Omni-Path"

    # --- Kernel Update Warning ---
    console_fail_msg "⚠️  WARNING: Kernel updates must be completed BEFORE installing Omni-Path."
    console_info_msg "If the kernel was recently updated, you MUST reboot before proceeding with Omni-Path installation."
    console_info_msg "Proceeding without a reboot after kernel updates will cause installation failures."
    read -p "Press Enter to continue, or Ctrl+C to cancel..."

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
