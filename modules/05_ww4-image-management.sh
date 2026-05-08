#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common.sh" ]; then
    source "${SCRIPT_DIR}/../common.sh"
else
    echo "Error: common.sh not found in parent directory."
    exit 1
fi

# --- Reusable Helper Functions ---

set_container_root_password() {
    local container_name=$1
    option_picked "Set Root Password for ${container_name}"

    if [ -z "$image_pw" ]; then
        console_fail_msg "The 'image_pw' variable is not set in your customer_set_vars.sh file."
        pause_for_review
        return 1
    fi

    read -p "This will set the root password in container '${container_name}' to '${image_pw}'. Are you sure? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "Password change cancelled."
        pause_for_review
        return 1
    fi

    console_taskstart_msg "Generating password hash..."
    local password_hash=$(echo "${image_pw}" | openssl passwd -1 -stdin)

    console_taskstart_msg "Applying password to container..."
    if wwctl container exec "${container_name}" --build=false -- /sbin/usermod -p '${password_hash}' root; then
        console_taskcomplete_msg "Root password has been set in container '${container_name}'."
        console_info_msg "Remember to rebuild the container image for the change to take effect."
    else
        console_fail_msg "Failed to set root password in container."
    fi
    pause_for_review
}

configure_container_post_import() {
    ## Configures the Required Minimal Packages, Password, and OpenHPC Packages.
    local container_name=$1
    local container_path=$(wwctl image show "${container_name}" | awk '{print $NF}')

    console_taskstart_msg "Syncing user/group info for ${container_name}..."
    wwctl container syncuser --write "${container_name}"

    console_taskstart_msg "Enabling EPEL repository in ${container_name}..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${EPEL_URL} || true

    console_taskstart_msg "Enabling OpenHPC repository in ${container_name}..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${OpenHPC3_DL} || true

    console_taskstart_msg "Installing prerequisite base packages in ${container_name}..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${BASE_PACKAGES_CONTAINER}

    console_taskstart_msg "Installing OpenHPC packages in ${container_name}..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${OHPC_PACKAGES_CONTAINER}

    # Check if Ganglia is installed on the headnode
    if rpm -q ganglia-gmond &>/dev/null; then
        read -p "Ganglia is installed on the headnode. Do you want to install ganglia-gmond in the container? (y/n)? " install_ganglia
        if [[ "$install_ganglia" =~ ^[Yy]$ ]]; then
            console_taskstart_msg "Installing Ganglia monitoring packages in ${container_name}..."
            wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ganglia-gmond
        else
            console_info_msg "Skipping Ganglia installation in container."
        fi
    fi

    # Configure services (direct file manipulation in CHROOT)
    #console_taskstart_msg "Configuring DNS in ${container_name}..." - #### THIS MIGHT BE HANDLED WITH TAGS NOW.
    #perl -pi -e "s/nameserver .*/nameserver $sms_ip/" "${container_path}/etc/resolv.conf"

    console_taskstart_msg "Configuring chrony in ${container_name}..."
    perl -pi -e "s/pool .*/server $sms_name iburst/" "${container_path}/etc/chrony.conf"

    console_taskstart_msg "Configuring rsyslog forwarding in ${container_name}..."
    echo "*.* @${sms_ip}:514" >> "${container_path}/etc/rsyslog.conf"

    console_taskstart_msg "Configuring security limits in ${container_name}..."
    echo '* soft memlock unlimited' >> "${container_path}/etc/security/limits.conf"
    echo '* hard memlock unlimited' >> "${container_path}/etc/security/limits.conf"

    # Enable services via chroot
    console_taskstart_msg "Enabling services in ${container_name}..."
    chroot "${container_path}" /usr/bin/systemctl enable chronyd munge slurmd
    if [[ "$install_ganglia" =~ ^[Yy]$ ]]; then
        chroot "${container_path}" /usr/bin/systemctl enable gmond
    fi

    # Set root password
    set_container_root_password "${container_name}"

    console_taskstart_msg "Building bootable image for ${container_name}..."
    wwctl container build "${container_name}"

    console_taskcomplete_msg "Container '${container_name}' configured and built successfully."
}

