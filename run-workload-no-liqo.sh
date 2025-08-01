#!/bin/bash

#SBATCH --signal=B:SIGTERM@60

set -euo pipefail

# Arguments:
WORKLOAD_SCRIPT=${1:-}
SHARE_MOUNT=${2:-}

if [[ -z "$WORKLOAD_SCRIPT" || -z "$SHARE_MOUNT" ]]; then
  echo "Usage: $0 <workload-script> <shared-mount-path>"
  exit 1
fi

# Ensure prerequisites

# check cgroups v2 enabled (Source: https://unix.stackexchange.com/a/480748/567139 )
if [ "$(stat -fc %T /sys/fs/cgroup/)" = "cgroup2fs" ]; then
    echo "cgroups v2 check passed: cgroups v2 is enabled"
else
    echo "cgroups v2 check failed: cgroups v2 is not enabled" >&2
    exit 3
fi

# Load dependencies in case a module manager is present on node
#module purge
#module load podman
#module load slirp4netns
#module load kubectl
#module load kind

# Print kind version
kind --version

# Enable bypass4netns for nerdctl
containerd-rootless-setuptool.sh install-bypass4netnsd

if [ -x "$(which nerdctl)" ]; then
    echo "nerdctl check passed"
else
    echo "nerdctl check failed: nerdctl not installed or not available in shell" >&2
    exit 4
fi

if [ -x "$(which kubectl)" ]; then
    echo "kubectl check passed"
else
    echo "kubectl check failed: kubectl not installed or not available in shell" >&2
    exit 4
fi

if [ -x "$(which kind)" ]; then
    echo "kind check passed"
else
    echo "kind check failed: kind not installed or not available in shell" >&2
    exit 4
fi

# Find out distribution - some distributions require different commands
if [ -f /etc/os-release ]
then
    . /etc/os-release
    # vars listed in /etc/os-release are now available as ENV vars
    echo "Successfully read /etc/os-release"
else
    echo "Warn: file /etc/os-release not present. Can not determine OS version. Proceeding with default procedure" >&2
fi

function random_unused_port {
  local port
  for ((port=30000; port<=32767; port++)); do
      ss -Htan | awk '{print $4}' | cut -d':' -f2 | grep "$port" > /dev/null
      if [[ $? == 1 ]] ; then
          echo "$port"
          break
      fi
  done
}

# Create kind kubernetes cluster ------------------------
cluster_name="$(uuidgen | tr -d '-' | head -c5)"
: "${K8S_PORT:=$(random_unused_port)}" # if K8S_PORT is not set
export K8S_PORT=$K8S_PORT
echo "K8S_PORT=$K8S_PORT"

function cleanup () {
  echo "Deleting Kind cluster container $cluster_name"
  # Delete kind Kubernetes cluster ------------------------
  # https://kind.sigs.k8s.io/docs/user/quick-start/
  KIND_EXPERIMENTAL_PROVIDER=nerdctl kind delete cluster --name "$cluster_name"
}

trap cleanup EXIT # Normal Exit
trap cleanup SIGTERM # Termination
trap cleanup SIGINT # CTRL + C

echo "Kind config:"
config_dir=$(dirname "$(realpath "$0")")
envsubst < "$config_dir"/kind-config-template.yaml

# https://kind.sigs.k8s.io/docs/user/rootless/
# https://kind.sigs.k8s.io/docs/user/quick-start/
# kind-config-template.yaml contains a mapping for the current directory into the `/app` directory inside the cluster container.

envsubst < "$config_dir"/kind-config-template.yaml | KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --name "$cluster_name" --wait 5m --config -

# Test kubectl and cluster
kubectl get nodes --context "kind-$cluster_name"
kubectl cluster-info --context "kind-$cluster_name"

K8S_CLUSTER_NAME="kind-$cluster_name"
export K8S_CLUSTER_NAME=$K8S_CLUSTER_NAME
# Source: https://collabnix.github.io/kubelabs/api.html
K8S_CLUSTER_API=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$K8S_CLUSTER_NAME')].cluster.server}")
export K8S_CLUSTER_API=$K8S_CLUSTER_API

# Create ServiceAccount and ClusterRoleBinding to enable admin access
# Existing SA such as kube-system:default seem to have only restricted access in Kind clusters
# Source: https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md
kubectl --context "$K8S_CLUSTER_NAME" create -f -  <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF
kubectl --context "$K8S_CLUSTER_NAME" create -f -  <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF
# Source: https://iximiuz.com/en/posts/kubernetes-api-call-simple-http-client/
# Kubernetes 1.24+
K8S_CLUSTER_API_TOKEN=$(kubectl --context "$K8S_CLUSTER_NAME" -n kube-system create token admin-user)
export K8S_CLUSTER_API_TOKEN=$K8S_CLUSTER_API_TOKEN

# Run Kubernetes Workload ------------------------
echo "Executing the Kubernetes workload script $1 on cluster kind-$cluster_name"
/bin/bash "$1" &
wait # wait for background process. Fix for not working signal handling in Slurm (See https://docs.gwdg.de/doku.php?id=en:services:application_services:high_performance_computing:running_jobs_slurm:signals)

# Deleting cluster is handled in cleanup function
