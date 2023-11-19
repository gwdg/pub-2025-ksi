#!/bin/bash
set -x # Print each command before execution

# Create workloads
kubectl create --context "$K8S_CLUSTER_NAME" namespace example
kubectl create --context "$K8S_CLUSTER_NAME" -n example -f example-workloads/workload-yaml/job-hello-world.yaml
# Wait for workloads to start
kubectl wait -n example --context "$K8S_CLUSTER_NAME" --for=condition=ready pod --selector=job-name=hello --timeout=10m
# Follow workload console logs and wait for completion
kubectl logs -f --context "$K8S_CLUSTER_NAME" -n example job/hello
# Delete workloads
kubectl delete --context "$K8S_CLUSTER_NAME" namespace example