#!/usr/bin/env bash

# This script depends on 'common.sh' to be in the same directory.
# If common.sh is not found, the script will exit.
if [ -f ./common.sh ]; then
    source ./common.sh
else
    echo "Error: common.sh not found. Please ensure it is in the same directory."
    exit 1
fi

# --- Warewulf and Cluster Management Functions ---

install_warewulf() {
    option_picked "Install Warewulf"
    console_info_msg "Installing Warewulf v4..."
    case $os_version_major in
        8)
            console_taskstart_msg "Installing OpenHPC 2.x and Warewulf v4 for EL8"
            dnf install -y "$OpenHPC2_DL"
            dnf install -y genders-ohpc ohpc-base ohpc-slurm-server pdsh-mod-genders-ohpc examples-ohpc-2.0-10.1.ohpc.2.0 ${warewulf_installer_file}
            ;;
        9)
            console_taskstart_msg "Installing OpenHPC 3.x and Warewulf v4 for EL9"
            dnf install -y "$OpenHPC3_DL"
            dnf install -y genders-ohpc ohpc-base ohpc-slurm-server pdsh-mod-genders-ohpc examples-ohpc-2.0-300.ohpc.1.6 ${warewulf_installer_file}
            ;;
    esac

    console_taskstart_msg "Performing initial Slurm configuration for Warewulf"
    cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf
    cp /etc/slurm/cgroup.conf.example /etc/slurm/cgroup.conf
    perl -pi -e "s/SlurmctldHost=\S+/SlurmctldHost=$sms_name/" /etc/slurm/slurm.conf
    perl -pi -e "s/ClusterName=\S+/ClusterName=$cluster_name/" /etc/slurm/slurm.conf
    sed -i 's/ReturnToService=1/ReturnToService=2/' /etc/slurm/slurm.conf
    sed -i '/ReturnToService=1/d' /etc/slurm/slurm.conf # Remove duplicate if it exists

    console_taskcomplete_msg "Warewulf v4 binaries installed successfully!"
    pause_for_review
}

configure_warewulf() {
    option_picked "Configure Warewulf (warewulf.conf)"
    console_info_msg "Configuring Warewulf v4..."
    if [ ! -f /etc/warewulf/warewulf.conf.orig ]; then
        cp -p /etc/warewulf/warewulf.conf /etc/warewulf/warewulf.conf.orig
        console_taskcomplete_msg "Backup of warewulf.conf created."
    fi

    readarray -t lines < <(nmcli conn show | awk '{print $1}' | grep -vE 'NAME|lo')
    echo "Please select the provisioning NIC:"
    select iface in "${lines[@]}"; do
        if [[ -n "$iface" ]]; then
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    read -e -p "Enter provisioning base network: " -i "${internal_base_net}" provisioning_net
    read -e -p "Enter master node provisioning IP: " -i "${sms_ip}" provisioning_ip
    read -e -p "Enter provisioning subnet mask: " -i "${internal_netmask}" provisioning_netmask
    read -e -p "Enter DHCP range start: " -i "${dynamic_range_start}" dhcp_range_start
    read -e -p "Enter DHCP range end: " -i "${dynamic_range_end}" dhcp_range_end

    perl -pi -e "s/10.0.0.0/$provisioning_net/g" /etc/warewulf/warewulf.conf
    perl -pi -e "s/10.0.0.1/$provisioning_ip/g" /etc/warewulf/warewulf.conf
    perl -pi -e "s/255.255.252.0/$provisioning_netmask/g" /etc/warewulf/warewulf.conf
    perl -pi -e "s/10.0.1.1/$dhcp_range_start/g" /etc/warewulf/warewulf.conf
    perl -pi -e "s/10.0.1.255/$dhcp_range_end/g" /etc/warewulf/warewulf.conf

    console_info_msg "Enabling NFS shares in warewulf.conf..."
    perl -pi -e 's|path: /opt|path: /opt/ohpc/pub|g' /etc/warewulf/warewulf.conf
    perl -pi -e 's/mount: false/mount: true/g' /etc/warewulf/warewulf.conf
    perl -pi -e 's/rw,sync/rw,sync,no_root_squash/g' /etc/warewulf/warewulf.conf

    read -p "Is this a large deployment (>200 Nodes) ? (yes/no): " response
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
        console_taskstart_msg "You've indicated this is a large deployment. Updating update interval to 300 seconds ..."
        perl -pi -e "s/update interval: 60/update interval: 300/g" /etc/warewulf/warewulf.conf
        console_taskcomplete_msg "Warewulf wwinit Update interval set to 300 seconds."
        
        sed -i '/^\[nfsd\]/a # Updated NFS Threads for Warewulfd\nthreads=32' /etc/nfs.conf && systemctl restart nfs-server
        console_taskcomplete_msg "NFS threads updated to 32. nfs-server service restarted."

    fi

    wwctl configure --all
    systemctl enable --now warewulfd
    systemctl restart rsyslog

    console_taskcomplete_msg "Warewulf v4 configured."
    pause_for_review
}

