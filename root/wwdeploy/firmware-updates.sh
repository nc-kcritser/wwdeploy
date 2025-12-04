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

# --- Firmware Functions ---

install_master_node_firmware() {
	option_picked "Update Master Node Firmware";

    # --- SAFETY CHECK ---
    read -p "This action will update the main system firmware and will reboot the server. Are you sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "Firmware update cancelled by user."
        pause_for_review
        return 1
    fi
    # --- END SAFETY CHECK ---

	# Update Dell firmware
	poweredge_model=`dmidecode|grep "Product Name:"|head -1|awk -F : '{print $2}'|awk -F " " '{print $2}'`
	fw_dir=/opt/ohpc/pub/apps/dell/firmware/PowerEdge/${poweredge_model}
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found!"
        console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		return 1;
	fi

	echo "Updating PowerEdge ${poweredge_model} firmware..."
	sleep 2

	# Set executable perms on the BIN files
	chmod +x -R ${fw_dir}/*.BIN
	for i in `ls ${fw_dir}|grep iDRAC`; do ${fw_dir}/$i -q; done
	# Update everything else except iDRAC, BIOS and CPLD firmware
	for i in `ls ${fw_dir}|grep BIN|grep -v BIOS|grep -v iDRAC|grep -v CPLD`; do ${fw_dir}/$i -q; done
	# Update BIOS and reboot
	for i in `ls ${fw_dir}|grep BIN|grep BIOS`; do ${fw_dir}/$i -q -r; done
	sleep 2
    pause_for_review
}

install_master_node_cpld_firmware() {
	option_picked "Update Master Node CPLD"

    # --- SAFETY CHECK ---
    read -p "This action will update the CPLD firmware and will force a reboot. Are you sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "CPLD update cancelled by user."
        pause_for_review
        return 1
    fi
    # --- END SAFETY CHECK ---

    # Update Dell CPLD firmware
	poweredge_model=`dmidecode|grep "Product Name:"|head -1|awk -F : '{print $2}'|awk -F " " '{print $2}'`
	fw_dir=/opt/ohpc/pub/apps/dell/firmware/PowerEdge/${poweredge_model}
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found!"
		console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		return 1;
	fi

	# Update CPLD firmware
	for i in `ls ${fw_dir}|grep BIN|grep CPLD`; do ${fw_dir}/$i -q; done

	# Reboot for the update to take effect
	racadm set BIOS.MiscSettings.PowerCycleRequest FullPowerCycle
	racadm jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
	racadm serveraction powercycle

	console_taskcomplete_msg "CPLD Firmware Cycle Complete - Rebooting Master Node - You will most likely lose connection"
    pause_for_review
}


# --- Sub-Menu for this script ---
show_firmware_menu() {
    while true; do
        clear
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "${BLUE}** Firmware Update Menu                 **${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        echo -e "  ${YELLOW}1)${BLUE} Update master node firmware (BIOS, etc.) ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Update master node CPLD firmware ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Return to Main Menu ${RESET}"
        echo -e "${BLUE}************************************************${RESET}"
        read -p "Enter your choice: " fw_choice

        case $fw_choice in
            1) install_master_node_firmware ;;
            2) install_master_node_cpld_firmware ;;
            3) exit 0 ;;
            *)
                echo "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_firmware_menu

