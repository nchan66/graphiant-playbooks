# KVM Deploy vEdge Configuration - Production

# Pre-requisite:
# ============================================================================
# 1. A KVM hypervisor with libvirt, OVMF (UEFI) firmware and swtpm. GNOS boots
#    via UEFI and expects an emulated TPM 2.0, so all three are required:
#      Debian/Ubuntu : apt install qemu-kvm libvirt-daemon-system ovmf swtpm swtpm-tools
#      RHEL-family   : dnf install qemu-kvm libvirt edk2-ovmf swtpm swtpm-tools
#    RHEL-family firmware lives at /usr/share/edk2/ovmf/ - override the paths below.
# 2. Run Terraform on the hypervisor (qemu:///system), or set libvirt_uri to
#    qemu+ssh://<user>@<host>/system with the SSH user in the 'libvirt' group.
# 3. The GNOS qcow2 image, as a hypervisor path or HTTP(S) URL. Contact
#    Graphiant support for the image matching your release.
# 4. Host bridges for mgmt, WAN and LAN (`ip link show type bridge`). The WAN
#    bridge needs outbound reachability to the Graphiant backbone: DNS/53,
#    HTTPS/443, IKE/500, IPsec NAT-T/4500, TLS/16000, NTP/123.
# 5. An edge onboarding token from the Graphiant Portal for the target Enterprise.

mode        = "production"
libvirt_uri = "qemu:///system"
vm_name     = "graphiant-vedge"

# Set image_source to import the GNOS qcow2, or base_volume_id to reuse a base
# volume from an earlier deployment.
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

# Domain hardware — defaults match the GNOS boot requirements. Override the
# firmware paths only if they differ on your hypervisor.
# machine_type             = "q35"
# cpu_mode                 = "host-passthrough"
# uefi_loader_path         = "/usr/share/OVMF/OVMF_CODE.fd"
# uefi_nvram_template_path = "/usr/share/OVMF/OVMF_VARS.fd"

# Keep the VNC console on loopback in production and reach it over an SSH tunnel.
vnc_listen_address = "127.0.0.1"

# Networking — interface order presented to GNOS is mgmt, wan, lan.
# Set <role>_bridge to attach to an existing host bridge, or leave it empty to
# have the module create a libvirt NAT network from <role>_network_prefix.
mgmt_bridge = "br-mgmt"
wan_bridge  = "br-wan"
lan_bridge  = "br-lan"
