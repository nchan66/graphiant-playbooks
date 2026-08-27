# KVM Deploy vEdge Configuration - Devtest mode (Internal Use Only)

# Pre-requisite:
# ============================================================================
# 1. A KVM hypervisor with libvirt, OVMF (UEFI) firmware and swtpm. GNOS boots
#    via UEFI and expects an emulated TPM 2.0, so all three are required:
#      Debian/Ubuntu : apt install qemu-kvm libvirt-daemon-system ovmf swtpm swtpm-tools
#      RHEL-family   : dnf install qemu-kvm libvirt edk2-ovmf swtpm swtpm-tools
#    RHEL-family firmware lives at /usr/share/edk2/ovmf/ - override the paths below.
# 2. Run Terraform on the hypervisor (qemu:///system), or set libvirt_uri to
#    qemu+ssh://<user>@<host>/system with the SSH user in the 'libvirt' group.
# 3. The devtest GNOS qcow2 image, as a hypervisor path or HTTP(S) URL.
# 4. The internal onboarding endpoints for the target environment.
# 5. An SSH keypair for the cloud-init user:
#      ssh-keygen -t ed25519 -f ~/.ssh/graphiant_vedge_devtest -N ''
#      cat ~/.ssh/graphiant_vedge_devtest.pub

mode        = "devtest"
libvirt_uri = "qemu:///system"
vm_name     = "graphiant-vedge-devtest"

# Reusing base_volume_id is much faster when redeploying edges from one image.
image_source = ""
# base_volume_id = ""

# token: Edge Authentication token for onboarding into a specific Enterprise
token = ""

# graphnos_role: device role announced in cloud-init. Edges onboard as "cpe".
# graphnos_role = "cpe"

# Domain sizing
vcpus        = 4
memory_mb    = 8192
disk_size_gb = 20
storage_pool = "default"

# Domain hardware — defaults match the GNOS boot requirements.
# machine_type             = "q35"
# cpu_mode                 = "host-passthrough"
# uefi_loader_path         = "/usr/share/OVMF/OVMF_CODE.fd"
# uefi_nvram_template_path = "/usr/share/OVMF/OVMF_VARS.fd"

# Expose VNC to the lab management network. Only appropriate on a trusted network.
vnc_listen_address = "0.0.0.0"

# Cloud-init user (devtest only)
ssh_public_key      = ""
cloud_init_username = "gnos"
cloud_init_password = ""

# Internal onboarding endpoints (devtest only)
onboarding_auth_url = ""
onboarding_gateway  = ""

# Networking — interface order presented to GNOS is cloud-init, mgmt, wan, lan.
# No host bridges are set, so the module creates a libvirt NAT network per role.
network_domain = "graphiant.local"

cloud_init_network_prefix = "10.20.0.0/24"
mgmt_network_prefix       = "10.20.1.0/24"
wan_network_prefix        = "10.20.2.0/24"
lan_network_prefix        = "10.20.3.0/24"

# Static addresses become DHCP reservations on the created networks, which only
# take effect if GNOS actually requests DHCP on that interface. WAN and LAN are
# managed by VPP and configured from the Graphiant Portal, so reservations there
# are likely inert - deploy_gnos_edge.sh passes addressing for the kernel
# management interface only. Left unset: read the addresses the hypervisor
# actually observes with `virsh domifaddr <vm_name>`.
#
# lan_static_ip is required when deploy_test_vm = true, since the test VM sets
# its default route to that address at cloud-init time.
# cloud_init_static_ip = "10.20.0.10"
# mgmt_static_ip       = "10.20.1.10"
# wan_static_ip        = "10.20.2.10"
# lan_static_ip        = "10.20.3.10"

# Test VM (optional) — on the LAN, default route via the vEdge
# deploy_test_vm         = true
# test_vm_static_ip      = "10.20.3.20"
# test_vm_password       = ""
# test_vm_ssh_public_key = ""
