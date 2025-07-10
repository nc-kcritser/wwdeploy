# Dell-OpenHPC-Warewulf

HPC deployment scripts for OpenHPC with Warewulf v4.5.8

This has been tested with Rocky 9.4-9.5, RHEL 9.4-9.5

The Folder Structure for Deployment is as follows

/root/
├── wwdeploy/
│   ├── common.sh
│   ├── deploy_warewulf.sh
│   ├── firmware-updates.sh
│   ├── hpc-software-installs.sh
│   ├── master-node-config.sh
│   ├── monitoring-security.sh
│   ├── network-config.sh
│   ├── troubleshooting.sh
│   ├── warewulf-config.sh
│   ├── ww4-image-management.sh
│   │
│   ├── customer-set-vars.sh      # (User-provided variables)
│   └── external-download-vars.sh # (User-provided variables)
│
└─── **Large ISOs/TGZs/RUNfile** go in the /root
