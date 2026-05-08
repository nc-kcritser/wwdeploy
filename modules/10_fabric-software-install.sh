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

inject_doca_into_image() {
    # Section - Installs DOCA into Compute Node (Prompts for Version, Installs Repo, Install DOCA Edition)
    

    # --- Select container ---
    mapfile -t containers < <(wwctl image list | awk 'NR>1 && !/^-/ {print $1}')
    if [ ${#containers[@]} -eq 0 ]; then
        console_fail_msg "No containers found."
        pause_for_review
        return
    fi

    local PS3="Select container to modify: "
    local container_name=""
    select container_choice in "${containers[@]}" "Cancel"; do
        if [[ "$container_choice" == "Cancel" ]]; then
            console_info_msg "DOCA injection cancelled."
            pause_for_review
            return 0
        elif [[ -n "$container_choice" ]]; then
            container_name="$container_choice"
            break
        else
            echo "Invalid selection."
        fi
    done

    local container_path=$(wwctl image show "${container_name}" | awk '{print $NF}')

    # --- Select DOCA version ---
    PS3="Select DOCA version: "
    local doca_menu=("3.3" "3.2.2 (LTS)" "3.2.1 (LTS)" "3.2.0 (LTS)" "3.1.0" "3.0.0" "2.9.4 (LTS)" "Cancel")
    local DOCA_VER=""

    select choice in "${doca_menu[@]}"; do
        case $choice in
            "Cancel")
                console_info_msg "DOCA injection cancelled."
                pause_for_review
                return 0
                ;;
            *)
                DOCA_VER=$(echo "$choice" | cut -d' ' -f1)
                break
                ;;
        esac
    done

    # --- Configure DOCA repository in container ---
    console_taskstart_msg "Configuring DOCA $DOCA_VER repository in container ${container_name}..."
    export DOCA_VER os_version_major
    mkdir -p "${container_path}/etc/yum.repos.d"
    envsubst < "${DEPLOY_ROOT}/files/doca.repo.template" > "${container_path}/etc/yum.repos.d/doca.repo"
    console_taskcomplete_msg "DOCA repository configured."

    # --- Select DOCA package variant ---
    PS3="Select DOCA package to inject: "
    local doca_pkgs=("doca-basic" "doca-ofed" "doca-networking" "doca-roce" "doca-all" "Cancel")
    local DOCA_PKG=""

    select pkg_choice in "${doca_pkgs[@]}"; do
        case $pkg_choice in
            "Cancel")
                console_info_msg "DOCA injection cancelled."
                pause_for_review
                return 0
                ;;
            *)
                DOCA_PKG="$pkg_choice"
                break
                ;;
        esac
    done

    # --- Detect kernel versions in the container ---
    echo_section_header "KERNEL VERSION DETECTION"

    console_taskstart_msg "Method 1 - wwctl image kernels:"
    wwctl image kernels "${container_name}"

    console_taskstart_msg "Method 2 - /boot search in container:"
    find "${container_path}/boot" -maxdepth 1 -name 'initramfs-*' | sed 's|.*/initramfs-||; s|\.img||'

    # --- Print next-step instructions ---
    echo ""
    echo_section_header "NEXT STEPS - RUN INSIDE CONTAINER SHELL"
    console_info_msg "You will be dropped into the container shell."
    console_info_msg "Run the following commands:"
    echo ""
    echo -e "  ${YELLOW}dnf install -y kernel-devel-\$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | head -1)${RESET}"
    echo -e "  ${YELLOW}dnf install -y ${DOCA_PKG}${RESET}"
    echo ""
    console_info_msg "If DKMS fails, check 'uname -r' vs 'rpm -q kernel' inside the shell."
    console_info_msg "When done: exit the shell, then run 'wwctl image build ${container_name}'"
    echo ""
    read -p "Press Enter to open container shell, or Ctrl+C to cancel..."

    # --- Launch interactive container shell ---
    wwctl image shell "${container_name}" --build=false

    console_taskcomplete_msg "Container shell exited."
    console_info_msg "Remember to: wwctl image build ${container_name}"
    pause_for_review
}

inject_mellanox_ofed_into_image() {
    option_picked "Inject Mellanox OFED into Compute Node Container Image"

    console_fail_msg "Function not yet implemented."
    pause_for_review
}

