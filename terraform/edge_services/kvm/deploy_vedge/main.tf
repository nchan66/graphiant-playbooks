terraform {
  required_version = ">= 1.3.0"

  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      # Pinned to 0.8.x. This provider is pre-1.0, so minor bumps are breaking:
      # 0.9.x replaces the resource schema used here with an XML-shaped one.
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  is_devtest = var.mode == "devtest"

  # GNOS assigns interface roles positionally, so NIC order is a contract. It
  # matches the AWS/Azure vEdge modules:
  #   production : mgmt=0, wan=1, lan=2
  #   devtest    : cloud-init=0, mgmt=1, wan=2, lan=3
  roles = local.is_devtest ? ["cloud_init", "mgmt", "wan", "lan"] : ["mgmt", "wan", "lan"]

  # Each role either attaches to an existing host bridge, or gets a libvirt NAT
  # network created from its prefix. Static IPs only apply to created networks,
  # since a host bridge is addressed by the external network.
  networking = {
    cloud_init = { bridge = var.cloud_init_bridge, prefix = var.cloud_init_network_prefix, ip = var.cloud_init_static_ip }
    mgmt       = { bridge = var.mgmt_bridge, prefix = var.mgmt_network_prefix, ip = var.mgmt_static_ip }
    wan        = { bridge = var.wan_bridge, prefix = var.wan_network_prefix, ip = var.wan_static_ip }
    lan        = { bridge = var.lan_bridge, prefix = var.lan_network_prefix, ip = var.lan_static_ip }
  }

  managed_networks = { for r in local.roles : r => local.networking[r] if local.networking[r].bridge == "" }

  # Ordered NICs for the domain. A null attribute is unset, so each NIC resolves
  # to either a bridge or a created network.
  nics = [for r in local.roles : {
    bridge     = local.networking[r].bridge != "" ? local.networking[r].bridge : null
    network_id = local.networking[r].bridge == "" ? libvirt_network.this[r].id : null
    addresses  = local.networking[r].bridge == "" && local.networking[r].ip != "" ? [local.networking[r].ip] : null
  }]

  # Cloud-init user data. Matches the graphnos block that deploy_gnos_edge.sh
  # writes on Graphiant hypervisors: role first, then the onboarding endpoints
  # (devtest only), then the token.
  user_data_production = <<-USERDATA
    #cloud-config

    graphnos:
      role: ${var.graphnos_role}
      token: "${var.token}"
  USERDATA

  user_data_devtest = <<-USERDATA
    #cloud-config

    graphnos:
      role: ${var.graphnos_role}
      onboarding-auth-url: ${var.onboarding_auth_url}
      onboarding-gw: ${var.onboarding_gateway}
      token: "${var.token}"

    users:
      - name: ${var.cloud_init_username}
        plain_text_passwd: '${var.cloud_init_password}'
        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
        lock_passwd: false
        groups: sudo
        shell: /bin/bash
        ssh-authorized-keys:
          - ${var.ssh_public_key}
  USERDATA

  user_data = local.is_devtest ? local.user_data_devtest : local.user_data_production

  base_volume_id = var.base_volume_id != "" ? var.base_volume_id : try(libvirt_volume.gnos_base[0].id, "")

  # The provider attaches the cloud-init ISO as an IDE CD-ROM, but q35 has no IDE
  # controller, so libvirt rejects the domain with "IDE controllers are unsupported
  # for this QEMU binary or machine type". virt-install puts the CD-ROM on SATA for
  # q35 (deploy_gnos_edge.sh uses --machine q35 with --cdrom); do the same here.
  cdrom_sata_xslt = <<-XSLT
    <?xml version="1.0" ?>
    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:output omit-xml-declaration="yes" indent="yes"/>
      <xsl:template match="node()|@*">
        <xsl:copy><xsl:apply-templates select="node()|@*"/></xsl:copy>
      </xsl:template>
      <xsl:template match="/domain/devices/disk[@device='cdrom']/target">
        <target dev="sda" bus="sata"/>
      </xsl:template>
    </xsl:stylesheet>
  XSLT
}

