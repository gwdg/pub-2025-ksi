#!/bin/bash
set -x # Print each command before execution

kubectl create --context "$K8S_CLUSTER_NAME" namespace bench
# Create workload as pods or jobs
kubectl create -n bench --context "$K8S_CLUSTER_NAME" -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: sysbench-cpu
spec:
  template:
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
kubectl wait -n bench --context "$K8S_CLUSTER_NAME" --for=condition=ready pod --selector=job-name=sysbench-cpu --timeout=10m
# Follow console logs and wait for completion
kubectl logs -f job/sysbench-cpu -n bench --context "$K8S_CLUSTER_NAME"

# Clean up
kubectl delete --context "$K8S_CLUSTER_NAME" namespace bench