inject_cornelis_into_image() {
    option_picked "Inject Cornelis Omni-Path into Compute Node Container Image"

    # --- Select container ---
    mapfile -t containers < <(wwctl image list | awk 'NR>1 && !/^-/ {print $1}')
    if [ ${#containers[@]} -eq 0 ]; then
        console_fail_msg "No containers found."
        pause_for_review
        return
    fi

    local PS3="Select container to modify: "
    local container_name=""
    select container_choice in "${containers[@]}" "Cancel"; do
        if [[ "$container_choice" == "Cancel" ]]; then
            console_info_msg "Omni-Path injection cancelled."
            pause_for_review
            return 0
        elif [[ -n "$container_choice" ]]; then
            container_name="$container_choice"
            break
        else
            echo "Invalid selection."
        fi
    done

    console_info_msg "NOTE: Cornelis Omni-Path installation in containers requires:"
    console_info_msg "  - Omni-Path tarball available in /root/ (extract on headnode first)"
    console_info_msg "  - Kernel version in container matches headnode kernel"
    console_info_msg "  - Sufficient disk space in container"
    read -p "Press Enter to proceed, or Ctrl+C to cancel..."

    console_taskstart_msg "Installing Cornelis Omni-Path packages in container ${container_name}..."
    if wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install libpsm2 libfabric; then
        console_taskcomplete_msg "Cornelis Omni-Path base packages installed in ${container_name}."
    else
        console_fail_msg "Failed to install Omni-Path packages in container ${container_name}."
        pause_for_review
        return 1
    fi

    console_info_msg "For full Omni-Path driver installation, please:"
    console_info_msg "  1. Extract CornelisOPX-*.tgz on headnode"
    console_info_msg "  2. Mount the directory in container or copy files"
    console_info_msg "  3. Run ./INSTALL inside container"
    console_info_msg "Remember to rebuild the container for changes to take effect."
    pause_for_review
}

install_mellanox_ofed() {
    option_picked "Install Mellanox OFED on Headnode from Local Tarball"

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

    # --- Install kernel headers (required for DKMS compilation) ---
    console_taskstart_msg "Installing kernel headers and development packages..."
    if ! dnf install -y kernel-devel kernel-headers; then
        console_fail_msg "Failed to install kernel headers. OFED installation requires these packages."
        pause_for_review
        return 1
    fi
    console_taskcomplete_msg "Kernel headers installed."

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

	# Install prerequisite packages (including kernel headers for DKMS compilation)
	console_taskstart_msg "Installing prerequisite packages..."
	if ! dnf install -y kernel-devel kernel-headers kernel-abi-stablelists atlas; then
		console_fail_msg "Failed to install prerequisite packages."
		pause_for_review
		return 1
	fi
	console_taskcomplete_msg "Prerequisite packages installed."

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

fabric_software_menu() {
    local option
    while true; do
        echo_menu_header "Fabric Software Installation"
        echo_section_header "HEADNODE INSTALLATION"
        echo " 1) Install DOCA from Online Repository"
        echo " 2) Install DOCA from Downloaded RPM"
        echo " 3) Install Mellanox OFED from Local Source/Tarball"
        echo " 4) Install Cornelis Omni-Path from Local Source/Tarball"
        echo ""
        echo_section_header "COMPUTE NODE IMAGE - INJECT FABRIC"
        echo " 5) Inject DOCA into Container Image"
        echo " 6) Inject Mellanox OFED into Container Image"
        echo " 7) Inject Cornelis Omni-Path into Container Image"
        echo ""
        echo " 0) Return to main menu"
        read -r -p "=> " option
        case $option in
            1) option_picked "Install DOCA from Online Repository"; install_doca_online ;;
            2) option_picked "Install DOCA from Downloaded RPM"; install_doca_rpm ;;
            3) option_picked "Install Mellanox OFED on Headnode"; install_mellanox_ofed ;;
            4) option_picked "Install Cornelis Omni-Path on Headnode"; install_omnipath ;;
            5) option_picked "Inject DOCA into Compute Node Container Image"; inject_doca_into_image ;;
            6) option_picked "Inject Mellanox OFED into Container Image"; inject_mellanox_ofed_into_image ;;
            7) option_picked "Inject Cornelis Omni-Path into Container Image"; inject_cornelis_into_image ;;
            0) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Module runs its own menu and exits
fabric_software_menu