configure_slurm() {
    option_picked "Configure Slurm Workload Manager"
	read -p "/etc/genders must be configured and nodes must be up. Proceed? (y/n): " proceed
	if [[ "$proceed" != "y" ]]; then console_info_msg "Slurm configuration cancelled."; return; fi

	if [ ! -f /etc/slurm/slurm.conf.orig ]; then cp /etc/slurm/slurm.conf /etc/slurm/slurm.conf.orig; fi

	# Reset config to original state before reconfiguring
	cp /etc/slurm/slurm.conf.orig /etc/slurm/slurm.conf

	sed -i '/NodeName=/d' /etc/slurm/slurm.conf
	sed -i '/PartitionName=/d' /etc/slurm/slurm.conf
	perl -pi -e "s/ReturnToService=1/ReturnToService=2/" /etc/slurm/slurm.conf

	# Simplified loop to configure partitions based on genders
    for group in $(genders -l | cut -d' ' -f2 | sort -u); do
        nodes=$(genders -s -a "$group")
        if [ -z "$nodes" ]; then continue; fi
        node_expr=$(/usr/bin/nodeset --fold ${nodes})
        first_node=$(echo "$nodes" | head -n1)

        real_mem=$(ssh "$first_node" "free -m | grep Mem" | awk '{ print $2 }')
        sockets=$(ssh "$first_node" "lscpu | grep 'Socket(s):'" | awk '{ print $NF }')
        cores_per_socket=$(ssh "$first_node" "lscpu | grep 'Core(s) per socket:'" | awk '{ print $NF }')
        threads_per_core=$(ssh "$first_node" "lscpu | grep 'Thread(s) per core:'" | awk '{ print $NF }')

        node_def="NodeName=${node_expr} Sockets=${sockets} CoresPerSocket=${cores_per_socket} ThreadsPerCore=${threads_per_core} RealMemory=${real_mem} State=UNKNOWN"
        partition_def="PartitionName=${group} Nodes=${node_expr} Default=NO MaxTime=24:00:00 State=UP"

        # Add GPU info if applicable
        # NOTE: The following section is commented out due to a reported bug.
        # if [[ "$group" == "gpu" ]]; then
        #    num_gpu=$(ssh "$first_node" "lspci | grep -i 'NVIDIA Corporation' | grep -i 'Tesla' | wc -l")
        #    gpu_model=$(ssh "$first_node" "lspci | grep -i 'NVIDIA Corporation' | grep -i 'Tesla' | head -1 | awk -F'[][]' '{print \$2}' | awk '{print \$1}')"
        #    node_def+=" Gres=gpu:${gpu_model}:${num_gpu}"
        # fi

        sed -i "/# COMPUTE NODES/a ${node_def}" /etc/slurm/slurm.conf
        sed -i "/# PARTITIONS/a ${partition_def}" /etc/slurm/slurm.conf
    done
    # Set 'compute' as the default partition if it exists
    if grep -q "PartitionName=compute" /etc/slurm/slurm.conf; then
        sed -i 's/PartitionName=compute Nodes=\(.*\)/PartitionName=compute Nodes=\1 Default=YES/' /etc/slurm/slurm.conf
    fi

	systemctl restart slurmctld
    console_taskcomplete_msg "Slurm configuration updated."
	pause_for_review
}

