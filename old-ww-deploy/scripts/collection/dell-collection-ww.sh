#!/bin/bash

RAC=/opt/dell/srvadmin/sbin/racadm

today_date=$(date +%m-%d-%Y)

# Get information about which nodes to query
read -e -p "Enter customer name (no spaces): " -i "customer" customer_name

read -e -p "Enter node base name: " -i "node" node_base

read -e -p "Enter first node: " -i "001" first_node

read -e -p "Enter last node: " -i "064" last_node

read -e -p "Enter interface for MAC capture: " -i "em1" nic

# Create the headers
createheader () {
        if [ ! -f ${customer_name}-Server_Info-${today_date}.csv ]; then
			echo "node,ServiceTag,Model,bios_version,CPLD,idrac_fw_version,MAC,NIC Speed,IP ADDR,CPUs,CPU Model,CPU Freq,Memory,InfiniBand GUID,IB Rate,IB Firmware,HDD-manufacturer,HDD-serial,Mode,Boot Dev,iDRAC Dev,iDRAC ip,iDRAC mac,Rack,U Location,Slot" > ${customer_name}-Server_Info-${today_date}.csv
			gathermaster
        fi
}

intelcpu () {
	# This routine to collect info for Intel CPUs
	cpu_model=`pdsh -w ${node} cat /proc/cpuinfo|grep "model name"|head -1|awk -F ' ' '{print $8}'`
	cpu_freq=`pdsh -w ${node} cat /proc/cpuinfo|grep "model name"|head -1|awk -F ' ' '{print $11}'`
}

amdcpu () {
	# This routine to collect info for AMD CPUs
	cpu_model=`pdsh -w ${node} cat /proc/cpuinfo |grep AMD|tail -1|awk -F : '{print $3}'|awk -F " " '{print $3}'`
	cpu_freq=`pdsh -w ${node} cat /proc/cpuinfo|grep MHz|tail -1|awk -F : '{print $3}'|awk -F " " '{print $1}'`
}

