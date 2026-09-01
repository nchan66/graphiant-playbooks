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

  # Every interface either attaches to a host bridge you name, or - when you
  # leave that setting empty - to a libvirt network this module creates. That is
  # the difference between Option B (existing bridges) and Option A (nothing
  # pre-configured on the host) in the README.
  create_mgmt_net = var.mgmt_bridge == ""
  create_wan_net  = length(var.wan_bridges) == 0
  create_lan_nets = var.lan_bridge == ""

  # NIC order is a contract with GNOS, which assigns interface roles positionally:
  #
  #   mgmt, wan1, local-mgmt, wan2..wanN, lan1..lanN
  #
  # The first ISP WAN is the VPP interface oss-agent uses to onboard, and GNOS
  # serves its local web server on the local-mgmt interface.
  nics = concat(
    [{
      label      = "mgmt"
      bridge     = local.create_mgmt_net ? null : var.mgmt_bridge
      network_id = local.create_mgmt_net ? libvirt_network.mgmt[0].id : null
    }],
    [{
      label      = "wan1"
      bridge     = local.create_wan_net ? null : var.wan_bridges[0]
      network_id = local.create_wan_net ? libvirt_network.wan[0].id : null
    }],
    var.enable_local_mgmt ? [{
      label      = "local-mgmt"
      bridge     = null
      network_id = libvirt_network.local_mgmt[0].id
    }] : [],
    local.create_wan_net ? [] : [
      for i, b in slice(var.wan_bridges, 1, length(var.wan_bridges)) : {
        label      = "wan${i + 2}"
        bridge     = b
        network_id = null
      }
    ],
    [for i in range(var.lan_count) : {
      label      = "lan${i + 1}"
      bridge     = local.create_lan_nets ? null : var.lan_bridge
      network_id = local.create_lan_nets ? libvirt_network.lan[i].id : null
    }]
  )

  lan_network_id = local.create_lan_nets ? try(libvirt_network.lan[0].id, null) : null

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
  # q35; do the same here.
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
# Networks
#
# Created only for interfaces where no host bridge was given. The mgmt and WAN
# networks are NAT so the vEdge can reach the Graphiant backbone with no host
# networking prepared; LAN networks are isolated, so the vEdge is the only path
# off the LAN.
#
# Note: for isolated LAN networks the Graphiant hypervisor tooling also writes
# 0x4000 to the bridge's group_fwd_mask so LLDP passes. That is a sysfs write the
# libvirt provider cannot perform - apply it manually if LLDP is needed:
#   echo 0x4000 | sudo tee /sys/class/net/<bridge>/bridge/group_fwd_mask
# -----------------------------------------------------------------------------
resource "libvirt_network" "mgmt" {
  count = local.create_mgmt_net ? 1 : 0

  name      = "${var.vm_name}-mgmt"
  mode      = "nat"
  addresses = [var.mgmt_network_prefix]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

resource "libvirt_network" "wan" {
  count = local.create_wan_net ? 1 : 0

  name      = "${var.vm_name}-wan"
  mode      = "nat"
  addresses = [var.wan_network_prefix]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

resource "libvirt_network" "local_mgmt" {
  count = var.enable_local_mgmt ? 1 : 0

  name      = "${var.vm_name}_lan_local-mgmt"
  mode      = "none"
  autostart = true
}

resource "libvirt_network" "lan" {
  count = local.create_lan_nets ? var.lan_count : 0

  name      = "${var.vm_name}_lan_${count.index + 1}"
  mode      = "none"
  autostart = true
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

# Delivered as a CD-ROM, matching virt-install --cdrom on Graphiant hypervisors.
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
# Test VM (optional) — a Debian cloud image on the LAN, statically addressed with
# its default route via the vEdge, for verifying traffic actually flows through
# the edge. Mirrors deploy_test_vm in the AWS/Azure modules.
#
# Unlike the cloud modules, the vEdge LAN address is not known to Terraform: GNOS
# manages the LAN under VPP and it is configured from the Graphiant Portal. So
# test_vm_gateway must be supplied, which makes this a post-onboarding step.
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
  size           = 10 * 1024 * 1024 * 1024
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
  USERDATA

  # Static addressing: the LAN has no DHCP server, and the default route must
  # point at the vEdge rather than anything libvirt provides.
  network_config = <<-NETCFG
    version: 2
    ethernets:
      primary:
        match:
          name: "en*"
        addresses: [${var.test_vm_ip_cidr}]
        routes:
          - to: 0.0.0.0/0
            via: ${var.test_vm_gateway}
  NETCFG

  lifecycle {
    precondition {
      condition     = var.test_vm_ip_cidr != "" && var.test_vm_gateway != ""
      error_message = "deploy_test_vm = true requires test_vm_ip_cidr and test_vm_gateway (the vEdge LAN address configured in Graphiant Portal)."
    }
  }
}

resource "libvirt_domain" "test_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name      = var.test_vm_name
  memory    = 1024
  vcpu      = 1
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
    bridge     = local.create_lan_nets ? null : var.lan_bridge
    network_id = local.lan_network_id
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