configure_warewulf_default_profile() {
    option_picked "Configure Warewulf Default Profile"
    read -e -p "Enter default provisioning netmask: " -i "${internal_netmask}" def_prov_netmask
    read -e -p "Enter default provisioning gateway: " -i "${sms_ip}" def_prov_gateway
    wwctl profile set -y default --netmask="${def_prov_netmask}" --gateway="${def_prov_gateway}"
    console_taskcomplete_msg "Default profile updated."
    pause_for_review
}

# --- Sub-Menu Functions ---

configure_ww_network_idrac() {
    read -e -p "Enter iDRAC subnet mask: " -i "${bmc_netmask}" idrac_netmask
    read -e -p "Enter iDRAC gateway ip: " -i "${sms_bmc_mgmt}" idrac_gateway
    read -e -p "Enter iDRAC default pw: " -i "${sms_bmc_passwd}" idrac_passwd
    wwctl profile set default --ipmiuser=root --ipmipass=$(idrac_passwd) --ipminetmask=${idrac_netmask} --ipmigateway=${idrac_gateway} --ipmiinterface=lanplus --ipmiwrite -y
    pause_for_review
}

configure_ww_network_ib() {
    read -e -p "Enter InfiniBand subnet mask: " -i "${ipoib_netmask}" ib_netmask
    wwctl profile set default --netname=ib --type=InfiniBand --mtu=4096 --netmask=${ib_netmask} -y
    pause_for_review
}

configure_ww_network_opa() {
    read -e -p "Enter OmniPath subnet mask: " -i "${ipoib_netmask}" opa_netmask
    wwctl profile set default --netname=opa --type=InfiniBand --netmask=${opa_netmask} -y
    pause_for_review
}

configure_ww_network_hse() {
    read -e -p "Enter High Speed Ethernet subnet mask: " -i "" hseth_netmask
    read -e -p "Enter High Speed Ethernet gateway ip: " -i "" hseth_gateway
    wwctl profile set default --netname=eth --type=Ethernet --netmask=${hseth_netmask} --gateway=${hseth_gateway} -y
    pause_for_review
}

show_networks_submenu() {
    local exit_submenu=false
    while [ "$exit_submenu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Configure Warewulf Networks        **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} iDRAC ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} InfiniBand ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} OmniPath ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} High Speed Ethernet ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Return to previous menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " net_choice
        case $net_choice in
            1) configure_ww_network_idrac ;;
            2) configure_ww_network_ib ;;
            3) configure_ww_network_opa ;;
            4) configure_ww_network_hse ;;
            5) exit_submenu=true ;;
            *) echo "Invalid choice." ; sleep 2;;
        esac
    done
}

create_ww_profile_compute() {
    wwctl profile add compute --comment "Standard compute nodes" -C compute  -y
    console_taskcomplete_msg "Profile 'compute' created."
    pause_for_review
}

create_ww_profile_bigmem() {
    wwctl profile add bigmem --comment "Large memory compute nodes" -C bigmem  -y
    console_taskcomplete_msg "Profile 'bigmem' created."
    pause_for_review
}

create_ww_profile_gpu() {
    wwctl profile add gpu --comment "Nodes with Nvidia GPU" --kernelargs "quiet crashkernel=no vga=791 net.naming-scheme=v238 modprobe.blacklist=nouveau" -C gpu  -y
    console_taskcomplete_msg "Profile 'gpu' created."
    pause_for_review
}

