#!/usr/bin/env bash
#
# Main Dispatcher Script for Dell HPC Warewulf Master Host Configuration
# Assumes all scripts are located in /root/wwdeploy/
#

# This script depends on 'common.sh' to be in the same directory.
# If common.sh is not found, the script will exit.
if [ -f ./common.sh ]; then
    source ./common.sh
else
    echo "Error: common.sh not found. Please ensure it is in the same directory."
    exit 1
fi

# --- Initial Setup and Pre-flight Checks ---

run_first() {
	# This function performs one-time setup tasks.
	if [ -f "/root/anaconda-ks.cfg" ]; then
		rm -f /root/anaconda-ks.cfg
	fi

	if [ ! -d "/opt/ohpc/pub/apps/dell/firmware/PowerEdge" ]; then
        console_info_msg "Performing first-time setup tasks..."
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

		# Configure chronyd to serve time to the cluster
		sed -i -e "s/#allow 192.168.0.0\/16/allow ${internal_base_net}\/${internal_cidr}/g" /etc/chrony.conf
		sed -i -e "s/#local stratum 10/local stratum 10/g" /etc/chrony.conf
		
        systemctl restart chronyd
        console_taskcomplete_msg "First-time setup complete."
        sleep 5
	fi
}

post_deployment_cleanup() {
    option_picked "Post Deployment Cleanup"
    read -p "This will remove all downloaded artifacts from /root. Are you sure? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "Cleanup cancelled."
        pause_for_review
        return
    fi

    console_info_msg "Cleaning up installation files from /root..."
	# This function cleans up the large downloaded files, typically stored in /root
	rm -rf /root/dell
	rm -f /root/dell_bright_*.tgz /root/l_*.sh /root/intel-oneapi*.sh /root/cuda_*.run /root/hpcx*.tbz /root/MLNX_OFED*.tgz /root/CornelisOPX*.tgz /root/OM-SrvAdmin-Dell*.gz /root/R*.iso
	console_taskcomplete_msg "Cleanup complete. Exiting script."
	exit 0
}

# --- Main Menu ---
show_main_menu() {
    while true; do
        clear
        echo -e "${BLUE}*************************************************${RESET}"
        echo -e "${BLUE}**     Dell HPC Warewulf Master Host Config    **${RESET}"
        echo -e "${BLUE}**               -- Main Menu --               **${RESET}"
        echo -e "${BLUE}*************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Initial Master Node Setup Menu ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Network Configuration Menu ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Firmware Update Menu ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Warewulf & Cluster Management Menu ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Warewulf Image Management Menu ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} HPC Software Installation Menu ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Monitoring & Security Menu ${RESET}"
        echo -e "  ${YELLOW}8)${BLUE} Troubleshooting Menu ${RESET}"
        echo -e "  ${YELLOW}9)${BLUE} Post-Deployment Cleanup ${RESET}"
        echo -e " ${YELLOW}10)${BLUE} Exit ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " main_choice

        case $main_choice in
            1) ./master-node-config.sh ;;
            2) ./network-config.sh ;;
            3) ./firmware-updates.sh ;;
            4) ./warewulf-setup.sh ;;
            5) ./ww4-image-management.sh ;;
            6) ./hpc-shared-software-installs.sh ;;
            7) ./monitoring-security.sh ;;
            8) ./troubleshooting.sh ;;
            9) post_deployment_cleanup ;;
            10) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}


# --- Script Execution Starts Here ---
run_first
show_main_menu
