#!/bin/bash
set -x # Print each command before execution

kubectl create --context "$K8S_CLUSTER_NAME" namespace bench
# Create workload as pods or jobs
kubectl create -n bench --context "$K8S_CLUSTER_NAME" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: sysbench
  name: sysbench-cpu
spec:
  containers:
  - command:
    - sysbench
    - cpu
    - --threads=56
    - --cpu-max-prime=20000
    - run
    image: severalnines/sysbench
    name: sysbench-cpu
  restartPolicy: Never
EOF

# Wait until pod starts https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#wait
kubectl wait -n bench --context "$K8S_CLUSTER_NAME" --for condition=Ready --timeout=10m pod/sysbench-cpu
# Wait until pod stops (there is no possibility to directly wait for pod complete - so this is the workaround https://stackoverflow.com/a/77036091/14355362)
kubectl wait -n bench --context "$K8S_CLUSTER_NAME" --for condition=Ready=False --timeout=200h pod/sysbench-cpu

# Print results
kubectl logs sysbench-cpu -n bench --context "$K8S_CLUSTER_NAME"

# Clean up
kubectl delete --context "$K8S_CLUSTER_NAME" namespace bench