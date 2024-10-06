################################################################################
# ENV VARS VALUES
################################################################################

# https://developer.hashicorp.com/terraform/language/values/variables

VM_COUNT = 3
VM_USER = "debian"
VM_HOSTNAME = "vm-node"
#VM_IMG_URL = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img"
#VM_IMG_URL = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"
VM_IMG_URL = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
VM_IMG_FORMAT = "qcow2"
VM_CIDR_RANGE = "10.10.10.10/24"
VM_CPU = 2
VM_MEMORY = 2048
VM_DISK_SPACE = 12
VM_SSH_KEY = "<insert your public key here>"