create_ww_profile_login() {
    wwctl profile add login --comment "User login node" -C login  -y
    console_taskcomplete_msg "Profile 'login' created."
    pause_for_review
}

create_ww_profile_storage() {
    wwctl profile add storage --comment "Storage node" -C storage -y
    console_taskcomplete_msg "Profile 'storage' created."
    pause_for_review
}

create_ww_profile_unmanaged() {
    wwctl profile add unmanaged --comment "Unmanaged Node - Used for Creating Host Entries" -y
    console_taskcomplete_msg "Profile 'Unmanaged' created."
    pause_for_review
}

show_profiles_submenu() {
    local exit_submenu=false
    while [ "$exit_submenu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Configure Warewulf Profiles        **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Compute ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Bigmem ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Nvidia GPU ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Login ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Storage ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Unmanaged Node ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Return to previous menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " prof_choice
        case $prof_choice in
            1) create_ww_profile_compute ;;
            2) create_ww_profile_bigmem ;;
            3) create_ww_profile_gpu ;;
            4) create_ww_profile_login ;;
            5) create_ww_profile_storage ;;
            6) create_ww_profile_unmanaged ;;
            7) exit_submenu=true ;;
            *) echo "Invalid choice." ; sleep 2 ;;
        esac
    done
}

create_ww_overlay_slurm() {
    if [ ! -f /etc/slurm/slurm.conf ]; then
        console_fail_msg "slurm.conf not found. Install Slurm first."
        sleep 3;
    else
        munge_uid=$(id -u munge)
        wwctl overlay create slurm
        wwctl overlay mkdir slurm /etc/slurm /etc/munge /var/lib/munge /var/log/munge
        wwctl overlay chown slurm /etc/munge/ "${munge_uid}" "${munge_uid}"
        wwctl overlay chown slurm /var/lib/munge "${munge_uid}" "${munge_uid}"
        wwctl overlay chown slurm /var/log/munge "${munge_uid}" "${munge_uid}"
        wwctl overlay import slurm /etc/slurm/slurm.conf
        wwctl overlay import slurm /etc/munge/munge.key
        wwctl overlay chown slurm /etc/munge/munge.key "${munge_uid}" "${munge_uid}"
        console_taskcomplete_msg "Slurm overlay created."
        pause_for_review
    fi
}

show_overlays_submenu() {
    local exit_submenu=false
    while [ "$exit_submenu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Configure Warewulf Overlays        **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Slurm ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Return to previous menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " ovrl_choice
        case $ovrl_choice in
            1) create_ww_overlay_slurm ;;
            2) exit_submenu=true ;;
            *) echo "Invalid choice."; sleep 2 ;;
        esac
    done
}

# --- Main Menu for this script ---
show_warewulf_menu() {
    local exit_main_menu=false
    while [ "$exit_main_menu" = false ]; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BOLDRED}** Warewulf & Cluster Management Menu    **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Install Warewulf ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Configure Warewulf (warewulf.conf) ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Configure Warewulf Default Profile ${RESET}"
        echo -e "  ${YELLOW}4)${BLUE} Configure Warewulf Networks (Sub-Menu) ${RESET}"
        echo -e "  ${YELLOW}5)${BLUE} Configure Warewulf Profiles (Sub-Menu) ${RESET}"
        echo -e "  ${YELLOW}6)${BLUE} Configure Warewulf Overlays (Sub-Menu) ${RESET}"
        echo -e "  ${YELLOW}7)${BLUE} Configure Slurm Workload Manager ${RESET}"
        echo -e "  ${YELLOW}8)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " choice

        case $choice in
            1) install_warewulf ;;
            2) configure_warewulf ;;
            3) configure_warewulf_default_profile ;;
            4) show_networks_submenu ;;
            5) show_profiles_submenu ;;
            6) show_overlays_submenu ;;
            7) configure_slurm ;;
            8) exit_main_menu=true ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_warewulf_menu
