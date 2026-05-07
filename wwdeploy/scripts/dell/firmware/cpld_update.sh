#!/bin/bash

# Usage: Create a folder for each server model in the cluster in /cm/shared/apps/dell/firmware/PowerEdge/

# Place firmware files in the folder.
# Execute update script on nodes.
# Examples

# If there is any doubt about the model, use dmidecode to validate.
# dmidecode|grep ModelName

# Place firmware files in the folder.
# Execute update script on nodes.
# Examples
#
# pdsh -w c[001-064] /cm/shared/apps/dell/firmware/firmware_update.sh
#
# pdsh -g rack=1 /cm/shared/apps/dell/firmware/firmware_update.sh
#

## Explicitly set racadm binary
RAC=/opt/dell/srvadmin/sbin/racadm

## Determine cluster management platform
if [ -d /opt/ohpc/pub/apps/dell/firmware/PowerEdge ]; then
	echo "Cluster manager is OpenHPC/Warewulf!"
	sleep 2
	fw_path=/opt/ohpc/pub/apps/dell/firmware/PowerEdge
elif [ -d /cm/shared/apps/dell/firmware/PowerEdge ]; then
	echo "Cluster manager is Base Command Manager/Bright!"
	sleep 2
	fw_path=/cm/shared/apps/dell/firmware/PowerEdge
fi

# Determine my model number from dmidecode information.
poweredge_model=`dmidecode|grep "Product Name:"|head -1|awk -F : '{print $2}'|awk -F " " '{print $2}'`

# Set my firmware directory based on my model number.
fw_dir=${fw_path}/${poweredge_model}


# Update CPLD
for i in `ls ${fw_dir}|grep BIN|grep CPLD`; do sh ${fw_dir}/$i -q; done


# Reboot for the update to take effect
$RAC set BIOS.MiscSettings.PowerCycleRequest FullPowerCycle
$RAC jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
$RAC serveraction powercycle
