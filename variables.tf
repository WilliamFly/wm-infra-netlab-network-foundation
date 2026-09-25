variable "base_image_path" {
  description = "Path to the Ubuntu 24.04 cloud image (qcow2) on the host"
  type        = string
}

variable "storage_pool" {
  description = "libvirt storage pool to create VM disks in"
  type        = string
  default     = "default"
}

variable "ssh_public_key" {
  description = "SSH public key installed on the router VM's admin user"
  type        = string
}

variable "router_vcpu" {
  description = "vCPUs for the router VM"
  type        = number
  default     = 1
}

variable "router_memory_mb" {
  description = "Memory (MB) for the router VM"
  type        = number
  default     = 1024
}

variable "create_private_test_vm" {
  description = "Whether to create the throwaway test VM on private-net (proves NAT/forwarding, then gets destroyed)"
  type        = bool
  default     = false
}
