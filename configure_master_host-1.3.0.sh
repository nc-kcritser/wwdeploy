#!/usr/bin/env bash
script_version=1.3.0

# Source openhpc-set-vars so we can auto fill as much information as possible.
source /root/openhpc-set-vars.sh
source /root/warewulf-download-vars.sh

script_debug_mode=true

# ICONS Color Palette Setup
CM="✔️ "
CROSS="✖️ "

BOLDRED='\033[01;31m' # bold red
RESET='\033[00;00m' # normal white
BLUE='\033[36m' # blue
YELLOW=`echo "\033[33m"` #yellow
RED_TEXT=`echo "\033[31m"`
FGRED=`echo "\033[41m"`
FGBLUE="\033[44m"
BLARROW="${BLUE} → ${RESET}"
YELLOWCM="${YELLOW} ✔ ${RESET}"

# System Info Gathering
. /etc/os-release
os_distro=$NAME			# Variable gathered from calling /etc/os-release
case "$os_distro" in
    *"Red Hat"*)
        os_version_full=$VERSION_ID 
        os_version_major=${VERSION_ID%%.*}
		os_id=$ID
        ;;
	*"Rocky Linux"*)
        os_version_full=$VERSION_ID 
        os_version_major=${VERSION_ID%%.*}
		os_id=$ID
        ;;
    *)
        echo -e "${CROSS} Unsupported OS: $os_distro"
        exit 1
        ;;
esac

## Setup other URLs that dont change - function moved to download-vars.sh
# EPEL_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-$os_version_major.noarch.rpm

#### Supporting Functions for the menus ####
option_picked() {
	# Advises what option was picked by informational message.
    MESSAGE=${@:-"${RESET}Error: No message passed"}
    echo -e "${BOLDRED}${MESSAGE}${RESET}"
}

console_info_msg() {
	# Display informational message to the console
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${BLARROW} ${MESSAGE} ${RESET}\n"
}

echo_menu_header() {
	# Display informational message to the console
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${BLUE}************************************************************************************************${RESET}"
	echo -e "           ${YELLOW}${MESSAGE}                                                           ${RESET}"
	echo -e "           ${YELLOW}OS Distro is: $os_distro - Major Release $os_version_major         ${RESET}"
	echo -e "${BLUE}************************************************************************************************${RESET}"
}

console_taskcomplete_msg() {
	# Display informational message to the console
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${YELLOWCM} ${MESSAGE} ${RESET}\n"
}
console_taskstart_msg() {
	# Display informational message to the console
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${YELLOW}- ${MESSAGE} ${RESET}\n"
}
console_fail_msg() {
	# Display informational message to the console
	MESSAGE=${@:-"${RESET}Error: No message passed"}
	echo -e "${CROSS} ${FGRED}${MESSAGE} ${RESET}\n" >&2
}

pause_for_review() {
    # Pause for reading
    read -p "→ Press any key to continue..." fackAnyKey
}

### Functions of the menu
show_security_menu() {
	# Show security menu options
	clear
	option_picked "Option 1 Picked"
	echo -e "${BLUE}Displaying Security Menu...${RESET}"
    while true; do
        echo "Choose an option:"
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
            6) echo "Returning to main script..."; return 0 ;;
            *) echo "Invalid choice. Please select a valid option." ;;
        esac
    done
}

manage_security() {
	# this function is called by other functions to actually perform the actions
    local action=$1

    case $action in
        disable_selinux)
            echo "Disabling SELinux..."
            sudo setenforce 0
            sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
			echo
			sleep 2
            ;;
        disable_firewall)
            echo "Disabling the firewall..."
			systemctl disable --now firewalld
			echo
			sleep 2
            ;;
        enable_firewall)
            echo "Enabling the firewall..."
            systemctl enable firewalld
            systemctl start firewalld
			systemctl is-active --quiet firewalld && echo "firewalld is running" || echo "firewalld is not running"
			pause_for_review
            ;;
        disable_both_se_fw)
            echo "Disabling SELinux and the firewall..."
            setenforce 0
            sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
            systemctl stop firewalld
            systemctl disable firewalld
			echo
			sleep 2
            ;;
		show_security_status)
            echo -e "${BOLDRED}Here is the current status of SELinux and the Firewall${RESET}"
            echo -e "${BOLDRED}Current SEStatus${RESET}\n"
			sestatus
			echo -e "\n${BOLDRED}SELinux Config File${RESET}\n" 
            grep -v '^#' /etc/selinux/config | grep 'SELINUX='
			
			echo -e "\n${BOLDRED}Firewall Status${RESET}\n" 
			systemctl is-active --quiet firewalld && echo "firewalld is running" || echo "firewalld is not running"
        
			echo
			sleep 2
            ;;
        *)
            echo "Invalid security option. Please choose a valid action."
			echo
            return 1
            ;;
    esac
}

prelaunch_check() { 
	# function maybe killed or moved to an option 0
	#### Prerequiste check for Required Files: Checks if the necessary files are located in the /root directory
	# Disable case sensitivity	
	shopt -s nocasematch

	declare -A required_files=(
		["R*.iso"]="An OS iso file not found, please place the OS .iso in /root"
		["OM-SrvAdmin-Dell*.gz"]="Dell OpenManage Server Agent file (OM-SrvAdmin-Dell*.gz) not found, please place the file in /root"
		["MLNX_OFED_LINUX*.tgz"]="Mellanox OFED file (MLNX_OFED_LINUX*.tgz) not found, please place the .tgz file in /root"
		["dell_bright*.tgz"]="Dell Bright deployment tarball not found, please place the .tgz file in /root"
		["hpcx-*.tbz"]="Mellanox HPC-X (hpcx-*.tbz) file not found, please place the .tbz file in /root"
		# ["intel-oneapi-*.sh"]="Intel oneAPI 2025 files not found, please place the .sh files in /root"  #### Excluded because some people use other versions
		["cuda*.run"]="Nvidia CUDA Driver / Toolkit runfile (cuda*.run) not found, please place the .run file in /root if you have GPU nodes"
	)
	for pattern in "${!required_files[@]}"; do
		if ! find /root -name "$pattern" -print -quit | grep -q .; then
			echo -e "$CROSS ${required_files[$pattern]}"
			sleep 1
				
		fi
	# Re-enable case sensitivity	
	shopt -u nocasematch
	done
}

configure_master_timezone_chrony() {
	# Configure the timezone
	option_picked "Option 9 Picked - Master Host Timezone and Time Server Configuration"
	console_info_msg "Configuring the timezone... "
	PS3='Choose time zone: '
	options=("Eastern" "Central" "Mountain" "Phoenix" "Pacific" "Alaska" "Honolulu")
	select opt in "${options[@]}"; do
		case $opt in
			"Eastern") timedatectl set-timezone America/New_York; break ;;
			"Central") timedatectl set-timezone America/Chicago; break ;;
			"Mountain") timedatectl set-timezone America/Denver; break ;;
			"Phoenix") timedatectl set-timezone America/Phoenix; break ;;
			"Pacific") timedatectl set-timezone America/Los_Angeles; break ;;
			"Alaska") timedatectl set-timezone America/Anchorage; break ;;
			"Honolulu") timedatectl set-timezone Pacific/Honolulu; break ;;
		esac
	done
	echo -e "${CM} Timezone has been set to $(timedatectl | grep "Time zone" | awk -F ': ' '{print $2}')"
	
	read -p "Do you want to configure the time server for the master host at this time? [y/n]: " response
	if [[ "$response" == "y" || "$response" == "Y" ]]; then
        # Backup the original chrony.conf
        cp -p /etc/chrony.conf /etc/chrony.conf.orig

        # Prompt for NTP server
        read -e -p "Enter NTP Server: " -i "${ntp_server}" ntp_server

		case "$os_distro" in
			"Rocky Linux")
				sed -i -e "s/pool 2.rocky.pool.ntp.org iburst/server ${ntp_server} iburst/g" /etc/chrony.conf
				;;
			"Red Hat")
				sed -i -e "s/pool 2.rhel.pool.ntp.org iburst/server ${ntp_server} iburst/g" /etc/chrony.conf
				;;
		esac
		echo -e "${CM} NTP server has been set to ${ntp_server} in /etc/chrony.conf ${RESET}"	
		echo -e "${BLARROW} Restarting chronyd service... ${RESET}"
		systemctl stop chronyd
		systemctl enable chronyd --now
		echo -e "${CM} Chronyd service has been restarted ${RESET} /n"
		sleep 5
    else
        echo -e "${BLARROW} Skipping NTP server configuration. ${RESET}"
    fi

	console_taskcomplete_msg "Current Chrony Sources: "
	console_info_msg "$(chronyc sources)"
	console_taskcomplete_msg "Current Chronyd Status is $(systemctl is-active --quiet chronyd && echo "running" || echo "not running")"
	pause_for_review
}

configure_master_hostname() {
    option_picked "Option 2 Picked - Configure Master Hostname"
    read -e -p "Enter hostname: " -i "${sms_name}" host_name

    # Set the hostname
    hostnamectl set-hostname "${host_name}"
}

configure_master_host_dns() {
	option_picked "Option 3 Picked";
	# Add DNS information now, so that NetworkManager won't mess with resolv.conf anymore
	site_domain=`hostname -d`
	read -e -p "Enter DNS search domains: " -i "$search_domains" search_domains
	read -e -p "Enter DNS server #1: " -i "${dns_server_1}" dns_server1
	read -e -p "Enter DNS server #2: " -i "${dns_server_2}" dns_server2
	read -e -p "Enter DNS server #3: " -i "${dns_server_3}" dns_server3

	echo -e " Configuring resolv.conf..."
	sleep 3
	rm -f /etc/resolv.conf.save
	sed -i '/#/d' /etc/resolv.conf
	sed -i '/search/d' /etc/resolv.conf
	sed -i '/nameserver/d' /etc/resolv.conf
	if [ -n "${search_domains}" ]; then
		echo "search ${search_domains}" > /etc/resolv.conf
	fi
	echo "nameserver ${dns_server1}" >> /etc/resolv.conf
	if [ -n "${dns_server2}" ]; then
		echo "nameserver ${dns_server2}" >> /etc/resolv.conf
	fi
	if [ -n "${dns_server3}" ]; then
		echo "nameserver ${dns_server3}" >> /etc/resolv.conf
	fi
}

install_openmanage_master() {
	clear;
	option_picked "Option 13 Picked - OpenManage Install"
    # Install Dell OpenManage
	cd /root
    wget -nc -P /root -U Mozilla $IDRACTOOLS_MULTI_DL_11_3

	dell_idrac_tools_file=$(ls /root | grep "^Dell-iDRACTools-Web-LX.*\.tar\.gz$")
	
	if [ -z "${dell_idrac_tools_file}" ]; then
		console_fail_msg "Dell IDRAC Tools tarball not found in /root \n - Please download the file and run this again."
		pause_for_review
		show_main_menu
	fi

	# Keeping for Austerity
	### If using OMSA Its this path - linux/RPMS/supportRPMS/srvadmin/RHEL$os_version_major/x86_64/
	### If using IDRACTools Its this path - iDRACTools/racadm/RHEL$os_version_major/x86_64
	cd /tmp
	file_count=$(ls /root | grep "^Dell-iDRACTools-Web-LX.*\.tar\.gz$" | wc -l)
	matching_files=$(ls /root | grep "^Dell-iDRACTools-Web-LX.*\.tar\.gz$")
	if [ "$file_count" -gt 1 ]; then
		console_fail_msg "Multiple files matching the pattern found: Dell-iDRACTools-Web-LX.*\.tar\.gz"
		echo "$matching_files"
		console_info_msg "Please ensure only one file is present in order to proceed"
		exit 1
	fi
	console_info_msg "Extracting Dell IDRAC Tools..."
	tar xvf /root/Dell-iDRACTools-Web-LX-*
	cd iDRACTools/racadm/RHEL$os_version_major/x86_64
	rm -f srvadmin-selinux*.rpm srvadmin-tomcat*.rpm
	console_info_msg "Installing Dell IDRAC Tools via DNF LocalInstall ..."
	dnf localinstall -y *.rpm
	cd /tmp/
	# For OMSA the line is this ## rm -rf setup.sh RPM-GPG-KEY license.txt COPYRIGHT.txt docs linux
	rm -rf license.txt COPYRIGHT.txt iDRACTools

	## IN EL8 there is a dractools.sh added to the /etc/profile.d/ directory with a single line, this only for RHEL9
	# Check if dractools.sh already exists
	if [ ! -f /etc/profile.d/dractools.sh ]; then
		# Add the export PATH line to dractools.sh
		echo 'export PATH="$PATH:/opt/dell/srvadmin/sbin"' > /etc/profile.d/dractools.sh
		console_taskcomplete_msg "dractools.sh added to /etc/profile.d/"
	else
		console_taskcomplete_msg "dractools.sh already exists in /etc/profile.d/"
	fi


	console_taskcomplete_msg "Dell IDRAC Tools have been installed successfully!"
	console_info_msg "You will need to restart your shell to use racadm"
	pause_for_review
}

