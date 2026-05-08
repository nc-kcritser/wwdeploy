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

install_idractools_master() {
	option_picked "Install Dell iDRAC Tools"
    # Install Dell OpenManage
	cd /root || return 1
    console_info_msg "Attempting to download tools from: $IDRACTOOLS_DL_URL"
    wget -nc -P /root -U Mozilla "$IDRACTOOLS_DL_URL"

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
	echo -e "\n${BLUE}Current /etc/resolv.conf:${RESET}"
	cat /etc/resolv.conf
    pause_for_review
}

configure_master_timezone_chrony() {
	option_picked "Configure Timezone and Time Server"
	console_info_msg "Configuring the timezone..."

	local tz_set=false
	while [ "$tz_set" = false ]; do
		echo -e "\n${BLUE}Timezone Selection${RESET}"
		echo " 0) UTC"
		echo " 1) Eastern"
		echo " 2) Central"
		echo " 3) Mountain"
		echo " 4) Phoenix"
		echo " 5) Pacific"
		echo " 6) Alaska"
		echo " 7) Honolulu"
		echo " 8) Specify custom timezone"
		echo " 9) Skip timezone configuration"
		read -p "=> " tz_choice

		case $tz_choice in
			0)
				timedatectl set-timezone UTC
				console_taskcomplete_msg "Timezone set to UTC."
				tz_set=true
				;;
			1)
				timedatectl set-timezone America/New_York
				console_taskcomplete_msg "Timezone set to Eastern."
				tz_set=true
				;;
			2)
				timedatectl set-timezone America/Chicago
				console_taskcomplete_msg "Timezone set to Central."
				tz_set=true
				;;
			3)
				timedatectl set-timezone America/Denver
				console_taskcomplete_msg "Timezone set to Mountain."
				tz_set=true
				;;
			4)
				timedatectl set-timezone America/Phoenix
				console_taskcomplete_msg "Timezone set to Phoenix."
				tz_set=true
				;;
			5)
				timedatectl set-timezone America/Los_Angeles
				console_taskcomplete_msg "Timezone set to Pacific."
				tz_set=true
				;;
			6)
				timedatectl set-timezone America/Anchorage
				console_taskcomplete_msg "Timezone set to Alaska."
				tz_set=true
				;;
			7)
				timedatectl set-timezone Pacific/Honolulu
				console_taskcomplete_msg "Timezone set to Honolulu."
				tz_set=true
				;;
			8)
				read -p "Enter timezone (e.g., Europe/Paris, Asia/Tokyo, Australia/Sydney): " custom_tz
				if timedatectl set-timezone "$custom_tz" 2>/dev/null; then
					console_taskcomplete_msg "Timezone set to $custom_tz."
					tz_set=true
				else
					console_fail_msg "Invalid timezone: $custom_tz (check /usr/share/zoneinfo for valid names)."
				fi
				;;
			9)
				console_info_msg "Skipping timezone configuration."
				tz_set=true
				;;
			*)
				echo "Invalid option. Please try again."
				;;
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
    sleep 5     # waiting for chrony to catchup.
	echo -e "\n${BLUE}Current Chrony NTP Sources:${RESET}"
	chronyc sources
	pause_for_review
}

create_local_users_groups() {
    option_picked "Create Local Users/Groups"
	if ! getent group dell >/dev/null; then groupadd -g 4999 dell; fi

	while true; do
		echo -e "\n${BLUE}User Creation Menu${RESET}"
		echo " 1) Create HPL user"
		echo " 2) Create GPU user"
		echo " 3) Create custom user"
		echo " 0) Finished - Return to main menu"
		read -p "=> " user_choice

		case $user_choice in
			1)
				if useradd hpl -u 4999 -g dell -c "High Performance Linpack" -m 2>/dev/null; then
					console_taskcomplete_msg "HPL user created successfully."
				else
					console_fail_msg "Failed to create HPL user (may already exist)."
				fi
				;;
			2)
				if useradd gpu -u 4998 -g dell -c "Nvidia CUDA HPL" -m 2>/dev/null; then
					console_taskcomplete_msg "GPU user created successfully."
				else
					console_fail_msg "Failed to create GPU user (may already exist)."
				fi
				;;
			3)
				read -p "Enter username: " user_name
				read -p "Enter display name: " display_name
				read -p "Enter user ID: " user_id
				if useradd "${user_name}" -u "${user_id}" -g dell -c "${display_name}" -m 2>/dev/null; then
					console_taskcomplete_msg "User '${user_name}' created. Setting password now..."
					passwd "${user_name}"
					console_taskcomplete_msg "Password set for '${user_name}'."
				else
					console_fail_msg "Failed to create user '${user_name}' (may already exist)."
				fi
				;;
			0)
				break
				;;
			*)
				echo "Invalid option. Please try again."
				;;
		esac
	done
    console_taskcomplete_msg "Exiting User creation function... returning to menu. "
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
        echo -e "  ${YELLOW}5)${BLUE} Install Dell iDRAC Tools ${RESET}"
        echo -e "  ${YELLOW}6)${BOLDRED} Install Fabrics (DOCA, MLNX-OFED, OPA) Menu ---> ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Create Local Users and Groups ${RESET}"
        echo -e "  ${YELLOW}8)${BLUE} Configure DNS / name servers ${RESET}"
        echo -e "  ${YELLOW}9)${BLUE} Configure time zone and time server ${RESET}"
        echo -e " ${YELLOW}10)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " mn_choice

        case $mn_choice in
		    0) show_security_menu ;;
			1) configure_master_hostname ;;
            2) "${SCRIPT_DIR}/modules/02_network-config.sh" ;;            
            3) install_ohpc_ww_prereqs ;;
            4) build_local_os_repo ;;
            5) install_idractools_master ;;
            6) "${SCRIPT_DIR}/modules/10_fabric-software-install.sh" ;;
            7) create_local_users_groups ;;
            8) configure_master_host_dns ;;
            9) configure_master_timezone_chrony ;;
            10) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_master_node_menu
