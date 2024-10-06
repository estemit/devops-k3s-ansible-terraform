################################################################################
# ENV VARS
################################################################################

# https://www.terraform.io/docs/commands/environment-variables.html

variable "VM_COUNT" {
  default = 3
  type = number
  description = "The Number of VM instances that will be created"
}

variable "VM_USER" {
  default = "ubuntu"
  type = string
  description = "The default user for the VMs"
}

variable "VM_HOSTNAME" {
  default = "vm-test"
  type = string
  description = "Hostname of our VMS"
}

variable "VM_IMG_URL" {
  default = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  type = string
  description = "The URL from where our cloud-init image will be downloaded"
}

variable "VM_IMG_FORMAT" {
  default = "qcow2"
  type = string
  description = "The cloud init image format"
}

variable "VM_CIDR_RANGE" {
  default = "10.10.10.10/24"
  type = string
  description = "Range of IPs available on our VM network"
}

variable "VM_CPU" {
  default = 1
  type = number
  description = "The amount of virtual CPUs"
}

variable "VM_MEMORY" {
  default = 1024
  type = number
  description = "The amount of memory in MiB"
}

variable "VM_DISK_SPACE" {
  default = 6
  type = number
  description = "Size in GB"
}

variable "VM_SSH_KEY" {
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKjulJUlgUpskhuV5Ls3fzd5vmKBNtTAXFYbc+ypD3vI ubuntu@srv02"
  type = string
}
