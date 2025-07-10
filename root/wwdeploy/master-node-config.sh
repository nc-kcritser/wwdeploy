#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.
# 'common.sh' should contain the color variables and helper functions.
# If common.sh is not found, the script will exit.
if [ -f ./common.sh ]; then
    source ./common.sh
else
    echo "Error: common.sh not found. Please ensure it is in the same directory."
    exit 1
fi

# --- Master Node Setup Functions ---

install_ohpc_ww_prereqs() {
	option_picked "Install Prerequisite Packages"
    echo -e "\n${FGBLUE} Installing RPMs needed for Warewulf, OFED dependancies and basic functionality\n${RESET}"
	echo -e "${BLARROW} OS Distribution is: $os_distro - Major Release $os_version_major ${RESET}"
	sleep 1
	# Install EPEL repo for additional packages
	console_info_msg "Installing EPEL repo for EL$os_version_major"
    EPEL_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_version_major.noarch.rpm
	dnf install -y ${EPEL_URL}
	if [ "$?" -eq 0 ]; then
		console_taskcomplete_msg "EPEL release installed successfully!"
	else
		console_fail_msg "Error: Failed to install the EPEL release. Please check the error. Exiting Script"
		exit 1
	fi

	# Disable GPG check for EPEL
	console_info_msg "Disabling GPG check for EPEL..."
	gpg_check=$(cat /etc/yum.repos.d/epel.repo | grep gpgcheck | head -1 | awk -F = '{print $2}')
	if [ "$gpg_check" -eq 1 ]; then
		sed -i -e 's/gpgcheck=1/gpgcheck=0/g' "/etc/yum.repos.d/epel.repo"
		console_taskcomplete_msg "GPG check for EPEL disabled."
	fi

	# Install core and development tools
	console_info_msg "Installing core and development tools..."
	if [ "$os_distro" == "Rocky Linux" ]; then
		console_info_msg "Rocky Linux Detected - Installing basic tools..."
		dnf install -y dnf-plugins-core vim tmux screen dialog tar rsync perl wget nfs-utils bind-utils dmidecode hwloc hwloc-libs net-tools ntpstat pciutils lsof tk tcl gcc-gfortran createrepo ipmitool ipcalc golang python3-clustershell xorg-x11-xauth firefox
		console_info_msg "Rocky Linux Detected - Installing development tools..."
		dnf groupinstall -y "Development Tools"
	else
		console_info_msg "RHEL Detected - Installing basic tools..."
        if ! dnf install -y dnf-plugins-core vim tmux screen dialog tar rsync perl wget nfs-utils bind-utils dmidecode hwloc hwloc-libs net-tools ntpstat pciutils lsof tk tcl gcc-gfortran createrepo ipmitool ipcalc golang python3-clustershell xorg-x11-xauth firefox; then
			console_fail_msg "DNF command failed. Please check your local repository configuration or RHEL activation."
			pause_for_review
            return 1
		fi
		console_info_msg "RHEL Detected - Installing development tools..."
		if ! dnf groupinstall -y "Development Tools"; then
			console_fail_msg "DNF groupinstall command failed. Please check your local repository configuration or RHEL activation."
			pause_for_review
            return 1
		fi
	fi

	# Enable CodeReady Builder / PowerTools repo
	case "$os_distro" in
		"Rocky Linux")
			console_info_msg "Attempting to enable Rocky Linux PowerTools/CRB repo..."
			repo_name=""
            [[ "$os_version_major" -eq 8 ]] && repo_name="powertools"
            [[ "$os_version_major" -eq 9 ]] && repo_name="crb"

            if [ -n "$repo_name" ]; then
                if dnf config-manager --set-enabled $repo_name; then
                    console_taskcomplete_msg "Enabled '$repo_name' repository successfully."
                else
                    console_fail_msg "Failed to enable '$repo_name' repository. Exiting."
                    exit 1
                fi
            fi
			;;
		"Red Hat")
			console_info_msg "Attempting to enable RHEL CodeReady Builder repo..."
			if ! subscription-manager repos --enable=codeready-builder-for-rhel-$os_version_major-x86_64-rpms; then
				console_fail_msg "RHEL CodeReady Builder repo enablement has failed. Please check your RHEL activation."
				pause_for_review
                return 1
			else
				console_taskcomplete_msg "Enabled RHEL CodeReady Builder repo successfully."
			fi
			;;
	esac
	pause_for_review
}