configure_container_selinux() {
    local container_chroot=$1
    local selinux_config_path="${container_chroot}/etc/selinux/config"

    if [ -f "${selinux_config_path}" ]; then
        console_info_msg "SELinux configuration detected in the container."
        read -p "Do you want to change the SELinux mode? (y/n): " change_selinux
        if [[ "$change_selinux" =~ ^[Yy]$ ]]; then
            PS3="Select the new SELinux mode: "
            options=("enforcing" "permissive" "disabled")
            select new_mode in "${options[@]}"; do
                if [[ -n "$new_mode" ]]; then
                    console_taskstart_msg "Setting SELinux mode to '${new_mode}'..."
                    sed -i "s/^SELINUX=.*/SELINUX=${new_mode}/" "${selinux_config_path}"
                    console_taskcomplete_msg "SELinux mode set in container."
                    break
                else
                    console_fail_msg "Invalid selection."
                fi
            done
        fi
    else
        console_info_msg "No SELinux configuration file found in container. Skipping SELinux configuration."
    fi
}


# --- Warewulf Image Management Functions ---

create_new_container_from_local_repo() {
    option_picked "Create New Warewulf Container from Local Repo"
    
    read -e -p "Enter name for the new container (e.g., rocky9-compute): " -i "$os_id$os_version_full" container_name
    if [ -z "$container_name" ]; then
        console_fail_msg "Container name cannot be empty."
        pause_for_review
        return 1
    fi

    # Check for existing container to prevent overwrite
    if wwctl container list | grep -q "^${container_name}\s"; then
        console_fail_msg "A container named '${container_name}' already exists."
        pause_for_review
        return 1
    fi

    local CHROOT="/tmp/image/${container_name}"
    # Clean up any previous failed attempts
    if [ -d "$CHROOT" ]; then
        console_info_msg "Removing existing temporary directory: $CHROOT"
        rm -rf "$CHROOT"
    fi
    mkdir -p "$CHROOT"

    # Define base packages with OS-specific additions
    local base_packages="basesystem ${BASE_PACKAGES_CONTAINER}"

    # Add OS-specific packages
    case "$os_id-$os_version_major" in
        "rhel-9") base_packages+=" ignition" ;;
        "rocky-9") base_packages+=" ignition rocky-release" ;;
        "rhel-8") base_packages+=" chkconfig" ;;
        "rocky-8") base_packages+=" chkconfig rocky-release" ;;
    esac

    console_taskstart_msg "Installing base OS into container image for $os_id-$os_version_major"
    yum -y --releasever "$os_version_full" --installroot "$CHROOT" install ${base_packages}
    if [ $? -ne 0 ]; then
        console_fail_msg "Yum install failed. Cleaning up temporary directory."
        rm -rf "/tmp/image"
        pause_for_review
        return 1
    fi

    # Copy necessary repo files into the chroot for further installs
    console_taskstart_msg "Copying repo files into the container"
    cp /etc/yum.repos.d/epel.repo "$CHROOT/etc/yum.repos.d/"
    cp /etc/yum.repos.d/OpenHPC.repo "$CHROOT/etc/yum.repos.d/" 2>/dev/null # May not exist yet
    cp /etc/yum.repos.d/$os_id$os_version_full-offline.repo "$CHROOT/etc/yum.repos.d/"

    # Configure SELinux in the container
    configure_container_selinux "$CHROOT"

    # Import and configure the container
    console_taskstart_msg "Importing container into Warewulf..."
    wwctl container import "$CHROOT" "$container_name"

    # Cleanup CHROOT before post-import configuration
    console_taskstart_msg "Cleaning up temporary directory..."
    rm -rf "/tmp/image"

    # Run post-import configuration (OHPC, services, password, build)
    configure_container_post_import "${container_name}"
    pause_for_review
}

download_container_image() {
    option_picked "Download Container from Registry"
    
    local image_uri
    local container_name
    
    PS3="Select an image source: "
    options=("Warewulf Rocky Linux (GHCR)" "Custom URI" "Cancel")
    select opt in "${options[@]}"; do
        case $opt in
            "Warewulf Rocky Linux (GHCR)")
                read -e -p "Enter the Rocky Linux version tag (ex: 9.4, 9.5): " version_tag
                if [ -z "$version_tag" ]; then
                    console_fail_msg "Version tag cannot be empty."
                    pause_for_review
                    break
                fi
                image_uri="docker://ghcr.io/warewulf/warewulf-rockylinux:${version_tag}"
                read -e -p "Enter a local name for this container (e.g., rocky-${version_tag}): " container_name
                break
                ;;
            "Custom URI")
                read -e -p "Enter the full image URI (e.g., docker://rockylinux/rockylinux:9): " image_uri
                read -e -p "Enter the local name for this container: " container_name
                break
                ;;
            "Cancel")
                return 0
                ;;
            *) echo "Invalid option." ;;
        esac
    done

    if [ -z "$image_uri" ] || [ -z "$container_name" ]; then
        console_info_msg "Download cancelled."
        pause_for_review
        return 1
    fi

    if wwctl image list | grep -q "^${container_name}\s"; then
        console_fail_msg "A container named '${container_name}' already exists."
        pause_for_review
        return 1
    fi

    console_taskstart_msg "Importing ${image_uri} as '${container_name}'..."
    if wwctl image import "${image_uri}" "${container_name}"; then
        console_taskcomplete_msg "Container '${container_name}' imported successfully."

        # Run post-import configuration (OHPC, services, password, build)
        configure_container_post_import "${container_name}"
    else
        console_fail_msg "Failed to import container. Check the image name and your network connection."
    fi
    pause_for_review
}

