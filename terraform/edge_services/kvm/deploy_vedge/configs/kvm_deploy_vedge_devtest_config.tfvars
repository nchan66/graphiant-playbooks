# KVM Deploy vEdge Configuration - Devtest mode (Internal Use Only)

# This is the Graphiant lab profile: it wires the edge onto the lab's existing
# host bridges and reproduces the interface layout deploy_gnos_edge.sh builds.
# Customers should use kvm_deploy_vedge_config.tfvars instead.

# Pre-requisite:
# ============================================================================
# 1. A KVM hypervisor with libvirt, OVMF (UEFI) firmware and swtpm:
#      apt install qemu-kvm libvirt-daemon-system ovmf swtpm swtpm-tools xsltproc
# 2. Run Terraform on the hypervisor (qemu:///system), or set libvirt_uri to
#    qemu+ssh://<user>@<host>/system with the SSH user in the 'libvirt' group.
#    Note that image_source is read by whichever machine runs Terraform.
# 3. The devtest GNOS qcow2, e.g. fetched with:
#      cd ~/systest-network
#      ./automated_gnos_image_download.sh <release> devtest-persist "$GITLAB_API_KEY"
# 4. The lab host bridges below must exist (`ip link show type bridge`).
# 5. An SSH keypair for the cloud-init user:
#      ssh-keygen -t ed25519 -f ~/.ssh/graphiant_vedge_devtest -N ''

mode        = "devtest"
libvirt_uri = "qemu:///system"
vm_name     = "graphiant-vedge-devtest"

# Reusing base_volume_id is much faster when redeploying edges from one image.
image_source = ""
# base_volume_id = ""

# token: Edge Authentication token for onboarding into a specific Enterprise
token = ""

# Domain sizing
vcpus        = 4
memory_mb    = 8192
disk_size_gb = 20
storage_pool = "default"

# Expose VNC to the lab management network. Only appropriate on a trusted network.
vnc_listen_address = "0.0.0.0"

# =============================================================================
# Cloud-init User Configuration (devtest only)
# =============================================================================
ssh_public_key      = ""
cloud_init_username = "gnos"
cloud_init_password = ""

# =============================================================================
# Edge Onboarding Configuration Parameters (For Internal Use Only)
# =============================================================================
# Endpoints per environment are listed in deploy_gnos_edge.sh (ONBOARDING_GW /
# ONBOARDING_AUTH_URL). For tisiphone:
#   onboarding_auth_url = "https://api.tisiphone.graphiant.io/v1/devices/oauth"
#   onboarding_gateway  = "onboarding-gateway.tisiphone.graphiant.io:16000"
onboarding_auth_url = ""
onboarding_gateway  = ""

# =============================================================================
# Networking — lab profile.
#
# NIC order presented to GNOS:
#   mgmt, wan1, local-mgmt, wan2..wanN, lan1..lanN
#
# These are the lab's existing host bridges, so nothing here is created except
# the per-device local-mgmt network.
#
# Note the off-by-one against deploy_gnos_edge.sh: two entries in wan_bridges
# means two real ISP WANs, which is wan_ints = 3 there, because that script
# counts the local-mgmt interface as part of its WAN list.
# =============================================================================
# Measured against a working edge on the sj-dr hypervisors:
#   sudo virsh domiflist <an-existing-edge>
# NIC 0 is br3000 there, not the br0 default in deploy_gnos_edge.sh.
mgmt_bridge       = "br3000"
wan_bridges       = ["br3001", "br3002"]
enable_local_mgmt = true
lan_count         = 3
lan_bridge        = "br_trunk"

# Set lan_bridge = "" for private per-device LAN networks (privatelan=1
# equivalent). LLDP then needs the group_fwd_mask applied by hand:
#   echo 0x4000 | sudo tee /sys/class/net/<bridge>/bridge/group_fwd_mask