install_ohpc_ww_prereqs() {
	option_picked "Option 01 Picked"
    echo -e "\n${FGBLUE} Installing RPMs needed for Warewulf, OFED dependancies and basic functionality\n${RESET}"
	echo -e "${BLARROW} OS Distribution is: $os_distro - Major Release $os_version_major ${RESET}"
	sleep 1
	# Install EPEL repo for additional packages
	### TODO : May need to add a check for the epel-release package, and the epel*.repo files in /etc/yum.repos.d/
	console_info_msg "Installing EPEL repo for EL$os_version_major"
	
	dnf install -y ${EPEL_URL}
	if [ "$?" -eq 0 ]; then
		console_taskcomplete_msg "EPEL release installed successfully!"
	else
		console_fail_msg "Error: Failed to install the EPEL release. Please check the error. Exiting Script"
		exit 1
	fi

	# Disable GPG check for EPEL - yum barfs on it.
	console_info_msg "Disabling GPG check for EPEL..."
	gpg_check=$(cat /etc/yum.repos.d/epel.repo | grep gpgcheck | head -1 | awk -F = '{print $2}')
	if [ "$gpg_check" -eq 1 ]; then
		sed -i -e 's/gpgcheck=1/gpgcheck=0/g' "/etc/yum.repos.d/epel.repo"
		console_taskcomplete_msg "Disabling GPG check for EPEL..."
	fi

	# Attempting to Load Tools and Development Tools
	console_info_msg "DNF - Installing core and development tools ... "
	if [ "$os_distro" == "Rocky Linux" ]; then
		# Rocky Linux Version
		console_info_msg "Rocky Linux Detected - Installing basic tools ... "
		dnf install -y dnf-plugins-core vim tmux screen dialog tar rsync perl tar wget nfs-utils bind-utils dmidecode hwloc hwloc-libs net-tools ntpstat pciutils lsof tk tcl gcc-gfortran createrepo ipmitool ntpstat ipcalc golang python3-clustershell xorg-x11-xauth firefox
		console_info_msg "Rocky Linux Detected - Installing development tools ... "
		dnf groupinstall -y "Development Tools"
	else
		# RHEL Version
		echo -e "${BOLDRED}[ NOTICE ] This command could fail you do not have a local repository configured yet or RHEL is not activated with subscriptions. ${RESET}"
		# Install basic tools
		console_info_msg "RHEL Detected - Installing basic tools ..."
		if ! dnf install -y dnf-plugins-core vim tmux screen dialog tar rsync perl tar wget nfs-utils bind-utils dmidecode hwloc hwloc-libs net-tools ntpstat pciutils lsof tk tcl gcc-gfortran createrepo ipmitool ntpstat ipcalc golang python3-clustershell xorg-x11-xauth firefox; then
			echo -e "${CROSS} DNF command failed. Please check your local repository configuration or RHEL activation. ${RESET}"
			sleep 5
			exit 1
		fi

		# Install development tools
		console_info_msg "RHEL Detected - Installing development tools ..."
		if ! dnf groupinstall -y "Development Tools"; then
			echo -e "${CROSS} DNF command failed. Please check your local repository configuration or RHEL activation. ${RESET}"
			sleep 5
			exit 1
		fi
	fi     

	# Rocky Specific - Enable Codebuilder/PowerTools
	case "$os_distro" in
		"Rocky Linux")
			console_info_msg "Attempting to enable EPEL PowerTools / Codebuilder Repos for Rocky Linux"
			case $os_version_major in
				8)
					if dnf config-manager --set-enabled powertools; then
						console_taskcomplete_msg "Enabled powertools successfully."
					else
						console_fail_msg "Failed to enable powertools. Exiting."
						exit 1
					fi
					;;
				9)
					if dnf config-manager --set-enabled crb; then
						console_taskcomplete_msg "Enabled crb successfully."
					else
						console_fail_msg "Failed to enable crb. Exiting."
						exit 1
					fi
					;;
			esac
			;;
		"Red Hat")
			console_info_msg "Attempting to enable RHEL Codebuilder"
			if ! subscription-manager repos --enable=codeready-builder-for-rhel-$os_version_major-x86_64-rpms; then
				console_fail_msg "RHEL Codebuilder Repo enablement has failed. Please check your RHEL activation."
				sleep 5
				exit 1
			else
				console_taskcomplete_msg "Enabled RHEL Codebuilder repo successfully."
			fi
			;;
	esac

	pause_for_review
	clear
}

