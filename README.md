# Kind Slurm Integration (KSI)

This repository covers an approach to run Kubernetes workloads in a Slurm cluster. 
The approach uses [Kind](https://github.com/kubernetes-sigs/kind) (Kubernetes in Docker) to set up temporary Kubernetes clusters. 
Kind supports [rootless Nerdctl](https://github.com/containerd/nerdctl/blob/main/docs/rootless.md).
This project originated in a [master’s thesis](https://doi.org/10.25625/GDFCFP) at the Georg August University of Göttingen.
The goal of the thesis was to investigate approaches to run Kubernetes workloads in a Slurm cluster.

## Prerequisites
First, a Slurm cluster has to be up and running.
Also, a shared storage among all cluster nodes (e.g., NFS) has to be present.
This project aims for RHEL-like 9 x86_64 distributions, but may work on other RHEL distributions as well.
Apart from that, all nodes have to have certain software installed:

- Bash
- Nerdctl
- Containerd
- Rootlesskit
- Containernetworking-plugins
- Slirp4netns
- Kind
- Kubectl
- Liqoctl

Also, all nodes must ensure certain configurations:
- cgroups v2 is enabled
- CPU delegation is enabled
- Kernel modules `ip6_tables`, `ip6table_nat`, `ip_tables`,  `iptable_nat` are loaded

The initial setup instructions to ensure the prerequisites can be found in [Setup.md](Setup.md).

## Getting Started
1. Clone this repository in a shared directory that is present on all nodes
2. `cd` into the directory
3. As an example, run:
```bash
srun -N3 /bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh $PWD
```

## Script: Run Slurm Job
The script [run-workload.sh](run-workload.sh) provides users the option to execute user-defined Kubernetes workloads as jobs on a Slurm cluster.
To do so, users can write a custom Linux shell script that creates workloads using kubectl.
The script [run-workload.sh](run-workload.sh) handles setting up a temporary Kubernetes cluster inside a container using [Kind](https://github.com/kubernetes-sigs/kind), 
it then executes the Kubernetes workload (user-defined workload script), and finally deletes the cluster when the workload is finished.
It supports multi-tenant usage - so multiple users can create multiple clusters and can use them separately. 
Also, a single user can create multiple Slurm jobs leading to multiple clusters in parallel on the same node.
Moreover, the script installs [Liqo](https://github.com/liqotech/liqo) to be able to form multi-node clusters.

To enable access to files on the host machine inside a Kubernetes workload, 
the current working directory of the host machine is shared with the Kubernetes cluster container. 
Inside the container it is available in `/app`. In a Kubernetes workload this directory can be included using a volume.
The script [workload-job-pytorch.sh](example-workloads/workload-job-pytorch/workload-job-pytorch.sh) gives an example on how the shared directory may be used.

### User-defined Workload Scripts
Users can write scripts that describe the workload.
Inside the script, `kubectl` is available for usage. 
During creating the Kubernetes cluster a random name is picked for the cluster. 
This name is available in the workload script through the variable `K8S_CLUSTER_NAME` and can be used in `kubectl` to reference the correct cluster e.g. `kubectl get jobs --context "$K8S_CLUSTER_NAME"`. 

To create Kubernetes resources, one can utilize `kubectl create --context "$K8S_CLUSTER_NAME"` followed by the resource just as in normal Kubernetes clusters.
Another important part of a workload script is that it also **waits for the workloads to be completed** (e.g. by using `kubectl wait --context "$K8S_CLUSTER_NAME"`). 
Otherwise, the cluster will be deleted without finishing the workload first.
Generally, it is a clean practice to delete the resources in a last step.
However, this is not strictly necessary due to the fact that the whole Kubernetes cluster is deleted in the end.

In workload scripts, the Kubernetes cluster can also be accessed by the Kubernetes REST API. For this use case, two environment variables are provided: `$K8S_CLUSTER_API` amd `$K8S_CLUSTER_API_TOKEN`. The file [workload-kube-api.sh](example-workloads/workload-kube-api/workload-kube-api.sh) provides an example. The token grants access to the service account `admin-user`, which has bound the role `cluster-admin`.

#### Variables
Overall following variables are available inside workload scripts:

| Variable Name         | Description                                                                                                                                                                                                                                                                                      |
|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| K8S_CLUSTER_NAME      | Name of the Kind cluster. Can be used in kubectl `--context`                                                                                                                                                                                                                                     |
| K8S_CLUSTER_API       | URL of the Kubernetes API                                                                                                                                                                                                                                                                        |
| K8S_CLUSTER_API_TOKEN | Token for the Kubernetes API                                                                                                                                                                                                                                                                     |
| K8S_PORT              | Port that is shared with the host machine. This port is selected on runtime from the range 30000 to 32767, in case it is not set beforehand. It can be used e.g. in a Kubernetes service - [workload-pod-nginx.sh](example-workloads/workload-pod-nginx/workload-pod-nginx.sh) gives an example. |


#### Examples

Following workload script is a minimal example:
```bash
# Create workloads
kubectl create --context "$K8S_CLUSTER_NAME" namespace example
kubectl create --context "$K8S_CLUSTER_NAME" -n example -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    spec:
      securityContext:
        runAsUser: 0
      containers:
      - name: hello
        image: alpine
        command: ['echo', 'hello world']
        volumeMounts:
          - name: project-vol
            mountPath: /app
      restartPolicy: OnFailure
      volumes:
        - name: project-vol
          hostPath:
            path: /app
            type: Directory
EOF
# Wait for workloads to finish
kubectl wait --context "$K8S_CLUSTER_NAME" -n example --for=condition=complete --timeout=10h job/hello 
# Print workload logs
kubectl logs --context "$K8S_CLUSTER_NAME" -n example job/hello
# Delete workloads
kubectl delete --context "$K8S_CLUSTER_NAME" namespace example
```

Further examples of workload scripts are included in the directory `example-workloads`: 
- [workload-pod-sysbench.sh](example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh): Runs a CPU benchmark. Gives also an example on how pods can be utilized, although it could also be implemented using a job. 
- [workload-job-pytorch.sh](example-workloads/workload-job-pytorch/workload-job-pytorch.sh): Runs a PyTorch training and stores the resulting model on the node in the directory `./kubernetes-pytorch/out/`
- [workload-yaml.sh](example-workloads/workload-yaml/workload-yaml.sh): Runs a hello-world job defined in a `yaml` file
- [workload-kube-api.sh](example-workloads/workload-kube-api/workload-kube-api.sh): Queries the Kubernetes REST API using curl
- [workload-pod-nginx.sh](example-workloads/workload-pod-nginx/workload-pod-nginx.sh): Runs an nginx webserver. This serves as an example how a service running on one node can be accessed from another node.

### Usage
In general, the script can run without root privileges.
Also, the path to your Kubernetes workload script has to be passed as an argument as well as the path to a shared folder that can be used for synchronization during multi-node setups.
Here, the script [workload-pod-sysbench.sh](example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh) is used as an example. 
Run the following command from the project root directory to use Slurm to execute the workload:
```bash
srun -N3 /bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh $PWD
```
> Here it is assumed that $PWD is on a shared file system.
> To utilize the full compute power of a machine, additional Slurm arguments may be needed.

#### sbatch
One can also use `sbatch` to run KSI. The following batch script `batch-ksi.sh` serves as an example:
```shell
#!/bin/bash
# batch-ksi.sh

#SBATCH --nodes=3

srun -N3 /bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh
```

Run the following command from the project root directory:
```shell
sbatch -D $PWD batch-ksi.sh
```

#### Run without Slurm
KSI can also operate without Slurm, however, multi-node usage is not supported without Slurm.
```bash
/bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh $PWD
```
To store the stdout and stderr in a file you can add following `tee` command:
```bash
/bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh $PWD |& tee log.txt
```

## Troubleshooting

### List All Kubernetes Clusters

To list all Kubernetes clusters run:
```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind get clusters
```
To list all Kubernetes nodes run:
```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind get nodes
```

Alternatively, you can gain insight on your existing Kubernetes clusters by listing all Nerdctl containers:
```bash
nerdctl ps -a
```

### Manually Deleting a Kubernetes Cluster 
In case a Slurm job fails, you might encounter a still running Kubernetes cluster. 
To delete this cluster you need to find out the name first.
Then you can run:
```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind delete cluster --name "cluster_name"
```
or for some distributions, you might need to use systemd-run to start kind into its own cgroup scope
```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl systemd-run --scope --user kind delete cluster --name "cluster_name"
```

## Common Errors
### PermissionError: [Errno 13] Permission Denied
Inside a Kubernetes pod or job, a permission denied error may occur. This usually means that the user is has no permissions to access a file or directory.  
A cause for this may be the directory mapping in the kind config [kind-config-template.yaml](kind-config-template.yaml) or the (un)set user in the pod or job.

Some container images may have set up a non-root user, that executes the application inside the container.
This fact can lead to the error mentioned above.
To solve this, explicitly set the user in the Kubernetes pod to root by adding:
```yaml
spec:
  # ...
  securityContext:
    runAsUser: 0
  # ...
```

To debug this you may run:
```bash
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: alpine
spec:
  securityContext:
    runAsUser: 0
  containers:
  - name: alpine
    image: alpine
    command: ['ls', '-aln', '/app']
    volumeMounts:
      - name: project-vol
        mountPath: /app
  restartPolicy: OnFailure
  volumes:
    - name: project-vol
      hostPath:
        path: /app
        type: Directory
EOF

kubectl logs pod/alpine
```

### Error During Creating Kind Cluster
```
ERROR: failed to create cluster: could not find a log line that matches "Reached target .*Multi-User System.*|detected cgroup v1"
```

This error seems to occur, when the machine does not have sufficient resources left. 
Each machine can only handle a certain number of Kind clusters.

Fix try to run workload on another cluster or delete other clusters first.