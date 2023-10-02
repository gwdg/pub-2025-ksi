# Kubernetes Slurm Integration based on Kind

This repository covers running Kubernetes workloads in a Slurm cluster. This approach uses Kind (Kubernetes in Docker) to set up temporary Kubernetes clusters. Kind supports rootless Podman that is a [valid choice for HPC use cases](https://www.redhat.com/en/blog/podman-paves-road-running-containerized-hpc-applications-exascale-supercomputers).

## Prerequisites

- All nodes run RHEL 9 based x86 distro (tested with CentOS Stream 9)
- cgroups v2 enabled on all nodes
- CPU delegation enabled on all nodes
- Slurm cluster up and running
- Bash installed on all nodes
- Podman and slirp4netns installed on all nodes
- Kind installed on all nodes
- Kubectl installed on all nodes

A pad with further instructions to install required software is available [here](https://pad.gwdg.de/9kSkGV-dTiyQ0kPdX50K0A?both#).

## Script: Batch Slurm Job
The script `slurm-kind.sh` provides users the option to execute user-defined Kubernetes workloads as batch jobs on a Slurm cluster.
Users can write a Linux shell script that creates workloads using kubectl.
`slurm-kind.sh` handles setting up a temporary Kubernetes cluster inside a container, 
then executes the Kubernetes workload, and finally deletes the cluster when the workload is finished.
It supports multi-tenant usage - multiple users can create multiple clusters and can use them separately. 
Also, a single user can create multiple Slurm jobs leading to multiple clusters in parallel.

In general, the script can run without root privileges. 
Also, the path too your Kubernetes workload script has to be passed as an argument:
```bash
/bin/bash slurm-kind.sh $PWD/example-workloads/workload-pod-sysbench.sh
```

To use Slurm to execute the workload run:
```bash
srun -N1 -c56 /bin/bash slurm-kind.sh $PWD/example-workloads/workload-pod-sysbench.sh
```

### User-defined Workload Scripts
As mentioned before, users can write scripts that describe the workload. Inside the script, `kubectl` is available for usage. 
How can the right clusters be selected in case of multiple jobs? 
During creating the Kubernetes cluster a random name is picked for the cluster. 
This name is available in the workload script through the variable `K8S_CLUSTER_NAME` and can be used in `kubectl` to reference the correct cluster e.g. `kubectl get pods --context "$K8S_CLUSTER_NAME"`. 

Another important part of a workload script is that it also waits for the workloads to be completed (e.g. by using kubectl wait). 
Otherwise, the cluster will be deleted without finishing the workload.

#### Examples
Have a look at the scripts in the directory `example-workloads` e.g. [workload-pod-sysbench.sh](example-workloads/workload-pod-sysbench.sh)

## Script: Interactive Slurm Job

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