build_local_os_repo() {
    option_picked "Configure Local OS Repo from ISO"

    os_iso=$(find /root -maxdepth 1 -name 'R*.iso' -print -quit)
    if [ -z "${os_iso}" ]; then
        console_fail_msg "$os_distro Linux OS iso not found in /root."
        console_info_msg "Please upload the iso file and run this function again."
        pause_for_review
        return 1
    fi

    console_info_msg "Backing up existing repo files... "
    mkdir -p /root/repo_backup
    cp /etc/yum.repos.d /root/repo_backup/*.repo / 2>/dev/null

    console_info_msg "Removing rhel and rocky online repos. They can be restored by copying them back from /root/repo_backup/"
    rm -f /etc/yum.repos.d/rocky.repo /etc/yum.repos.d/redhat.repo

    mkdir -p /opt/ohpc/pub/repo/$os_id$os_version_full
    mkdir -p /mnt/iso
    # Mount only if not already mounted
    mountpoint -q /mnt/iso || mount -o loop "${os_iso}" /mnt/iso

    # Use an array to safely capture the full path of the rsync package
    shopt -s nullglob
    pkg_files=(/mnt/iso/BaseOS/Packages/r/rsync*.rpm)
    shopt -u nullglob

    # Check if rsync is already installed. If not, install it.
    if ! rpm -q rsync &>/dev/null; then
        if [ ${#pkg_files[@]} -eq 1 ]; then
            console_info_msg "Found rsync package: ${pkg_files[0]}"
            console_info_msg "Installing rsync from the mounted iso..."
            
            # Pass the explicit, non-wildcard path to dnf
            if ! dnf localinstall -y "${pkg_files[0]}"; then
                console_fail_msg "DNF command failed to install rsync. See errors above."
                pause_for_review
                umount /mnt/iso
                return 1
            fi
        else
            console_fail_msg "Error: rsync is not installed and found ${#pkg_files[@]} rsync packages on the ISO instead of 1."
            pause_for_review
            umount /mnt/iso
            return 1
        fi
    else
        console_info_msg "rsync is already installed. Skipping installation."
    fi

    console_info_msg "Copying iso contents to the repo location..."
    # Check the exit code of rsync. If it fails, print an error, clean up, and exit the function.
    if ! rsync -av --info=progress2 /mnt/iso/ /opt/ohpc/pub/repo/$os_id$os_version_full/; then
        console_fail_msg "rsync failed to copy ISO contents. Check for errors above and disk space."
        pause_for_review
        umount /mnt/iso
        return 1
    fi

    console_info_msg "Creating the local repo file..."
    cat << EOF > /etc/yum.repos.d/$os_id$os_version_full-offline.repo
[BaseOS-LocalRepo]
name=BaseOS Packages $os_distro $os_version_full Linux - Offline (Local)
metadata_expire=-1
gpgcheck=0
enabled=1
baseurl=file:///opt/ohpc/pub/repo/$os_id$os_version_full/BaseOS/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[AppStream-LocalRepo]
name=AppStream Packages $os_distro $os_version_full Offline (Local)
metadata_expire=-1
gpgcheck=0
enabled=1
baseurl=file:///opt/ohpc/pub/repo/$os_id$os_version_full/AppStream/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

    umount /mnt/iso
    rmdir /mnt/iso
    console_taskcomplete_msg "Local OS repo created successfully."
    pause_for_review
}

install_openmanage_master() {
	option_picked "Install Dell OpenManage (iDRAC Tools)"
    # Install Dell OpenManage
	cd /root || return 1
    wget -nc -P /root -U Mozilla "$IDRACTOOLS_MULTI_DL_11_3"

	dell_idrac_tools_file=$(find /root -maxdepth 1 -name 'Dell-iDRACTools-Web-LX*.tar.gz' -print -quit)

	if [ -z "${dell_idrac_tools_file}" ]; then
		console_fail_msg "Dell iDRAC Tools tarball not found in /root. Please download the file and run this again."
		pause_for_review
		return 1
	fi

	cd /tmp || return 1
	console_info_msg "Extracting Dell iDRAC Tools..."
	tar xf "${dell_idrac_tools_file}"
	cd iDRACTools/racadm/RHEL"$os_version_major"/x86_64 || return 1
	rm -f srvadmin-selinux*.rpm srvadmin-tomcat*.rpm
	console_info_msg "Installing Dell iDRAC Tools via DNF LocalInstall..."
	dnf localinstall -y *.rpm
	cd /tmp/ || return 1
	rm -rf license.txt COPYRIGHT.txt iDRACTools

	if [ ! -f /etc/profile.d/dractools.sh ]; then
		echo 'export PATH="$PATH:/opt/dell/srvadmin/sbin"' > /etc/profile.d/dractools.sh
		console_taskcomplete_msg "dractools.sh added to /etc/profile.d/"
	else
		console_taskcomplete_msg "dractools.sh already exists in /etc/profile.d/"
	fi

	console_taskcomplete_msg "Dell iDRAC Tools have been installed successfully!"
	console_info_msg "You may need to restart your shell to use racadm."
	pause_for_review
}

# install_mellanox_ofed_master() {
# 	option_picked "Install Mellanox OFED"
# 	# Attempt to download Mellanox OFED based on OS version
# 	case $os_version_major in
# 		8) wget -nc "$MLNX_OFED_2303_EL8_DL" ;;
# 		9) wget -nc "$MLNX_OFED_2303_EL9_DL" ;;
# 	esac
# 
# 	mlnx_ofed_file=$(find /root/ -maxdepth 1 -name 'MLNX_OFED_LINUX*.tgz' -print -quit)
# 	if [ -z "${mlnx_ofed_file}" ];then
# 		console_fail_msg "Mellanox OFED tarball not found in /root. Please download the file and run this again."
# 		pause_for_review
# 		return 1
# 	fi
# 
# 	cd /tmp || return 1
# 	tar zxf "${mlnx_ofed_file}"
# 	cd MLNX_OFED_LINUX* || return 1
# 	./mlnxofedinstall --skip-distro-check --without-32bit --without-fw-update --kmp --enable-opensm -q
# 	systemctl enable --now opensmd
# 	cd /tmp || return 1
# 	rm -rf MLNX_OFED_LINUX* ofed.conf.save ofed.conf
#     console_taskcomplete_msg "Mellanox OFED installation complete."
# 	pause_for_review
# }

install_mellanox_ofed_master() {
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

install_nvidia_doca_ofed_master() {
    option_picked "Install NVIDIA DOCA Host"

    # --- Download Step ---
    console_info_msg "Attempting to download DOCA Host RPM..."
	echo "Downloading DOCA Host RPM from: $MLNX_DOCA_OFED_3_DL_URL"
    if ! wget -nc "$MLNX_DOCA_OFED_3_DL_URL"; then
        console_fail_msg "Download failed. Check URL and network."
        pause_for_review
        return 1
    fi

    # --- Find Downloaded RPM ---
    local FILENAME="doca-host-3.0.0*.rpm"
    local found_file
    found_file=$(find /root/ -maxdepth 1 -name "$FILENAME" -print -quit)
    if [ -z "${found_file}" ]; then
        console_fail_msg "RPM matching '$FILENAME' not found in /root."
        pause_for_review
        return 1
    fi

    # --- Install RPM using DNF ---
    console_info_msg "Installing DOCA from RPM: ${found_file}..."
    if ! dnf localinstall -y "${found_file}"; then
        console_fail_msg "DNF command failed to install DOCA RPM. See errors above."
        pause_for_review
        return 1
    fi

    console_taskcomplete_msg "NVIDIA DOCA Host installation complete."
    pause_for_review
}


install_cornelis_omnipath_masternode () {
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

manage_security() {
    local action=$1
    case $action in
        disable_selinux)
            console_taskstart_msg "Disabling SELinux..."
            setenforce 0
            sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
            console_taskcomplete_msg "SELinux is disabled."
			;;
        disable_firewall)
            console_taskstart_msg "Disabling the firewall..."
			systemctl disable --now firewalld
            console_taskcomplete_msg "Firewall is disabled."
			;;
        enable_firewall)
            console_taskstart_msg "Enabling the firewall..."
            systemctl enable --now firewalld
			systemctl is-active --quiet firewalld && console_taskcomplete_msg "firewalld is running." || console_fail_msg "firewalld failed to start."
            ;;
        disable_both_se_fw)
            manage_security disable_selinux
            manage_security disable_firewall
            ;;
		show_security_status)
            echo -e "${BOLDRED}--- Security Status ---${RESET}"
            echo -e "${YELLOW}SELinux Status:${RESET}"
			sestatus
			echo -e "\n${YELLOW}SELinux Config File:${RESET}"
            grep -v '^#' /etc/selinux/config | grep 'SELINUX='
			echo -e "\n${YELLOW}Firewall Status:${RESET}"
			systemctl is-active --quiet firewalld && echo "firewalld is running" || echo "firewalld is not running"
            ;;
        *)
            console_fail_msg "Invalid security option."
            return 1
            ;;
    esac
    pause_for_review
}

show_security_menu() {
	while true; do
        clear
        option_picked "Security Menu"
        echo "1) Disable SELinux"
        echo "2) Disable Firewall"
        echo "3) Disable Both SELinux and Firewall"
        echo "4) Enable Firewall"
		echo "5) Show Security and Firewall Status"
        echo "6) Return to previous menu"
        read -p "Enter your choice [1-6]: " choice

        case $choice in
            1) manage_security disable_selinux ;;
            2) manage_security disable_firewall ;;
            3) manage_security disable_both_se_fw ;;
            4) manage_security enable_firewall ;;
			5) manage_security show_security_status ;;
            6) return 0 ;;
            *) echo "Invalid choice. Please select a valid option."; sleep 2 ;;
        esac
    done
}

configure_master_hostname() {
    option_picked "Configure Master Hostname"
    read -e -p "Enter new hostname: " -i "$(hostname)" host_name
    if [ -n "$host_name" ]; then
        hostnamectl set-hostname "${host_name}"
        console_taskcomplete_msg "Hostname set to ${host_name}."
    else
        console_fail_msg "Hostname cannot be empty."
    fi
    pause_for_review
}

configure_master_host_dns() {
	option_picked "Configure DNS / Name Servers";
	read -e -p "Enter DNS search domains (space separated): " -i "$search_domains" search_domains
	read -e -p "Enter DNS server #1: " -i "${dns_server_1}" dns_server1
	read -e -p "Enter DNS server #2: " -i "${dns_server_2}" dns_server2
	read -e -p "Enter DNS server #3: " -i "${dns_server_3}" dns_server3

	console_info_msg "Configuring /etc/resolv.conf..."
	> /etc/resolv.conf # Clear the file
	if [ -n "${search_domains}" ]; then
		echo "search ${search_domains}" >> /etc/resolv.conf
	fi
	if [ -n "${dns_server1}" ]; then
        echo "nameserver ${dns_server1}" >> /etc/resolv.conf
    fi
    if [ -n "${dns_server2}" ]; then
		echo "nameserver ${dns_server2}" >> /etc/resolv.conf
	fi
	if [ -n "${dns_server3}" ]; then
		echo "nameserver ${dns_server3}" >> /etc/resolv.conf
	fi
    console_taskcomplete_msg "/etc/resolv.conf has been updated."
    pause_for_review
}

configure_master_timezone_chrony() {
	option_picked "Configure Timezone and Time Server"
	console_info_msg "Configuring the timezone..."
	PS3='Choose time zone: '
	options=("Eastern" "Central" "Mountain" "Phoenix" "Pacific" "Alaska" "Honolulu" "Skip")
	select opt in "${options[@]}"; do
		case $opt in
			"Eastern") timedatectl set-timezone America/New_York; break ;;
			"Central") timedatectl set-timezone America/Chicago; break ;;
			"Mountain") timedatectl set-timezone America/Denver; break ;;
			"Phoenix") timedatectl set-timezone America/Phoenix; break ;;
			"Pacific") timedatectl set-timezone America/Los_Angeles; break ;;
			"Alaska") timedatectl set-timezone America/Anchorage; break ;;
			"Honolulu") timedatectl set-timezone Pacific/Honolulu; break ;;
            "Skip") break;;
		esac
	done
	console_taskcomplete_msg "Timezone is now: $(timedatectl | grep "Time zone" | awk -F ': ' '{print $2}')"

	read -p "Do you want to configure the NTP server for the master host? [y/n]: " response
	if [[ "$response" == "y" || "$response" == "Y" ]]; then
        cp -p /etc/chrony.conf /etc/chrony.conf.backup."$(date +%F-%T)"
        read -e -p "Enter NTP Server FQDN or IP: " -i "${ntp_server}" ntp_server
        if [ -n "$ntp_server" ]; then
            sed -i -e "s/^pool .*/server ${ntp_server} iburst/g" /etc/chrony.conf
            console_taskcomplete_msg "NTP server set to ${ntp_server} in /etc/chrony.conf."
            console_info_msg "Restarting chronyd service..."
            systemctl restart chronyd
            console_taskcomplete_msg "Chronyd service restarted."
        else
            console_fail_msg "NTP Server cannot be empty."
        fi
    else
        console_info_msg "Skipping NTP server configuration."
    fi
	pause_for_review
}

