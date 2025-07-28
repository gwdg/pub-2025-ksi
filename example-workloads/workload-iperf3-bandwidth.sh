#!/bin/bash
# Docs:
# - https://iperf.fr/iperf-doc.php#3doc
# - https://docs.nvidia.com/networking-ethernet-software/knowledge-base/Configuration-and-Usage/Monitoring/Throughput-Testing-and-Troubleshooting/

set -x # Print each command before execution

kubectl create --context "$K8S_CLUSTER_NAME" namespace bench
# Create workload as pods or jobs
kubectl create -n bench --context "$K8S_CLUSTER_NAME" -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: iperf
spec:
  template:
    spec:
      securityContext:
        runAsUser: 0
      containers:
      - image: networkstatic/iperf3
        name: iperf
        command: ["sh", "-c"]
        args:
        - |
          iperf3 --json -c "10.254.1.27" -p 5003 -i 1 -t 30
      restartPolicy: Never
EOF

kubectl wait --context "$K8S_CLUSTER_NAME" --for=condition=complete --timeout=10h job/iperf -n bench

# Print results
kubectl logs job/iperf -n bench --context "$K8S_CLUSTER_NAME"

# Clean up
kubectl delete --context "$K8S_CLUSTER_NAME" namespace bench
