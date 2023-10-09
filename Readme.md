# Kubernetes Slurm Integration based on Kind

This repository covers an approach to run Kubernetes workloads in a Slurm cluster. 
This approach uses [Kind](https://github.com/kubernetes-sigs/kind) (Kubernetes in Docker) to set up temporary Kubernetes clusters. 
Kind supports [rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) which is a [valid choice for HPC use cases](https://www.redhat.com/en/blog/podman-paves-road-running-containerized-hpc-applications-exascale-supercomputers).
This project is part of my master’s thesis of investigating approaches to run Kubernetes workloads in a Slurm cluster.

## Prerequisites

- All nodes run RHEL 9 based x86 distro (tested with CentOS Stream 9)
- cgroups v2 enabled on all nodes
- CPU delegation enabled on all nodes
- Slurm cluster up and running
- Bash installed on all nodes
- Podman and slirp4netns installed on all nodes
- Kind installed on all nodes
- Kubectl installed on all nodes

The initial setup instructions to ensure the prerequisites can be found in [Setup.md](Setup.md).

## Script: Run Slurm Job
The script [run-workload.sh](run-workload.sh) provides users the option to execute user-defined Kubernetes workloads as batch jobs on a Slurm cluster.
Users can write custom Linux shell script that creates workloads using kubectl.
The script [run-workload.sh](run-workload.sh) handles setting up a temporary Kubernetes cluster inside a container using [Kind](https://github.com/kubernetes-sigs/kind), 
then executes the Kubernetes workload (user-defined workload script), and finally deletes the cluster when the workload is finished.
It supports multi-tenant usage - so multiple users can create multiple clusters and can use them separately. 
Also, a single user can create multiple Slurm jobs leading to multiple clusters in parallel on the same node.


The Kubernetes cluster container shares the current working directory of the host machine. 
Inside the container it is available in `/app`. 
The script [workload-job-pytorch.sh](example-workloads/workload-job-pytorch/workload-job-pytorch.sh) gives an example on how the shared directory may be used.

### User-defined Workload Scripts
As mentioned before, users can write scripts that describe the workload. Inside the script, `kubectl` is available for usage. 
How can the right clusters be selected in case of multiple jobs? 
During creating the Kubernetes cluster a random name is picked for the cluster. 
This name is available in the workload script through the variable `K8S_CLUSTER_NAME` and can be used in `kubectl` to reference the correct cluster e.g. `kubectl get pods --context "$K8S_CLUSTER_NAME"`. 

Another important part of a workload script is that it also **waits for the workloads to be completed** (e.g. by using kubectl wait). 
Otherwise, the cluster will be deleted without finishing the workload.

#### Examples
Workload script examples are included in the directory `example-workloads`: 
- [workload-pod-sysbench.sh](example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh)
- [workload-job-pytorch.sh](example-workloads/workload-job-pytorch/workload-job-pytorch.sh)

### Usage
In general, the script can run without root privileges.
Also, the path to your Kubernetes workload script has to be passed as an argument. Here, the script [workload-pod-sysbench.sh](example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh) is used as an example:
```bash
/bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh
```
To store the stdout and stderr in a file you can add following `tee` command:
```bash
/bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh |& tee log.txt
```

To use Slurm to execute the workload run:
```bash
srun -N1 -c56 /bin/bash run-workload.sh $PWD/example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh
```

## Script: Start Interactive Slurm Job

To set up an interactive Kubernetes cluster in a Slurm job run:

TODO

Ideas:
- Slurm job that creates a cluster (fire and forget) that can be used from login node. 
May need to implement some function to delete the cluster on job cancellation.
- Interactive slum job
## Troubleshooting

### List All Kubernetes Clusters

To list all Kubernetes clusters run:
```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind get clusters
```
To list all Kubernetes nodes run:
```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind get nodes
```


Alternatively, you can gain insight on your existing Kubernetes clusters by listing all Podman containers:
```bash
podman ps -a
```

### Manually Deleting a Kubernetes Cluster 
In case a Slurm job fails, you might encounter a still running Kubernetes cluster. 
To delete this cluster you need to find out the name first.
Then you can run:
```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name "cluster_name"
```
or for some distributions, you might need to use systemd-run to start kind into its own cgroup scope
```bash
KIND_EXPERIMENTAL_PROVIDER=podman systemd-run --scope --user kind delete cluster --name "cluster_name"
```