#!/bin/bash
set -x # Print each command before execution

echo "K8S_PORT: $K8S_PORT"

kubectl create --context "$K8S_CLUSTER_NAME" namespace nginx
# Create workload as pods or jobs
kubectl create -n nginx --context "$K8S_CLUSTER_NAME" -f - <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: NodePort
  ports:
  - name: http
    nodePort: $K8S_PORT
    port: 80
  selector:
    app: nginx
EOF

# Wait until pod starts https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#wait
kubectl wait -n nginx --context "$K8S_CLUSTER_NAME" --for condition=Ready --timeout=10m pod/nginx

echo "Waiting 200h... CTRL + C or cancel Slurm job to exit"
# Wait until pod stops (there is no possibility to directly wait for pod complete - so this is the workaround https://stackoverflow.com/a/77036091/14355362)
kubectl wait -n nginx --context "$K8S_CLUSTER_NAME" --for condition=Ready=False --timeout=200h pod/nginx

# Print results
kubectl logs nginx -n nginx --context "$K8S_CLUSTER_NAME"

# Clean up
kubectl delete --context "$K8S_CLUSTER_NAME" namespace nginx