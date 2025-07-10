#!/usr/bin/bash

#### Cluster General Information 
cluster_name=prime                              # Name of the cluster
sms_name=prime1                                 # Hostname for SMS server 
external_domain=hpc-lab.org                     # External network domain name
search_domains=hpc-lab.org                      # DNS search domains

# NTP server for time synchronization
ntp_server=time.google.com

# DNS Server 1
dns_server_1=8.8.8.8
dns_server_2=1.1.1.1
dns_server_3=

##### INTERNAL / PROVISIONING NETWORKING SETUP ####### 
sms_ip=172.16.0.1                                # Internal IP address on SMS server
sms_eth_internal=ens20                           # Internal Ethernet interface on SMS
internal_base_net=172.16.0.0                     # Internal network information
internal_netmask=255.255.252.0                   # Subnet netmask for internal network
internal_cidr=22                                 # CIDR for internal network

#### External Network Information
sms_eth_external=ens18            # External Ethernet interface on SMS
sms_external_ip=10.67.0.211       # External network information
external_netmask=255.255.255.0      # Subnet netmask for external network
external_cidr=24                    # CIDR for external network
external_gateway=10.67.0.1        # Gateway for external network

# Realm for LDAP Authentication
realm=DELL.COM

# Local network domain name
# Do NOT change this unless you want to deviate from "Bright style" DNS inside the cluster
domain_name=cluster

###### InfiniBand or OmniPath network information
sms_mlnx=ib0                        # Mellanox interface on SMS
sms_ipoib=172.16.8.1                # Head Node IP for Infiniband/Omnipath Network
ipoib_base_net=172.16.8.0
ipoib_netmask=255.255.252.0
ipoib_cidr=22
ipoib_gateway=172.16.8.1

#DHCP Information 
#Dynamic range for internal / provisioning network
dynamic_range=200-200
dynamic_range_start=172.16.2.100
dynamic_range_end=172.16.2.200

# Generic Image Password
image_pw=Dellsvcs1

# iDRAC Config
bmc_username=root                           # BMC username for use by IPMI
bmc_password=calvin                         # BMC password for use by IPMI

# Shared / Dedicated
# shared=0 , dedicated=1
bmc_method=0

# VLAN tag (If being used. If not, leave BLANK!)
bmc_vlan_tag=

# iDRAC network information
sms_bmc_user=root
sms_bmc_passwd=calvin
sms_bmc_ip_address=172.16.4.10
sms_bmc_netmask=255.255.252.0
sms_bmc_gateway=172.16.4.1

##### Alias Network Information 
sms_bmc_mgmt=172.16.4.1
bmc_base_net=172.16.4.0
bmc_netmask=255.255.252.0
bmc_cidr=22

# Nagios web access password
nagios_web_password=Dellsvcs1

# Optional:
# BeeGFS System Management host name
sysmgmtd_host=

# Lustre MGS mount name
mgs_fs_name=
