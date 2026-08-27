# -----------------------------------------------------------------------------
# Core
# -----------------------------------------------------------------------------
variable "mode" {
  description = "Deployment mode: 'production' for customer-facing, 'devtest' for internal use with SSH access"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "devtest"], var.mode)
    error_message = "Mode must be either 'production' or 'devtest'."
  }
}

variable "libvirt_uri" {
  description = "libvirt connection URI. Use 'qemu:///system' when Terraform runs on the hypervisor, or 'qemu+ssh://<user>@<host>/system' for a remote KVM host (the SSH user must be able to reach the system libvirt socket)."
  type        = string
  default     = "qemu:///system"
}

variable "vm_name" {
  description = "libvirt domain name for the vEdge, also used to name its volumes and networks"
  type        = string
  default     = "graphiant-vedge"
}

variable "vcpus" {
  description = "Number of vCPUs assigned to the vEdge"
  type        = number
  default     = 4

  validation {
    condition     = var.vcpus >= 2
    error_message = "The Graphiant vEdge requires at least 2 vCPUs."
  }
}

variable "memory_mb" {
  description = "Memory assigned to the vEdge, in MiB"
  type        = number
  default     = 8192

  validation {
    condition     = var.memory_mb >= 4096
    error_message = "The Graphiant vEdge requires at least 4096 MiB of memory."
  }
}

variable "disk_size_gb" {
  description = "Size of the vEdge qcow2 overlay disk, in GiB. Must be at least as large as the GNOS base image."
  type        = number
  default     = 20
}

variable "storage_pool" {
  description = "libvirt storage pool used for the base image, overlay disk and cloud-init ISO"
  type        = string
  default     = "default"
}

variable "graphnos_role" {
  description = "GNOS device role announced in cloud-init. Edges onboard as 'cpe', which is what deploy_gnos_edge.sh sets on Graphiant hypervisors; 'gateway' and 'core' are the other roles used by that tooling."
  type        = string
  default     = "cpe"
}

