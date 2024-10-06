#### Hello, today we are going to automate the entire process of provisioning and configuring a High Availability and fully compliant Kubernetes distribution, providing an easy, repeatable way to create a k3s cluster that you can run in just a few minutes.

### Table of Contents
1. [Summary](#Summary)
2. [Prerequisites](#Prerequisites)
3. [Walkthrough: Installing everything we will use on the machine](#install)
4. [Walkthrough: **Terraform** - Create Infrastructure](#terraform)
5. [Walkthrough: **Ansible** - Create K3S Cluster](#ansible)
6. [Walkthrough: Cleaning up](#clean)
7. [Conclusion](#conclusion)
8. [Bonus](#bonus)

- ## Summary
<a name="Summary"></a>
In the following guide, you will see how to use Terraform and Ansible to fully automate the deployment of a local Kubernetes cluster on KVM (Kernel-based Virtual Machine). Terraform will be used with the Libvirt API to provision the infrastructure (nodes) where our local Kubernetes cluster will run on, while Ansible will be used to provision and configure Kubernetes on the individual nodes. We will also make use of Cloud-init in order to initialise our nodes with the required dependencies provisioned.

Our Kubernetes cluster will be a 3 node HA setup (High Availability with [etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)) with all the nodes representing both control plane (master node) and data plane (worker node) because of the limited resources at our disposal. The cluster will be provisioned with the following capabilities:
- [Flannel](https://github.com/flannel-io/flannel) - responsible for networking in k3s
- [KubeVIP](https://kube-vip.io/) - provides a load balancer for the k3s nodes - so that we can access our cluster via a single VIP address
- [MetalLB](https://metallb.universe.tf/) - provides a bare metal load balancer for the k3s services - so that we can expose sevices outside of k3s via their own IP
- [Traefik](https://traefik.io/traefik/) - provides ingress proxy for k3s - so that we can expose secure services outside of k3s
- [Longhorn](https://longhorn.io/) - provides distributed persistent block storage for our pods
- [Cert-Manager](https://cert-manager.io/) - responsible for managing all certificates within our cluster

All the source code including this guide can also be found on my GitHub repo here:

- [ ] https://github.com/estemit/devops-k3s-ansible-terraform

Let’s get started!

- ## Prerequisites
<a name="Prerequisites"></a>
Any physical or virtual linux machine that can run KVM and the Libvirt API. The machine MUST have Virtualization enabled. We will provision 3 nodes on it, each with 2 cores, 2GB of RAM and 12GB of disk space, so the machine will need to have at least more than the combined resources of all the nodes.

I've done this on my Intel 11900H MiniPC with 16GB RAM and 500GB disk space. I run Proxmox as a Hypervisor on this MiniPC so I provisioned a VM with Ubuntu 24.04 server and with 10 CPUs, 10 GB RAM and 50GB of disk space.

- ## Walkthrough: Installing everything we will use on the machine
<a name="install"></a>
Following are the instructions to install all the needed software on our machine. If you are doing this on a different Linux distro than Ubuntu 24.04, the instructions may differ. Please check the specific instructions for your distro.

We will be installing the following software packages:
- Git
- KVM with the libvirt API
- Terraform
- Ansible
- Kubectl
.

- ### Clone the repo:

It's easier to clone the repo and have all the code ready on the machine:

```
sudo apt install git
git clone https://github.com/estemit/devops-k3s-ansible-terraform.git
cd devops-k3s-ansible-terraform
```

Also, we will need to provision our nodes with a SSH key for ansible to do it's thing. Create one now with the command bellow and hit enter for everything:

```
ssh-keygen -o
```

- #### Install KVM:

To install KVM and it's related packages run the following command:

```
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils genisoimage cpu-checker -y
```

To make sure the machine has virtualization enabled run the following command:

```
kvm-ok
```

The output should be something like:

> INFO: /dev/kvm exists
> KVM acceleration can be used

There is an issue with apparmour for qemu causing permission denied errors ([link to issue](https://github.com/dmacvicar/terraform-provider-libvirt/issues/546)), so we will disable apparmour for our KVM install:

```
echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd
```

Test the install:

```
sudo virsh list --all
```

- #### Install Terraform

To install Terraform on our machine run the following commands:

```
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

Test the install:

```
terraform version
```

- #### Install Ansible

To install Ansible on our machine run the following commands:

```
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

Test the install:

```
ansible --version
```

When running our ansible playbook later we will run into an issue where ansible can't find the python package `netaddr` even though this should have been already present. To fix this we will install netaddr via pip now:

```
sudo apt install python3-pip
pip install netaddr --break-system-packages
```

- #### Install Kubectl CLI

To install kubectl CLI on our machine run the following commands:

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -rf kubectl
```

Test the install:

```
kubectl version
```

That's it. We should now have all we need in order to run our automation.

- ## Walkthrough: **Terraform** - Create Infrastructure
<a name="terraform"></a>
The Terraform files are in the infra directory so:

```
cd infra
```

Description of the files in this DIR:
- `cloud_init.cfg` - this is the configuration file for our cloud-init. In here we provision our k3s node users with ssh keys, harden our ssh, update and install packages like open-iscsi that will be needed for longhorn to install properly
- `network_config.cfg` - this is the network interface configuration for our cloud-init. We end up not using this since we need to apply a fixed IP to our nodes and increment the IP for each node
- `main.tf` - this is our main Terraform file. To use Terraform with KVM, we use the [libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) provider from the Terraform Provider Registry. In here we provision our k3s nodes with all the components needed (storage pool, cloud-init disk, storage disk, network etc.)
- `terraform.tf` - this is where we define our variables
- `variables.auto.tfvars` - this is where we set our variables. We can specify here the values that we want our k3s nodes to have: number of nodes, default user, node hostname, the cloud-init distro, our network range, nr of CPU, amount of RAM, amount of disk space for each node and our SSH key that will be provisioned on each node

We will use the latest cloud image from Debian 12 since I found that this works best with our KVM setup and it consumes fewer resources than the Ubuntu one.

`VM_SSH_KEY = "<insert your public key here>"`

Replace the value of the SSH public key in the `variables.auto.tfvars` with the one from the key that we created at the beginning of this guide. To view your public key:

```
cat ~/.ssh/id_*.pub
```

Ok, now we can create our infrastructure. First let's initialize terraform:

```
terraform init
```

Now let's execute a plan to see all the objects that terraform will create:

```
terraform plan
```

And to actually create our k3s nodes:

```
terraform apply -auto-approve
```

If all goes well, Terraform will create our 3 nodes along with a network for them. At the end, Terraform will output the IP for each individual node that was created. Should look something like this:

> Changes to Outputs:
>   + virtual_machines = [
>       + "10.10.10.10",
>       + "10.10.10.11",
>       + "10.10.10.12",
>     ]

We can confirm this by checking on KVM:

```
sudo virsh list --all
```

The output should look like this:

>  Id   Name        State
> ---------------------------
>  1    vm-node-1   running
>  2    vm-node-2   running
>  3    vm-node-0   running


In case something goes wrong (kernel panic) you need to clean up KVM and Terraform state in order to start over. You can start over from `terraform init` again after that. Here's how to do that:

```
sudo virsh undefine vm-node-0 --remove-all-storage
sudo virsh undefine vm-node-1 --remove-all-storage
sudo virsh undefine vm-node-2 --remove-all-storage
sudo virsh pool-undefine vm-node_pool
sudo virsh net-undefine vm-node_network
rm -rf .terraform*
rm -rf terraform.tfstate*
```

Ok, so we now have our infrastructure in place and we are ready to install and configure our k3s cluster on it.

- ## Walkthrough: **Ansible** - Create K3S Cluster
<a name="ansible"></a>
The Ansible playbooks are in the k3s directory so:

```
cd ../k3s
```

Notable files in this DIR:
- `ansible.cfg` - this is the Ansible configuration file, should work out of the box
- `inventory/my-cluster/group_vars/all.yml` - this is where we can set the values for all the variables. We can configure here all aspects of our k3s installation, should work out of the box
- `inventory/my-cluster/group_vars/hosts.ini` - this is our hosts file. Here is where we set all the nodes that we want to manipulate with our ansible playbooks, should work out of the box
- `site.yml` - this is our main playbook that we'll use to provision and configure our k3s cluster
- `reboot.yml` - this playbook can reboot our nodes
- `reset.yml` - this playbook will clean up and remove anything that we've installed and configured with `site.yml` playbook, returning our nodes to the state they were before

First time run - this should already be present when we installed ansible but to be on the safe side run this command to make sure all dependencies are installed:

```
ansible-galaxy install -r ./collections/requirements.yml
```

We can launch our playbook with the following command:

```
ansible-playbook ./site.yml -i ./inventory/my-cluster/hosts.ini
```

If all goes well, after a couple of minutes, we should now have our k3s cluster provisioned and configured with all we need. The last lines of the ansible playbook should look something like:

> PLAY RECAP *****************************************************************************************************************************************************************************************************************************************************************************
> 10.10.10.10                : ok=69   changed=30   unreachable=0    failed=0    skipped=25   rescued=0    ignored=0
> 10.10.10.11                : ok=46   changed=17   unreachable=0    failed=0    skipped=31   rescued=0    ignored=0
> 10.10.10.12                : ok=46   changed=17   unreachable=0    failed=0    skipped=31   rescued=0    ignored=0

Let's check if Kube-VIP created our VIP and we can reach our cluster via it's loadbalancer:

```
ping 10.10.10.100
```

The playbook also downloads the `kubeconfig` file from one of the master nodes and stores it in the current directory. In order to be able to issue `kubectl` commands to our cluster we need to put the `kubeconfig` file here:

```
mkdir -p ~/.kube && mv kubeconfig ~/.kube/config
```

We can now start interacting with our cluster. To see the k3s nodes:

```
kubectl get nodes -o wide
```

The output should look like this:

> NAME        STATUS   ROLES                       AGE     VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION   CONTAINER-RUNTIME
> vm-node-0   Ready    control-plane,etcd,master   3m11s   v1.30.2+k3s2   10.10.10.10   none        Debian GNU/Linux 12 (bookworm)   6.1.0-26-amd64   containerd://1.7.17-k3s1
> vm-node-1   Ready    control-plane,etcd,master   2m51s   v1.30.2+k3s2   10.10.10.11   none        Debian GNU/Linux 12 (bookworm)   6.1.0-26-amd64   containerd://1.7.17-k3s1
> vm-node-2   Ready    control-plane,etcd,master   2m36s   v1.30.2+k3s2   10.10.10.12   none        Debian GNU/Linux 12 (bookworm)   6.1.0-26-amd64   containerd://1.7.17-k3s1

You can check all the pods with this command:

```
kubectl get pods -A -o wide
```

Let's install a test nginx app to see our new cluster in action:

```
kubectl apply -f example/rwx-nginx-deployment.yaml
```

Have a look at the deployment with:

```
kubectl describe deployment rwx-test
```

Notice that we have 3 pods running in HA mode.
Let's check if the pods have their storage attached from Longhorn:

```
kubectl describe persistentvolumeclaim rwx-test
```

Notice the events, Longhorn created the persistent volumes for the pods that are highly available and replicated across all nodes:

> Events:
>   Type    Reason                 Age    From                                                                                      Message
>   ----    ------                 ----   ----                                                                                      -------
>   Normal  Provisioning           4m13s  driver.longhorn.io_csi-provisioner-58cc84b487-m6b7x_1eba16e5-9e41-4487-81ce-2d708b9672c0  External provisioner is provisioning volume for claim "default/rwx-test"
>   Normal  ExternalProvisioning   4m13s  persistentvolume-controller                                                               Waiting for a volume to be created either by the external provisioner 'driver.longhorn.io' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
>   Normal  ProvisioningSucceeded  4m8s   driver.longhorn.io_csi-provisioner-58cc84b487-m6b7x_1eba16e5-9e41-4487-81ce-2d708b9672c0  Successfully provisioned volume pvc-8f38ccb8-bac5-4120-a580-6bc85d976847

Let's have a look also at the service for these pods:

```
kubectl describe service rwx-test
```

Notice the events, we can reach this service via it's own external IP that got assigned from MetalLB:

> Events:
>   Type    Reason       Age    From                Message
>   ----    ------       ----   ----                -------
>   Normal  IPAllocated  2m15s  metallb-controller  Assigned IP ["10.10.10.102"]

- ## Walkthrough: Cleaning up
<a name="clean"></a>
Now that we are done with our cluster, let's clear it up.
To remove the k3s installation from all nodes run the playbook:

```
ansible-playbook ./reset.yml -i ./inventory/my-cluster/hosts.ini
```

To remove the nodes we created with Terraform run this command from the `infra` DIR:

```
terraform destroy -f -auto-approve
```

And there you have it, we are back to square one, but we can recreate everything back up with 2 commands, the `terraform apply` and then running the `ansible site playbook`.

- ## Conclusion
<a name="conclusion"></a>
Using automation, we were able to provision and configure our local cluster in record time. And it was all done with code through the power of Terraform and Ansible. We can scale our cluster as needed, just by setting the number of nodes we desire in our Terraform variable, and then adding the IP of the new nodes under our worker nodes group in the .ini file and run our ansible playbook to provision the new nodes.

In order for a Kubernetes cluster to be considered production ready, the following  considerations must be taken into account:
- _Availability_ - high availability (HA) must be ensured at multiple levels: nodes (control plane and data plane), pods, load balancing, persistent storage
- _Scale_ - the ability to add and remove nodes and pods from a cluster based on actual demand, e.g. A tool like [Karpenter](https://karpenter.sh/)
- _Security and access management_ - role-based access control (RBAC) and other security mechanisms must be implemented in order to make sure that users and workloads can get access to the resources they need, while keeping workloads, and the cluster itself, secure
- _Logging and Monitoring_ - central logging implementation like OpenTelemetry with Elastic Search will drastically speed up the time it takes to debug a critical issue within a cluster or the applications that run inside it. A central monitoring solution based on Prometheus and Grafana will vastly increase the visibility of the performance of the cluster and the applications inside of it. However, these implementations take a lot more time to plan and implement.  

- ## Bonus - k8s cluster with Vagrant
<a name="bonus"></a>
There is also a vagrant DIR so let's check it out:

```
cd vagrant
```

Let's quickly install Vagrant and VirtualBox on our machine:

```
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vagrant virtualbox -y
```

If you are doing this on the same machine we used until now we need to add KVM hypervisor to the deny list in order for VirtualBox to run correctly and then reboot our machine:

```
lsmod | grep kvm
echo 'blacklist kvm-intel' | sudo tee -a /etc/modprobe.d/blacklist.conf
sudo reboot
```

In order to let Vagrant create private networks we need to run this command:

```
sudo mkdir -p /etc/vbox/ && sudo touch /etc/vbox/networks.conf && echo '* 0.0.0.0/0 ::/0' | sudo tee -a /etc/vbox/networks.conf
```

Let's bring our cluster UP:

```
vagrant up
```

After a long wait, we should now have our k8s cluster provisioned with Calico Network Plugin, Metrics server, and Kubernetes dashboard configured using only a `Vagrant file` and some `bash scripts`.

Lets hop on the `controlplane` node of our k8s cluster:

```
vagrant ssh controlplane
```

Now we can interact with our new Kubernetes cluster using `kubectl`:

```
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

Great Success!!!