gathermaster () {
        master_node=`hostname -s`
        echo -e "-> Gathering from ${master_node}"
        ServiceTag=`$RAC getsvctag|head -1|awk -F : '{print $1}'`
        Model=`$RAC getsysinfo|grep Model|awk -F = '{print $2}'|awk -F ' ' '{print $2}'`
        bios_version=`$RAC getsysinfo -w -s|grep "System BIOS Version"|awk -F = '{print $2}'`
	    cpld_version=`$RAC get BIOS.sysinformation.SystemCpldVersion|awk -F = '{print $2}'|grep -v BIOS`
        idrac_fw_version=`$RAC get iDRAC.Info|grep Version|grep -v CPLD|grep -v IPMI|grep -v Rollback|awk -F = '{print $2}'`
        MAC=`ifconfig ${nic}|grep ether|awk -F ' ' '{print $2}'`
        nic_speed=`ethtool ${nic}|grep Speed|awk -F : '{print $2}'`
	      ip_addr=`ip addr show ${nic} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n 1`	
        num_cpu=`cat /proc/cpuinfo|grep processor|wc -l`
		cpu_vendor=`cat /proc/cpuinfo|grep AuthenticAMD|tail -1|awk -F : '{print $2}'|sed -e 's/^[ \t]*//'`
		if [ "$cpu_vendor" == "AuthenticAMD" ]; then
			cpu_model=`cat /proc/cpuinfo |grep AMD|tail -1|awk -F : '{print $2}'|awk -F " " '{print $3}'`
			cpu_freq=`cat /proc/cpuinfo|grep MHz|tail -1|awk -F : '{print $2}'|awk -F " " '{print $1}'`
		else
			cpu_model=`cat /proc/cpuinfo|grep "model name"|head -1|awk -F ' ' '{print $7}'`
			cpu_freq=`cat /proc/cpuinfo|grep "model name"|head -1|awk -F ' ' '{print $10}'`
		fi
        mem=`free -g|grep Mem|awk -F ' ' '{print $2}'`
        ib_dev=`ibstat|head -1|awk -F \' '{print $2}'`
        ib_guid=`ibstat|grep "Node GUID"|head -1|awk -F ' ' '{print $3}'`
        ib_rate=`ibstat|grep Rate|head -1|awk -F : '{print $2}'`
        ib_fw_version=`ibstat|grep Firmware|head -1|awk -F : '{print $2}'`
        HDD_manufacturer=`$RAC storage get pdisks -o|grep Manufacturer|head -1|awk -F = '{print $2}'`
        HDD_serial=`$RAC storage get pdisks -o|grep SerialNumber|head -1|awk -F = '{print $2}'`
        mode=`$RAC get BIOS.BiosBootSettings.BootMode|grep -v Settings|awk -F = '{print $2}'`
        bootdev=`$RAC get BIOS.BiosBootSettings.BootSeq|awk -F = '{print $2}'|grep -v BiosBootSettings|awk -F , '{print $1}'`
		idrac_dev=`$RAC get idrac.nic.Selection|awk -F = '{print $2}'|grep -v idrac.`
        idrac_ip=`$RAC get idrac.IPv4|grep Address|awk -F = '{print $2}'`
        idrac_mac=`$RAC get idrac.NIC|grep MACAddress|awk -F = '{print $2}'`
        echo -e "${master_node},${ServiceTag},${Model},${bios_version},${cpld_version},${idrac_fw_version},${MAC},${nic_speed},${ip_addr},${num_cpu},${cpu_model},${cpu_freq},${mem},${ib_guid},${ib_rate},${ib_fw_version},"${HDD_manufacturer// /}","${HDD_serial// /}",${mode},${bootdev},${idrac_dev},${idrac_ip},${idrac_mac}" >> ${customer_name}-Server_Info-${today_date}.csv
}


# Use pdsh to get info from nodes
gatherinfo () {
        node=${node_base}${i}
        echo -e "--> Gathering from ${node}"
        ServiceTag=`pdsh -w ${node} $RAC getsvctag|head -1|awk -F : '{print $2}'`
        Model=`pdsh -w ${node} $RAC getsysinfo|grep Model|awk -F = '{print $2}'|awk -F ' ' '{print $2}'`
        bios_version=`pdsh -w ${node} $RAC getsysinfo -w -s|grep "System BIOS Version"|awk -F = '{print $2}'`
	      cpld_version=`pdsh -w ${node} $RAC get BIOS.sysinformation.SystemCpldVersion|awk -F = '{print $2}'|grep -v BIOS`
        idrac_fw_version=`pdsh -w ${node} $RAC get iDRAC.Info|grep Version|grep -v CPLD|grep -v IPMI|grep -v Rollback|awk -F = '{print $2}'`
        MAC=`pdsh -w ${node} ifconfig ${nic}|grep ether|awk -F ' ' '{print $3}'`
        nic_speed=`pdsh -w ${node} ethtool ${nic}|grep Speed|awk -F : '{print $3}'`
	      ip_addr=`wwctl node export ${node} | grep -A3 default | grep ipaddr | cut -d':' -f2 | xargs`
    		cpu_vendor=`pdsh -w ${node} cat /proc/cpuinfo|grep AuthenticAMD|tail -1|awk -F : '{print $3}'|sed -e 's/^[ \t]*//'`
	    	num_cpu=`pdsh -w ${node} cat /proc/cpuinfo|grep processor|wc -l`
		if [ "$cpu_vendor" == AuthenticAMD ];then
			amdcpu
		else
			intelcpu
		fi
        mem=`pdsh -w ${node} free -g|grep Mem|awk -F ' ' '{print $3}'`
        ib_dev=`pdsh -w ${node} ibstat|head -1|awk -F \' '{print $2}'`
		ib_guid=`pdsh -w ${node} ibstat|grep "Node GUID"|head -1|awk -F ' ' '{print $4}'`
        ib_rate=`pdsh -w ${node} ibstat|grep Rate|head -1|awk -F : '{print $3}'`
        ib_fw_version=`pdsh -w ${node} ibstat|grep Firmware|head -1|awk -F : '{print $3}'`
        HDD_manufacturer=`pdsh -w ${node} $RAC storage get pdisks -o|grep Manufacturer|head -1|awk -F = '{print $2}'`
        HDD_serial=`pdsh -w ${node} $RAC storage get pdisks -o|grep SerialNumber|head -1|awk -F = '{print $2}'`
        mode=`pdsh -w ${node} $RAC get BIOS.BiosBootSettings.BootMode|grep -v Settings|awk -F = '{print $2}'`
		if [ "$mode" == "Bios" ];then
			bootdev=`pdsh -w ${node} $RAC get BIOS.BiosBootSettings.BootSeq|awk -F = '{print $2}'|grep -v BiosBootSettings|awk -F , '{print $1}'`
		else
			bootdev=`pdsh -w ${node} $RAC get bios.PxeDev1Settings.PxeDev1Interface|awk -F = '{print $2}'|grep -v Setup`
		fi
        idrac_dev=`pdsh -w ${node} $RAC get idrac.nic.Selection|awk -F = '{print $2}'|grep -v idrac.`
		idrac_ip=`pdsh -w ${node} $RAC get idrac.IPv4|grep Address|awk -F = '{print $2}'`
        idrac_mac=`pdsh -w ${node} $RAC get idrac.NIC|grep MACAddress|awk -F = '{print $2}'`
        echo -e "${node},${ServiceTag},${Model},${bios_version},${cpld_version},${idrac_fw_version},${MAC},${nic_speed},${nic_speed},${num_cpu},${cpu_model},${cpu_freq},${mem},${ib_guid},${ib_rate},${ib_fw_version},"${HDD_manufacturer// /}","${HDD_serial// /}",${mode},${bootdev},${idrac_dev},${idrac_ip},${idrac_mac}" >> ${customer_name}-Server_Info-${today_date}.csv
}

# Do the work
createheader

for i in `seq -w ${first_node} ${last_node}`; do gatherinfo ${node_base}${i}; done
