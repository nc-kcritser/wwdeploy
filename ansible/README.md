# Ansible Conversion of wwdeploy Bash Scripts

This directory contains Ansible playbooks that replace the interactive bash script modules with idempotent, configuration-driven equivalents.

## Structure

- `inventory.ini` — Ansible inventory file defining the `master` host group
- `group_vars/all.yml` — Cluster configuration variables (replaces `site-config.sh`)
- `requirements.yml` — Ansible collection dependencies
- `01_master-node-config.yml` — Module 01: Master node setup (packages, DNS, NTP, users, security)

## Installation

Install required Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## Usage

### Dry-run (check mode)

```bash
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --check
```

### Run all tasks

```bash
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml
```

### Run specific tags (sections)

```bash
# Only install packages and repos
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --tags prereqs

# Only configure DNS and NTP
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --tags dns,ntp

# Only create users and groups
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --tags users

# Only manage security (SELinux, firewall)
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --tags security
```

### Override variables

Pass variables via `--extra-vars` or `-e`:

```bash
# Set timezone to US Central
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  -e timezone=America/Chicago

# Enable local repo setup from ISO
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  --tags local_repo -e configure_local_repo=true

# Install iDRAC tools
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  --tags idrac -e install_idrac_tools=true

# Custom NTP server
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  -e ntp_server=pool.ntp.org
```

## Configuration Variables

Edit `ansible/group_vars/all.yml` to customize cluster settings:

- **Cluster identity**: `cluster_name`, `sms_name`, `external_domain`, `search_domains`
- **Networking**: Internal, external, InfiniBand, BMC networks and IPs
- **DNS/NTP**: `dns_server_*`, `ntp_server`, `timezone`
- **Users**: `image_pw`, `bmc_password`, etc.
- **Download URLs**: `idrac_tools_url`
- **Flags**: `install_prereqs`, `create_users`, `configure_dns`, `configure_ntp`, `configure_hostname`, `configure_local_repo`, `install_idrac_tools`, `selinux_state`, `firewall_enabled`

## Module 01 Conversion

The bash script `modules/01_master-node-config.sh` is converted as follows:

| Bash Function | Ansible Tag | Idempotent | Notes |
|---|---|---|---|
| `install_ohpc_ww_prereqs()` | `prereqs` | ✓ | EPEL, core packages, CRB/PowerTools |
| `build_local_os_repo()` | `local_repo` | ✓ | ISO mount, rsync, repo file creation |
| `install_idractools_master()` | `idrac` | ✓ | Download tarball, extract, install RPMs |
| `manage_security()` | `security` | ✓ | SELinux and firewalld state management |
| `configure_master_hostname()` | `hostname` | ✓ | Set hostname via systemd |
| `configure_master_host_dns()` | `dns` | ✓ | Write /etc/resolv.conf |
| `configure_master_timezone_chrony()` | `ntp` | ✓ | Set timezone, configure Chrony server |
| `create_local_users_groups()` | `users` | ✓ | Create dell group, hpl and gpu users |

Interactive menus are replaced with boolean flags and Ansible tags.

## Next Steps

After module 01, similar playbooks can be created for:

1. `02_network-config.yml` — nmcli interface setup, Bind/named configuration
2. `03_firmware-updates.yml` — Dell firmware updates (BIOS, iDRAC, CPLD, FPGA)
3. `04_warewulf-setup.yml` — Warewulf v4, Slurm, profiles, overlays
4. `05_ww4-image-management.yml` — Container image creation, modification, building
5. `06_hpc-shared-software.yml` — HPC compilers, EasyBuild, Spack, MPI libraries
6. `07_monitoring.yml` — Nagios, Ganglia (deprecated)
7. `08_troubleshooting.yml` — Diagnostic playbooks
8. `09_post-deployment-cleanup.yml` — Artifact cleanup
9. `10_fabric-software.yml` — DOCA, MLNX OFED, OmniPath installation and image injection
10. `11_security_nat.yml` — firewalld NAT, IP forwarding, Fail2Ban