install_cornelis_omnipath_masternode () {
    option_picked "Option 15 Picked - Install Cornelis Networks Omni-Path";
    # Install Cornelis Networks Omni-Path
	mkdir -p /opt/ohpc/pub/apps/cornelis/{RPM,firmware}
	cornelis_file=`ls /root|grep CornelisOPX`
	cornelis_working_dir=`ls /root/|grep CornelisOPX|awk -F tgz '{print $1}'|sed 's/\.$//'`
	if [ -z ${cornelis_file} ];then
		echo "Cornelis Networks Omni-Path tarball not found in /root"
		echo "Please download the file and run this again."
		pause_for_review
		clear;
		show_main_menu;
	fi

	# Install prequisite RPMs
	dnf install -y kernel-abi-stablelists atlas

	# Move firmware RPMs
	mv hfi1*.rpm /opt/ohpc/pub/apps/cornelis/RPM/

	# Install Omni-Path
	cd /tmp
	tar zxvf /root/$cornelis_file
	cd /tmp/$cornelis_working_dir
	./INSTALL -a
	cd /tmp
	rm -rf /tmp/$cornelis_working_dir

	# Install firmware RPMs
	dnf localinstall -y /opt/ohpc/pub/apps/cornelis/RPM/*.rpm

	pause_for_review
}

interface_config_masterhost_provisioning() {
	option_picked "Option 4 Picked";
    # Configure perface
	readarray -t lines < <(nmcli conn show|awk -F ' ' '{print $1}'|grep -v NAME|grep -v lo)

	# Prompt the user to select one of the lines.
	echo "Please select a nic:"
	select choice in "${lines[@]}"; do
		[[ -n $choice ]] || { echo "Invalid choice. Please try again." >&2; continue; }
		break # valid choice was made; exit prompt.
	done

	# Split the chosen line into ID and serial number.
	read -r iface sn unused <<<"$choice"

	# Get ip information
	read -e -p "Enter ip address : " -i "${sms_ip}" prov_ipaddr
	read -e -p "Enter subnet CIDR : " -i "${internal_cidr}" prov_cidr

	# Configure the interface
	nmcli connection delete ${iface}
	nmcli connection add type ethernet con-name ${iface} ifname ${iface} ipv4.method manual ipv4.addresses ${prov_ipaddr}/${prov_cidr}
	nmcli connection up ${iface}
	nmcli connection modify ${iface} connection.autoconnect yes
	
	sleep 2
	pause_for_review
}

interface_config_masterhost_alias() {
	option_picked "Option 5 Picked - Configure Alias Interface"
	# Configure additional ethernet address for iDRAC/mgmt communication
	readarray -t lines < <(nmcli conn show|awk -F ' ' '{print $1}'|grep -v NAME|grep -v lo)

	# Prompt the user to select nic.
	echo "Please select a nic where iDRACs will be accessible: "
	select choice in "${lines[@]}"; do
		[[ -n $choice ]] || { echo "Invalid choice. Please try again." >&2; continue; }
		break # valid choice was made; exit prompt.
	done

	# Split the chosen line into ID and serial number.
	read -r iface sn unused <<<"$choice"

	# Get ip information
	read -e -p "Enter ip address : " -i "${sms_bmc_mgmt}" alias_ipaddr
	read -e -p "Enter subnet CIDR : " -i "${internal_cidr}" alias_cidr

	# Add the ip address to the interface
	nmcli conn mod ${iface} +ipv4.addresses "${alias_ipaddr}/${alias_cidr}"

	# Restart the interface for the new ip to become active
	nmcli connection down ${iface}
	nmcli connection up ${iface}
	sleep 2
	pause_for_review
}

interface_config_masterhost_external() { 
	option_picked "Option 6 Picked - Configure External Interface";
	# Configure external ethernet interface
	readarray -t lines < <(nmcli conn show|awk -F ' ' '{print $1}'|grep -v NAME|grep -v lo)

	# Prompt the user to select nic.
	echo "Please select the nic for external connection: "
	select choice in "${lines[@]}"; do
		[[ -n $choice ]] || { echo "Invalid choice. Please try again." >&2; continue; }
		break # valid choice was made; exit prompt.
	done

	# Split the chosen line into ID and serial number.
	read -r iface sn unused <<<"$choice"

	# Get ip information
	read -e -p "Enter external ip address : " -i "${sms_external_ip}" external_ipaddr
	read -e -p "Enter external subnet CIDR : " -i "${external_cidr}" external_cidr
	read -e -p "Enter gateway ip address : " -i "${external_gateway}" external_gateway

	# Configure the interface
	nmcli connection delete ${iface}
	nmcli connection add type ethernet con-name ${iface} ifname ${iface} ipv4.method manual ipv4.addresses ${external_ipaddr}/${external_cidr} ipv4.gateway ${external_gateway}
	nmcli connection up ${iface}
	nmcli connection modify ${iface} connection.autoconnect yes
	sleep 2
	pause_for_review
} 

interface_config_masterhost_infiniband() {
	option_picked "Option 7 Picked - Configure InfiniBand Interface for Master Host"
	#Configure InfiniBand interface
	echo -e "${BLARROW} Checking for MLNX OFED Drivers ${RESET}"
	mlnx_ofed_version=`ofed_info|grep OFED| head -1|awk -F - '{print $2$3}'|awk -F ' ' '{print $1}'`
	if [ -z "${mlnx_ofed_version}" ];then
		echo ""
		echo "$mlnx_ofed_version is empty, which means that Mellanox OFED is not installed"
		echo ""
		echo "Please install Mellanox OFED, then run this again"
		echo ""
		sleep 4
		pause_for_review
		clear;
		show_main_menu;
	fi

	readarray -t lines < <(nmcli conn show|awk -F ' ' '{print $1}'|grep -v NAME|grep -v lo)

	# Prompt the user to select the IB interface.
	echo "Please select the InfiniBand interface: "
	select choice in "${lines[@]}"; do
		[[ -n $choice ]] || { echo "Invalid choice. Please try again." >&2; continue; }
		break # valid choice was made; exit prompt.
	done

	# Split the chosen line into ID and serial number.
	read -r iface sn unused <<<"$choice"

	# Get InfiniBand ip information
	read -e -p "Enter InfiniBand ip address : " -i "${sms_ipoib}" ib_ipaddr
	read -e -p "Enter InfiniBand subnet CIDR : " -i "${ipoib_cidr}" ib_cidr

	# Configure the interface
	nmcli connection delete ${iface}
	nmcli connection add type infiniband con-name ${iface} ifname ${iface} ipv4.method manual ipv4.addresses ${ib_ipaddr}/${ib_cidr}
	nmcli connection up ${iface}
	nmcli connection modify ${iface} connection.autoconnect yes

    sleep 2
	pause_for_review
}

interface_config_idrac_masterhost() {
	option_picked "Option 8 Picked - Configure iDRAC on Master Host";
    # Make sure we can do the task before we begin
	if [ ! -f /opt/dell/srvadmin/sbin/racadm ]; then
		echo "Dell OpenManage Server Agent not installed.."
		echo ""
		echo "racadm is required in order to configure the iDRAC interface."
		echo ""
		echo "Please install Dell OMSA and run this again."
		sleep 5
		clear;
		show_main_menu;
	fi
    
	# Configure master node iDRAC ip address
	PS3='Choose LOM for iDRAC connection: '
	options=("Dedicated" "LOM1" "LOM2" "LOM3" "LOM4")
	select opt in "${options[@]}"; do
		case $opt in
			"Dedicated"|"LOM1"|"LOM2"|"LOM3"|"LOM4") idrac_iface=$opt; break ;;
		esac
	done

	read -e -p "Enter iDRAC password: " -i "${sms_bmc_passwd}" idrac_passwd
	read -e -p "Enter iDRAC ip address: " -i "${sms_bmc_ip_address}" idrac_ipaddr
	read -e -p "Enter iDRAC subnet mask: " -i "${sms_bmc_netmask}" idrac_netmask
	read -e -p "Enter iDRAC gateway ip address: " -i "${sms_bmc_gateway}" idrac_gateway
	read -e -p "Enter iDRAC VLAN tag (blank for none): " -i "" idrac_vlan_tag
	# Configure the iDRAC
	racadm set iDRAC.IPMILan.Enable 1

	# Allow for any password to be set
	racadm set idrac.security.minimumpasswordscore 0
	racadm set iDRAC.tuning.DefaultCredentialWarning 0
	
	# Disable IDRAC Host Header Check (for Tunnelling to easier)
	racadm set idrac.webserver.HostHeaderCheck 0

	# Disable DHCP
	racadm set iDRAC.IPv4.DHCPEnable 0
	racadm set iDRAC.IPv4.DNSFromDHCP 0
	racadm set iDRAC.Nic.DNSDomainFromDHCP 0

	# Disable ipv6
	racadm set idrac.ipv6.AutoConfig Disabled
	racadm set idrac.ipv6.Enable Disabled

	# Configure password
	racadm set iDRAC.Users.2.Password ${idrac_passwd}

	# Configure ip info
	racadm set iDRAC.IPv4.Address ${idrac_ipaddr}
	racadm set iDRAC.IPv4.Netmask ${idrac_netmask}
	racadm set iDRAC.IPv4.Gateway ${idrac_gateway}

	# Configure shared/dedicated LOM
	racadm set iDRAC.NIC.Selection ${idrac_iface}

	# Configure VLAN tag
	if [ -z "${idrac_vlan_tag}" ];then
		racadm set iDRAC.NIC.VLanMode Enabled
		racadm set iDRAC.NIC.VLanID "${idrac_vlan_tag}"
	fi

	# Reset the iDRAC
	console_info_msg "Forcing a RAC Reset"
	racadm recreset hard -f

    sleep 2; pause_for_review
}

install_mellanox_ofed_master() {
	option_picked "Option 14 Picked";
	### TODO :Attempt to download Mellanox OFED by EL Version and add multiple releases
	case $os_version_major in
		8) os_version_major=8 wget -nc $MLNX_OFED_2303_EL8_DL ;;
		9) os_version_major=9 wget -nc $MLNX_OFED_2303_EL9_DL ;;
	esac
			
	# Install Mellanox OFED
	mlnx_ofed_file=$(ls /root/|grep MLNX_OFED_LINUX*.tgz)
	if [ -z ${mlnx_ofed_file} ];then
		echo "Mellanox OFED tarball not found in /root"
		echo ""
		echo "Please download the file and run this again."
		sleep 3
		clear;
		show_main_menu;
	fi

	cd /tmp
	tar zxvf /root/MLNX_OFED_LINUX*.tgz
	cd /tmp/MLNX_OFED_LINUX*
	./mlnxofedinstall --skip-distro-check --without-32bit --without-fw-update --kmp --enable-opensm -q
	systemctl enable opensmd --now
	cd /tmp
	rm -rf MLNX_OFED_LINUX* ofed.conf.save ofed.conf

	pause_for_review
}

build_local_os_repo() {
    option_picked "Option 11 Picked - Configure Local OS Repo from ISO"

    # Configure local OS RPM repo
	# First, get rid of the default repo files
	os_iso=$(ls /root/ | grep -i 'R.*\.iso')
	if [ -z "${os_iso}" ];then
		console_fail_msg "$os_distro Linux OS iso not found in /root \n"
		console_info_msg "Upload the iso file and run again."
		pause_for_review
		clear;
		show_main_menu;
	fi

	# Create a backup of the default repo files
	console_info_msg "Create a backup of the default repo files..."
	mkdir /root/default_yum_repos 2>/dev/null
	if [ "$?" -ne 0 ]; then
		console_info_msg "Directory /root/default_yum_repos already exists."
	fi
	mv  /etc/yum.repos.d/*.repo /root/default_yum_repos/

	###  TODO: Need to add a check if EPEL was already installed, if it was then either restore the epel*.repo 
	mkdir -p /opt/ohpc/pub/repo/$os_id$os_version_full
	# Mount the iso file
	mkdir -p /mnt/iso
	mount -o loop /root/$os_iso /mnt/iso

	# Install Rsync based on version each could be organzied differently 
	console_info_msg "Installing rsync from the mounted iso..."
	rsyncpath1="/mnt/iso/BaseOS/Packages/r/rsync*.rpm"
	rsyncpath2="/mnt/iso/BaseOS/Packages/rsync*.rpm"
	# Try the first path
	if ls $rsyncpath1 1> /dev/null 2>&1; then
		console_taskcomplete_msg "Found rsync package in path: $rsyncpath1"
		dnf localinstall -y $rsyncpath1
	elif ls $rsyncpath2 1> /dev/null 2>&1; then
		# Try the second path if the first one fails
		console_taskcomplete_msg "Found rsync package in path: $rsyncpath2"
		dnf localinstall -y $rsyncpath2
	else
		# If neither path contains the package, report an error
		console_fail_msg "Rsync package not found in either path."
		exit 1
	fi

	# Copy the iso contents to the repo location and create the repo file
	console_info_msg "Copying iso contents to the repo location ..."
	rsync -av /mnt/iso/* /opt/ohpc/pub/repo/$os_id$os_version_full
	console_info_msg "Creating the local repo file ..."
	cat << EOF > /etc/yum.repos.d/$os_id$os_version_full-offline.repo
[BaseOS]
name=BaseOS Packages $os_distro $os_version_full Linux - Offline (Local)
metadata_expire=-1
gpgcheck=0
enabled=1
baseurl=file:///opt/ohpc/pub/repo/$os_id$os_version_full/BaseOS/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[AppStream]
name=AppStream Packages $os_distro $os_version_full Offline (Local)
metadata_expire=-1
gpgcheck=0
enabled=1
baseurl=file:///opt/ohpc/pub/repo/$os_id$os_version_full/AppStream/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

	umount /mnt/iso
	rm -rf /mnt/iso
	pause_for_review

}

install_master_node_cpld_firmware() {
	option_picked "Option 17 Picked - Update Master Node CPLD"	
    # Update Dell CPLD firmware
	poweredge_model=`dmidecode|grep "Product Name:"|head -1|awk -F : '{print $2}'|awk -F " " '{print $2}'`
	fw_dir=/opt/ohpc/pub/apps/dell/firmware/PowerEdge/${poweredge_model}
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found! \n"
		console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		clear;
		show_main_menu;
	fi

	# Update CPLD firmware
	for i in `ls ${fw_dir}|grep BIN|grep CPLD`; do sh ${fw_dir}/$i -q; done

	# Reboot for the update to take effect
	racadm set BIOS.MiscSettings.PowerCycleRequest FullPowerCycle
	racadm jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
	racadm serveraction powercycle
	
	console_taskcomplete_msg "CPLD Firmware Cycle Complete - Rebooting Master Node - You will most likely lose connection"
}

install_master_node_firmware() {
	option_picked "Option 16 Picked";
	# Update Dell firmware
	poweredge_model=`dmidecode|grep "Product Name:"|head -1|awk -F : '{print $2}'|awk -F " " '{print $2}'`
	fw_dir=/opt/ohpc/pub/apps/dell/firmware/PowerEdge/${poweredge_model}
	if [ ! -d "$fw_dir" ]; then
		echo -e "${CROSS} [ERROR] ${FGRED} Firmware directory not found! ${NORMAL} /n"
		echo -e "${BLARROW} Please upload firmware for the PowerEdge ${poweredge_model} and run again. "
		pause_for_review
		clear;
		show_main_menu;
	fi

	echo "Updating PowerEdge ${poweredge_model} firmware..."
	sleep 2

	# Set executable perms on the BIN files
	chmod +x -R ${fw_dir}/*.BIN
	for i in `ls ${fw_dir}|grep iDRAC`; do sh ${fw_dir}/$i -q; done
	# Update everything else except iDRAC, BIOS and CPLD firmware
	for i in `ls ${fw_dir}|grep BIN|grep -v BIOS|grep -v iDRAC|grep -v CPLD`; do sh ${fw_dir}/$i -q; done
	# Update BIOS and reboot
	for i in `ls ${fw_dir}|grep BIN|grep BIOS`; do sh ${fw_dir}/$i -q -r; done
	sleep 2

}

install_openhpc_packages_master() {
    option_picked "Option 18 Picked - Install OpenHPC Packages";
    # Install OpenHPC Packages based on which version of the OS is being used (EL8 = 2.x, EL9 = 3.x)
	
	
	# Install OpenHPC 
	echo "Installing OpenHPC packages..."
	echo ""
	dnf install -y gcc nhc-ohpc gnu12-compilers-ohpc gnu13-compilers-ohpc ohpc-autotools EasyBuild-ohpc spack-ohpc valgrind-ohpc openmpi5-gnu13-ohpc mpich-ofi-gnu13-ohpc mpich-ucx-gnu13-ohpc ohpc-gnu13-openmpi5-parallel-libs ohpc-gnu13-mpich-parallel-libs ohpc-gnu13-perf-tools lmod-defaults-gnu13-openmpi5-ohpc
	sleep 2
	pause_for_review
}

install_configure_warewulf_menu() {
	clear
	option_picked "Option 18 Picked - Install/Configure Warewulf v4";
	echo "-------------------------------------------"
	echo "     Warewulf v4 Installation Menu         "
	echo "-------------------------------------------"
	# Install Warewulf v4
	PS3='Install / Configure Warewulf v4: '
	options=("Install" "Configure" "Containers" "Default" "Networks" "Profiles" "Overlays" "Networks" "Partitions" "Menu" )
	select opt in "${options[@]}"
	do
		case $opt in
			"Install") 
				echo "Installing Warewulf v4"
				case $os_version_major in
					8) 
						echo -e "${BLARROW} Installing Warewulf v4 for EL8 ${NORMAL}"
						console_taskstart_msg "Installing OpenHPC 2.x Online Repo for EL8"
						dnf install -y $OpenHPC2_DL
						console_taskstart_msg "Installing Warewulf v4 Components Online Repo for EL8"
						dnf install -y genders-ohpc ohpc-base ohpc-slurm-server pdsh-mod-genders-ohpc examples-ohpc-2.0-10.1.ohpc.2.0 ${WW_INSTALL_RPM}
						;;
					9) 
						echo -e "${BLARROW} Installing Warewulf v4 for EL9 ${NORMAL}"
						console_taskstart_msg "Installing OpenHPC 3.x Online Repo for EL9"
						dnf install -y $OpenHPC3_DL
						console_taskstart_msg "Installing Warewulf v4 Components Online Repo for EL9"
						dnf install -y genders-ohpc ohpc-base ohpc-slurm-server pdsh-mod-genders-ohpc examples-ohpc-2.0-300.ohpc.1.6 ${WW_INSTALL_RPM}
						;;
				esac

				# Quick initial configuration of slurm.conf
				console_taskstart_msg "Backing up original slurm config and updating for Warewulf v4"
				cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf
				cp /etc/slurm/cgroup.conf.example /etc/slurm/cgroup.conf
				perl -pi -e "s/SlurmctldHost=\S+/SlurmctldHost=$sms_name/" /etc/slurm/slurm.conf
				perl -pi -e "s/ClusterName=\S+/ClusterName=$cluster_name/" /etc/slurm/slurm.conf

				# Remove extra ReturnToService line
				return_line=`cat /etc/slurm/slurm.conf|grep ReturnToService|grep -v "#"|wc -l`
				if [ "$return_line" -gt "1" ]; then sed -i '0,/ReturnToService=1/{/ReturnToService=1/d}' /etc/slurm/slurm.conf; fi

				# Configure desired ReturnToService
				perl -pi -e "s/ReturnToService=1/ReturnToService=2/" /etc/slurm/slurm.conf

				console_taskcomplete_msg "Warewulf binaries for v4 Installed Successfully!"
				pause_for_review
				break
				;;
			"Configure")
				console_info_msg "Configuring Warewulf v4"
				# Backup the file, just in case
				console_taskstart_msg "Backing up original Warewulf configuration file"
				# Check for a backup warewulf.conf file, if it doesn't exist, create it and backup the original (we dont want to touch this again)
				if [ ! -f /etc/warewulf/warewulf.conf.orig ]; then
					console_info_msg "File /etc/warewulf/warewulf.conf.orig does not exist"
					cp -p /etc/warewulf/warewulf.conf /etc/warewulf/warewulf.conf.orig
					console_taskcomplete_msg "Backup of warewulf.conf created at /etc/warewulf/warewulf.conf.orig."
				else
					console_taskcomplete_msg "File /etc/warewulf/warewulf.conf.orig does exist. No backup created."
				fi
				## Remove resolv.conf template so we don't get a useless file:
				# Leave a backup copy, just in case
				#console_taskstart_msg "Removing resolv.conf.ww template"
				#cp -p /var/lib/warewulf/overlays/wwinit/rootfs/resolv.conf.ww /var/lib/warewulf/overlays/wwinit/rootfs/resolv.conf.ww /var/lib/warewulf/overlays/wwinit/rootfs/resolv.conf.ww.saved
				#wwctl overlay delete wwinit resolv.conf.ww

				console_info_msg "Gathering Information - Please answer the following questions:"

				# Get provisioning ethernet interface
				readarray -t lines < <(nmcli conn show|awk -F ' ' '{print $1}'|grep -v NAME|grep -v lo)

				# Prompt the user to select one of the lines.
				echo "Please select the provisioning nic:"
				select choice in "${lines[@]}"; do
					[[ -n $choice ]] || { echo "Invalid choice. Please try again." >&2; continue; }
					break # valid choice was made; exit prompt.
				done

				# Split the chosen line into ID and serial number.
				read -r iface sn unused <<<"$choice"

				console_info_msg "${iface} will be configured as the provisioning interface"
				echo ""

				# Get provisioning network
				read -e -p "Enter provisioning base network : " -i "${internal_base_net}" provisioning_net

				# Set provisioning network
				perl -pi -e "s/10.0.0.0/"$provisioning_net"/g if /network/" /etc/warewulf/warewulf.conf

				# Get head node provisioning ip address
				read -e -p "Enter provisioning ip address: " -i "${sms_ip}" provisioning_ip

				# Set head node provisioning ip address
				perl -pi -e "s/10.0.0.1/"$provisioning_ip"/g if /ipaddr/" /etc/warewulf/warewulf.conf

				# Get provisioning netmask
				read -e -p "Enter provisioning subnet mask: " -i "${internal_netmask}" provisioning_netmask

				# Set provisioning netmask
				perl -pi -e "s/255.255.252.0/"$provisioning_netmask"/g if /netmask/" /etc/warewulf/warewulf.conf

				# Get DHCP range
				read -e -p "Enter DHCP range start: " -i "${dynamic_range_start}" dhcp_range_start
				echo ""
				read -e -p "Enter DHCP range end: " -i "${dynamic_range_end}" dhcp_range_end

				# Set DHCP range
				perl -pi -e "s/10.0.1.1/"$dhcp_range_start"/g if /range start/" /etc/warewulf/warewulf.conf
				perl -pi -e "s/10.0.1.255/"$dhcp_range_end"/g if /range end/" /etc/warewulf/warewulf.conf

				# Configure NFS shares
				perl -pi -e "s/path: \/opt(?!\/ohpc\/pub)/path: \/opt\/ohpc\/pub/g if /path: \/opt/" /etc/warewulf/warewulf.conf
				perl -pi -e "s/mount: false/mount: true/g" /etc/warewulf/warewulf.conf

				# Update options for NFS shares
				perl -pi -e "s/rw,sync/rw,sync,no_root_squash/g if /export options/" /etc/warewulf/warewulf.conf
				perl -pi -e "s/ro,sync,no_root_squash/rw,sync,no_root_squash/g if /export options/" /etc/warewulf/warewulf.conf

				# Check for Large Deployment (>300 nodes) if yes, then change update interval to 5m (300s)
				read -p "Is this a large deployment (>300 Nodes) ? (yes/no): " response
				if [[ "$response" == "y" || "$response" == "Y" ]]; then
					console_taskstart_msg "You've indicated this is a large deployment. Updating update interval to 300 seconds ..."
					perl -pi -e "s/update interval: 60/update interval: 300/g" /etc/warewulf/warewulf.conf
				fi

				# Run configure ww4
				wwctl configure --all

				# Enable and start ww4
				systemctl enable warewulfd --now

				sleep 5
				#### TODO - Doesnt work in WW4.6 (Change to systemctl status warewulfd)
				# wwctl server status
				# console_taskcomplete_msg "Warewulf v4 Configured Successfully! - Warewulf Server Status Shown Above"

				# Configure rsyslog to receive from cluster nodes
				console_taskstart_msg "Configuring rsyslog to receive from cluster nodes"
				echo 'module(load="imudp") # needs to be done just once' >> /etc/rsyslog.d/ohpc.conf
				echo 'input(type="imudp" port="514")' >> /etc/rsyslog.d/ohpc.conf

				# Restart rsyslog for changes to take effect
				systemctl restart rsyslog

				# Configure example genders file
				console_taskstart_msg "Configuring sample entries in /etc/genders"
				echo "c[001-064] compute" >> /etc/genders
				echo "b[001-004] bigmem" >> /etc/genders
				echo "g[001-016] gpu" >> /etc/genders
				echo "l[001-002] login" >> /etc/genders

				# Import current kernel (deprecated in 4.6)
				# wctl kernel import $(uname -r)

				pause_for_review
				break
				;;
			"Containers")
				# Create OS container
				# Make sure everything is clean before we start
				if [ -d  /tmp/image/ ]; then
					rm -rf /tmp/image/
				fi
				## TODO Detect RHEL - disable online repos


				read -e -p "Enter name for container, such as compute,bigmem,gpu,login or storage: " -i "$os_id$os_version_full" container_name
				case "$os_id-$os_version_major" in
				"rhel-8")
					console_taskstart_msg "Installing base configuration into container image for rhel-8"
					yum -y --releasever $os_version_full install --installroot /tmp/image/$container_name basesystem bash chkconfig coreutils e2fsprogs xfsprogs parted gdisk bind-utils ethtool filesystem findutils gawk grep initscripts iproute iputils net-tools mtr nfs-utils pam psmisc rsync pdsh bc sed setup shadow-utils rsyslog chrony tzdata ntpstat words zlib tar less gzip which util-linux openssh-clients openssh-server dhclient pciutils vim-minimal shadow-utils strace cronie crontabs cpio wget ipmitool yum NetworkManager kernel kernel-devel perl libnl3 tcl tk lsof gcc-gfortran numactl-libs hwloc hwloc-libs lshw hostname
					;;
				"rhel-9")
					console_taskstart_msg "Installing base configuration into container image for rhel-9"
					yum -y --releasever $os_version_full install --installroot /tmp/image/$container_name basesystem bash chkconfig coreutils e2fsprogs xfsprogs parted ignition gdisk bind-utils ethtool filesystem findutils gawk grep initscripts iproute iputils net-tools mtr nfs-utils pam psmisc rsync pdsh bc sed setup shadow-utils rsyslog chrony tzdata ntpstat words zlib tar less gzip which util-linux openssh-clients openssh-server dhclient pciutils vim-minimal shadow-utils strace cronie crontabs cpio wget ipmitool yum NetworkManager kernel kernel-devel perl libnl3 tcl tk lsof gcc-gfortran numactl-libs hwloc hwloc-libs lshw hostname 
					;;
				"rocky-8")
					console_taskstart_msg "Installing base configuration into container image for rocky-8"
					yum -y --releasever $os_version_full install --installroot /tmp/image/$container_name basesystem bash chkconfig coreutils e2fsprogs xfsprogs parted gdisk bind-utils ethtool filesystem findutils gawk grep initscripts iproute iputils net-tools mtr nfs-utils pam psmisc rsync pdsh bc sed setup shadow-utils rsyslog chrony tzdata ntpstat words zlib tar less gzip which util-linux openssh-clients openssh-server dhclient pciutils vim-minimal shadow-utils strace cronie crontabs cpio wget ipmitool yum NetworkManager kernel kernel-devel perl libnl3 tcl tk lsof gcc-gfortran numactl-libs hwloc hwloc-libs lshw hostname rocky-release
					;;
				"rocky-9")
					console_taskstart_msg "Installing base configuration into container image for rocky-8"
					yum -y --releasever $os_version_full install --installroot /tmp/image/$container_name basesystem bash chkconfig coreutils e2fsprogs xfsprogs parted ignition gdisk bind-utils ethtool filesystem findutils gawk grep initscripts iproute iputils net-tools mtr nfs-utils pam psmisc rsync pdsh bc sed setup shadow-utils rsyslog chrony tzdata ntpstat words zlib tar less gzip which util-linux openssh-clients openssh-server dhclient pciutils vim-minimal shadow-utils strace cronie crontabs cpio wget rocky-release ipmitool yum NetworkManager kernel kernel-devel perl libnl3 tcl tk lsof gcc-gfortran numactl-libs hwloc hwloc-libs lshw hostname rocky-release
					;;
				*)
					# Account for any non-supported configs 
					console_taskstart_msg "Guess what.  This is not a supported configuration, attempting $os_id-$os_version_major"
					exit 1
					;;
				esac

				CHROOT=/tmp/image/$container_name

				# Install Dell IDRAC Tools agent
				console_info_msg "Extracting Dell IDRAC Tools in $container_name"
				cd /tmp 
				tar xvf /root/Dell-iDRACTools-Web-LX-*
				cd iDRACTools/racadm/RHEL$os_version_major/x86_64
				# remove selinux and tomcat if they exist
				rm -f srvadmin-selinux*.rpm srvadmin-tomcat*.rpm
				console_info_msg "Installing Dell IDRAC Tools via DNF LocalInstall ..."
				dnf localinstall -y --installroot=$CHROOT *.rpm
				cd /tmp/
				rm -rf license.txt COPYRIGHT.txt iDRACTools

				if [ ! -f $CHROOT/etc/profile.d/dractools.sh ]; then
					echo 'export PATH="$PATH:/opt/dell/srvadmin/sbin"' > $CHROOT/etc/profile.d/dractools.sh
					console_taskcomplete_msg "dractools.sh added to $CHROOT/etc/profile.d/"
				else
					console_taskcomplete_msg "dractools.sh already exists in $CHROOT/etc/profile.d/"
				fi

				sleep 10

				# Install Mellanox OFED
				# Determine if Mellanox OFED is installed on the head node:
				console_taskstart_msg "Installing Mellanox OFED in $container_name"
				mlnx_ofed_installed=`rpm -qa|grep mlnx-ofa_kernel`

				if [ ! -z "$mlnx_ofed_installed" ];then
					cd $CHROOT/tmp
					tar zxvf /root/MLNX_OFED*.tgz
					chroot $CHROOT /bin/bash -c "/tmp/MLNX_OFED*/mlnxofedinstall --without-32bit --without-fw-update --skip-distro-check --distro rhel$os_version_full --kmp --hpc -q"
					chroot $CHROOT /bin/bash -c "rm -rf /tmp/MLNX_OFED* /tmp/ofed.conf"
				fi

				## Install Nvidia GPU driver
			#	if [ $container_name = "test" ]; then
			#		cp /root/cuda*.run $CHROOT/tmp
			#		cp /root/datacenter-gpu-manager*.rpm $CHROOT/tmp
			#		cp /root/nvidia-fabric-manager*.rpm $CHROOT/tmp
			#		mount --bind /sys $CHROOT/sys/
			#		mount --bind /dev $CHROOT/dev/
			#		mount -t proc /proc $CHROOT/proc/

					# Install CUDA driver
#					chroot $CHROOT /bin/bash -c "sh cuda*.run --silent --driver"

					# Install Nvidia Datacenter GPU Manager
			#		chroot $CHROOT /bin/bash -c "rpm -ivh $CHROOT/tmp/datacenter-gpu-manager*.rpm"

					# # Install Nvidia Fabric Manager
			#		chroot $CHROOT /bin/bash -c "rpm -ivh $CHROOT/tmp/nvidia-fabric-manager*.rpm"

					## Cleanup
			#		rm -f $CHROOT/tmp/cuda*.run
			#		rm -f $CHROOT/tmp/datacenter-gpu-manager*.rpm
			#		rm -f $CHROOT/tmp/nvidia-fabric-manager*.rpm
			#		chroot $CHROOT /bin/bash -c "/usr/bin/nvidia-persistenced"
			#		umount $CHROOT/sys/
			#		umount $CHROOT/dev/
			#		umount $CHROOT/proc/

					# Install Apptainer
			#		dnf install -y --installroot=$CHROOT apptainer apptainer-suid
			#	fi

				# Install OpenHPC packages
				console_taskstart_msg "Installing OpenHPC packages in $container_name"

				console_taskstart_msg "Copying EPEL*.repo from /etc/yum.repos.d to the image"
				cp /etc/yum.repos.d/epel.repo $CHROOT/etc/yum.repos.d/
				console_taskstart_msg "Copying the OpenHPC repo from /etc/yum.repos.d to the image"
				cp /etc/yum.repos.d/OpenHPC.repo $CHROOT/etc/yum.repos.d/
				console_taskstart_msg "Copying the OS offline repo from /etc/yum.repos.d to the image" 
				cp /etc/yum.repos.d/$os_id$os_version_full-offline.repo $CHROOT/etc/yum.repos.d/ 
				dnf -y --installroot $CHROOT install $EPEL_URL
				
				# Install OpenHPC packages in the container if they are not storage
				console_taskstart_msg "Installing OpenHPC packages in $container_name"
				if [ $container_name != "storage" ]; then
					dnf -y --installroot=$CHROOT install ohpc-base-compute 
					dnf -y --installroot=$CHROOT install ohpc-slurm-client
					dnf -y --installroot=$CHROOT install nhc-ohpc
				fi

				
				if [ $container_name = "storage" ]; then
					console_taskstart_msg "Installing storage packages in $container_name (because you are creating a storage container)"
					dnf -y --installroot=$CHROOT install numactl
				fi

				console_taskstart_msg "Configuring with lmod and ganglia $container_name"
				# Install Lmod needs active crb repo for lua-filesystem, lua-posix - without activation this needs to be done manually
				#### TODO : check for rpms first in /root (lua-filesystem, lua-posix), if not there prompt to check for them using crb repo to download
				dnf -y --installroot=$CHROOT localinstall /root/lua-*.rpm
				dnf -y --installroot=$CHROOT install lmod-ohpc
				
				# Configure name server 
				#### TODO (this may not be necessary as its in the wwinit overlay in 4.5)
				cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf

				# Configure Ganglia
				dnf -y --installroot=$CHROOT install ganglia-gmond
				cp -p /etc/ganglia/gmond.conf $CHROOT/etc/ganglia/

				# Configure the master node to be the first source of DNS
				perl -pi -e "s/127.0.0.1/$sms_ip/" $CHROOT/etc/resolv.conf

				# Configure chrony for time sync with head node
				#### TODO: update this to be rocky-agnostic *pool.ntp.org"
				perl -pi -e "s/pool 2.rocky.pool.ntp.org/server $sms_name/g if /pool/" $CHROOT/etc/chrony.conf

				# Create systemd script to configure the time zone
				### TODO: Obsoleted in WW4.6 - use localtime tag and overlay (wwctl profile set default --tagadd="localtime=America/New_York")
				my_time_zone=`timedatectl show|grep Timezone|awk -F = '{print $2}'`

				
				cat <<EOF > $CHROOT/usr/lib/systemd/system/systemd-timezone.service
[Unit]
Description=service to set Time Zone
After=network.target
StartLimitIntervalSec=5

[Service]
Type=oneshot
Restart=on-failure
RestartSec=3
ExecStart=/usr/bin/timedatectl set-timezone $my_time_zone

[Install]
WantedBy=multi-user.target
EOF
				# Configure rsyslog
				# Define compute node forwarding destination
				echo "*.* @${sms_ip}:514" >> $CHROOT/etc/rsyslog.conf
				echo "Target=\"${sms_ip}\" Protocol=\"udp\"" >> $CHROOT/etc/rsyslog.conf

				# Disable most local logging on computes. Emergency and boot logs will remain on the compute nodes
				perl -pi -e "s/^\*\.info/\\#\*\.info/" $CHROOT/etc/rsyslog.conf
				perl -pi -e "s/^authpriv/\\#authpriv/" $CHROOT/etc/rsyslog.conf
				perl -pi -e "s/^mail/\\#mail/" $CHROOT/etc/rsyslog.conf
				perl -pi -e "s/^cron/\\#cron/" $CHROOT/etc/rsyslog.conf
				perl -pi -e "s/^uucp/\\#uucp/" $CHROOT/etc/rsyslog.conf

				# Edit file settings
				cp -p /etc/security/limits.conf /etc/security/limits.conf.orig
				perl -pi -e 's/# End of file/\* soft memlock unlimited\n$&/s' /etc/security/limits.conf
				perl -pi -e 's/# End of file/\* hard memlock unlimited\n$&/s' /etc/security/limits.conf
				perl -pi -e 's/# End of file/\* soft memlock unlimited\n$&/s' ${CHROOT}/etc/security/limits.conf
				perl -pi -e 's/# End of file/\* hard memlock unlimited\n$&/s' ${CHROOT}/etc/security/limits.conf

				# Enable services 
				## Timezone service is obsoleted in WW4.6
				chroot $CHROOT /bin/bash -c "systemctl enable systemd-timezone.service --now"
				chroot $CHROOT systemctl enable chrony --now
				chroot $CHROOT systemctl enable munge --now
				chroot $CHROOT systemctl enable slurmd --now
				chroot $CHROOT systemctl enable gmond --now

				# Import the container to warewulf
				wwctl container import /tmp/image/$container_name $container_name

				# Sync user/group info to the container
				wwctl container syncuser --write $container_name

				# Build the compressed bootable image
				wwctl container build $container_name

				# Cleanup
				rm -rf /tmp/image/

				sleep 2
				break
				;;
			"Default")
				# Configure default node profile
				read -e -p "Enter provisioning subnet mask: " -i "${internal_netmask}" def_prov_netmask
				# Get provisioning gateway
				read -e -p "Enter provisioning gateway: " -i "${sms_ip}" def_prov_gateway
				
				echo "Setting provisioning subnet mask and gateway for the default node profile"
				wwctl profile set -y default --netmask=${def_prov_netmask} --gateway=${def_prov_gateway}

				# Prompt to set a default nic profile for the provisioning network 
				read -p "Do you want to set a default provisioning NIC? (y/n): " response

				case "$response" in 
					[yY][eE][sS]|[yY])
						# Ask user to confirm or change the NIC
						read -p "Enter the provisioning NIC [default: $sms_eth_internal]: " provisioned_nic
						# Use default if input is empty
						provisioned_nic="${user_nic:-$sms_eth_internal}"
						echo "Provisioning NIC set to: $provisioned_nic"
						wwctl profile set -y default --netdev=$provisioned_nic
						;;
					[nN][oO]|[nN])
						echo "Default Provisioning NIC setup skipped. Make sure you define this on the node level."
						;;
					*)
						echo "Invalid input. Please enter 'y' or 'n'."
						;;
				esac


				sleep 2
				break
				;;

			"Networks")
				## Configure networks
				PS3="Select network to create/configure: "
				select net in iDRAC InfiniBand OmniPath "High Speed Ethernet" Quit
				do
					case $net in
						"iDRAC")
							echo "You selected iDRAC"
							# Confirm iDRAC netmask
							read -e -p "Enter iDRAC subnet mask: " -i "${bmc_netmask}" idrac_netmask
							read -e -p "Enter iDRAC gateway ip: " -i "${sms_bmc_gateway}" idrac_gateway
							echo y|wwctl profile set default --ipmiuser=${bmc_username} --ipmipass=${bmc_password} --ipminetmask=${idrac_netmask} --ipmigateway=${idrac_gateway} --ipmiinterface=lanplus
							sleep 2
							;;
						"InfiniBand")
							echo "You selected InfiniBand"
							read -e -p "Enter InfiniBand subnet mask: " -i "${ipoib_netmask}" ib_netmask
							echo y|wwctl profile set default --netname=ibnet --type=InfiniBand --mtu 4096 --netmask=${ib_netmask}
							sleep 2
							;;
						"OmniPath")
							echo "You selected OmniPath"
							read -e -p "Enter OmniPath subnet mask: " -i "${ipoib_netmask}" opa_netmask
							echo y|wwctl profile set default --netname=opanet --type=InfiniBand --netmask=${opa_netmask}
							sleep 2
							;;
						"High Speed Ethernet")
							echo "You selected High Speed Ethernet"
							read -e -p "Enter High Speed Ethernet subnet mask: " -i "" hseth_netmask
							read -e -p "Enter High Speed Ethernet gateway ip: " -i "" hseth_gateway
							echo y|wwctl profile set default --netname=hsethernet --type=Ethernet --netmask=${hseth_netmask} --gateway=${hseth_gateway}
							sleep 2
							;;
						"Quit")
							break;;
						*)
							echo "Invalid choice. Please try again."
							;;
					esac
				done

				sleep 2
				break
				;;

			"Profiles")
				# Create profiles
				PS3="Select profile to create: "
				select prof in InfiniBand Compute Bigmem "Nvidia GPU" "AMD GPU" Login  Storage "AMD Zen3 Kernel" Quit
				do
					case $prof in
						"InfiniBand")
							echo "You selected InfiniBand"
							sleep 2
							echo y|wwctl profile add infiniband-nodes --comment "Nodes that have Mellanox InfiniBand" --netname ibnet --mtu 4096 --netmask ${ipoib_netmask} --type infiniband
							;;
						"Compute")
							echo "You selected Compute"
							sleep 2
							echo y|wwctl profile add --comment "Standard compute nodes" -C compute compute
							;;
						"Bigmem")
							echo "You selected Bigmem"
							sleep 2
							echo y|wwctl profile add --comment "Large memory compute nodes" -C bigmem bigmem
							;;
						"Nvidia GPU")
							echo "You selected Nvidia GPU Compute"
							sleep 2
							echo y|wwctl profile add --comment "Compute nodes with Nvidia GPU" --kernelargs "quiet crashkernel=no vga=791 net.naming-scheme=v238 modprobe.blacklist=nouveau" -C gpu gpu
							;;
						"AMD GPU")
							echo "You selected AMD GPU Compute"
							sleep 2
							echo y|wwctl profile add --comment "Compute nodes with AMD GPU" --kernelargs "quiet crashkernel=no vga=791 net.naming-scheme=v238 modprobe.blacklist=nouveau" -C gpu-amd gpu-amd
							;;
						"Login")
							echo "You selected Login"
							sleep 2
							echo y|wwctl profile add --comment "User login node" -C login login
							;;
						"Storage")
							echo "You selected Storage"
							sleep 2
							echo y|wwctl profile add --comment "Storage node" -C storage storage
							;;
						"AMD Zen3 Kernel")
							echo "You selected AMD Kernel parameter"
							sleep 2
							echo y|wwctl profile add --comment "AMD Zen3 Kernel Parameter" --kernelargs "quiet crashkernel=no vga=791 net.naming-scheme=v238 iommu=pt"  amdkernel
							;;
						"Quit")
							break;;
						*)
							echo "Invalid choice. Please try again."
							;;
					esac
				done

				sleep 1
				break
				;;
			"Overlays")
				# Create overlays
				PS3="Select overlay to create: "
				select ovrl in Slurm Quit
				do
					case $ovrl in
						"Slurm")
							echo "You selected Slurm"
							sleep 2
							if [ ! -f /etc/slurm/slurm.conf ]; then
								echo "slurm.conf not found"
								echo "Install slurm before running"
								sleep 3
								clear;
								show_main_menu;
							fi

							munge_uid=`cat /etc/passwd|grep munge|awk -F : '{print $3}'`
							wwctl overlay create slurm
							wwctl overlay mkdir slurm /etc/slurm
							wwctl overlay mkdir slurm /etc/munge/
							wwctl overlay chown slurm /etc/munge/ ${munge_uid} ${munge_uid}
							wwctl overlay mkdir slurm /var/lib/munge
							wwctl overlay chown slurm /var/lib/munge ${munge_uid} ${munge_uid}
							wwctl overlay mkdir slurm /var/log/munge
							wwctl overlay chown slurm /var/log/munge ${munge_uid} ${munge_uid}
							wwctl overlay import slurm /etc/slurm/slurm.conf
							wwctl overlay import slurm /etc/munge/munge.key
							wwctl overlay chown slurm /etc/munge/munge.key ${munge_uid} ${munge_uid}

							# Add slurm overlay to profiles that need it
							slurm_profs=`wwctl profile list|awk -F ' ' '{print $1}'|grep -v default|grep -v PROFILE|grep -v =`
							for profile in $slurm_profs; do echo y|wwctl profile set $profile slurm; done
							sleep 2
							;;
						"Quit")
							break;;
						*)
							echo "Invalid choice. Please try again."
							;;
					esac
				done
				sleep 2
				break
				;;
			"Partitions")
				echo "Nothing yet.."
				sleep 3
				break
				;;
			"Menu")
				echo "Returning to main menu.."
				sleep 2
				clear;
				show_main_menu;
				;;
		esac
	done
	sleep 2

}
run_first() {
	# Since this directory will only not exist the first time
	# this script is run, this is basically a "run once" section.
	if [ -f "/root/anaconda-ks.cfg" ]; then
		rm -f /root/anaconda-ks.cfg
	fi

	if [ ! -d "/opt/ohpc/pub/apps/dell/firmware/PowerEdge" ]; then
		mkdir -p /opt/ohpc/pub/apps/dell/firmware/PowerEdge

		# Configure SSHD for speed and allowing X11
		cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
		sed -i 's|#Port 22|Port 22|g' /etc/ssh/sshd_config
		sed -i 's|#LoginGraceTime 2m|LoginGraceTime 1m|g' /etc/ssh/sshd_config
		sed -i 's|#MaxAuthTries 6|MaxAuthTries 5|g' /etc/ssh/sshd_config
		sed -i 's|#UseDNS no|UseDNS no|g' /etc/ssh/sshd_config
		sed -i 's|#X11Forwarding no|X11Forwarding yes|g' /etc/ssh/sshd_config
		sed -i 's|#X11DisplayOffset 10|X11DisplayOffset 10|g' /etc/ssh/sshd_config
		sed -i 's|#AllowTcpForwarding yes|AllowTcpForwarding yes|g' /etc/ssh/sshd_config
		systemctl restart sshd.service

		# These are specific for serving time to the cluster via chronyd
		# Confgure where we want to share NTP
		sed -i -e "s/#allow 192.168.0.0\/16/allow ${internal_base_net}\/${internal_cidr}/g" /etc/chrony.conf

		# Serve time even if not synchronized to a time source
		sed -i -e "s/#local stratum 10/local stratum 10/g" /etc/chrony.conf
		/bin/systemctl restart chronyd
	fi  
}

