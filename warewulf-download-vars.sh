#!/usr/bin/env bash

#Populate System Variables
. /etc/os-release

warewulf_deploy_version=4.5.8
ww_el=${PLATFORM_ID#*:}                 # Gives us the el8/el9
elnumber=${PLATFORM_ID##*:el}


# From the internet -- Enterprise Linux 8/9 (depending on platform it is run on)
WW_INSTALL_RPM=https://github.com/warewulf/warewulf/releases/download/v$warewulf_deploy_version/warewulf-$warewulf_deploy_version-1.$ww_el.x86_64.rpm
WW_DRACUT_RPM=https://github.com/warewulf/warewulf/releases/download/v$warewulf_deploy_version/warewulf-dracut-$warewulf_deploy_version-1.$ww_el.noarch.rpm
# From local host ( if you have the files in your local host or for offline install)
#warewulf_installer_file=/root/warewulf-4.5.8-1.el8.x86_64.rpm
#warewulf_dracut_file=/root/warewulf-dracut-4.5.8-1.el9.noarch.rpm

## OpenManage DLs (Recommending 11_2)
IDRACTOOLS_MULTI_DL_11_0=https://dl.dell.com/FOLDER08952875M/1/Dell-iDRACTools-Web-LX-11.0.0.0-5139_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_1=https://dl.dell.com/FOLDER09667202M/1/Dell-iDRACTools-Web-LX-11.1.0.0-5294_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_2=https://dl.dell.com/FOLDER12112988M/1/Dell-iDRACTools-Web-LX-11.2.1.0-528_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_3=https://dl.dell.com/FOLDER12638439M/1/Dell-iDRACTools-Web-LX-11.3.0.0-795_A00.tar.gz
IDRACTOOLS_DL_URL=$IDRACTOOLS_MULTI_DL_11_2

## Mellanox OFED DLs - URL Valid as of 29 APR 2025
MLNX_OFED_2310_DL_URL=https://content.mellanox.com/ofed/MLNX_OFED-23.10-4.0.9.1/MLNX_OFED_LINUX-23.10-4.0.9.1-rhel$VERSION_ID-x86_64.tgz
MLNX_OFED_2410_DL_URL=https://content.mellanox.com/ofed/MLNX_OFED-24.10-2.1.8.0/MLNX_OFED_LINUX-24.10-2.1.8.0-rhel$VERSION_ID-x86_64.tgz
MLNX_OFED_DL_URL=$MLNX_OFED_2310_DL_URL

# OpenHPC DLs (2 for EL8 and 3 for EL9)
OpenHPC2_DL=https://repos.openhpc.community/OpenHPC/2/EL_8/x86_64/ohpc-release-2-1.el8.x86_64.rpm
OpenHPC3_DL=https://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm

# EPEL URL 
EPEL_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-$ww_el.noarch.rpm

# HPC-X URLs
HPCX218_URL=https://content.mellanox.com/hpc/hpc-x/v2.18.1/hpcx-v2.18.1-gcc-mlnx_ofed-redhat9-cuda12-x86_64.tbz

# Intel URLs (Future Implement)
INTEL23_BASEKIT_URL=
INTEL23_HPCKIT_URL=
INTEL24_BASEKIT_URL=
INTEL24_HPCKIT_URL=
INTEL25_BASEKIT_URL=
INTEL25_HPCKIT_URL=
