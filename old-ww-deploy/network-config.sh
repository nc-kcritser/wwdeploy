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


# --- Network Functions ---

interface_config_masterhost_provisioning() {
	option_picked "Configure Provisioning Interface";
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
	option_picked "Configure Alias Interface"
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
	option_picked "Configure External Interface";
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
	option_picked "Configure InfiniBand Interface for Master Host"
	#Configure InfiniBand interface
	echo -e "${BLARROW} Checking for MLNX OFED Drivers ${RESET}"
	if ! command -v ofed_info &> /dev/null; then
        console_fail_msg "ofed_info command not found. Mellanox OFED does not appear to be installed."
        echo "Please install Mellanox OFED, then run this again"
        pause_for_review
        return 1
    fi

	mlnx_ofed_version=`ofed_info|grep OFED| head -1|awk -F - '{print $2$3}'|awk -F ' ' '{print $1}'`
	if [ -z "${mlnx_ofed_version}" ];then
		console_fail_msg "$mlnx_ofed_version is empty, which means that Mellanox OFED is not installed"
		echo "Please install Mellanox OFED, then run this again"
		pause_for_review
		return 1;
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

configure_caching_nameserver() {
    option_picked "Configure Caching Nameserver"
    # Configure caching nameserver
	echo "Installing Bind and configuring caching nameserver"
	sleep 2
	dnf install -y bind

	cp -p /etc/named.conf /etc/named.conf.orig

	# Enable caching name server.
	sed -i -e "s/127.0.0.1;/127.0.0.1; ${sms_ip};/" /etc/named.conf

	# Point master node to itself for DNS
	sed -i $'/nameserver/{inameserver 127.0.0.1\n:a;n;ba}' /etc/resolv.conf

	# Point DNS to forwarders
	sed -i '/allow-query/a \\tforwarders \t{ '"${dns_server_1}"'; '"${dns_server_2}"'; };' /etc/named.conf

	# Enable and start named
	systemctl enable named --now

	sleep 2
	pause_for_review
}

# --- Sub-Menu for this script ---
show_network_menu() {
    while true; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BLUE}** Network Configuration Menu         **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Configure provisioning ethernet interface ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Configure alias interface for IPMI/MGMT ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Configure external ethernet interface ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Configure InfiniBand interface ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Configure Caching Nameserver ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " net_choice

        case $net_choice in
            1) interface_config_masterhost_provisioning ;;
            2) interface_config_masterhost_alias ;;
            3) interface_config_masterhost_external ;;
            4) interface_config_masterhost_infiniband ;;
            5) configure_caching_nameserver ;;
            6) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_network_menu
