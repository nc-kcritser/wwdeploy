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

# --- Helper Functions ---

get_poweredge_model() {
    dmidecode | grep "Product Name:" | head -1 | awk -F': ' '{print $2}' | awk '{print $2}'
}

get_firmware_directory() {
    local model="$1"
    echo "/opt/ohpc/pub/apps/dell/firmware/PowerEdge/${model}"
}

# --- Firmware Functions ---

install_master_node_firmware() {
	option_picked "Update Master Node Firmware"

    # --- SAFETY CHECK ---
    read -p "This action will update the main system firmware and will reboot the server. Are you sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "Firmware update cancelled by user."
        pause_for_review
        return 1
    fi

	local poweredge_model=$(get_poweredge_model)
	local fw_dir=$(get_firmware_directory "$poweredge_model")

	console_info_msg "Detected PowerEdge model: ${poweredge_model}"
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found: $fw_dir"
        console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		return 1
	fi

	console_info_msg "Starting firmware update for PowerEdge ${poweredge_model}..."
	console_info_msg "Setting executable permissions on firmware files..."
	chmod +x -R "${fw_dir}"/*.BIN

	# Update iDRAC firmware first
	console_taskstart_msg "Updating iDRAC firmware..."
	for fw_file in "${fw_dir}"/iDRAC*.BIN; do
		if [ -f "$fw_file" ]; then
			console_info_msg "  → $(basename "$fw_file")"
			"$fw_file" -q
		fi
	done

	# Update all other firmware except iDRAC, BIOS, FPGA, and CPLD
	console_taskstart_msg "Updating component firmware (excluding BIOS, FPGA, CPLD)..."
	for fw_file in "${fw_dir}"/*.BIN; do
		if [ -f "$fw_file" ]; then
			filename=$(basename "$fw_file")
			if ! [[ "$filename" =~ (BIOS|iDRAC|FPGA|CPLD) ]]; then
				console_info_msg "  → $filename"
				"$fw_file" -q
			fi
		fi
	done

	# Update BIOS firmware last and trigger reboot
	console_taskstart_msg "Updating BIOS firmware (will initiate reboot)..."
	for fw_file in "${fw_dir}"/BIOS*.BIN; do
		if [ -f "$fw_file" ]; then
			console_info_msg "  → $(basename "$fw_file")"
			"$fw_file" -q -r
		fi
	done

	console_taskcomplete_msg "Firmware update sequence complete. System rebooting..."
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

	local poweredge_model=$(get_poweredge_model)
	local fw_dir=$(get_firmware_directory "$poweredge_model")

	console_info_msg "Detected PowerEdge model: ${poweredge_model}"
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found: $fw_dir"
		console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		return 1
	fi

	console_info_msg "Starting CPLD firmware update for PowerEdge ${poweredge_model}..."
	console_taskstart_msg "Updating CPLD firmware..."

	local cpld_count=0
	for fw_file in "${fw_dir}"/CPLD*.BIN; do
		if [ -f "$fw_file" ]; then
			console_info_msg "  → $(basename "$fw_file")"
			"$fw_file" -q
			((cpld_count++))
		fi
	done

	if [ "$cpld_count" -eq 0 ]; then
		console_fail_msg "No CPLD firmware files found in $fw_dir"
		pause_for_review
		return 1
	fi

	console_info_msg "Initiating power cycle via iDRAC..."
	racadm set BIOS.MiscSettings.PowerCycleRequest FullPowerCycle
	racadm jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
	racadm serveraction powercycle

	console_taskcomplete_msg "CPLD firmware update complete - System rebooting (connection will be lost)"
    pause_for_review
}

install_master_node_fpga_firmware() {
	option_picked "Update Master Node FPGA (17th Gen)"

    # --- SAFETY CHECK ---
    read -p "This action will update the FPGA firmware. Are you sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        console_info_msg "FPGA update cancelled by user."
        pause_for_review
        return 1
    fi

	local poweredge_model=$(get_poweredge_model)
	local fw_dir=$(get_firmware_directory "$poweredge_model")

	console_info_msg "Detected PowerEdge model: ${poweredge_model}"
	if [ ! -d "$fw_dir" ]; then
		console_fail_msg "Firmware directory not found: $fw_dir"
		console_info_msg "Please upload firmware for the PowerEdge ${poweredge_model} and run again."
		pause_for_review
		return 1
	fi

	console_info_msg "Starting FPGA firmware update for PowerEdge ${poweredge_model}..."
	console_taskstart_msg "Updating FPGA firmware..."

	local fpga_count=0
	for fw_file in "${fw_dir}"/FPGA*.BIN; do
		if [ -f "$fw_file" ]; then
			console_info_msg "  → $(basename "$fw_file")"
			"$fw_file" -q
			((fpga_count++))
		fi
	done

	if [ "$fpga_count" -eq 0 ]; then
		console_fail_msg "No FPGA firmware files found in $fw_dir"
		pause_for_review
		return 1
	fi

	console_taskcomplete_msg "FPGA firmware update complete ($fpga_count file(s) updated)"
    pause_for_review
}


# --- Sub-Menu for this script ---
show_firmware_menu() {
    local option
    while true; do
        echo_menu_header "Firmware Update Menu - Head Node"
        echo -e "  ${YELLOW}1)${BLUE} Update master node firmware (BIOS, component firmware) ${RESET}"
        echo -e "  ${YELLOW}2)${BLUE} Update master node CPLD firmware ${RESET}"
        echo -e "  ${YELLOW}3)${BLUE} Update master node FPGA firmware (16th-17th Gen) ${RESET}"
        echo -e "  ${YELLOW}0)${BLUE} Return to Main Menu ${RESET}"
        read -r -p "=> " option

        case $option in
            1) install_master_node_firmware ;;
            2) install_master_node_cpld_firmware ;;
            3) install_master_node_fpga_firmware ;;
            0) break ;;
            *)
                echo "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# --- Script execution starts here ---
show_firmware_menu

