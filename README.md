# Dell-OpenHPC-Warewulf

## HPC deployment scripts for OpenHPC with Warewulf v4.6.4. 

This has been tested with Rocky 9.4 and 9.5, RHEL 9.4 and 9.5

## Deployment Folder Structure
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
* cuda_12*.run (Example large artifact)