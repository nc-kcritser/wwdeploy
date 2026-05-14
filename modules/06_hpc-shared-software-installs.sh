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

# --- HPC Software (as in Shared Software) Installation Functions ---

install_openhpc_packages_master() {
    option_picked "Install OpenHPC Server Packages"
	
    console_info_msg "Adding OpenHPC repository to master node..."
    # Note: The $OpenHPC3_DL variable should be defined in your sourced vars file.
    yum install -y $OpenHPC3_DL
    if [ $? -ne 0 ]; then
        console_fail_msg "Failed to add OpenHPC repository. Please check the URL or your network connection."
        pause_for_review
        return 1
    fi
    console_info_msg "Installing OpenHPC Server packages..."

	dnf install -y gcc nhc-ohpc gnu12-compilers-ohpc gnu13-compilers-ohpc ohpc-autotools EasyBuild-ohpc spack-ohpc valgrind-ohpc openmpi5-gnu13-ohpc mpich-ofi-gnu13-ohpc mpich-ucx-gnu13-ohpc ohpc-gnu13-openmpi5-parallel-libs ohpc-gnu13-mpich-parallel-libs ohpc-gnu13-perf-tools lmod-defaults-gnu13-openmpi5-ohpc
    if [ $? -ne 0 ]; then
        console_fail_msg "Failed to install OpenHPC packages. Please check your network connection or the repository URL."
        pause_for_review
        return 1
    fi
	console_taskcomplete_msg "OpenHPC packages installed."
	pause_for_review
}

install_mellanox_hpcx() {
    option_picked "Install Mellanox HPC-X"
    ## TODO: Re-wrap and build multiple versions of HPC-X using modules
	wget -nc "$HPCX218_URL"
	hpcx_file=$(find /root -maxdepth 1 -name 'hpcx*.tbz' -print -quit)
	if [ -z "${hpcx_file}" ];then
		console_fail_msg "Mellanox HPC-X tarball not found in /root. Please upload the file and run this again."
		pause_for_review
		return 1
	fi

	mkdir -p /opt/ohpc/pub/apps/mellanox
	tar xvf "${hpcx_file}" -C /opt/ohpc/pub/apps/mellanox
	mlnx_hpcx_dir=$(ls /opt/ohpc/pub/apps/mellanox/|grep hpcx)

	# Add to /etc/profile on head node
	echo "" >> /etc/profile
	echo "module use /opt/ohpc/pub/apps/mellanox/$mlnx_hpcx_dir/modulefiles" >> /etc/profile
    console_taskcomplete_msg "HPC-X module path added to /etc/profile."
	pause_for_review
}

install_intel_oneapi() {
    option_picked "Install Intel oneAPI"
    ## TODO: Update and Versions (now 2026, and old 2025) Intel One API
    PS3='Select oneAPI version to install: '
	options=( "2023.1.0" "2024.0.1" "2025.0.0" "Cancel" )
	select opt in "${options[@]}"; do
		case $opt in
			"2023.1.0"|"2024.0.1"|"2025.0.0")
				console_info_msg "Installing Intel oneAPI version ${opt}..."
				# This is a placeholder for the actual installation commands for each version
                # You would add the specific wget and installer commands here.
                console_fail_msg "Installer for version ${opt} not yet implemented in this script."
				break
				;;
            "Cancel")
                break
                ;;
            *)
                echo "Invalid option."
                ;;
		esac
	done
    pause_for_review
}

install_nvidia_cuda() {
    option_picked "Install Nvidia CUDA Toolkit"
    ## TODO: Update and Validate NVIDIA CUDA
	cuda_file=$(find /root -maxdepth 1 -name 'cuda*.run' -print -quit)
    if [ -z "${cuda_file}" ]; then
        console_fail_msg "Nvidia CUDA runfile not found in /root. Please download and run again."
        pause_for_review
        return 1
    fi
	cuda_version=$(basename "${cuda_file}" | awk -F_ '{print $2}')

	console_info_msg "Installing CUDA Toolkit $cuda_version"
	sh "${cuda_file}" --silent --toolkit --toolkitpath=/opt/ohpc/pub/apps/nvidia/cuda/toolkit/$cuda_version

	console_info_msg "Creating Nvidia Toolkit modulefile..."
	mkdir -p /opt/ohpc/pub/modulefiles/nvidia/cuda/
	cat << EOF > /opt/ohpc/pub/modulefiles/nvidia/cuda/$cuda_version
#%Module1.0
proc ModulesHelp { } {
    puts stderr "This module sets the Nvidia CUDA Toolkit path, version $cuda_version"
}
module-whatis "Name: Nvidia CUDA Toolkit v$cuda_version"
set version $cuda_version
prepend-path PATH /opt/ohpc/pub/apps/nvidia/cuda/toolkit/\$version/bin
prepend-path LD_LIBRARY_PATH /opt/ohpc/pub/apps/nvidia/cuda/toolkit/\$version/lib64
EOF
    console_taskcomplete_msg "Nvidia CUDA Toolkit module file created."
	pause_for_review
}


hpc_software_menu() {
    local option
    while true; do
        echo_menu_header "HPC Software Installation"
        echo " 1) Install OpenHPC Server Packages"
        echo " 2) Install Mellanox HPC-X"
        echo " 3) Install Intel oneAPI Toolkit"
        echo " 4) Install Nvidia CUDA Toolkit"
        echo " 0) Return to main menu"
        read -r -p "=> " option
        case $option in
            1) install_openhpc_packages_master ;;
            2) install_mellanox_hpcx ;;
            3) install_intel_oneapi ;;
            4) install_nvidia_cuda ;;
            0) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Module runs its own menu and exits
hpc_software_menu
                                                                                                                                                                                                      