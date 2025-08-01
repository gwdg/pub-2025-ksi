# Initial Setup
This setup guide describes the required software and necessary configurations for KSI. Run following commands as `root` user, unless stated otherwise.
After the setup is completed, the machine must be rebooted in order for all configurations to take effect.
This guide aims for RHEL 9 based x86 distros and is tested with CentOS Stream 9 (SELinux disabled). 

The commands listed below should be executed as root unless stated otherwise.
This setup has to be performed on every worker node in the cluster.

## Test Setup Versions
We tested this setup with following software versions. 
Potentially, newer versions should also work.

| Software     | Version                            | Comment                                        |
|--------------|------------------------------------|------------------------------------------------|
| Linux OS     | RHEL-like 9 (Kernel 5.14 or newer) | Older Linux distros may not support cgroups v2 |
| Slurm        | slurm 23.02.5                      |                                                |
| Nerdctl      | v2.1.3                             |                                                |
| containerd   | v1.7.27                            |                                                |
| rootlesskit  | v2.3.5                             |                                                |
| slirp4netns  | v1.3.2                             | Enables rootless container networking          |
| bypass4netns | v0.4.2                             | Enables rootless container networking          |
| Kind         | 0.29.0                             |                                                |
| Kubectl      | Client Version: v1.33.3            |                                                |
| libseccomp   | 2.5.2                              | Required by bypass4netns                       |
| Liqoctl      | v1.0.1                             |                                                |


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
> According to [Kind documentation](https://kind.sigs.k8s.io/docs/user/rootless/#host-requirements), this is not enabled by default because “the runtime impact of [delegating the “cpu” controller] is still too high”. Beware that changing this configuration may affect system performance.

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

## Enable Rootless Containerd

### Install Containerd
```bash
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
# if config-manager is not available run
dnf install 'dnf-command(config-manager)'

dnf install -y containerd.io
```

### Install Build Tools and Dependencies
```bash
dnf install git go make iptables libseccomp-devel yq jq
```

### Install Rootlesskit
```bash
git clone https://github.com/rootless-containers/rootlesskit.git
cd rootlesskit
make
make install
```

### Install Nerdctl
```bash
git clone https://github.com/containerd/nerdctl.git
cd nerdctl
make
make install
```

### Install CNI Plugins
```bash
dnf install -y containernetworking-plugins slirp4netns
```

### Set up Rootless Containerd
Switch to the rootless user that will run rootless containers.
```bash
containerd-rootless-setuptool.sh install
```
If you switched to that user via `su` or `sudo` this might not work as certain environment variables are not set up.
Either login to the user directly, for example via ssh or run the following commands:
```bash
export DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/{$UID}/bus'
export XDG_RUNTIME_DIR="/run/user/{$UID}"
```
As root run the following command:
```bash
loginctl enable-linger YOUR_ROOTLESS_USER
```
Then try to run again:
```bash
containerd-rootless-setuptool.sh install
```
If there is an error regarding newuidmap, run as root the following and try again:
```bash
chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap
```

### Install Bypass4netns
```bash
git clone https://github.com/rootless-containers/bypass4netns.git
cd bypass4netns
make
make install
```

As rootless user run the following command:
```bash
containerd-rootless-setuptool.sh install-bypass4netns
```

### Test Rootless Containerd
Run as the rootless user:
```bash
nerdctl run -it --rm -p 8080:80 --annotation nerdctl/bypass4netns=true alpine
```
If you haven't rebooted, you need to manually load the modules:
```bash
modprobe -a ip_tables ip6_tables iptable_nat ip6table_nat
```

## Install Rootless Kubernetes

### Install Kubectl
```bash
# Source: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### Install kind
```bash
# Source: https://kind.sigs.k8s.io/docs/user/quick-start/
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind
```

### Test Kind
To test Kind (without Slurm), run following as the rootless user:
```bash
# Create kind Kubernetes cluster
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --name kind

kubectl get nodes --context kind-kind
kubectl cluster-info --context kind-kind

# Run following to delete kind Kubernetes cluster
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind delete cluster --name kind
```

### Download KSI
```bash
git clone https://github.com/gwdg/pub-2025-ksi.git
```

### Enable bypass4netns annotations in Kind
The annotation `nerdctl/bypass4netns=true` must be passed to nerdctl whenever Kind creates a container via nerdctl.
However, to our knowledge, Kind does not support passing annotations to the underlying container runtime.
As a workaround we have created a wrapper script for nerdctl, [nerdctl-wrapper.sh](nerdctl-wrapper.sh), which injects the annotation.
To install the wrapper execute the following commands:
```bash
# Check where your nerdctl binary is, assuming it is in /usr/local/bin below
which nerdctl

mv /usr/local/bin/nerdctl /usr/local/bin/nerdctl.real

cd ksi # cd to the KSI directory
cp nerdctl-wrapper.sh /usr/local/bin/nerdctl
chmod +x /usr/local/bin/nerdctl
```

Rerun the test code and watch for nerdctl-wrapper.log file to appear under $HOME.
If the file appears and shows that the annotation was injected, the workaround is successful and KSI is ready to be used.

## Common Issues

### rootless provider requires setting systemd property "Delegate=yes" - however "Delegate=yes" is already set

```
kind create cluster --name 618b9
using nerdctl due to KIND_EXPERIMENTAL_PROVIDER
enabling experimental nerdctl provider
ERROR: failed to create cluster: running kind with rootless provider requires setting systemd property "Delegate=yes", see https://kind.sigs.k8s.io/docs/user/rootless/
```

**Fix:** On some distributions, you might need to use systemd-run to start kind into its own cgroup scope:

```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl systemd-run --scope --user kind create cluster
```

### "run/user/0" is not owned by the current user
```
ERRO[0000] XDG_RUNTIME_DIR "run/user/0" is not owned by the current user.
```

**Fix:** Use SSH to login or to switch user instead of `su username`.
- https://learn.redhat.com/t5/Containers-DevOps-OpenShift/Podman-Rootless/td-p/31095
- https://rootlesscontaine.rs/getting-started/common/login/
