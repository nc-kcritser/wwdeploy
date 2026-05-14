#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.
# If common.sh is not found, the script will exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common.sh" ]; then
    source "${SCRIPT_DIR}/../common.sh"
else
    echo "Error: common.sh not found in parent directory."
    exit 1
fi

# --- Security Functions ---

enable_configure_firewalld() {
    option_picked "Enable and Configure firewalld and NAT Rules for Headnode"
    read -p "This will enable firewalld and set rules for a cluster environment. Proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then console_info_msg "Firewall configuration cancelled."; return; fi

	systemctl enable --now firewalld

	read -e -p "Enter provisioning interface name: " -i "$sms_eth_internal" internal_iface
	read -e -p "Enter external/public interface name: " -i "$sms_eth_external" external_iface

	console_info_msg "Assigning interfaces to firewalld zones..."
	firewall-cmd --permanent --zone=trusted --add-interface="$internal_iface"
	firewall-cmd --permanent --zone=public --add-interface="$external_iface"

	console_info_msg "Enabling IP forwarding and masquerading..."
	echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
	sysctl -p /etc/sysctl.d/99-ip-forward.conf
	firewall-cmd --permanent --zone=public --add-masquerade

	console_info_msg "Configuring public zone services..."
	firewall-cmd --permanent --zone=public --add-service=ssh
	firewall-cmd --permanent --zone=public --add-service=http
	firewall-cmd --permanent --zone=public --add-service=https
	console_info_msg "Configuring warewulf firewall rule - if this fails, you likely havent installed warewulf yet..."
	firewall-cmd --permanent --zone=public --add-service=warewulf
	
	console_info_msg "Reloading firewall to apply changes..."
	firewall-cmd --reload
    console_taskcomplete_msg "Firewalld configured for cluster operation."
	pause_for_review
}

secure_sshd_with_fail2ban() {
    option_picked "Secure SSHD with Fail2Ban"
    console_info_msg "Fail2Ban monitors SSHD login attempts and automatically bans IPs that exceed the failed login threshold (default: 1 hour ban). It installs a systemd service and modifies /etc/fail2ban/jail.local."
	dnf install -y fail2ban
	cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

	# Enable sshd jail
	sed -i -e '/^\[sshd\]/a enabled = true' /etc/fail2ban/jail.local
	# Increase ban time
	sed -i -e 's/^bantime\s*=.*/bantime  = 1h/' /etc/fail2ban/jail.local

	systemctl enable --now fail2ban
    console_taskcomplete_msg "Fail2Ban has been installed and configured for SSHD."
	pause_for_review
}

security_menu() {
    local option
    while true; do
        echo_menu_header "Security Configuration"
        echo " 1) Enable and Configure firewalld with NAT"
        echo " 2) Secure SSHD with Fail2Ban"
        echo " 0) Return to main menu"
        read -r -p "=> " option
        case $option in
            1) option_picked "Enable and Configure firewalld"; enable_configure_firewalld ;;
            2) option_picked "Secure SSHD with Fail2Ban"; secure_sshd_with_fail2ban ;;
            0) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Module runs its own menu and exits
security_menu
