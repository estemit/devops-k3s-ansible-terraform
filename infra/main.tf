################################################################################
# PROVIDERS
################################################################################
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.8.0"
    }
  }
}

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}


################################################################################
# DATA TEMPLATES
################################################################################

# https://www.terraform.io/docs/providers/template/d/file.html

# https://www.terraform.io/docs/providers/template/d/cloudinit_config.html

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    VM_USER = var.VM_USER
    VM_SSH_KEY = var.VM_SSH_KEY
  }
}

# We want to assign static IPs for each VM (increment IP with each VM) and since we cannot do this in cloud init config we're not using network confing and set and increment the IP in the network interface for each VM

# data "template_file" "network_config" {
#   template = file("${path.module}/network_config.cfg")
# }


################################################################################
# RESOURCES
################################################################################

resource "libvirt_pool" "vm" {
  name = "${var.VM_HOSTNAME}_pool"
  type = "dir"
  path = "/tmp/terraform-provider-libvirt-pool-ubuntu"
}

# We fetch the latest ubuntu release image from their mirrors, we cannot specify disk size with source URL
resource "libvirt_volume" "vm" {
  count  = var.VM_COUNT
  name   = "${var.VM_HOSTNAME}-${count.index}_base-volume.${var.VM_IMG_FORMAT}"
  pool   = libvirt_pool.vm.name
  source = var.VM_IMG_URL
  format = var.VM_IMG_FORMAT
# we cannot specify disk size with source URL
#  size = 1024*1024*1024*var.VM_DISK_SPACE
}

# Because the cloud init image has verry limited disk space, we create another volume that is based on the cloud init image but here we can specify the disk size
resource "libvirt_volume" "server_disk" {
  count          = var.VM_COUNT
  name           = "${var.VM_HOSTNAME}-${count.index}_volume.${var.VM_IMG_FORMAT}"
  size           = 1024*1024*1024*var.VM_DISK_SPACE
  pool           = libvirt_pool.vm.name
  base_volume_id = libvirt_volume.vm[count.index].id
}

# Create a public network for the VMs
resource "libvirt_network" "vm_public_network" {
   name = "${var.VM_HOSTNAME}_network"
   mode = "nat"
   domain = "${var.VM_HOSTNAME}.local"
   addresses = ["${var.VM_CIDR_RANGE}"]
   dhcp {
    enabled = true
   }
   dns {
    enabled = true
   }
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to provision our VMs and add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "${var.VM_HOSTNAME}_cloudinit.iso"
  user_data      = data.template_file.user_data.rendered
#  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.vm.name
}

# Create the machine
resource "libvirt_domain" "vm" {
  count  = var.VM_COUNT
  name   = "${var.VM_HOSTNAME}-${count.index}"
  memory = var.VM_MEMORY
  vcpu   = var.VM_CPU

  cloudinit = "${libvirt_cloudinit_disk.cloudinit.id}"

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id = "${libvirt_network.vm_public_network.id}"
    network_name = "${libvirt_network.vm_public_network.name}"
# set and increment the static IP in the network interface for each VM
    addresses = ["10.10.10.${count.index + 10}"]
#So that we can output the IPs of our VMs we need to wait for them to get the IP assigned
    wait_for_lease = true
  }

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why.
  #
  # This is a known bug on cloud images, since they expect a console
  # we need to pass it:
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
#    volume_id = "${libvirt_volume.vm[count.index].id}"
# We pass our main resizable disk here instead of the cloud init one
    volume_id = "${libvirt_volume.server_disk[count.index].id}"
# Longhorn wont work without this
    scsi      = "true"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

################################################################################
# TERRAFORM OUTPUT
################################################################################

output "virtual_machines" {
  value = libvirt_domain.vm.*.network_interface.0.addresses.0
}

# output "ips" {
#     value = "${libvirt_domain.vm[*].network_interface[*].addresses[0]}"
# }

# resource "local_file" "ips" {
#     content  = values(libvirt_domain.vm)[*].network_interface.*.addresses[0]
#     filename = "ips.txt"
# }

################################################################################
# TERRAFORM CONFIG
################################################################################

terraform {
  required_version = ">= 0.12"
}