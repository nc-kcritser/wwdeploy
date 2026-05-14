# Bash to Ansible Migration - Phase 1 Complete

## Summary

Module 01 (Master Node Configuration) has been successfully converted from bash to Ansible. The conversion maintains feature parity while providing idempotence, better error handling, and tag-based execution control.

## What Was Created

```
ansible/
├── README.md                          # Usage guide and reference
├── requirements.yml                   # Ansible collection dependencies
├── inventory.ini                      # Host inventory (master group)
├── group_vars/
│   └── all.yml                        # Configuration variables (replaces site-config.sh)
└── 01_master-node-config.yml          # Main playbook (replaces modules/01_master-node-config.sh)
```

## Key Features

✓ **Idempotent** — Safe to run repeatedly  
✓ **Non-interactive** — Variables replace bash prompts  
✓ **Tag-driven** — Run any section independently (`--tags prereqs`, `--tags dns,ntp`, etc.)  
✓ **Configurable** — Override any setting via `-e` or inventory  
✓ **Documented** — Full README with examples  
✓ **Side-by-side** — Original bash scripts remain untouched  

## Playbook Tags

| Tag | Function | When to Use |
|---|---|---|
| `prereqs` | Install EPEL, packages, development tools, CRB | Setup fresh master node |
| `local_repo` | Mount ISO, rsync, create local yum repo | Offline installation |
| `idrac` | Download and install Dell iDRAC Tools | Dell server management |
| `security` | Configure SELinux and firewalld | Security hardening |
| `hostname` | Set system hostname | Network setup |
| `dns` | Configure /etc/resolv.conf | DNS configuration |
| `ntp` | Set timezone and Chrony NTP server | Time sync setup |
| `users` | Create dell group, hpl and gpu users | User management |

## Quick Start

```bash
# Install dependencies
ansible-galaxy collection install -r ansible/requirements.yml

# Dry-run (check mode)
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --check

# Run full playbook
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml

# Run only prerequisites
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml --tags prereqs

# Enable local repo setup and run it
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  --tags local_repo -e configure_local_repo=true
```

## Configuration

All defaults are in `ansible/group_vars/all.yml`. Override any with:

```bash
# Custom timezone
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  -e timezone=America/Chicago

# Custom NTP server
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  -e ntp_server=ntp.example.com

# Enable firewall
ansible-playbook -i ansible/inventory.ini ansible/01_master-node-config.yml \
  -e firewall_enabled=true
```

## Roadmap

Next modules to convert (in priority order):

1. **Module 11** (`11_security_nat.sh`) — firewalld, NAT, Fail2Ban (cleanest conversion)
2. **Module 02** (`02_network-config.sh`) — nmcli interface config
3. **Module 04** (`04_warewulf-setup.sh`) — Warewulf + Slurm (most complex)
4. **Module 05** (`05_ww4-image-management.sh`) — Container image mgmt
5. **Module 10** (`10_fabric-software-install.sh`) — OFED, DOCA, OmniPath

Modules 07 and 08 are marked as unmaintained in the original bash code.

## Testing Recommendations

- [ ] Dry-run entire playbook with `--check`
- [ ] Run `prereqs` tag on fresh system
- [ ] Test DNS tag with custom nameservers
- [ ] Test NTP tag with custom server and timezone
- [ ] Test user creation with `users` tag
- [ ] Test security tag with SELinux state changes
- [ ] Test idempotence by running full playbook twice

## Branch

All changes committed to: `claude/bash-to-ansible-UVzYx`

Commits:
- Add Ansible configuration for module 01
- Add main Ansible playbook for module 01  
- Add README.md for ansible directory