# -----------------------------------------------------------------------------
# Networks — one per role that has no host bridge
# -----------------------------------------------------------------------------
resource "libvirt_network" "this" {
  for_each = local.managed_networks

  name      = "${var.vm_name}-${replace(each.key, "_", "-")}"
  mode      = "nat"
  domain    = var.network_domain
  addresses = [each.value.prefix]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

# -----------------------------------------------------------------------------
# Volumes — the GNOS qcow2 is imported once, then backed by a thin overlay per
# vEdge, the same layout the Graphiant hypervisor tooling uses with virt-install
# -----------------------------------------------------------------------------
resource "libvirt_volume" "gnos_base" {
  count = var.base_volume_id == "" ? 1 : 0

  name   = "${var.vm_name}-gnos-base.qcow2"
  pool   = var.storage_pool
  source = var.image_source
  format = "qcow2"

  lifecycle {
    precondition {
      condition     = var.image_source != ""
      error_message = "Set image_source to the GNOS qcow2 (hypervisor path or HTTP(S) URL), or base_volume_id to reuse an imported base volume."
    }
  }
}

resource "libvirt_volume" "vedge" {
  name           = "${var.vm_name}.qcow2"
  pool           = var.storage_pool
  format         = "qcow2"
  base_volume_id = local.base_volume_id
  size           = var.disk_size_gb * 1024 * 1024 * 1024
}

# Delivered as a CD-ROM, matching virt-install --cdrom cloud.qcow2 on Graphiant
# hypervisors.
resource "libvirt_cloudinit_disk" "vedge" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = var.storage_pool
  user_data = local.user_data
}

# -----------------------------------------------------------------------------
# vEdge domain
#
# GNOS boot requirements, mirrored from the Graphiant hypervisor virt-install:
# UEFI/OVMF firmware, emulated TPM 2.0, q35, host CPU passthrough.
# -----------------------------------------------------------------------------
resource "libvirt_domain" "vedge" {
  name      = var.vm_name
  memory    = var.memory_mb
  vcpu      = var.vcpus
  machine   = var.machine_type
  autostart = true

  firmware = var.uefi_loader_path

  nvram {
    template = var.uefi_nvram_template_path
    file     = "/var/lib/libvirt/qemu/nvram/${var.vm_name}_VARS.fd"
  }

  cpu {
    mode = var.cpu_mode
  }

  tpm {
    backend_type    = "emulator"
    backend_version = "2.0"
    model           = "tpm-crb"
  }

  disk {
    volume_id = libvirt_volume.vedge.id
  }

  cloudinit = libvirt_cloudinit_disk.vedge.id

  dynamic "network_interface" {
    for_each = local.nics
    content {
      bridge     = network_interface.value.bridge
      network_id = network_interface.value.network_id
      addresses  = network_interface.value.addresses
    }
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = var.vnc_listen_address
    autoport       = true
  }

  xml {
    xslt = local.cdrom_sata_xslt
  }

  lifecycle {
    precondition {
      condition     = !local.is_devtest || var.onboarding_gateway != ""
      error_message = "devtest mode requires onboarding_gateway to be set."
    }
  }
}

# -----------------------------------------------------------------------------
# Test VM (optional) — Debian cloud image on the LAN, default route via the
# vEdge. Mirrors deploy_test_vm in the AWS/Azure modules.
# -----------------------------------------------------------------------------
resource "libvirt_volume" "test_vm_base" {
  count = var.deploy_test_vm ? 1 : 0

  name   = "${var.test_vm_name}-base.qcow2"
  pool   = var.storage_pool
  source = var.test_vm_image_source
  format = "qcow2"
}

resource "libvirt_volume" "test_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name           = "${var.test_vm_name}.qcow2"
  pool           = var.storage_pool
  format         = "qcow2"
  base_volume_id = libvirt_volume.test_vm_base[0].id
  size           = var.test_vm_disk_size_gb * 1024 * 1024 * 1024
}

resource "libvirt_cloudinit_disk" "test_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name = "${var.test_vm_name}-cloudinit.iso"
  pool = var.storage_pool

  user_data = <<-USERDATA
    #cloud-config

    users:
      - name: ${var.test_vm_username}
        plain_text_passwd: '${var.test_vm_password}'
        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
        lock_passwd: false
        groups: sudo
        shell: /bin/bash
        ssh-authorized-keys:
          - ${var.test_vm_ssh_public_key}

    runcmd:
      - ip route del default || true
      - ip route add default via ${var.lan_static_ip}
  USERDATA

  lifecycle {
    precondition {
      condition     = var.lan_static_ip != ""
      error_message = "deploy_test_vm = true requires lan_static_ip, which the test VM uses as its default gateway."
    }
  }
}

resource "libvirt_domain" "test_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name      = var.test_vm_name
  memory    = var.test_vm_memory_mb
  vcpu      = var.test_vm_vcpus
  machine   = var.machine_type
  autostart = true

  cpu {
    mode = var.cpu_mode
  }

  disk {
    volume_id = libvirt_volume.test_vm[0].id
  }

  cloudinit = libvirt_cloudinit_disk.test_vm[0].id

  network_interface {
    bridge     = var.lan_bridge != "" ? var.lan_bridge : null
    network_id = var.lan_bridge == "" ? libvirt_network.this["lan"].id : null
    addresses  = var.lan_bridge == "" && var.test_vm_static_ip != "" ? [var.test_vm_static_ip] : null
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  xml {
    xslt = local.cdrom_sata_xslt
  }
}