show_main_menu() {
    echo -e "${BLUE}* Script Version: ${script_version} * Detected OS - $os_distro $os_version_full * OSType - $os_id ${RESET}"
	echo ""
    echo -e "${BLUE}************************************************${RESET}"
    echo -e "${BLUE}**    Dell HPC Warewulf Master Host Config    **${RESET}"
    echo -e "${BLUE}************************************************${RESET}"
    echo -e "${BLUE}**${YELLOW}  1)${BLUE} Disable firewalld/SELinux (master node) ${RESET}"
	echo -e "${BLUE}**${YELLOW} 11)${BLUE} Configure local OS repo from ISO ${RESET}"
	echo -e "${BLUE}**${YELLOW} 12)${BLUE} Install prerequisite RPM packages ${RESET}"
	echo -e "${BLUE}**${YELLOW} 13)${BLUE} Install Dell OpenManage (master node) ${RESET}"
	echo -e "${BLUE}**${YELLOW}  2)${BLUE} Configure hostname (master node)  ${RESET}"
    echo -e "${BLUE}**${YELLOW}  3)${BLUE} Configure DNS / name servers ${RESET}"
    echo -e "${BLUE}**${YELLOW}  4)${BLUE} Configure provisioning ethernet interface (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW}  5)${BLUE} Configure alias interface for ipmi/mgmt connectivty (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW}  6)${BLUE} Configure external ethernet interface (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW}  7)${BLUE} Configure InfiniBand interface (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW}  8)${BLUE} Configure iDRAC/ipmi interface (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW}  9)${BLUE} Configure time zone and time server (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 14)${BLUE} Install Mellanox OFED (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 15)${BLUE} Install Cornelis Networks Omni-Path (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 16)${BLUE} Update master node firmware (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 17)${BLUE} Update master node CPLD firmware (master node) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 18)${BLUE} Install/Configure Warewulf v4 ${RESET}"
    echo -e "${BLUE}**${YELLOW} 19)${BLUE} Install OpenHPC (v2.x/v3.x) ${RESET}"
    echo -e "${BLUE}**${YELLOW} 20)${BLUE} Configure File Synchronization ${RESET}"
    echo -e "${BLUE}**${YELLOW} 21)${BLUE} Create Users/Groups ${RESET}"
    echo -e "${BLUE}**${YELLOW} 22)${BLUE} Configure User tests ${RESET}"
    echo -e "${BLUE}**${YELLOW} 23)${BLUE} Install Mellanox HPC-X ${RESET}"
    echo -e "${BLUE}**${YELLOW} 24)${BLUE} Install Intel oneAPI ${RESET}"
    echo -e "${BLUE}**${YELLOW} 25)${BLUE} Install Nvidia CUDA Toolkit ${RESET}"
    echo -e "${BLUE}**${YELLOW} 26)${BLUE} Configure Slurm Workload Manager ${RESET}"
	echo "MONITORING"
    echo -e "${BLUE}**${YELLOW} 27)${BLUE} Install / Configure Nagios monitoring / alerting ${RESET}"
    echo -e "${BLUE}**${YELLOW} 28)${BLUE} Install / Configure Ganglia monitoring ${RESET}"
    echo -e "${BLUE}**${YELLOW} 29)${BLUE} Enable firewalld  ${RESET}"
    echo -e "${BLUE}**${YELLOW} 30)${BLUE} Secure sshd with Fail2Ban  ${RESET}"
    echo -e "${BLUE}**${YELLOW} 31)${BLUE} Configure Caching Nameserver  ${RESET}"
    echo -e "${BLUE}**${YELLOW} 32)${BLUE} Post Deployment Cleanup !!!RUN THIS BEFORE LEAVING!!!  ${RESET}"
    echo -e "${BLUE}************************************************${RESET}"
    echo -e "${ENTER_LINE}Please enter a menu option and enter or ${RED_TEXT}enter to exit. ${RESET}"
    read opt

while [ opt != '' ]
do
    if [[ $opt = "" ]]; then
    exit;
    else
    case $opt in
		1) show_security_menu; clear; show_main_menu ;;
		2) configure_master_hostname; clear; show_main_menu ;;
		3) configure_master_host_dns; clear; show_main_menu ;;
		4) interface_config_masterhost_provisioning; clear; show_main_menu ;;
		5) interface_config_masterhost_alias; clear; show_main_menu ;;
		6) interface_config_masterhost_external; clear; show_main_menu ;;
		7) interface_config_masterhost_infiniband; clear; show_main_menu ;;
		8) interface_config_idrac_masterhost; clear; show_main_menu ;;
		9) configure_master_timezone_chrony; clear; show_main_menu ;;
		11) build_local_os_repo; clear; show_main_menu ;;
		12) install_ohpc_ww_prereqs; clear; show_main_menu ;;
		13) install_openmanage_master;	clear; show_main_menu ;;
		14) install_mellanox_ofed_master; clear; show_main_menu ;;
		15) install_cornelis_omnipath_masternode; clear; show_main_menu ;;
		16) install_master_node_firmware; clear; show_main_menu ;;
        17) install_master_node_cpld_firmware; clear; show_main_menu ;;
        18) install_configure_warewulf_menu; clear; show_main_menu ;;
        19) install_openhpc_packages_master; clear; show_main_menu ;;
		20) clear; option_picked "Option 20 Picked";
        # Configure File Synchronization
	echo ""
	echo "Enter nodes to push files to"
	echo ""
	echo "Example: "-g compute,bigmem,gpu,login""
	echo "or"
	echo "Example: "-w c[001-032]""
	echo ""
	read -e -p "Enter nodes : " -i "-g compute,bigmem,gpu,login"  node_list
	echo "" 
	echo "Enter minutes between cron jobs (Suggest 5 or 10)"
	echo ""
	read -e -p "Enter minutes : " -i "5"  cron_time
	
	# Get existing cron, if any
	crontab -l > /tmp/cron.out

	# Remove previous version (if exists)
	if [ -f "/root/bin/filesync.sh" ]; then
		rm -f /root/bin/filesync.sh
		sed -i '/filesync.sh/d' /tmp/cron.out
	fi

	# Add the sync job to cron
	echo "*/${cron_time} * * * * /root/bin/filesync.sh > /dev/null 2>&1" >> /tmp/cron.out

	# Create file sync script
	if [ ! -d /root/bin ]; then
		mkdir -p /root/bin
	fi
	tee > /root/bin/filesync.sh << EOF
