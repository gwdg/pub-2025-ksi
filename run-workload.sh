#!/bin/bash
set -x # Print each command before execution
set -e # fail and abort script if one command fails
set -o pipefail

if [ -z "$1" ]; then
    echo "Missing argument: Script is not specified. Pass a path to a script." >&2
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "File does not exists for passed path" >&2
    exit 2
fi

# Ensure prerequisites ------------------------

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

if [ -x "$(which podman)" ]; then
    echo "podman check passed"
else
    echo "podman check failed: podman not installed or not available in shell" >&2
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


# Create kind kubernetes cluster ------------------------
cluster_name="$(uuidgen | tr -d '-' | head -c5)"

function cleanup () {
  echo "Deleting Kind cluster container $cluster_name"
  # Delete kind Kubernetes cluster ------------------------
  if [[ "$NAME" == "CentOS Stream" && "$VERSION_ID" = "8" ]]; then
    # On some distributions, you might need to use systemd-run to start kind into its own cgroup scope
    KIND_EXPERIMENTAL_PROVIDER=podman systemd-run --scope --user kind delete cluster --name "$cluster_name"
  else
      # https://kind.sigs.k8s.io/docs/user/quick-start/
    KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name "$cluster_name"
  fi
}
trap cleanup EXIT # Normal Exit
trap cleanup SIGTERM # Termination from Slurm and CTRL + C

# https://kind.sigs.k8s.io/docs/user/rootless/
# https://kind.sigs.k8s.io/docs/user/quick-start/
# kind-config.yaml contains a mapping for the current directory into the `/app` directory inside the cluster container.
if [[ "$NAME" == "CentOS Stream" && "$VERSION_ID" = "8" ]]; then
  # On some distributions, you might need to use systemd-run to start kind into its own cgroup scope:
  KIND_EXPERIMENTAL_PROVIDER=podman systemd-run --scope --user kind create cluster --name "$cluster_name" --wait 5m --config ./kind-config.yaml
else
  KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name "$cluster_name" --wait 5m --config ./kind-config.yaml
fi

# Test kubectl and cluster
kubectl get nodes --context "kind-$cluster_name"
kubectl cluster-info --context "kind-$cluster_name"

# Run Kubernetes Workload ------------------------
echo "Executing the Kubernetes workload script $1 on cluster kind-$cluster_name"
K8S_CLUSTER_NAME="kind-$cluster_name" /bin/bash "$1"

# Deleting cluster is handled in cleanup function