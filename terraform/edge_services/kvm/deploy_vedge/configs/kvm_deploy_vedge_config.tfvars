# KVM Deploy vEdge Configuration - Production

# Quick start:
# ============================================================================
# Only image_source and token are required. With no bridges set, this module
# creates the libvirt networks itself, so a hypervisor with no networking
# prepared will still bring up a working edge:
#
#   image_source = "/var/lib/libvirt/images/gnos.qcow2"
#   token        = "<onboarding token>"
#   terraform apply -var-file="configs/kvm_deploy_vedge_config.tfvars"
#
# For a real deployment, point the interfaces at your own host bridges in the
# Networking section below.

# Pre-requisite:
# ============================================================================
# 1. A KVM hypervisor with libvirt, OVMF (UEFI) firmware and swtpm. GNOS boots
#    via UEFI and expects an emulated TPM 2.0, so all three are required:
#      Debian/Ubuntu : apt install qemu-kvm libvirt-daemon-system ovmf swtpm swtpm-tools
#      RHEL-family   : dnf install qemu-kvm libvirt edk2-ovmf swtpm swtpm-tools
#    RHEL-family firmware lives at /usr/share/edk2/ovmf/ - override the paths below.
# 2. Run Terraform on the hypervisor (qemu:///system), or set libvirt_uri to
#    qemu+ssh://<user>@<host>/system with the SSH user in the 'libvirt' group.
#    Note that image_source is read by whichever machine runs Terraform.
# 3. The GNOS qcow2 image. Contact Graphiant support for the image matching
#    your release.
# 4. An edge onboarding token from the Graphiant Portal for your Enterprise.
# 5. If attaching to host bridges, the WAN bridge needs outbound reachability to
#    the Graphiant backbone: DNS/53, HTTPS/443, IKE/500, IPsec NAT-T/4500,
#    TLS/16000, NTP/123.

mode        = "production"
libvirt_uri = "qemu:///system"
vm_name     = "graphiant-vedge"

# =============================================================================
# Required
# =============================================================================
# image_source: path or URL to the GNOS qcow2. Alternatively set base_volume_id
# to reuse a base volume imported by an earlier deployment.
image_source = ""
# base_volume_id = ""

# token: onboarding token for your Enterprise in the Graphiant Portal
token = ""

# =============================================================================
# Sizing
# =============================================================================
vcpus        = 4
memory_mb    = 8192
disk_size_gb = 20
storage_pool = "default"

# =============================================================================
# Networking
#
# NIC order presented to GNOS:
#   mgmt, wan1, local-mgmt, wan2..wanN, lan1..lanN
#
# Name a host bridge to attach an interface to your existing network, or leave
# it empty and this module creates a libvirt network for it. Check what bridges
# exist with: ip link show type bridge
# =============================================================================
# mgmt_bridge: local management interface (NIC 0)
mgmt_bridge = ""

# wan_bridges: ISP WAN bridges in order. Add a second entry for dual-WAN.
#   wan_bridges = ["br-wan"]
#   wan_bridges = ["br-wan", "br-wan2"]
wan_bridges = []

# lan_bridge: shared by all LAN interfaces. Empty creates one isolated network
# per LAN, so the vEdge is the only path off the LAN.
lan_bridge = ""

# lan_count: number of LAN interfaces
lan_count = 1

# CIDRs for the created NAT networks. Only used when the matching bridge is empty.
# mgmt_network_prefix = "10.30.0.0/24"
# wan_network_prefix  = "10.30.1.0/24"

# =============================================================================
# Advanced — defaults match the GNOS boot requirements. Override the firmware
# paths only if they differ on your hypervisor.
# =============================================================================
# graphnos_role            = "cpe"
# enable_local_mgmt        = true
# machine_type             = "q35"
# cpu_mode                 = "host-passthrough"
# uefi_loader_path         = "/usr/share/OVMF/OVMF_CODE.fd"
# uefi_nvram_template_path = "/usr/share/OVMF/OVMF_VARS.fd"

# Keep the VNC console on loopback and reach it over an SSH tunnel.
vnc_listen_address = "127.0.0.1"

# =============================================================================
# Test VM (optional) — verifies traffic flows through the vEdge.
#
# The vEdge LAN address is configured in the Graphiant Portal and is not known
# to Terraform, so set test_vm_gateway to it after the edge has onboarded.
# =============================================================================
# deploy_test_vm         = true
# test_vm_ip_cidr        = "192.168.100.10/24"
# test_vm_gateway        = "192.168.100.1"
# test_vm_password       = ""
# test_vm_ssh_public_key = ""
