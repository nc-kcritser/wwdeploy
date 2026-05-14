#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common.sh" ]; then
    source "${SCRIPT_DIR}/../common.sh"
else
    echo "Error: common.sh not found in parent directory."
    exit 1
fi

# --- Troubleshooting Functions ---

cluster_sanity_check() {
    option_picked "Cluster Sanity Check"
    
    if [ ! -f /etc/genders ]; then
        console_fail_msg "/etc/genders file not found. Cannot determine nodes to check."
        pause_for_review
        return 1
    fi

    # Get all nodes from the genders file
    local all_nodes=$(genders -e | tr ',' ' ')

    if [ -z "$all_nodes" ]; then
        console_fail_msg "No nodes found in /etc/genders file."
        pause_for_review
        return 1
    fi

    console_info_msg "Checking network connectivity from all nodes to master..."
    # Using -S to get a summary of which nodes failed, if any
    if pdsh -w "${all_nodes}" ping -c 1 "${sms_ip}" >/dev/null; then
        console_taskcomplete_msg "All nodes can ping the master."
    else
        console_fail_msg "Some nodes could not ping the master. Run 'pdsh -w ${all_nodes} ping -c 1 ${sms_ip}' for details."
    fi

    console_info_msg "Checking status of 'munge' service on all nodes..."
    if pdsh -w "${all_nodes}" systemctl is-active --quiet munge; then
        console_taskcomplete_msg "Munge service is active on all nodes."
    else
        console_fail_msg "Munge service is INACTIVE on one or more nodes."
        # Show which nodes failed
        pdsh -S -w "${all_nodes}" 'systemctl is-active --quiet munge || echo "munge is inactive on $HOSTNAME"'
    fi

    console_info_msg "Checking status of 'slurmd' service on all nodes..."
    if pdsh -w "${all_nodes}" systemctl is-active --quiet slurmd; then
        console_taskcomplete_msg "Slurmd service is active on all nodes."
    else
        console_fail_msg "Slurmd service is INACTIVE on one or more nodes."
        # Show which nodes failed
        pdsh -S -w "${all_nodes}" 'systemctl is-active --quiet slurmd || echo "slurmd is inactive on $HOSTNAME"'
    fi

    console_info_msg "Verifying provisioned container for all nodes..."
    wwctl node list
    
    console_taskcomplete_msg "Sanity check complete."
    pause_for_review
}


check_network() {
    option_picked "Check Network Connectivity"
    
    local gateway=$(ip route | grep default | awk '{print $3}')
    
    console_info_msg "Pinging default gateway (${gateway})..."
    if ping -c 2 "${gateway}" &> /dev/null; then
        console_taskcomplete_msg "Gateway is reachable."
    else
        console_fail_msg "Gateway is UNREACHABLE."
    fi

    console_info_msg "Pinging public IP (8.8.8.8) to check external connectivity..."
    if ping -c 2 8.8.8.8 &> /dev/null; then
        console_taskcomplete_msg "Public IP is reachable."
    else
        console_fail_msg "Public IP is UNREACHABLE. Check firewall or upstream network."
    fi

    console_info_msg "Pinging public domain (google.com) to check DNS resolution..."
    if ping -c 2 google.com &> /dev/null; then
        console_taskcomplete_msg "DNS resolution is working."
    else
        console_fail_msg "DNS resolution FAILED. Check /etc/resolv.conf or DNS server."
    fi

    pause_for_review
}

check_services() {
    option_picked "View Service Status"
    
    local services=(
        warewulfd
        slurmctld
        munge
        dhcpd
        tftp.socket
        chronyd
        named
        fail2ban
        nagios
    )

    for service in "${services[@]}"; do
        # Use systemctl list-units to see if the service file exists at all
        if systemctl list-units --full -all | grep -q "${service}"; then
            # Use systemctl is-active to check the current state
            if systemctl is-active --quiet "${service}"; then
                echo -e "  ${YELLOWCM} ${service} is active (running)"
            else
                echo -e "  ${CROSS} ${service} is inactive (dead)"
            fi
        fi
    done

    pause_for_review
}

check_nodes() {
    option_picked "Check Warewulf Node Status"
    echo "Nodes that have not checked in"
    wwctl node status --unknown
    pause_for_review
}

view_logs() {
    option_picked "View System Logs"
    PS3='Select a log to view: '
    options=("messages" "secure" "warewulf" "slurm" "Cancel")
    select opt in "${options[@]}"; do
        case $opt in
            "messages") journalctl -f -u rsyslog ;;
            "secure") journalctl -f -u sshd ;;
            "warewulf") journalctl -f -u warewulfd ;;
            "slurm") tail -f /var/log/slurmctld.log ;;
            "Cancel") break ;;
            *) echo "Invalid option." ;;
        esac
    done
}


# --- Main Menu for this script ---
show_troubleshooting_menu() {
    local exit_menu=false
    while [ "$exit_menu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Troubleshooting Menu                 **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Cluster Sanity Check ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Check Master Network Connectivity ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} View Master Service Status ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Check Warewulf Node Status ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} View System Logs ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " choice

        case $choice in
            1) cluster_sanity_check ;;
            2) check_network ;;
            3) check_services ;;
            4) check_nodes ;;
            5) view_logs ;;
            6) exit_menu=true ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_troubleshooting_menu
