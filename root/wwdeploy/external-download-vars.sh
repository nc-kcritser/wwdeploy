#!/usr/bin/env bash

#Populate System Variables
. /etc/os-release

WW4_DEPLOY_VERSION=4.5.8
WW_EL=${PLATFORM_ID#*:}                 # Gives us the el8/el9
ELNUM=${PLATFORM_ID##*:el}              # Gives us the 8 or 9 from el8 or el9
VERSION_NODOT="${VERSION_ID//./}"             # Converts 8.6 to 86, 9.2 to 92, etc.

# From the internet -- Enterprise Linux 8/9 (depending on platform it is run on)
warewulf_installer_file=https://github.com/warewulf/warewulf/releases/download/v$WW4_DEPLOY_VERSION/warewulf-$WW4_DEPLOY_VERSION-1.$WW_EL.x86_64.rpm
warewulf_dracut_file=https://github.com/warewulf/warewulf/releases/download/v$WW4_DEPLOY_VERSION/warewulf-dracut-$WW4_DEPLOY_VERSION-1.$WW_EL.noarch.rpm
# From local host ( if you have the files in your local host or for offline install)
#warewulf_installer_file=/root/warewulf-4.5.8-1.el8.x86_64.rpm
#warewulf_dracut_file=/root/warewulf-dracut-4.5.8-1.el9.noarch.rpm

## OpenManage DLs (Recommending 11_3 as of 2 JUL 2025)
IDRACTOOLS_MULTI_DL_11_0=https://dl.dell.com/FOLDER08952875M/1/Dell-iDRACTools-Web-LX-11.0.0.0-5139_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_1=https://dl.dell.com/FOLDER09667202M/1/Dell-iDRACTools-Web-LX-11.1.0.0-5294_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_2=https://dl.dell.com/FOLDER12112988M/1/Dell-iDRACTools-Web-LX-11.2.1.0-528_A00.tar.gz
IDRACTOOLS_MULTI_DL_11_3=https://dl.dell.com/FOLDER12638439M/1/Dell-iDRACTools-Web-LX-11.3.0.0-795_A00.tar.gz
IDRACTOOLS_DL_URL=$IDRACTOOLS_MULTI_DL_11_3

## Mellanox OFED DLs - URL Valid as of 29 APR 2025
MLNX_OFED_2310_DL_URL=https://content.mellanox.com/ofed/MLNX_OFED-23.10-4.0.9.1/MLNX_OFED_LINUX-23.10-4.0.9.1-rhel$VERSION_ID-x86_64.tgz
MLNX_OFED_2410_DL_URL=https://content.mellanox.com/ofed/MLNX_OFED-24.10-2.1.8.0/MLNX_OFED_LINUX-24.10-2.1.8.0-rhel$VERSION_ID-x86_64.tgz
MLNX_DOCA_OFED_3_DL_URL=https://www.mellanox.com/downloads/DOCA/DOCA_v3.0.0/host/doca-host-3.0.0-058000_25.04_rhel$VERSION_NODOT.x86_64.rpm

# OpenHPC DLs (2 for EL8 and 3 for EL9)
OpenHPC2_DL=https://repos.openhpc.community/OpenHPC/2/EL_8/x86_64/ohpc-release-2-1.el8.x86_64.rpm
OpenHPC3_DL=https://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm

EPEL_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-$ELNUM.noarch.rpm

# HPC-X DLs - URL Valid as of 29 APR 2025
HPCX218_URL=https://content.mellanox.com/hpc/hpc-x/v2.18.1/hpcx-v2.18.1-gcc-mlnx_ofed-redhat9-cuda12-x86_64.tbz
