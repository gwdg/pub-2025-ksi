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

# Ensure prerequisites ------------------------

# check cgroups v2 enabled (Source: https://unix.stackexchange.com/a/480748/567139 )
if [ "$(stat -fc %T /sys/fs/cgroup/)" = "cgroup2fs" ]; then
    echo "cgroups v2 check passed: cgroups v2 is enabled"
else
    echo "cgroups v2 check failed: cgroups v2 is not enabled" >&2
    exit 3
fi

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

CLUSTER_NAME="liqo-${SLURM_PROCID:-$$}"
CLUSTER_ID="${SLURM_PROCID}"
CONTROL_PLANE_PORT=$((6443 + CLUSTER_ID))
WORKER_IP=$(hostname -I | awk '{print $1}')

cat > kind-config-${CLUSTER_NAME}.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    extraMounts:
    - hostPath: ${SHARE_MOUNT}/app
      containerPath: /app
    extraPortMappings:
      - containerPort: 6443
        hostPort: ${CONTROL_PLANE_PORT}
        listenAddress: "${WORKER_IP}"
EOF

mkdir -p "${SHARE_MOUNT}/app"

function cleanup () {
  echo "[Task ${CLUSTER_ID}] Cleaning up KinD cluster..."
  # Delete kind Kubernetes cluster ------------------------
  if [[ "$NAME" == "CentOS Stream" && "$VERSION_ID" = "8" ]]; then
    # On some distributions, you might need to use systemd-run to start kind into its own cgroup scope
    KIND_EXPERIMENTAL_PROVIDER=nerdctl systemd-run --scope --user kind delete cluster --name "$cluster_name"
  else
      # https://kind.sigs.k8s.io/docs/user/quick-start/
    KIND_EXPERIMENTAL_PROVIDER=nerdctl kind delete cluster --name "$cluster_name"
  fi
}

trap cleanup EXIT # Normal Exit
trap cleanup SIGTERM # Termination
trap cleanup SIGINT # CTRL + C

echo "[Task ${CLUSTER_ID}] Creating KinD cluster: $CLUSTER_NAME"
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.29.0 --config kind-config-${CLUSTER_NAME}.yaml --wait 60s

# Get the name of the control-plane container
CONTROL_PLANE_CONTAINER="${CLUSTER_NAME}-control-plane"

# Get the container IP
CONTAINER_IP=$(nerdctl inspect -f '{{ .NetworkSettings.IPAddress }}' "$CONTROL_PLANE_CONTAINER")

# Export kubeconfig to shared mount
KUBECONFIG_EXPORT_PATH="${SHARE_MOUNT}/kubeconfig-liqo-${CLUSTER_ID}.yaml"
echo "[Task ${CLUSTER_ID}] Exporting kubeconfig to ${KUBECONFIG_EXPORT_PATH} ..."
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind get kubeconfig --name "$CLUSTER_NAME" > "${KUBECONFIG_EXPORT_PATH}"

# Patch the kubeconfig to use external host IP instead of container hostname
sed -i "s|https://.*control-plane:6443|https://${WORKER_IP}:${CONTROL_PLANE_PORT}|g" "${KUBECONFIG_EXPORT_PATH}"

# Add insecure-skip-tls-verify and remove CA cert
yq eval '.clusters[].cluster |= . + {"insecure-skip-tls-verify": true} | .clusters[].cluster.certificate-authority-data = null' -i "${KUBECONFIG_EXPORT_PATH}"

echo "[Task ${CLUSTER_ID}] Waiting for all nodes to be ready..."
kubectl --kubeconfig="${KUBECONFIG_EXPORT_PATH}" wait node --all --for=condition=Ready --timeout=120s

echo "[Task ${CLUSTER_ID}] Installing Liqo on cluster..."
liqoctl install kind --kubeconfig "${KUBECONFIG_EXPORT_PATH}" || {
  echo "ERROR: Liqo install failed!"
  exit 1
}

# Extract current-context and export required env vars
K8S_CLUSTER_NAME=$(yq eval '.["current-context"]' "${KUBECONFIG_EXPORT_PATH}")
export KUBECONFIG="${KUBECONFIG_EXPORT_PATH}"
export K8S_CLUSTER_NAME

echo "[Task ${CLUSTER_ID}] Liqo install complete. Running workload..."
bash "$WORKLOAD_SCRIPT" "$SHARE_MOUNT"
WORKLOAD_EXIT_CODE=$?

if [[ $WORKLOAD_EXIT_CODE -ne 0 ]]; then
  echo "[Task ${CLUSTER_ID}] Workload script exited with code $WORKLOAD_EXIT_CODE"
else
  echo "[Task ${CLUSTER_ID}] Workload completed successfully"
fi

rm -f kind-config-${CLUSTER_NAME}.yaml
rm -f kubeconfig-liqo-${CLUSTER_ID}.yaml

echo "[Task ${CLUSTER_ID}] Done."
exit $WORKLOAD_EXIT_CODE