create_users_groups() {
    option_picked "Create Users/Groups"
	if ! getent group dell >/dev/null; then groupadd -g 4999 dell; fi

	PS3='Select user type to create: '
	options=("hpl" "gpu" "custom" "Quit")
	select opt in "${options[@]}"; do
		case $opt in
			"hpl") useradd hpl -u 4999 -g dell -c "High Performance Linpack" -m ;;
			"gpu") useradd gpu -u 4998 -g dell -c "Nvidia CUDA HPL" -m ;;
			"custom")
				read -p "Enter username: " user_name
				read -p "Enter display name: " display_name
				read -p "Enter user ID: " user_id
				useradd "${user_name}" -u "${user_id}" -g dell -c "${display_name}" -m
				passwd "${user_name}"
				;;
			"Quit") break ;;
		esac
	done
    console_taskcomplete_msg "User creation process finished."
    pause_for_review
}

# --- Sub-Menu for this script ---
show_master_node_menu() {
    while true; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}**      Initial Master Node Setup Menu        **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}0)${BLUE} Security Menu (SELinux/Firewall) ${RESET}"
		echo -e "  ${YELLOW}1)${BLUE} Configure hostname ${RESET}"
        echo -e "  ${YELLOW}2)${BOLDRED} Go to Network Configuration Menu ---> ${RESET}"        
		echo -e "  ${YELLOW}3)${BLUE} Install prerequisite RPM packages ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Configure local OS repo from ISO ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Install Dell OpenManage (iDRAC Tools) ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Install Mellanox OFED ${RESET}"
		echo -e "  ${YELLOW}7)${BLUE} Install NVIDIA DOCA-OFED ${BOLDRED}(Not Yet Implemented) ${RESET}"
        echo -e "  ${YELLOW}8)${BLUE} Install Cornelis Omni-Path ${RESET}"
        echo -e "  ${YELLOW}9)${BLUE} Create Users and Groups ${RESET}"
        echo -e " ${YELLOW}10)${BLUE} Configure DNS / name servers ${RESET}"
        echo -e " ${YELLOW}11)${BLUE} Configure time zone and time server ${RESET}"
        echo -e " ${YELLOW}12)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " mn_choice

        case $mn_choice in
		    0) show_security_menu ;;
			1) configure_master_hostname ;;
            2)
                if [ -f ./network-config.sh ]; then
                    ./network-config.sh
                else
                    console_fail_msg "network-config.sh not found in the current directory."
                    pause_for_review
                fi
                ;;            
            3) install_ohpc_ww_prereqs ;;
            4) build_local_os_repo ;;
            5) install_openmanage_master ;;
            6) install_mellanox_ofed_master ;;
			7) install_nvidia_doca_ofed_master ;;
            8) install_cornelis_omnipath_masternode ;;
            9) create_users_groups ;;
            10) configure_master_host_dns ;;
            11) configure_master_timezone_chrony ;;
            12) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_master_node_menu
