output "public_network_id" {
  value = libvirt_network.public.id
}

output "private_network_id" {
  value = libvirt_network.private.id
}

output "data_network_id" {
  value = libvirt_network.data.id
}
