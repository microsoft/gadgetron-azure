# Rancher RKE setup

[Rancher Kubernetes Engine (RKE)](https://rancher.com/docs/rke/latest/en/) is a simple CNCF-certified Kubernetes distribution, which runs entirely within Docker. It makes it easy to setup Kubernetes as long as you are running a supported version of Docker. Be sure to check the latest version of the [installation instructions](https://rancher.com/docs/rke/latest/en/installation/) for details.

Download the latest [RKE release](https://github.com/rancher/rke/releases) and then proceed with installation, e.g.:

```bash
# Replace version with correct version for your platform
wget https://github.com/rancher/rke/releases/download/v1.0.16/rke_linux-amd64
sudo mv rke_linux-amd64 /usr/bin/rke
sudo chmod +x /usr/bin/rke
```

Create a new configuration file:

```bash
rke config --name cluster.ym
```

Follow the prompts to produle a configuration file and then start cluster with:

```bash
rke up
```

Now you should be able to interact with the cluster:

```bash
export KUBECONFIG=~/kube_config_cluster.yml
kubectl get nodes
```

Rancher RKE does not have a default `StorageClass`, which is needed for the Gadgetron, so you could install something like [Longhorn](https://longhorn.io/)

```bash
git clone https://github.com/longhorn/longhorn && cd longhorn
kubectl create namespace longhorn-system
helm install longhorn ./chart --namespace longhorn-system
```

And now when you install the Gadgetron with the helm chart be sure to use Longhorn as the storage class:

```bash
helm install gt1 helm/gadgetron --set storage.storageClass=longhorn
```