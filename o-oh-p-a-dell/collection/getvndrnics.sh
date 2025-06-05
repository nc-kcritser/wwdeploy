#!/bin/bash
# Get Vendor NIC Info (for PCI Based Ethernet NICs (such as on XE Class Hardware)

RAC=/opt/dell/srvadmin/sbin/racadm

$RAC get Nic.VndrConfigPage.1 | grep MacAddr | grep -v Virt | cut -d "=" -f 2
$RAC get Nic.VndrConfigPage.2 | grep MacAddr | grep -v Virt | cut -d "=" -f 2
