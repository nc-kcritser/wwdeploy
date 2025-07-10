

# Grab a list of all macs for default/provisioning
wwctl node list --net | grep default

# Grab a list of all the idrac addresses 
wwctl node list --ipmi 

# wwctl grab a fullall
wwctl node list --fullall

# Grab a list of all active overlays (System/Runtime)
wwctl node list --long 

# Grab Configs (slurm,gres,warewulf,nodes.conf,chrony)
