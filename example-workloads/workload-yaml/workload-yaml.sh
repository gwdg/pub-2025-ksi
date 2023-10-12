#!/bin/bash
set -x # Print each command before execution

# Create workloads
kubectl create --context "$K8S_CLUSTER_NAME" namespace example
kubectl create --context "$K8S_CLUSTER_NAME" -n example -f example-workloads/workload-yaml/job-hello-world.yaml
# Wait for workloads to finish
kubectl wait --context "$K8S_CLUSTER_NAME" -n example --for=condition=complete --timeout=10h job/hello
# Print workload logs
kubectl logs --context "$K8S_CLUSTER_NAME" -n example job/hello
# Delete workloads
kubectl delete --context "$K8S_CLUSTER_NAME" namespace example