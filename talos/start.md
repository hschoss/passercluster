
export CONTROL_PLANE_IP=192.168.178.200

WORKER_IP=("192.168.178.201" "192.168.178.202" "192.168.178.203")


talosctl get disks --insecure --nodes $CONTROL_PLANE_IP



       runtime     Disk   nvme0n1   2         256 GB   false       nvme                     eui.000000000000000100a07519245c4abd   MTFDHBA256TCK-1AS1AABHA   UHPVN0153CX0WI



nvme0n1


export CLUSTER_NAME=passercluster
export DISK_NAME=nvme0n1



talosctl gen config $CLUSTER_NAME https://$CONTROL_PLANE_IP:6443 --install-disk /dev/$DISK_NAME




talosctl apply-config --insecure --nodes 192.168.178.201 --file passer-w-01.yaml
talosctl apply-config --insecure --nodes 192.168.178.202 --file passer-w-02.yaml
talosctl apply-config --insecure --nodes 192.168.178.203 --file passer-w-03.yaml



talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file controlplane.yaml





talosctl kubeconfig alternative-kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig
export KUBECONFIG=./passer-kubeconfig


talosctl get disks --insecure --nodes $CONTROL_PLANE_IP