#!/bin/bash

# Sync host info to other cluster nodes
pdcp NODES /etc/hosts /etc

# Sync user/group info to other cluster nodes
pdcp NODES /etc/passwd /etc
pdcp NODES /etc/group /etc
pdcp NODES /etc/shadow /etc

# Sync slurm scheduler configuration
pdcp NODES /etc/slurm/slurm.conf /etc/slurm
pdcp NODES /etc/munge/munge.key /etc/munge
pdsh NODES chown -R munge:munge /etc/munge/
pdsh NODES systemctl start munge
pdsh NODES systemctl start slurmd

EOF
	# Edit the nodes
	perl -pi -e "s/NODES/$node_list/g" /root/bin/filesync.sh

	# Make the script executable
	chmod +x /root/bin/filesync.sh

	# Reimport the crontab
	crontab /tmp/cron.out

	# Cleanup
	rm -f /tmp/cron.out
	sleep 2
	clear;
	show_main_menu;
    ;;

    21) clear;
    option_picked "Option 21 Picked";
        # Create Users/Groups

	# Create Dell group if it doesn't exist
	dell_group=`cat /etc/group|grep dell`

	if [ -z "$dell_group" ]; then
		groupadd -g 4999 dell
	fi

	PS3='Select user to create: '
	echo "Select user to create: "
	options=("hpl" "gpu" "other" )
	select opt in "${options[@]}"
	do
		case $opt in
			"hpl")
				useradd hpl -u 4999 -g 4999 -c "High Performance Linpack" -m
				break
				;;
			"gpu")
				useradd gpu -u 4998 -g 4999 -c "Nvidia CUDA High Performance Linpack" -m
				break
				;;
			"other")
				# Get username
				read -e -p "Enter username : " -i "" user_name
				# Get display name
				read -e -p "Enter display name : " -i "" display_name
				# Get user ID
				read -e -p "Enter user ID (blank if none): " -i "5001" user_id
				# Get group ID
				read -e -p "Enter group ID (blank if none): " -i "4999" group_id
				# Get shell
				read -e -p "Enter preferred shell : " -i "/bin/bash" user_shell

				# Create the user
				if [[ -z "${group_id}" ]] &&  [[ -z "${user_id}" ]];then
					useradd $user_name -c "${display_name}" -s ${user_shell} -m
					passwd $user_name
				elif [[ -z "${group_id}" ]] && [[ ! -z "${user_id}" ]];then
					# Check if the group exists, create it if it does not
					groupcheck=`cat /etc/group|grep ${group_id}`
					if [ -z "${groupcheck}" ];then
						# Get group name
						read -e -p "Enter group name (one word, no spaces, cannot be blank): " -i "" group_name
						groupadd -g ${group_id}
					fi
					useradd $user_name -u ${user_id} -g ${group_id} -c "${display_name}" -s ${user_shell} -m
					passwd $user_name
				elif [[ ! -z "${group_id}" ]] && [[ -z "${user_id}" ]];then
					# Check if the group exists, create it if it does not
					groupcheck=`cat /etc/group|grep ${group_id}`
					if [ -z "${groupcheck}" ];then
						# Get group name
						read -e -p "Enter group name (one word, no spaces, cannot be blank): " -i "" group_name
						groupadd -g ${group_id} ${group_name}
					fi
					useradd $user_name -g ${group_id} -c "${display_name}" -s ${user_shell} -m
					passwd $user_name
				elif [[ ! -z "${group_id}" ]] && [[ ! -z "${user_id}" ]];then
					# Check if the group exists, create it if it does not
					groupcheck=`cat /etc/group|grep ${group_id}`
					if [ -z "${groupcheck}" ];then
						# Get group name
						read -e -p "Enter group name (one word, no spaces, cannot be blank): " -i "" group_name
						groupadd -g ${group_id} ${group_name}
					fi
					useradd $user_name -u ${user_id} -g ${group_id} -c "${display_name}" -s ${user_shell} -m
					passwd $user_name
				fi
				break
				;;
		esac
	done

	sleep 2
	clear;
    show_main_menu;
    ;;

    22) clear;
    option_picked "Option 22 Picked";
        # Unpack stuff into hpl or gpu user dirs
	dell_hpc_file=`ls /root/|grep dell_bright*.tgz`
	if [[ -z "$dell_hpc_file" ]]; then
		echo ""
		echo ""
		echo "Please upload the file and run this again."
		sleep 3
		clear;
		show_main_menu;
	fi

	# Unpack Bright tarball so we can use those files
	if [ ! -d /root/dell ]; then
		tar zxvf /root/dell_bright*.tgz
	fi

	# Copy racadm scripts so they can be used
	cp /root/dell/scripts/hpc_bios_settings.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/racadm*.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/dell-collection*.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/get_ServiceTag.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/create_tsr.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/f1_error_prompt.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/scripts/PsbCheck_5.sh /opt/ohpc/pub/apps/dell/
	cp /root/dell/files/slurm-cheat-sheet\(quick\&dirty\).txt /root/
	cp /root/dell/files/Credentials.txt /root/
	chmod +x /opt/ohpc/pub/apps/dell/*.sh

	# Unpack Mellanox tools
	mkdir -p /opt/ohpc/pub/apps/mellanox
	cp /root/dell/scripts/configure_fattree_sm.sh /opt/ohpc/pub/apps/mellanox/
	chmod +x /opt/ohpc/pub/apps/mellanox/configure_fattree_sm.sh
	tar xvf /root/dell/files/splitport.tar -C /opt/ohpc/pub/apps/mellanox/


	hpl_dir=`cat /etc/passwd|grep hpl|awk -F : '{print $6}'`
	if [ ! -d "$hpl_dir" ]; then
		echo "HPL user not created"
		echo ""
		echo "Create HPL user, then rerun this function"
		sleep 3
		clear;
		show_main_menu;
	fi

	# Identify CPU and unpack corresponding files:
	proc_vendor=`cat /proc/cpuinfo |grep vendor_id|head -1|awk -F : '{print $2}'|sed -e 's/^[ \t]*//'`
	echo ""
	echo "Master node CPU architecture is ${proc_vendor}"
	echo ""
	sleep 2

	# Configure files in hpl homedir
	HPLDIR=`cat /etc/passwd|grep hpl|awk -F : '{print $6}'`
	mkdir -p $HPLDIR/{bin,alltoall,bibw}
	mkdir -p $HPLDIR/{single/logs,full/logs}
	cp /root/dell/scripts/execute_alltoall.sh $HPLDIR/
	cp /root/dell/scripts/evaluate_bibw.sh $HPLDIR/
	cp /root/dell/scripts/evaluate_bibw_alt.sh $HPLDIR/
	cp /root/dell/scripts/evaluate_hpl_singles.sh $HPLDIR/
	cp /root/dell/scripts/evaluate_stream.sh $HPLDIR/
	cp /root/dell/files/HPL.dat $HPLDIR/single/
	cp /root/dell/files/HPL.dat_full $HPLDIR/full/HPL.dat
	cp /root/dell/scripts/hpl_pxq.sh $HPLDIR/
	cp /root/dell/scripts/hpl_calculate_N.sh $HPLDIR/
	cp /root/dell/scripts/hpl_calculate_N.py $HPLDIR/
	cp /root/dell/scripts/hpl_efficiency_calc.sh $HPLDIR/
	cp /root/dell/scripts/hpl_theoretical_peak_calc.sh $HPLDIR/
	cp /root/dell/files/Running_benchmarks.txt $HPLDIR/
	cp /root/dell/files/slurm-sbatch-examples.txt $HPLDIR/
	chmod +x $HPLDIR/*.sh
	chmod +x $HPLDIR/*.py

	PS3='Choose compute architecture: '
	arch=("Intel" "AMD" "Both" "Quit")
	select fav in "${arch[@]}"; do
		case $fav in
			"Intel")
				HPLDIR=`cat /etc/passwd|grep hpl|awk -F : '{print $6}'`
				mkdir -p $HPLDIR/stream;tar zxvf /root/dell/files/stream-unified-2023.tgz -C $HPLDIR/stream
				cp /root/dell/scripts/single.sh $HPLDIR/
				cp /root/dell/scripts/runhpl.sh $HPLDIR/full/
				chmod +x $HPLDIR/*.sh
				break
				;;

			"AMD")
				HPLDIR=`cat /etc/passwd|grep hpl|awk -F : '{print $6}'`
				tar -zxvf /root/dell/files/amd-hpl-zen3-20230811.tgz -C $HPLDIR/
				cp /root/dell/scripts/single-amd.sh $HPLDIR/
				mkdir -p $HPLDIR/stream;tar zxvf /root/dell/files/stream-unified-2023.tgz -C $HPLDIR/stream
				cp /root/dell/scripts/set_AMD_params.sh $HPLDIR/
				tar zxvf /root/dell/files/amd/zen4/amd-zen-stream-2022_11.tar.gz -C $HPLDIR/
				cp /root/dell/files/amd/zen4/node.sh $HPLDIR/amd-zen-stream-2022_11/
				cp /root/dell/files/amd/zen4/run.sh $HPLDIR/amd-zen-stream-2022_11/
				tar zxvf /root/dell/files/amd/zen4/amd-zen-hpl-2023_07_18.tar.gz -C $HPLDIR/
				cp /root/dell/files/amd/zen4/single-amd-zen4.sh $HPLDIR/
				cp /root/dell/files/amd/zen4/HPL.dat.zen4 $HPLDIR/single/
				cp /root/dell/files/amd/zen4/evaluate_hpl_singles_zen4.sh $HPLDIR/
				cp /root/dell/scripts/amd_hpc_bios_settings_step*.sh /opt/ohpc/pub/apps/dell/
				cp /root/dell/files/amd/zen4/amd_hpc_bios_settings_zen4.sh /opt/ohpc/pub/apps/dell/
				chmod +x $HPLDIR/*.sh
				chmod +x /opt/ohpc/pub/apps/dell/amd_hpc_bios*.sh
				break
				;;

			"Both")
				HPLDIR=`cat /etc/passwd|grep hpl|awk -F : '{print $6}'`
				cp /root/dell/scripts/single.sh $HPLDIR/
				mkdir -p $HPLDIR/stream;tar zxvf /root/dell/files/stream-unified-2023.tgz -C $HPLDIR/stream

				tar -zxvf /root/dell/files/amd-hpl-zen3-20230811.tgz -C $HPLDIR/
				cp /root/dell/scripts/single-amd.sh $HPLDIR/
				cp /root/dell/scripts/amd_hpc_bios_settings_step*.sh /opt/ohpc/pub/apps/dell/
				cp /root/dell/files/amd/zen4/amd_hpc_bios_settings_zen4.sh /opt/ohpc/pub/apps/dell/
				cp /root/dell/scripts/set_AMD_params.sh $HPLDIR/
				tar zxvf /root/dell/files/amd/zen4/amd-zen-stream-2022_11.tar.gz -C $HPLDIR/
				cp /root/dell/files/amd/zen4/node.sh $HPLDIR/amd-zen-stream-2022_11/
				cp /root/dell/files/amd/zen4/run.sh $HPLDIR/amd-zen-stream-2022_11/
				tar zxvf /root/dell/files/amd/zen4/amd-zen-hpl-2023_07_18.tar.gz -C $HPLDIR/
				cp /root/dell/files/amd/zen4/single-amd-zen4.sh $HPLDIR/
				cp /root/dell/files/amd/zen4/HPL.dat.zen4 $HPLDIR/single/
				cp /root/dell/files/amd/zen4/evaluate_hpl_singles_zen4.sh $HPLDIR/
				chmod +x $HPLDIR/*.sh
				chmod +x /opt/ohpc/pub/apps/dell/*.sh
				break
				;;
			"Quit")
				echo "User requested exit"
				clear;
				show_main_menu;
				break
				;;
			*) echo "invalid option $REPLY";;
		esac
	done

	sleep 2
	clear;
    show_main_menu;
    ;;

    23) clear;
    option_picked "Option 23 Picked";
        # Install Mellanox HPC-X
	# Attempt to download HPC-X
	wget -nc $HPCX218_URL
	hpcx_file=`ls /root/|grep hpcx*.tbz`
	if [ -z "${hpcx_file}" ];then
		echo "Mellanox HPC-X tarball not found in /root"
		echo ""
		echo "Please upload the file and run this again."
		sleep 3
		clear;
		show_main_menu;
	fi

	mkdir -p /opt/ohpc/pub/apps/mellanox
	tar xvf /root/hpcx*.tbz -C /opt/ohpc/pub/apps/mellanox
	hpcx_version=`ls /root/|grep hpcx|awk -F v '{print $2}'|awk -F - '{print $1}'`
	file_dir=`ls /opt/ohpc/pub/apps/mellanox`
	file_dir_path=/opt/ohpc/pub/apps/mellanox/$file_dir
	mlnx_hpcx_dir=`ls /opt/ohpc/pub/apps/mellanox/|grep hpcx`

	# Add to /etc/profile on head node
	echo "" >> /etc/profile
	echo "### For Mellanox OFED 
	echo "module use /opt/ohpc/pub/apps/mellanox/$mlnx_hpcx_dir/modulefiles" >> /etc/profile

	# Add to /etc/profile in containers
	for i in `ls /var/lib/warewulf/chroots/`; do echo "" >> /var/lib/warewulf/chroots/$i/etc/profile;echo "module use /opt/ohpc/pub/apps/mellanox/$mlnx_hpcx_dir/modulefiles" >> /var/lib/warewulf/chroots/$i/etc/profile; done

	# Rebuild containers to save the change
	for i in `ls /var/lib/warewulf/chroots/`; do wwctl container build $i; done

	pause_for_review
	clear;
    show_main_menu;
    ;;

    24) clear;
    option_picked "Option 24 Picked";
        PS3='Install Intel oneAPI: '
	options=( "Install 2023.1.0" "Install 2024.0.1" "Install 2025.0.0" "Menu" )
	select opt in "${options[@]}"
	do
		case $opt in
			"Install 2023.1.0")
				# Install Intel oneAPI
				oneapi_version=`ls /root|grep HPCKit|grep -oe '\([0-9.]*\)'|head -1`

				echo "Installing Intel oneAPI HPCKit version ${oneapi_version}..."
				echo ""
				sleep 2

				chmod +x /root/l_*.sh
				./l_BaseKit*_offline.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all
				./l_HPCKit*_offline.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all

				/opt/ohpc/pub/apps/intel/oneapi-$oneapi_version/modulefiles-setup.sh
				mkdir -p /opt/ohpc/pub/modulefiles/intel/
				cd /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version/modulefiles
				cp -R --preserve=links advisor /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links ccl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links clck /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links compiler /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links compiler-rt /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links dal /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links debugger /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links dnnl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links dpct /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links dpl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links icc /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links init_opencl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links inspector /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links intel_ippcp_intel64 /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links intel_ipp_intel64 /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links itac /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links mkl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links mpi /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links oclfpga /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links tbb /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links vtune /opt/ohpc/pub/modulefiles/intel/
				cd /root/
				rm -rf /root/intel

				sleep 2
				break
				;;

			"Install 2024.0.1")
				# Attempt to download Intel oneAPI
				wget -nc https://registrationcenter-download.intel.com/akdlm/IRC_NAS/e6ff8e9c-ee28-47fb-abd7-5c524c983e1c/l_BaseKit_p_2024.2.1.100_offline.sh
				wget -nc https://registrationcenter-download.intel.com/akdlm/IRC_NAS/67c08c98-f311-4068-8b85-15d79c4f277a/l_HPCKit_p_2024.0.1.38_offline.sh

				# Install Intel oneAPI
				oneapi_version=`ls /root|grep HPCKit|grep -oe '\([0-9.]*\)'|head -1`

				echo "Installing Intel oneAPI HPCKit version ${oneapi_version}..."
				echo ""
				sleep 2

				chmod +x /root/l_*.sh
				./l_BaseKit*_offline.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all
				./l_HPCKit*_offline.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all

				/opt/ohpc/pub/apps/intel/oneapi-$oneapi_version/modulefiles-setup.sh
				mkdir -p /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/compiler /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/mkl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/mpi /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/ifort /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/advisor /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/compiler-rt /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/debugger /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dnnl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dpct /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dpl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/itac /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/oclfpga /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/ccl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/vtune /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/tbb /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/inspector /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/intel_ippcp_intel64 /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/intel_ipp_intel64 /opt/ohpc/pub/modulefiles/intel/
				rm -rf /root/modulefiles
				rm -rf /root/intel

				sleep 2
				break
				;;

			"Install 2025.0.0")
				# Attempt to download Intel oneAPI
				wget -nc https://registrationcenter-download.intel.com/akdlm/IRC_NAS/96aa5993-5b22-4a9b-91ab-da679f422594/intel-oneapi-base-toolkit-2025.0.0.885_offline.sh
				wget -nc https://registrationcenter-download.intel.com/akdlm/IRC_NAS/0884ef13-20f3-41d3-baa2-362fc31de8eb/intel-oneapi-hpc-toolkit-2025.0.0.825_offline.sh

				# Install Intel oneAPI
				oneapi_version=`ls /root|grep hpc-toolkit|grep -oe '\([0-9.]*\)'|head -1`

				echo "Installing Intel oneAPI HPCKit version ${oneapi_version}..."
				echo ""
				sleep 2

				chmod +x /root/intel-oneapi*.sh
				./intel-oneapi-base*.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all
				./intel-oneapi-hpc*.sh -a -s --eula accept --install-dir /opt/ohpc/pub/apps/intel/oneapi-$oneapi_version --components all

				/opt/ohpc/pub/apps/intel/oneapi-$oneapi_version/modulefiles-setup.sh
				mkdir -p /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/tbb /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/compiler /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/compiler-rt /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/umf /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/mkl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/mpi /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/advisor /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/debugger /opt/ohpc/pub/modulefiles/inte/
				cp -R --preserve=links /root/modulefiles/oclfpga /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/vtune /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dal /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dnnl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dpct /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/dpl /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/intel_ippcp_intel64 /opt/ohpc/pub/modulefiles/intel/
				cp -R --preserve=links /root/modulefiles/intel_ipp_intel64 /opt/ohpc/pub/modulefiles/intel/
				rm -rf /root/modulefiles
				rm -rf /root/intel

				sleep 2
				break
				;;

			"Menu" )
				break
				;;
		esac
	done

	sleep 1
	clear;
    show_main_menu;
    ;;

    25) clear; option_picked "Option 25 Picked";
        # Install Nvidia CUDA Toolkit
	## Gather information
	cuda_version=`ls /root|grep cuda*.run|awk -F _ '{print $2}'`
	cuda_file=`ls /root|grep cuda*.run`

	## Install Nvidia CUDA Toolkit
	cd /root
	echo "Installing CUDA Toolkit $cuda_version"
	sh ./$cuda_file --silent --toolkit --toolkitpath=/opt/ohpc/pub/apps/nvidia/cuda/toolkit/$cuda_version

	## Create Nvidia Toolkit modulefile
	mkdir -p /opt/ohpc/pub/modulefiles/nvidia/cuda/
	cat << EOF > /opt/ohpc/pub/modulefiles/nvidia/cuda/$cuda_version
#%Module1.0#####################################################################
proc ModulesHelp { } {

puts stderr " "
puts stderr "This module sets the Nvidia CUDA Toolkit path"
puts stderr " "
puts stderr "Version $cuda_version"
puts stderr " "

}

module-whatis "Name: Nvidia CUDA Toolkit"
module-whatis "Version: $cuda_version"
module-whatis "Category: GPU / AI Tools"
module-whatis "Description: set path for Nvidia CUDA Toolkit"

set     version                 $cuda_version

prepend-path    PATH            /opt/ohpc/pub/apps/nvidia/cuda/toolkit/$cuda_version/bin
prepend-path	LD_LIBRARY_PATH	/opt/ohpc/pub/apps/nvidia/cuda/toolkit/$cuda_version/lib64
EOF

	sleep 2
	clear;
    show_main_menu;
    ;;

    26) clear; option_picked "Option 26 Picked";
        ## Configure Slurm Workload Manager

	echo "/etc/genders MUST be configured in order for this to work."
	echo ""
	echo "The first node of each profile type MUST be up in order for this to work."
	echo ""

	read -e -p "Ready to proceed y/n?: " -i "y" proceed

	if [ "$proceed" != "y" ]; then
		echo "Returning to menu..."
		sleep 2
		clear;
		show_main_menu;
	fi

	# See if this is a reconfigure.
	if [ -f /etc/slurm/slurm.conf.orig ]; then
		read -e -p "A saved file exists. Is this a reconfiguration? y/n : " -i "y" reconfig
	fi

	# If first run, save the original in case we do this over again.
	if [ ! -f /etc/slurm/slurm.conf.orig ]; then
		cp /etc/slurm/slurm.conf /etc/slurm/slurm.conf.orig
	fi

	## Delete what we don't want
	# Remove the default entries:
	sed -i '/NodeName=/d' /etc/slurm/slurm.conf
	sed -i '/Nodes=/d' /etc/slurm/slurm.conf

	# Correct values
	perl -pi -e "s/ReturnToService=1/ReturnToService=2/" /etc/slurm/slurm.conf
	perl -pi -e "s/# OpenHPC default configuration/# Dell OpenHPC default configuration/" /etc/slurm/slurm.conf

	# Determine which groups of compute node types we have
	wwctl profile list|grep -v PROFILE|grep -v infiniband-nodes|grep -v Login|grep -v default|grep -v amdkernel|grep -v gpukernel|awk -F ' ' '{print $1}' > /tmp/compute_groups

	# Check for compute
	compute_nodes=`cat /tmp/compute_groups |grep compute`
	if [ -z "$compute_nodes" ]; then
		compute=0
	else
		compute=1
	fi

	# Check for bigmem
	bigmem_nodes=`cat /tmp/compute_groups |grep bigmem`
	if [ -z "$bigmem_nodes" ]; then
		bigmem=0
	else
		bigmem=1
	fi

	# Check for gpu
	gpu_nodes=`cat /tmp/compute_groups |grep gpu`
	if [ -z "$gpu_nodes" ]; then
		gpu=0
	else
		gpu=1
	fi

	configure_compute () {
		# Get nodes
		nodes=`wwctl node list|grep compute|awk -F ' ' '{print $1}'`

		# Create an expression
		node_expr=`/usr/bin/nodeset --fold ${nodes}`

		# Gather information from a node
		first_node=`wwctl node list|grep compute|head -1|awk -F ' ' '{print $1}'`
		real_mem=`ssh $first_node "free -g | grep Mem" | awk '{ print $2 }'`G
		sockets=`ssh $first_node "lscpu | grep Socket" | awk '{ print $NF }'`
		threads_per_core=`ssh $first_node "lscpu | grep 'per core'" | awk '{ print $NF }'`
		cores_per_socket=`ssh $first_node "lscpu | grep 'per socket'" | awk '{ print $NF }'`
		sed -i "/ReturnToService=2/i \
			NodeName=${node_expr} Sockets=${sockets} CoresPerSocket=${cores_per_socket} ThreadsPerCore=${threads_per_core} RealMemory=${real_mem} State=UNKNOWN" /etc/slurm/slurm.conf

		echo "Adding ${node_expr} to the Compute partition"
		sed -i "/ReturnToService=2/i \
			PartitionName=compute Nodes=${node_expr} Default=YES MaxTime=24:00:00 State=UP" /etc/slurm/slurm.conf
	}

	configure_bigmem () {
		# Get nodes
		nodes=`wwctl node list|grep bigmem|awk -F ' ' '{print $1}'`

		# Create an expression
		node_expr=`/usr/bin/nodeset --fold ${nodes}`

		# Gather information from a node
		first_node=`wwctl node list|grep bigmem|head -1|awk -F ' ' '{print $1}'`
		real_mem=`ssh $first_node "free -g | grep Mem" | awk '{ print $2 }'`G
		sockets=`ssh $first_node "lscpu | grep Socket" | awk '{ print $NF }'`
		threads_per_core=`ssh $first_node "lscpu | grep 'per core'" | awk '{ print $NF }'`
		cores_per_socket=`ssh $first_node "lscpu | grep 'per socket'" | awk '{ print $NF }'`
		sed -i "/ReturnToService=2/i \
			NodeName=${node_expr} Sockets=${sockets} CoresPerSocket=${cores_per_socket} ThreadsPerCore=${threads_per_core} RealMemory=${real_mem} State=UNKNOWN" /etc/slurm/slurm.conf

		echo "Adding ${node_expr} to the Bigmem partition"
		sed -i "/ReturnToService=2/i \
			PartitionName=bigmem Nodes=${node_expr} MaxTime=24:00:00 State=UP" /etc/slurm/slurm.conf
	}

	configure_gpu () {
		# Get nodes
		nodes=`wwctl node list|grep gpu|awk -F ' ' '{print $1}'`

		# Create an expression
		node_expr=`/usr/bin/nodeset --fold ${nodes}`

		# Gather information from a node
		first_node=`wwctl node list|grep gpu|head -1|awk -F ' ' '{print $1}'`
		real_mem=`ssh $first_node "free -g | grep Mem" | awk '{ print $2 }'`G
		sockets=`ssh $first_node "lscpu | grep Socket" | awk '{ print $NF }'`
		threads_per_core=`ssh $first_node "lscpu | grep 'per core'" | awk '{ print $NF }'`
		cores_per_socket=`ssh $first_node "lscpu | grep 'per socket'" | awk '{ print $NF }'`
		num_gpu=`pdsh -w ${first_node} lspci|grep -i nvidia|grep -i tesla|wc -l`
		gpu_model=`pdsh -w ${first_node} lspci|grep -i nvidia|grep -i tesla|head -1|awk -F [ '{print $2}'|awk -F ' ' '{print $2}'`

		sed -i "/ReturnToService=2/i \
			NodeName=${node_expr} Sockets=${sockets} CoresPerSocket=${cores_per_socket} ThreadsPerCore=${threads_per_core} RealMemory=${real_mem} Gres=gpu:${gpu_model}:${num_gpu} State=UNKNOWN" /etc/slurm/slurm.conf

		echo "Adding ${node_expr} to the GPU partition"
		sed -i "/ReturnToService=2/i \
			PartitionName=gpu Nodes=${node_expr} MaxTime=24:00:00 State=UP" /etc/slurm/slurm.conf
	}

	if [ "$compute" == "1" ]; then
		configure_compute
	fi

	if [ "$bigmem" == "1" ]; then
		configure_bigmem
	fi

	if [ "$gpu" == "1" ]; then
		configure_gpu
	fi

	# Cleanup
	rm -f /tmp/compute_groups

	# Restart slurm for changes to take effect
	echo "restarting slurmctld for the configuration to take effect..."
	systemctl restart slurmctld

	if [ "$compute" == "1" ]; then
		pdcp -g compute /etc/slurm/slurm.conf /etc/slurm/
		pdsh -g compute systemctl restart munge
		pdsh -g compute systemctl restart slurmd
	fi

	if [ "$bigmem" == "1" ]; then
		pdcp -g bigmem /etc/slurm/slurm.conf /etc/slurm/
		pdsh -g bigmem systemctl restart munge
		pdsh -g bigmem systemctl restart slurmd
	fi

	if [ "$gpu" == "1" ]; then
		pdcp -g gpu /etc/slurm/slurm.conf /etc/slurm/
		pdsh -g gpu systemctl restart munge
		pdsh -g gpu systemctl restart slurmd
	fi

	sleep 2
	clear;
    show_main_menu;
    ;;

    27) clear;
    option_picked "Option 27 Picked";
        ## Install and configure Nagios
	dnf install -y nagios nagios-plugins-nagios

	systemctl enable httpd --now
	htpasswd -c /etc/nagios/passwd nagiosadmin

	# Create index.html file for the master node so that a warning doesn't get triggered
	cat << EOF >/var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
<title>Index</title>
</head>
<body>

<p>This page left intentionally blank.</p>

</body>
</html>
EOF

	# Check if this has been run before
	if [ -f /etc/nagios/nagios.cfg.orig ]; then
		read -e -p "A saved file exists. Is this a reconfiguration? y/n : " -i "y" reconfig
	fi

	# Create object folders and node template
	mkdir /etc/nagios/templates
	mkdir /etc/nagios/objects/{hosts.d,hostgroups.d}

	# Before we add any nodes, get Nagios config ready:
	if [ "$reconfig" == "y" ]; then
		/usr/bin/unalias cp
		cp /etc/nagios/nagios.cfg.orig /etc/nagios/nagios.cfg
		cp /etc/nagios/objects/localhost.cfg.orig /etc/nagios/objects/localhost.cfg
		rm -f /etc/nagios/objects/hostgroups.d/*.cfg
		rm -f /etc/nagios/objects/hosts.d/*.cfg
	fi

	# Save the original config files
	cp /etc/nagios/nagios.cfg cp /etc/nagios/nagios.cfg.orig
	cp /etc/nagios/objects/localhost.cfg /etc/nagios/objects/localhost.cfg.orig

	cat << EOF >/etc/nagios/templates/host.cfg
define host {
  host_name	HOST
  alias		ALIAS
  hostgroups	GROUP
  address	10.10.10.101
  use		generic-host
  check_command	check-host-alive
  max_check_attempts	5
  contact_groups	admins
}
EOF

        cat << EOF >/etc/nagios/templates/group.cfg
define hostgroup {
  hostgroup_name	NAME
  alias			GROUP nodes	
  members		MEMBERS
}
EOF

        # Configure Nagios to use the host and hostgroup folders
	perl -i -lne 'print $_;print "cfg_dir=/etc/nagios/objects/hostgroups.d" if(/cfg_file\=\/etc\/nagios\/objects\/templates.cfg/);' /etc/nagios/nagios.cfg
	perl -i -lne 'print $_;print "cfg_dir=/etc/nagios/objects/hosts.d" if(/cfg_file\=\/etc\/nagios\/objects\/templates.cfg/);' /etc/nagios/nagios.cfg

	# Update location of mail binary for alert command
	perl -pi -e "s/ \/bin\/mail/ \/usr\/bin\/mailx/g" /etc/nagios/objects/commands.cfg

	# Update email address of contact for alerts
	perl -pi -e "s/nagios\@localhost/root\@$localhost/" /etc/nagios/objects/contacts.cfg

	# Configure head node cfg file
	perl -pi -e "s/linux-servers/headnode/g if /hostgroup_name/" /etc/nagios/objects/localhost.cfg
	perl -pi -e "s/Linux Servers/Head Node/g if /alias/" /etc/nagios/objects/localhost.cfg

	configure_compute () {
		# Get compute nodes
		wwctl node list|grep compute|awk -F ' ' '{print $1}' > /tmp/compute_nodes
		for node in `cat /tmp/compute_nodes`; do cp /etc/nagios/templates/host.cfg /etc/nagios/objects/hosts.d/$node.cfg; node_addr=`cat /etc/hosts|grep $node|grep -v \#|awk -F ' ' '{print $1}'`; sed -i -e "s/HOST/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/ALIAS/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/GROUP/compute/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/10.10.10.101/$node_addr/g" /etc/nagios/objects/hosts.d/$node.cfg; done
		cp /etc/nagios/templates/group.cfg /etc/nagios/objects/hostgroups.d/compute.cfg
		node_string=$(tr '\n' ',' < /tmp/compute_nodes | sed 's/,$//')
		/usr/bin/perl -i -pe 's|NAME|compute|g' /etc/nagios/objects/hostgroups.d/compute.cfg
		/usr/bin/perl -i -pe 's|GROUP|Compute|g' /etc/nagios/objects/hostgroups.d/compute.cfg
		/usr/bin/perl -i -pe 's|MEMBERS|'"$node_string"'|g' /etc/nagios/objects/hostgroups.d/compute.cfg
	}

        configure_bigmem () {
		# Get bigmem nodes
		wwctl node list|grep bigmem|awk -F ' ' '{print $1}' > /tmp/bigmem_nodes
		for node in `cat /tmp/bigmem_nodes`; do cp /etc/nagios/templates/host.cfg /etc/nagios/objects/hosts.d/$node.cfg; node_addr=`cat /etc/hosts|grep $node|grep -v \#|awk -F ' ' '{print $1}'`; sed -i -e "s/HOST/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/ALIAS/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/GROUP/bigmem/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/10.10.10.101/$node_addr/g" /etc/nagios/objects/hosts.d/$node.cfg; done
		cp /etc/nagios/templates/group.cfg /etc/nagios/objects/hostgroups.d/bigmem.cfg
		node_string=$(tr '\n' ',' < /tmp/bigmem_nodes | sed 's/,$//')
		/usr/bin/perl -i -pe 's|NAME|bigmem|g' /etc/nagios/objects/hostgroups.d/bigmem.cfg
		/usr/bin/perl -i -pe 's|GROUP|Bigmem|g' /etc/nagios/objects/hostgroups.d/bigmem.cfg
		/usr/bin/perl -i -pe 's|MEMBERS|'"$node_string"'|g' /etc/nagios/objects/hostgroups.d/bigmem.cfg
	}

        configure_gpu () {
		# Get gpu nodes
		wwctl node list|grep gpu|awk -F ' ' '{print $1}' > /tmp/gpu_nodes
		for node in `cat /tmp/gpu_nodes`; do cp /etc/nagios/templates/host.cfg /etc/nagios/objects/hosts.d/$node.cfg; node_addr=`cat /etc/hosts|grep $node|grep -v \#|awk -F ' ' '{print $1}'`; sed -i -e "s/HOST/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/ALIAS/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/GROUP/gpu/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/10.10.10.101/$node_addr/g" /etc/nagios/objects/hosts.d/$node.cfg; done
		cp /etc/nagios/templates/group.cfg /etc/nagios/objects/hostgroups.d/gpu.cfg
		node_string=$(tr '\n' ',' < /tmp/gpu_nodes | sed 's/,$//')
		/usr/bin/perl -i -pe 's|NAME|gpu|g' /etc/nagios/objects/hostgroups.d/gpu.cfg
		/usr/bin/perl -i -pe 's|GROUP|GPU|g' /etc/nagios/objects/hostgroups.d/gpu.cfg
		/usr/bin/perl -i -pe 's|MEMBERS|'"$node_string"'|g' /etc/nagios/objects/hostgroups.d/gpu.cfg

	}

        configure_login () {
		# Get gpu nodes
		wwctl node list|grep login|awk -F ' ' '{print $1}' > /tmp/login_nodes
		for node in `cat /tmp/login_nodes`; do cp /etc/nagios/templates/host.cfg /etc/nagios/objects/hosts.d/$node.cfg; node_addr=`cat /etc/hosts|grep $node|grep -v \#|awk -F ' ' '{print $1}'`; sed -i -e "s/HOST/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/ALIAS/$node/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/GROUP/login/g" /etc/nagios/objects/hosts.d/$node.cfg; sed -i -e "s/10.10.10.101/$node_addr/g" /etc/nagios/objects/hosts.d/$node.cfg; done
		cp /etc/nagios/templates/group.cfg /etc/nagios/objects/hostgroups.d/login.cfg
		node_string=$(tr '\n' ',' < /tmp/login_nodes | sed 's/,$//')
		/usr/bin/perl -i -pe 's|NAME|login|g' /etc/nagios/objects/hostgroups.d/login.cfg
		/usr/bin/perl -i -pe 's|GROUP|Login|g' /etc/nagios/objects/hostgroups.d/login.cfg
		/usr/bin/perl -i -pe 's|MEMBERS|'"$node_string"'|g' /etc/nagios/objects/hostgroups.d/login.cfg
	}

        finish () {
		rm -f /tmp/*_nodes
		systemctl restart nagios

		# Enable Postfix so that Nagios alerts will be sent to the root user.
		systemctl enable postfix --now
	}

        for group in `wwctl profile list|grep -v infiniband|grep -v PROFILE|grep -v default|grep -v amdkernel|grep -v gpukernel|awk -F ' ' '{print $1}'`; do configure_$group; done
	finish

      sleep 2
      clear;
      show_main_menu;
      ;;

      27) clear;
      option_picked "Option 27 Picked";
        ## Install / configure Ganglia monitoring
	dnf install -y https://dl.rockylinux.org/pub/rocky/9/devel/x86_64/os/Packages/l/libmemcached-awesome-1.1.0-12.el9.x86_64.rpm
	dnf install -y ganglia rrdtool ganglia-gmetad ganglia-gmond ganglia-web

	cat << EOF >/etc/httpd/conf.d/ganglia.conf
#
# Ganglia monitoring system php web frontend
#

Alias /ganglia /usr/share/ganglia

<Location /ganglia>
  AllowOverride All
  Require all granted
  Allow from all
  Deny from none
</Location>
EOF

	## Grab the example gmond.conf file
	cp /opt/ohpc/pub/examples/ganglia/gmond.conf /etc/ganglia/gmond.conf.orig
	cp /opt/ohpc/pub/examples/ganglia/gmond.conf /etc/ganglia/gmond.conf

	## Edit gmond.conf for THIS head node
	/usr/bin/perl -i -pe 's|<sms>|'"$sms_ip"'|g' /etc/ganglia/gmond.conf
	/usr/bin/perl -i -pe 's|name = "OpenHPC"|name = "OpenHPC Cluster"|g' /etc/ganglia/gmond.conf

	## Edit gmetad.conf
	#cp -p /etc/ganglia/gmetad.conf /etc/ganglia/gmetad.conf.orig
	#perl -pi -e "s/my cluster/OpenHPC Cluster/g if /data_source/" /etc/ganglia/gmetad.conf

	systemctl enable httpd gmetad gmond --now

	## Inform about compute nodes
	echo "If you have already created containers, be sure to copy /etc/ganglia/gmond.conf into those containers and rebuild them."

      sleep 4
      clear;
      show_main_menu;
      ;;

      29) clear;
      option_picked "Option 29 Picked";
        # Enable and start firewalld
	echo -e "\e[32mEnabling and starting firewalld..."
	echo -e "\e[0m"
	systemctl enable firewalld --now

	# Settings
	# Configure inside interface:
	read -e -p "Enter provisioning interface: " -i "$sms_eth_internal" internal

	# Configure outside interface:
	read -e -p "Enter external interface: " -i "$sms_eth_external" external

	# Configure internal network:
	NETMASK=`ifconfig $internal|grep netmask|awk -F ' ' '{print $4}'`

	case "$NETMASK" in
		"255.255.255.252") CIDR=/30 ;;
		"255.255.255.248") CIDR=/29 ;;
		"255.255.255.240") CIDR=/28 ;;
		"255.255.255.224") CIDR=/27 ;;
		"255.255.255.192") CIDR=/26 ;;
		"255.255.255.128") CIDR=/25 ;;
		"255.255.255.0")   CIDR=/24 ;;
		"255.255.254.0")   CIDR=/23 ;;
		"255.255.252.0")   CIDR=/22 ;;
		"255.255.248.0")   CIDR=/21 ;;
		"255.255.240.0")   CIDR=/20 ;;
		"255.255.224.0")   CIDR=/19 ;;
		"255.255.192.0")   CIDR=/18 ;;
		"255.255.128.0")   CIDR=/17 ;;
		"255.255.0.0")     CIDR=/16 ;;
	esac

	internal_cidr=`ipcalc -p 1.1.1.1 ${internal_netmask}|awk -F = '{print $2}'`
	internal_net=`ifconfig $internal|grep broadcast|awk -F ' ' '{print $6}'|awk -F . '{print $1"."$2"."$3"."0}'`
	internal_network=$internal_base_net/$internal_cidr
	echo ""
	echo "Internal network is $internal_network"

	with_System () {
		echo -e "\e[32mAdding $internal to trusted firewalld zone..."
		echo -e "\e[0m"
		nmcli c mod "System $internal" connection.zone trusted"
		echo -e "\e[31mAdding $external to public firewalld zone...
		echo -e "\e[0m"
		nmcli c mod "System $external" connection.zone public
	}

	without_System () {
		echo -e "\e[32mAdding $internal to trusted firewalld zone..."
		echo -e "\e[0m"
		nmcli c mod "$internal" connection.zone trusted
		echo -e "\e[31mAdding $external to public firewalld zone..."
		echo -e "\e[0m"nmcli c mod "$external" connection.zone public
	}

	SYSTEM=`nmcli c|grep $internal|grep System`
	if [ -z "$SYSTEM" ]; then
		without_System
	else
		with_System
	fi

	# Ensure that ip forwarding is enabled in the kernel:
	# enable ip forwarding NOW:
	echo ""
	echo -e "\e[32mEnabling ip forwarding..."
	echo -e "\e[0m"
	sysctl -w net.ipv4.ip_forward=1

	# Make sure ip forwarding works after reboot:
	cp -p /etc/sysctl.conf /etc/sysctl.conf.orig
	echo -e "net.ipv4.ip_forward = 1" >>  /etc/sysctl.conf
	echo -e "\e[0m"

	# Configure ip masquerading so that cluster nodes can get out through master:
	echo -e "\e[32mEnabling ip masquerading..."
	echo -e "\e[0m"
	firewall-cmd --zone=public --add-masquerade --permanent

	# Setting trusted network WIDE OPEN:echo -e "\e[32mSetting internal interface to WIDE OPEN..."
	echo -e "\e[32mSetting internal interface to WIDE OPEN..."
	echo -e "\e[0m"
	firewall-cmd --permanent --zone=trusted --set-target=ACCEPT

	# Configure the public (external) zone:
	echo -e "\e[31mDisabling dhcpv6 on external interface..."
	echo -e "\e[0m"
	firewall-cmd --zone=public --remove-service=dhcpv6-client --permanent

	echo -e "\e[32mEnabling http on external interface..."
	echo -e "\e[0m"
	firewall-cmd --zone=public --permanent --add-service=http

	echo -e "\e[32mEnabling https on external interface..."
	echo -e "\e[0m"
	firewall-cmd --zone=public --permanent --add-service=https

	#echo -e "\e[32mEnabling LDAP and LDAPS on external interface..."
	#echo -e "\e[0m"
	#firewall-cmd --zone=public --permanent --add-service={ldap,ldaps}

	echo -e "\e[31mDisabling cockpit on external interface..."
	echo -e "\e[0m"
	firewall-cmd --zone=public --remove-service=cockpit --permanent

	# Reload firewalld so changes take effect:
	echo -e "\e[0m"
	echo -e "\e[32mReloading firewalld so that new rules take effect..."
	echo -e "\e[0m"
	firewall-cmd --complete-reload

	echo ""
	echo -e "\e[34mFirewalld configuration complete!"
	echo -e "\e[0m"
	sleep 2
	clear;
      show_main_menu;
      ;;

      30) clear;
      option_picked "Option 30 Picked";
        # Configure Fail2Ban
	echo "Installing and Configuring Fail2Ban"
	dnf install -y fail2ban

	cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

	perl -p -i -e "s/bantime  = 10m/bantime  = 15m/g" /etc/fail2ban/jail.local

	perl -pi -e '/\[sshd\]/&&++$n==2 and $_.="enabled = true\n"' /etc/fail2ban/jail.local

	systemctl enable fail2ban --now

	sleep 2
	clear;
      show_main_menu;
      ;;


      31) clear;
      option_picked "Option 31 Picked";
        # Configure caching nameserver
	echo "Installing Bind and configuring caching nameserver"
	sleep 2
	dnf install -y bind

	cp -p /etc/named.conf /etc/named.conf.orig

	# Enable caching name server.
	sed -i -e s/127.0.0.1\;/127.0.0.1\;$sms_ip\;/ /etc/named.conf

	# Point master node to itself for DNS
	sed -i $'/nameserver/{inameserver 127.0.0.1\n:a;n;ba}' /etc/resolv.conf

	# Point DNS to forwarders (# Need to figure out how to add forwarders)
	sed -i '/allow-query/a \\tforwarders \t{ '"${dns_server_1}"'; '"${dns_server_2}"'; };' /etc/named.conf

	# Enable and start named
	systemctl enable named --now

	sleep 2
	clear;
      show_main_menu;
      ;;

      32) clear;
      option_picked "Option 32 Picked";
        echo "Cleaning up after myself..."
	sleep 2
	rm -rf /root/dell
	rm -f configure_master_host*.sh dell_bright_* l_*.sh intel-oneapi*.sh cuda_*.run hpcx*.tbz MLNX_OFED*.tgz CornelisOPX*.tgz OM-SrvAdmin-Dell*.gz R*.iso 
	exit 0

	;;


      esac
    fi
  done
}



### Main Function 
# prelaunch_check
run_first

clear
show_main_menu
