# Dell-OpenHPC-Warewulf

## HPC deployment scripts for OpenHPC with Warewulf v4.6.4. 

This has been tested with Rocky and Red Hat Enterprise Linux (RHEL) in the 9.x Branch (9.4 - 9.7).  
As of May 7, 2026 -Warewulf Supports - EL8, EL9 and EL10 flavors 

**THIS BUNDLE CURRENTLY ONLY SUPPORTS DEPLOYMENTS FOR EL9 FLAVORS**

# Prerequisites

Warewulf Head Nodes should be built with the appropriate ISO from the vendor. (Rocky,RHEL) - Ubuntu Head Nodes are not supported at this time.

It is recommended during the installer to do the following:
- Set a hostname
- Disable Security Policy
- Setup Disk completely for productions (including partitions for /var, /tmp and others as recommended)
- Use the Minimal or Server (non-gui) - If a customer wants a GUI, install it afterwards (or they can).

## Deployment Folder Structure
The deployment is issued as a bundle (tar.gz) that should be unpacked in /root)

This document outlines the required directory structure for the deployment tool and its related files.

📂 /root/wwdeploy/
* This is the main directory for the deployment tool itself. All the .sh script modules and your custom variable files should be placed here. You will run the deployment by navigating into this directory and executing bash deploy_warewulf.sh.

This Folder includes:
* common.sh
* deploy_warewulf.sh
* firmware-updates.sh
* hpc-software-installs.sh
* master-node-config.sh
* monitoring-security.sh
* network-config.sh
* troubleshooting.sh
* warewulf-config.sh
* ww4-image-management.sh
* customer-set-vars.sh (User-provided variables)
* external-download-vars.sh (User-provided variables)

📦 /root/
* This directory is used as a holding area for the large software packages (ISOs, tarballs, runfiles) that the scripts will install. The scripts are designed to look for these files in /root/ by default. With the exception of the Rocky/RHEL ISO. Most files will download automatically.

This folder should include: 
* RHEL9*.iso (Example large artifact)
* MLNX_OFED*.tgz (Example large artifact)
* DOCA_OFED*.tgz (Example large artifact)
* cuda_12*.run (Example large artifact)