#!/bin/bash

set -x # Print each command before execution

# List all namespaces
curl -X GET "$K8S_CLUSTER_API/api/v1/namespaces" --header "Authorization: Bearer $K8S_CLUSTER_API_TOKEN" --insecure
# List all pods in default namespace
curl -X GET "$K8S_CLUSTER_API/api/v1/namespaces/default/pods" --header "Authorization: Bearer $K8S_CLUSTER_API_TOKEN" --insecure
