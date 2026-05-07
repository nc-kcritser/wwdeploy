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

# --- Monitoring & Security Functions ---

install_configure_nagios() {
    option_picked "Install & Configure Nagios"
	dnf install -y nagios nagios-plugins-nagios httpd
	systemctl enable --now httpd
	htpasswd -b -c /etc/nagios/passwd nagiosadmin nagiosadmin
    echo "Nagios admin user 'nagiosadmin' created with password 'nagiosadmin'. Please change this."

	# Create object folders and templates
	mkdir -p /etc/nagios/templates
	mkdir -p /etc/nagios/objects/{hosts.d,hostgroups.d}

	# Backup original configs
	[ ! -f /etc/nagios/nagios.cfg.orig ] && cp /etc/nagios/nagios.cfg /etc/nagios/nagios.cfg.orig
	[ ! -f /etc/nagios/objects/localhost.cfg.orig ] && cp /etc/nagios/objects/localhost.cfg /etc/nagios/objects/localhost.cfg.orig

	# Configure Nagios to use the new directories
	sed -i '/cfg_file=\/etc\/nagios\/objects\/localhost.cfg/a cfg_dir=/etc/nagios/objects/hosts.d' /etc/nagios/nagios.cfg
	sed -i '/cfg_dir=\/etc\/nagios\/objects\/hosts.d/a cfg_dir=/etc/nagios/objects/hostgroups.d' /etc/nagios/nagios.cfg

	# Update mail command and contact email
	sed -i 's|/bin/mail|/usr/bin/mailx|g' /etc/nagios/objects/commands.cfg
	sed -i "s/nagios@localhost/root@$(hostname -f)/" /etc/nagios/objects/contacts.cfg

	console_info_msg "Nagios has been installed. You can now add host/group configs to /etc/nagios/objects/."
	systemctl restart nagios
    pause_for_review
}

install_configure_ganglia() {
    option_picked "Install & Configure Ganglia"
	dnf install -y ganglia rrdtool ganglia-gmetad ganglia-gmond ganglia-web
    if [ "$os_version_major" -eq 9 ]; then
        # EL9 requires this specific dependency manually
        dnf install -y https://dl.rockylinux.org/pub/rocky/9/devel/x86_64/os/Packages/l/libmemcached-awesome-1.1.0-12.el9.x86_64.rpm
    fi


	cat << EOF >/etc/httpd/conf.d/ganglia.conf
Alias /ganglia /usr/share/ganglia
<Location /ganglia>
  Require all granted
</Location>
EOF

	# Configure gmond and gmetad
	cp /opt/ohpc/pub/examples/ganglia/gmond.conf /etc/ganglia/gmond.conf
	perl -pi -e "s|<sms>|${sms_ip}|g" /etc/ganglia/gmond.conf
	perl -pi -e 's|name = "OpenHPC"|name = "My HPC Cluster"|g' /etc/ganglia/gmond.conf
	perl -pi -e 's|data_source "my cluster" localhost|data_source "My HPC Cluster" localhost|' /etc/ganglia/gmetad.conf

	systemctl enable --now httpd gmetad gmond
	systemctl restart httpd gmetad gmond
    console_taskcomplete_msg "Ganglia has been installed and configured."
    console_info_msg "Access the web UI at http://$(hostname -f)/ganglia"
	pause_for_review
}

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

	console_info_msg "Reloading firewall to apply changes..."
	firewall-cmd --reload
    console_taskcomplete_msg "Firewalld configured for cluster operation."
	pause_for_review
}

secure_sshd_with_fail2ban() {
    option_picked "Secure SSHD with Fail2Ban"
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

# --- Main Menu for this script ---
show_monitoring_security_menu() {
    while true; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BLUE}** Monitoring & Security Menu             **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Install & Configure Nagios ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Install & Configure Ganglia ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Enable & Configure firewalld and NAT for the headnode ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Secure SSHD with Fail2Ban ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " ms_choice

        case $ms_choice in
            1) install_configure_nagios ;;
            2) install_configure_ganglia ;;
            3) enable_configure_firewalld ;;
            4) secure_sshd_with_fail2ban ;;
            5) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_monitoring_security_menu