list_containers() {
    option_picked "List Warewulf Containers"
    wwctl container list
    pause_for_review
}

run_manual_post_processing() {
    option_picked "Run Manual Post Processing / Prerequisites on a Container"

    mapfile -t containers < <(wwctl image list | awk 'NR>1 && !/^-/ {print $1}')
    if [ ${#containers[@]} -eq 0 ]; then
        console_fail_msg "No containers found to configure."
        pause_for_review
        return
    fi

    PS3="Select a container to configure: "
    select container_name in "${containers[@]}" "Cancel"; do
        if [[ "$container_name" == "Cancel" ]]; then
            return
        elif [[ -n "$container_name" ]]; then
            break
        else
            echo "Invalid selection."
        fi
    done

    configure_container_post_import "${container_name}"
    pause_for_review
}

build_container() {
    option_picked "Build Warewulf Container"

    mapfile -t containers < <(wwctl image list | awk 'NR>1 && !/^-/ {print $1}')
    if [ ${#containers[@]} -eq 0 ]; then
        console_fail_msg "No containers found to build."
        pause_for_review
        return
    fi

    PS3="Select a container to build: "
    select container_name in "${containers[@]}" "Cancel"; do
        if [[ "$container_name" == "Cancel" ]]; then
            return
        elif [[ -n "$container_name" ]]; then
            break
        else
            echo "Invalid selection."
        fi
    done

    console_taskstart_msg "Building container: ${container_name}"
    if wwctl container build "${container_name}"; then
        console_taskcomplete_msg "Build complete for ${container_name}."
    else
        console_fail_msg "Failed to build container '${container_name}'."
    fi
    pause_for_review
}

# --- Modify Image Functions ---

install_container_base_packages() {
    local container_name=$1

    option_picked "Install Base Packages in ${container_name}"

    console_taskstart_msg "Enabling EPEL repository in container..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${EPEL_URL}  || true

    console_taskstart_msg "Installing base packages..."
    wwctl image exec "${container_name}" --build=false -- /usr/bin/dnf -y install ${BASE_PACKAGES_CONTAINER}
    if [ $? -eq 0 ]; then
        console_taskcomplete_msg "Base packages installed in ${container_name}."
        console_info_msg "Container is ready for modifications. You can now add OFED, GPU drivers, etc."
    else
        console_fail_msg "Failed to install base packages in ${container_name}."
    fi

    pause_for_review
}

modify_container_add_mofed() {
    local container_name=$1
    console_info_msg "Adding Mellanox OFED to ${container_name}..."
    console_fail_msg "Function not yet implemented."
    pause_for_review
}

modify_container_add_cornelis() {
    local container_name=$1
    console_info_msg "Adding Cornelis OFED to ${container_name}..."
    console_fail_msg "Function not yet implemented."
    pause_for_review
}

modify_container_add_ganglia() {
    local container_name=$1
    local CHROOT="/var/lib/warewulf/chroots/${container_name}"
    console_info_msg "Adding Ganglia to ${container_name}..."
    dnf -y --installroot="$CHROOT" install ganglia-gmond
    console_taskcomplete_msg "Ganglia installed in ${container_name}."
    console_info_msg "Remember to rebuild the container image."
    pause_for_review
}

modify_container_add_dell_utils() {
    local container_name=$1
    local CHROOT="/var/lib/warewulf/chroots/${container_name}"
    option_picked "Add Dell Utilities (OMSA/iDRAC) to ${container_name}"

    local dell_idrac_tools_file=$(find /root -maxdepth 1 -name 'Dell-iDRACTools-Web-LX*.tar.gz' -print -quit)
    if [ -z "${dell_idrac_tools_file}" ]; then
        console_fail_msg "Dell iDRAC Tools tarball not found in /root. Please download and run this again."
        pause_for_review
        return 1
    fi

    # Create a temporary directory for extraction
    local temp_dir=$(mktemp -d)
    console_info_msg "Extracting Dell iDRAC Tools to ${temp_dir}..."
    tar -xf "${dell_idrac_tools_file}" -C "${temp_dir}"
    
    local rpm_path="${temp_dir}/iDRACTools/racadm/RHEL${os_version_major}/x86_64"
    if [ ! -d "${rpm_path}" ]; then
        console_fail_msg "Could not find RPM directory in extracted tarball."
        rm -rf "${temp_dir}"
        pause_for_review
        return 1
    fi

    console_taskstart_msg "Installing Dell iDRAC Tools into the container..."
    # Install all RPMs from the directory into the chroot
    dnf --installroot="${CHROOT}" localinstall -y ${rpm_path}/*.rpm
    
    if [ $? -eq 0 ]; then
        console_taskcomplete_msg "Dell iDRAC Tools installed in ${container_name}."
        # Add racadm to path
        echo 'export PATH="$PATH:/opt/dell/srvadmin/sbin"' > "${CHROOT}/etc/profile.d/dractools.sh"
        console_info_msg "racadm path added to profile.d in container."
        console_info_msg "Remember to rebuild the container image for changes to take effect."
    else
        console_fail_msg "Failed to install Dell iDRAC Tools in ${container_name}."
    fi

    # Cleanup temporary directory
    rm -rf "${temp_dir}"
    pause_for_review
}

modify_container_add_nvidia_repo() {
    local container_name=$1
    console_info_msg "Adding NVIDIA drivers from repo to ${container_name}..."
    console_fail_msg "Function not yet implemented."
    pause_for_review
}

show_nvidia_submenu() {
    local container_name=$1
    local exit_submenu=false
    while [ "$exit_submenu" = false ]; do
        clear
        option_picked "Add NVIDIA GPU Drivers to ${container_name}"
        echo "2) Install from NVIDIA online repository"
        echo "3) Return to previous menu"
        read -p "Enter your choice: " choice
        case $choice in
            1) modify_container_add_nvidia_runfile "${container_name}" ;;
            2) modify_container_add_nvidia_repo "${container_name}" ;;
            3) exit_submenu=true ;;
            *) echo "Invalid option." ; sleep 2 ;;
        esac
    done
}

show_modify_image_menu() {
    option_picked "Modify Existing Container Image"
    
    # Let user select a container
    mapfile -t containers < <(wwctl container list | awk 'NR>1 && !/^-/ {print $1}')
    if [ ${#containers[@]} -eq 0 ]; then
        console_fail_msg "No containers found to modify."
        pause_for_review
        return
    fi
    
    PS3="Select a container to modify: "
    select container_name in "${containers[@]}" "Cancel"; do
        if [[ "$container_name" == "Cancel" ]]; then
            return
        elif [[ -n "$container_name" ]]; then
            break
        else
            echo "Invalid selection."
        fi
    done

    while true; do
        echo_menu_header "Modifying Container: ${container_name}"
        echo -e "  ${YELLOW}1)${BLUE} Install Base Packages ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Set Root Password ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Add Mellanox OFED Drivers ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Add Cornelis OFED Drivers ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Add Ganglia Monitoring ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Add Dell Utilities (OMSA/iDRAC) ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Add NVIDIA GPU Drivers (Sub-Menu) ${RESET}"
        echo -e "  ${YELLOW}0)${BLUE} Return to Image Menu ${RESET}"
        read -p "Enter your choice: " choice
        case $choice in
            1) install_container_base_packages "${container_name}" ;;
            2) set_container_root_password "${container_name}" ;;
            3) modify_container_add_mofed "${container_name}" ;;
            4) modify_container_add_cornelis "${container_name}" ;;
            5) modify_container_add_ganglia "${container_name}" ;;
            6) modify_container_add_dell_utils "${container_name}" ;;
            7) show_nvidia_submenu "${container_name}" ;;
            0) break ;;
            *) echo "Invalid option." ; sleep 2 ;;
        esac
    done
}


# --- Main Menu for this script ---
show_image_menu() {
    local exit_menu=false
    while [ "$exit_menu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Warewulf Image Management Menu              **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Create New OS Container (from local repo) ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Download Container from Registry (Internet Access Required) ${RESET}"
        echo -e "${BLUE}------------------------------------------------${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Build Container ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Maintain Container (modify/manage) ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Run Manual Post Processing / Prerequisites ${RESET}"
        echo -e "${BLUE}------------------------------------------------${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} List Existing Containers ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " choice

        case $choice in
            1) create_new_container_from_local_repo ;;
            2) download_container_image ;;
            3) build_container ;;
            4) show_modify_image_menu ;;
            5) run_manual_post_processing ;;
            6) list_containers ;;
            7) exit_menu=true ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_image_menu
