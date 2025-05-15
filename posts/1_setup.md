# Contents

- [K3S Cluster](#k3s-cluster)
  - [Installing Talos in the nodes](#installing-talos-in-the-nodes)
    - [Creating the deployment structure](#creating-the-deployment-structure)
      - [Patches](#patches)
      - [Nodes](#nodes)
      - [Rendering the configuration](#rendering-the-configuration)
    - [Deploying the first node](#deploying-the-first-node)

# K3S Cluster

As the main objective of this is using a distro that would allow me to interact
enough with the K8S ecosystem, while not being too overwhelming.

I'm choosing Talos, as it'll handle all the OS management for me, and let me
focus on learning Kubernetes only. It also is a very secure system, and as I'll
be exposing things to the internet, having sane default is better for me.

The alternative I was considering was K3S + NixOS, where I could handle all
deployments through `deploy-rs`. I really like NixOS, but I feel that in this
context it'll be errors from a complex system like Kubernetes sitting on top of
errors in another complex system like NixOS. I'll pass for now.

## Installing Talos in the nodes

At first this seemed straightforward, as I was following the Getting Started
guide by Talos. But then I found
[this excellent series](https://datavirke.dk/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/),
which I'm going to be using as reference.

First, I created the secrets and config files using the following command:

```sh
``talosctl gen secrets --output-file secrets.yaml
```

Which generated two files:

- `secrets.yaml`
- `talosconfig`.

Then I added it to the default config as:

```sh
talosctl config merge ./talosconfig
```

Finally, in the `~./.talos/config` I set the control plane node endpoint:

```yaml
avatar:
  endpoints:
    - 192.168.1.3
```

### Creating the deployment structure

For the structure of the repo I'm following the series, where there are three
directories: `patches`, `nodes` and `rendered`:

- `patches`: holds general configuration and patches to be applied to all nodes.
- `nodes`: holds configuration for specific nodes, like their IP, etc.
- `rendered`: holds the generated YAML machine configuration files from the
  patches and nodes files.

After creating the folders, I got to the following place:

```
├── nodes
│   └── aang.yaml
├── patches
│   ├── allow-controlplane-workloads.yaml
│   ├── cluster-name.yaml
│   └── drives-management.yaml
└── rendered
```

#### Patches

I created three patches. The first two are really simple, where it allows the
control plane to also have workloads, and setting the cluster name:

```yaml
# ./patches/allow-controlplane-workloads.yaml
cluster:
  allowSchedulingOnControlPlanes: true
```

```yaml
# ./patches/cluster-name.yaml
cluster:
  clusterName: avatar
```

Finally, as my MiniPCs only have one NVMe each, and Talos takes the whole drive
as ephemeral by default, we needed to create a data volume. In this case, all my
nodes takes this configuration, hence I've placed this here:

```yaml
apiVersion: v1alpha1
kind: VolumeConfig
name: EPHEMERAL
provisioning:
  diskSelector:
    match: system_disk
  maxSize: 100GB
  grow: false
---
apiVersion: v1alpha1
kind: UserVolumeConfig
name: data
provisioning:
  diskSelector:
    match: system_disk
  minSize: 1GB
filesystem:
  type: ext4
```

I've come to this solution after reading
[this GitHub Issue in the Talos repo](https://github.com/siderolabs/talos/issues/8367).

#### Nodes

Now, for the Aang node, which is going to be my control plane, I got the
following:

```yaml
machine:
  install:
    disk: /dev/nvme0n1
    image: ghcr.io/siderolabs/installer:v1.10.1
    wipe: true
  network:
    hostname: aang
    interfaces:
      - interface: enp3s0
        addresses:
          - 192.168.1.3
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
        dhcp: true
```

I wanted to be declarative about the networking part of this, like setting the
correct IP I'm using. For this, first I need to know the networking interface
I'm using. We can get this with the following command

```
talosctl -n 192.168.1.3 get links --insecure
NODE   NAMESPACE   TYPE         ID        VERSION   TYPE       KIND     OPER STATE   LINK STATE
       ...         ...          ...       ...       ...        ...      ...          ...
       network     LinkStatus   enp3s0    3         ether               up           true
       ...         ...          ...       ...       ...        ...      ...          ...
```

In this case, we see that the :`enp3s0` is our ethernet interface which is
currently up. We can then add this to our YAML file as I id above.

#### Rendering the configuration

After I finished the patches and nodes configuration, we can get the whole thing
as follows. I exported my cluster name and API endpoint as to make it easier to
read/write.

```sh
talosctl gen config \
        --output rendered/aang.yaml \
        --output-types controlplane \
        --with-cluster-discovery=false \
        --with-secrets secrets.yaml \
        --config-patch @patches/cluster-name.yaml \
        --config-patch @patches/allow-controlplane-workloads.yaml \
        --config-patch @patches/drives-management.yaml \
        --config-patch @nodes/aang.yaml \
        $CLUSTER_NAME \
        $API_ENDPOINT
```

This will output a file in `rendered/aang.yaml` which would be our machine
configuration.

### Deploying the first node

I have already my rendered machine configuration, so I can do the first
deployment!

This can be done like this:

```sh
talosctl --nodes 192.168.1.3 apply-config --file rendered/aang.yaml --insecure
```

After a bit, my system rebooted, and is now waiting me to bootstrap it. We can
se the dashboard using:

```sh
talosctl --nodes 192.168.1.3 dashboard
```

```
user: warning: [2025-05-10T19:41:39.400432499Z]: [talos] etcd is waiting to join the cluster, if this node is the first node in the cluster, please run `talosctl bootstrap`
 against one of the following IPs:
 user: warning: [2025-05-10T19:41:39.400539499Z]: [talos] [192.168.1.3]
```

I'll just do what it asks me to do:

```
talosctl --nodes 192.168.1.3 bootstrap
```

After a bit it got to `READY = true`, so we are done! I'll reboot to check we
are OK!

```
talosctl --nodes 192.168.1.3 reboot
```

Aaaaaand it worked! We got Talos in our first node. Finally, I want to merge
this into my local Kubernetes configuration:

```
talosctl kubeconfig --nodes 192.168.1.3 --endpoints 192.168.1.3
```

After this is done we can explore our cluster 😎

```sh
❯ kubectl get nodes

NAME   STATUS   ROLES           AGE   VERSION
aang   Ready    control-plane   10m   v1.33.0

```

After this, I'll have to repeat the process for the second node, which I'll name `katara` :) 

For now, this is it!

