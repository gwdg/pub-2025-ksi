# Initial Setup
This setup guide describes the required software and necessary configurations for KSI. Run following commands as `root` user, unless stated otherwise.
After the setup is completed, the machine must be rebooted in order for all configurations to take effect.
This guide aims for RHEL 9 based x86 distros and is tested with CentOS Stream 9 (SELinux disabled). 

## Test Setup Versions
We tested this setup with following software versions. 
These are the latest versions at the time of developing this project.
Potentially, newer versions should also work.

| Software      | Version                            | Comment                                        |
|---------------|------------------------------------|------------------------------------------------|
| Linux OS      | CentOS Stream 9                    | Older Linux distros may not support cgroups v2 |
| Slurm         | slurm 23.02.5                      |                                                |
| Podman        | podman version 4.6.1               |                                                |
| slirp4netns   | slirp4netns 1.2.2-1                | Enables rootless container networking          |
| Kind          | kind version 0.20.0                |                                                |
| Kubectl       | Client Version: v1.28.2            |                                                |
| shadow-utils  | shadow-utils 2:4.9-8               | Enables usage of `newuidmap` and `newgidmap`   |
| Bash          | GNU bash, version 5.1.8(1)-release |                                                |


## Check cgroups v2 enabled
```bash
# Source: https://unix.stackexchange.com/a/480748/567139
if [ "$(stat -fc %T /sys/fs/cgroup/)" = "cgroup2fs" ]; then
    echo "cgroups v2 check passed: cgroups v2 is enabled"
else
    echo "cgroups v2 check failed: cgroups v2 is not enabled" >&2
fi
```
### Enable cgroups v2
If cgroups v2 is not enabled, enable it first. To do so, follow these instructions: https://rootlesscontaine.rs/getting-started/common/cgroup2/#enabling-cgroup-v2

## Enable CPU, CPUSET, and I/O Delegation
```bash
# Sources: 
# https://rootlesscontaine.rs/getting-started/common/cgroup2/#enabling-cpu-cpuset-and-io-delegation
# https://kind.sigs.k8s.io/docs/user/rootless/#host-requirements
mkdir -p /etc/systemd/system/user@.service.d
cat >/etc/systemd/system/user@.service.d/delegate.conf <<EOF
[Service]
Delegate=yes
EOF
systemctl daemon-reload
```
> Accrording to [Kind documentation](https://kind.sigs.k8s.io/docs/user/rootless/#host-requirements), this is not enabled by default because “the runtime impact of [delegating the “cpu” controller] is still too high”. Beware that changing this configuration may affect system performance.

## Enable Networking
Enable loading following Linux kernel modules:
```bash
# Source: https://kind.sigs.k8s.io/docs/user/rootless/#host-requirements
cat >/etc/modules-load.d/iptables.conf <<EOF
ip6_tables
ip6table_nat
ip_tables
iptable_nat
EOF
```

## Enable User Namespaces
> Since RHEL 8, the configuration `echo "user.max_user_namespaces=28633" > /etc/sysctl.d/userns.conf` is not required anymore. 
> This was needed for RHEL 7. Source: https://rootlesscontaine.rs/getting-started/common/sysctl/

## Install shadow-utils
shadow-utils enables usage of newuidmap and newgidmap
```bash
# Source: https://rootlesscontaine.rs/getting-started/common/subuid/
dnf install -y shadow-utils
```

## Install Podman
```bash
# slirp4netns needed for rootless container networking
dnf install -y slirp4netns podman
```

## Install Kubectl
```bash
# Source: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

## Install kind
```bash
# Source: https://kind.sigs.k8s.io/docs/user/quick-start/
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-arm64
chmod +x ./kind
mv ./kind /usr/local/bin/kind
```

## Test Kind
Finally, to test Kind (without Slurm), run following as an unprivileged user:
```bash
# Create kind Kubernetes cluster
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name kind

kubectl get nodes --context kind-kind
kubectl cluster-info --context kind-kind

# Run following to delete kind Kubernetes cluster
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name kind
```

## Reboot
After the setup is completed, the machine must be rebooted in order for all configurations to take effect.


## Common Issues

### rootless provider requires setting systemd property "Delegate=yes" - however "Delegate=yes" is already set

```
kind create cluster --name 618b9
using podman due to KIND_EXPERIMENTAL_PROVIDER
enabling experimental podman provider
ERROR: failed to create cluster: running kind with rootless provider requires setting systemd property "Delegate=yes", see https://kind.sigs.k8s.io/docs/user/rootless/
```

**Fix:** On some distributions, you might need to use systemd-run to start kind into its own cgroup scope:

```bash
KIND_EXPERIMENTAL_PROVIDER=podman systemd-run --scope --user kind create cluster
```


### "run/user/0" is not owned by the current user
```
ERRO[0000] XDG_RUNTIME_DIR "run/user/0" is not owned by the current user.
```

**Fix:** Use SSH to login or to switch user instead of `su username`.
- https://learn.redhat.com/t5/Containers-DevOps-OpenShift/Podman-Rootless/td-p/31095
- https://rootlesscontaine.rs/getting-started/common/login/
