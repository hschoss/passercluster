
export CONTROL_PLANE_IP=192.168.178.200

WORKER_IP=("192.168.178.201" "192.168.178.202" "192.168.178.203")



export CLUSTER_NAME=passercluster
export DISK_NAME=nvme0n1


talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file passer-cp-01.yaml


talosctl apply-config --insecure --nodes 192.168.178.201 --file passer-w-01.yaml
talosctl apply-config --insecure --nodes 192.168.178.202 --file passer-w-02.yaml
talosctl apply-config --insecure --nodes 192.168.178.203 --file passer-w-03.yaml




talosctl get disks --insecure --nodes 192.168.178.201




hallo


talosctl apply-config \
  --insecure \
  --nodes 192.168.178.201 \
  --file passer-w-01.yaml \
  --mode reboot


talosctl apply-config \
  --insecure \
  --nodes $CONTROL_PLANE_IP \
  --file passer-cp-01.yaml
   reboot



talosctl apply-config \
  --insecure \
  --nodes 192.168.178.201 \
  --file passer-w-01.yaml \
  --mode reboot





