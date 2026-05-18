## Step 1: i prepared my infrastructure
To create your production cluster infrastructure:

    Boot your machines using the Talos ISO image
    Ensure network access on your nodes.

Here is how to do each step:


## Step 2: storing my IP addresses in variables
CONTROL_PLANE_IP=("192.168.178.200") 
WORKER_IP=("192.168.178.201" "192.168.178.202" "192.168.178.203")

## Step 3: Decide your Kubernetes endpoint

Dedicated load balancer: Set a dedicated load balancer that routes to your control plane nodes.
DNS records: Create multiple DNS records that point to all your control plane nodes

i set up my DNS records in my fritzbox

Internet
   |
[Load Balancer]
   |
-------------------
|   |   |   |   |
Pods Pods Pods Pods


## Step 4: saving my endpoint in a variable
export YOUR_ENDPOINT=192.168.178.200

## Step 5: generating secrets bundle
```
talosctl gen secrets -o secrets.yaml
```
watch out to add it to my .gitignore 


## Step 6: generating machine configuration
```
export CLUSTER_NAME=passercluster
talosctl gen config --with-secrets secrets.yaml --talos-version v1.13 $CLUSTER_NAME https://$YOUR_ENDPOINT:6443
```

## Step 7: Unmounting the ISO


## Step 8:
talosctl --nodes 192.168.178.200 get links --insecure
talosctl get disks --insecure --nodes 192.168.178.200


## Step 9: Patching
touch controlplane-patch-1.yaml # For patching the control plane nodes configuration
touch worker-patch-1.yaml # For patching the worker nodes configuration




## Longhorn Setup

192.168.178.203   runtime     Disk   sdf     6         4.0 TB   naa.5000c500c4c3387c   ST4000LM024-2AN1    jellyfin
192.168.178.203   runtime     Disk   sdg     4         4.0 TB   naa.5000c500c4c34fa3   ST4000LM024-2AN1
192.168.178.203   runtime     Disk   sdh     2         250 GB   naa.5002538e4976b40b   Samsung SSD 860     talos 
192.168.178.203   runtime     Disk   sdi     5         500 GB   naa.50014ee25e4d0f4a   WDC WD5000AAKX-6    velero cluster backup pod

192.168.178.202   runtime     Disk   nvme0n1   2         2.0 TB   nvme.c0a9-323333384538373843454343        2338E878CECC        nextcloud
192.168.178.202   runtime     Disk   sdb       6         1.0 TB   naa.5002538e097270d5                      Samsung SSD 860     talos 


192.168.178.201   runtime     Disk   nvme0n1   2         1.0 TB   eui.0026b7683f8280c5  KINGSTON SA2000M81000G 50026B7683F8280C  immich + talos

192.168.178.200   runtime     Disk   nvme0n1   2         256 GB   eui.000000000000000100a07519245c4abd   MTFDHBA256TCK-1AS1AABHA talos

# hannes at schlaeptop in ~/passercluster/talos
>
