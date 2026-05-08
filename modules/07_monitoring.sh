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

# --- Monitoring Functions ---

install_configure_nagios() {
    option_picked "Install & Configure Nagios"
	console_info_msg "This branch is no longer maintained. "
	pause_for_review
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
	console_info_msg "This branch is no longer maintained. "
	pause_for_review
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

# --- Main Menu for this script ---
monitoring_menu() {
    local option
    while true; do
        echo_menu_header "Monitoring Installation"
        echo " 1) Install & Configure Nagios"
        echo " 2) Install & Configure Ganglia"
        echo " 0) Return to main menu"
        read -r -p "=> " option
        case $option in
            1) option_picked "Install & Configure Nagios"; install_configure_nagios ;;
            2) option_picked "Install & Configure Ganglia"; install_configure_ganglia ;;
            0) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Module runs its own menu and exits
monitoring_menu