variable "token" {
  description = "Graphiant vEdge onboarding authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Image — set exactly one of these
# -----------------------------------------------------------------------------
variable "image_source" {
  description = "Path or URL to the GNOS qcow2 image, imported as a base volume. Ignored when base_volume_id is set."
  type        = string
  default     = ""
}

variable "base_volume_id" {
  description = "ID of an already-imported GNOS base volume to back the vEdge disk. Set this to share one base image across several vEdge deployments instead of re-importing the qcow2."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Domain hardware — defaults match the GNOS boot requirements
# -----------------------------------------------------------------------------
variable "machine_type" {
  description = "QEMU machine type. GNOS is validated on q35."
  type        = string
  default     = "q35"
}

variable "cpu_mode" {
  description = "libvirt CPU mode. host-passthrough is required for the vEdge dataplane to use host CPU features."
  type        = string
  default     = "host-passthrough"
}

variable "uefi_loader_path" {
  description = "Path on the hypervisor to the OVMF UEFI firmware code. GNOS boots via UEFI, not SeaBIOS. Debian/Ubuntu use /usr/share/OVMF/OVMF_CODE.fd; RHEL-family hosts typically use /usr/share/edk2/ovmf/OVMF_CODE.fd."
  type        = string
  default     = "/usr/share/OVMF/OVMF_CODE.fd"
}

variable "uefi_nvram_template_path" {
  description = "Path on the hypervisor to the OVMF NVRAM variables template used to seed each domain's NVRAM store"
  type        = string
  default     = "/usr/share/OVMF/OVMF_VARS.fd"
}

variable "vnc_listen_address" {
  description = "Address the domain's VNC console listens on. Defaults to loopback; set to 0.0.0.0 only on a trusted management network."
  type        = string
  default     = "127.0.0.1"
}

# -----------------------------------------------------------------------------
# Devtest-specific
# -----------------------------------------------------------------------------
variable "ssh_public_key" {
  description = "SSH public key for the cloud-init user (devtest only)"
  type        = string
  default     = ""
}

variable "cloud_init_username" {
  description = "Username for the cloud-init user created in devtest mode"
  type        = string
  default     = "gnos"
}

variable "cloud_init_password" {
  description = "Password for the cloud-init user created in devtest mode"
  type        = string
  sensitive   = true
  default     = ""
}

variable "onboarding_auth_url" {
  description = "Internal Graphiant OAuth authentication endpoint (devtest only)"
  type        = string
  default     = ""
}

variable "onboarding_gateway" {
  description = "Internal Graphiant onboarding service hostname and port (devtest only)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Networking
#
# Per interface role, either set <role>_bridge to attach to an existing host
# bridge (typical in production), or leave it empty and the module creates a
# libvirt NAT network from <role>_network_prefix (typical in devtest).
#
# <role>_static_ip becomes a DHCP reservation on a created network, so it only
# takes effect if GNOS requests DHCP on that interface - WAN and LAN are managed
# by VPP and configured from the Graphiant Portal, so reservations there may be
# inert. It is ignored entirely for bridge-attached interfaces, where the
# external network does the addressing.
# -----------------------------------------------------------------------------
variable "network_domain" {
  description = "DNS domain assigned to libvirt networks created by this module"
  type        = string
  default     = "graphiant.local"
}

variable "cloud_init_bridge" {
  description = "Existing host bridge for the cloud-init interface (devtest only)"
  type        = string
  default     = ""
}

variable "cloud_init_network_prefix" {
  description = "CIDR for a new cloud-init libvirt network (devtest only)"
  type        = string
  default     = "10.20.0.0/24"
}

variable "cloud_init_static_ip" {
  description = "DHCP reservation for the cloud-init interface (devtest only)"
  type        = string
  default     = ""
}

variable "mgmt_bridge" {
  description = "Existing host bridge for the local management interface"
  type        = string
  default     = ""
}

variable "mgmt_network_prefix" {
  description = "CIDR for a new management libvirt network"
  type        = string
  default     = "10.20.1.0/24"
}

variable "mgmt_static_ip" {
  description = "DHCP reservation for the management interface. Closest analog to the edge_mgmt_ipaddr argument of deploy_gnos_edge.sh."
  type        = string
  default     = ""
}

variable "wan_bridge" {
  description = "Existing host bridge for the WAN interface. In production this is normally the bridge with outbound reachability to the Graphiant backbone."
  type        = string
  default     = ""
}

variable "wan_network_prefix" {
  description = "CIDR for a new WAN libvirt network"
  type        = string
  default     = "10.20.2.0/24"
}

variable "wan_static_ip" {
  description = "DHCP reservation for the WAN interface. GNOS manages WAN under VPP, so this may have no effect."
  type        = string
  default     = ""
}

variable "lan_bridge" {
  description = "Existing host bridge for the LAN (customer ingress) interface"
  type        = string
  default     = ""
}

variable "lan_network_prefix" {
  description = "CIDR for a new LAN libvirt network"
  type        = string
  default     = "10.20.3.0/24"
}

variable "lan_static_ip" {
  description = "DHCP reservation for the LAN interface. GNOS manages LAN under VPP, so this may have no effect - verify with `virsh domifaddr` rather than assuming it applied. Required when deploy_test_vm = true, since the test VM uses it as its default gateway."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Test VM (optional)
# -----------------------------------------------------------------------------
variable "deploy_test_vm" {
  description = "Whether to deploy a test VM on the LAN with its default route via the vEdge"
  type        = bool
  default     = false
}

variable "test_vm_name" {
  description = "libvirt domain name for the test VM"
  type        = string
  default     = "graphiant-vedge-test-vm"
}

variable "test_vm_vcpus" {
  description = "Number of vCPUs for the test VM"
  type        = number
  default     = 1
}

variable "test_vm_memory_mb" {
  description = "Memory for the test VM, in MiB"
  type        = number
  default     = 1024
}

variable "test_vm_disk_size_gb" {
  description = "Size of the test VM overlay disk, in GiB"
  type        = number
  default     = 10
}

variable "test_vm_image_source" {
  description = "Path or URL to a cloud-init enabled qcow2 for the test VM"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "test_vm_static_ip" {
  description = "DHCP reservation for the test VM on the LAN network"
  type        = string
  default     = ""
}

variable "test_vm_username" {
  description = "Username created on the test VM"
  type        = string
  default     = "graphiant"
}

variable "test_vm_password" {
  description = "Password for the test VM user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "test_vm_ssh_public_key" {
  description = "SSH public key authorised for the test VM user"
  type        = string
  default     = ""
}
