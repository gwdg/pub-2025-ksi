#!/bin/bash
# Source: https://github.com/soerenmetje/kubernetes-pytorch

set -x # Print each command before execution

if [ ! -d "kubernetes-pytorch" ]; then
  echo "kubernetes-pytorch directory does not exist. Cloning repository first..."
  git clone https://github.com/soerenmetje/kubernetes-pytorch.git
else
  echo "kubernetes-pytorch directory already exist."
fi

cd "kubernetes-pytorch" || exit 1


kubectl create --context "$K8S_CLUSTER_NAME" namespace pytorch

kubectl create --context "$K8S_CLUSTER_NAME" -n pytorch -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: pytorch-example
spec:
  template:
    spec:
      securityContext:
        runAsUser: $UID
      containers:
      - name: pytorch
        image: bitnami/pytorch:2.0.1
        command: ['python', '/app/src/main.py']
        volumeMounts:
          - name: project-vol
            mountPath: /app
      restartPolicy: OnFailure
      volumes:
        - name: project-vol
          hostPath:
            path: /app/kubernetes-pytorch
            type: Directory
EOF
# wait for training to finish
kubectl wait --context "$K8S_CLUSTER_NAME" --for=condition=complete --timeout=10h job/pytorch-example -n pytorch

kubectl logs --context "$K8S_CLUSTER_NAME" -n pytorch job/pytorch-example

kubectl delete --context "$K8S_CLUSTER_NAME" namespace pytorch
# Model remains in directory out

ls -al out/
cd ..