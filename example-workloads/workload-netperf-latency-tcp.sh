#!/bin/bash
# Docs: https://docs.nvidia.com/networking-ethernet-software/knowledge-base/Configuration-and-Usage/Monitoring/Throughput-Testing-and-Troubleshooting/

set -x # Print each command before execution

kubectl create --context "$K8S_CLUSTER_NAME" namespace bench
# Create workload as pods or jobs
kubectl create -n bench --context "$K8S_CLUSTER_NAME" -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: netperf
spec:
  template:
    spec:
      securityContext:
        runAsUser: 0
      containers:
      - image: networkstatic/netperf
        name: netperf
        command: ["sh", "-c"]
        args:
        - |
          netperf -H "10.254.1.27" -p 16604 -l 30 -t TCP_RR -- -r 200 -o min_latency,max_latency,mean_latency,stddev_latency
      restartPolicy: Never
EOF

kubectl wait --context "$K8S_CLUSTER_NAME" --for=condition=complete --timeout=10h job/netperf -n bench

# Print results
kubectl logs job/netperf -n bench --context "$K8S_CLUSTER_NAME"

# Clean up
kubectl delete --context "$K8S_CLUSTER_NAME" namespace bench
