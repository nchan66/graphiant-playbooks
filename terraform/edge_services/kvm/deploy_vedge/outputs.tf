output "mode" {
  description = "Deployment mode (production or devtest)"
  value       = var.mode
}

output "domain_id" {
  description = "libvirt domain ID (UUID) of the vEdge"
  value       = libvirt_domain.vedge.id
}

output "domain_name" {
  description = "libvirt domain name of the vEdge"
  value       = var.vm_name
}

output "interface_order" {
  description = "Ordered interface roles as attached to the domain. GNOS assigns roles positionally, so this is what the appliance sees."
  value       = local.roles
}

output "base_volume_id" {
  description = "ID of the GNOS base volume backing the vEdge disk. Pass this as base_volume_id in further deployments to reuse the imported image."
  value       = local.base_volume_id
}

output "networks_created" {
  description = "Map of interface role to the libvirt network this module created for it. Bridge-attached roles are absent."
  value       = { for r, n in libvirt_network.this : r => { name = n.name, addresses = n.addresses } }
}

output "mgmt_ip" {
  description = "The mgmt_static_ip requested as a DHCP reservation, or null when unset. This is what was asked for, not what the interface actually holds - confirm with `virsh domifaddr <domain_name>`."
  value       = var.mgmt_static_ip != "" ? var.mgmt_static_ip : null
}

output "wan_ip" {
  description = "The wan_static_ip requested as a DHCP reservation, or null when unset. This is what was asked for, not what the interface actually holds - confirm with `virsh domifaddr <domain_name>`."
  value       = var.wan_static_ip != "" ? var.wan_static_ip : null
}

output "lan_ip" {
  description = "The lan_static_ip requested as a DHCP reservation, or null when unset. GNOS manages the LAN under VPP, so confirm the address the hypervisor observes with `virsh domifaddr <domain_name>` before using it as the vEdge LAN address in Graphiant Portal."
  value       = var.lan_static_ip != "" ? var.lan_static_ip : null
}

output "serial_console_command" {
  description = "Command to attach to the vEdge serial console on the hypervisor"
  value       = "virsh --connect ${var.libvirt_uri} console ${var.vm_name}"
}

output "test_vm_ip" {
  description = "Test VM address on the LAN network (only when deploy_test_vm = true and test_vm_static_ip is set)"
  value       = var.deploy_test_vm && var.test_vm_static_ip != "" ? var.test_vm_static_ip : null
}
