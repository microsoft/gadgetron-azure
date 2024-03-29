
# Gadgetron in Kubernetes

This repository contains a setup for running a distributed deployment of the [Gadgetron](https://github.com/gadgetron/gadgetron) in a Kubernetes cluster. The setup has been developed for and tested with [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/services/kubernetes-service) but should work on other Kubernetes deploymentes too.

The setup uses [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) to adjust the number of Gadgetron instances (pods) running in the cluster in response to gadgetron activity and it relies on [cluster-autoscaling](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) to adjust the number of nodes. Specifically, an increase reconstruction activity will lead to the deployment of more Gadgetron instances and when the resources on existing nodes are exhausted more will be added. Idle nodes will be removed from the cluster after some idle time. 

Shared files (dependencies and exported data) are stored in persistent volumes, which could be backed by [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/).

The Gadgetron uses a script to discover remote worker nodes. The script is specified in the `GADGETRON_REMOTE_WORKER_COMMAND` environment variable, which references a script added in a ConfigMap. The is also a PreStop lifecycle hook script, which is used to ensure that Gadgetron instances with active connections are not abruptly disconnected. 

## Deployment Instructions

The repository contains a [script](scripts/deploy-aks.sh) for setting up an Azure Kubernetes Service (AKS) cluster. You can use this to deploy a test cluster for the Gadgetron:

```bash
./scripts/deploy-aks.sh -n <NAME OF CLUSTER>
```

Use `./scripts/deploy-aks.sh --help` to see configuration options.

You can also manually deploy the cluster and necessary components:

1. Set up a Kubernets cluster. Please see instructions for [Azure Kubernetes Service (AKS)](aks-setup.md).

1. Deploy [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) to allow metrics collection from the Gadgetron:

    ```bash
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set commonLabels.prometheus=monitor \
        --set prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.prometheus=monitor
    ```

    This will install the operator, Prometheus server, Grafana, etc. 

1. Deploy the [Prometheus Adapter](https://github.com/kubernetes-sigs/prometheus-adapter):

    ```bash
    helm install --namespace monitoring prometheus-adapter prometheus-community/prometheus-adapter -f custom-metrics/custom-metrics.yaml
    ```

    The Prometheus Adapter is responsible for aggregating metrics from Promtheus and exposing them as custom metrics that we can use for scaling the Gadgetron. Be sure to pay attention to the `prometheus.url` parameter in the `custom-metrics.yaml` file. It has to point to the prometheus operator (find it with `kubectl get svc -n monitoring`).

1. Deploy a storage account for the [mrd-storage-server](https://github.com/ismrmrd/mrd-storage-server):

  ```bash
  storageServerSa="${cluster_name}sa"
  storageServerSa="$(echo "$storageServerSa" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
  az storage account create -n "$storageServerSa" -g "$rg_name" -l "$cluster_location"
  kubectl create secret generic storageserversa --from-literal=connectionString="$(az storage account show-connection-string --name "$storageServerSa" | jq -r .connectionString)" --dry-run=client -o yaml | kubectl apply -f -
  ```

  If you choose a different secret name. Make a note of it and supply it when deploying the help chart below.

1. Deploy Gadgetron with helm chart:

    ```bash
    helm install <nameofgadgetroninstance> helm/gadgetron/ --set storage.storageClass=azurefile
    ```

    >Note: Select an appropriate `storageClass` for your Kubernetes setup.


    To use a specific node pool:

    ```bash
    helm install --set nodeSelector.agentpool=userpool <nameofgadgetroninstance> helm/gadgetron/
    ```

    For details on targeting a GPU node pool, see below or [test_values.yml](scripts/test_values.yml)

1. Check that metrics are flowing. After deploying the Gadgetron, it should start emitting metrics and they should be exposed as custom metrics. You can check that you can read them with:

    ```bash
    kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/gadgetron_activity | jq .
    ```

### Realistic Deployment Configuration

The Gadgetron [helm chart](helm/gadgetron) has a number of settings that you will probably need to adjust for your scenario. The defaults will get you started but a more reliastic deployment might have a configuration like this:

```yaml
# Freeze the image version
image:
  repository: ghcr.io/gadgetron/gadgetron/gadgetron_ubuntu_rt_cuda@sha256:7f55c1fd1cdd45c898884265649dedfe85ac297384ec5f096e3da9298fe61a16
hpa:
  maxReplicas: 20
  minReplicas: 1
  targetInstanceUtilization: 500m
  # Between the hours of 7am and 6pm (UTC) on weekdays keep a minimum of 5 replicas 
  schedule:
    up:
      schedule: "0 7 * * 1-5"
      minReplicas: 5
    down:
      schedule: "0 18 * * 1-5"
      minReplicas: 1
# I want to use my GPU nodes
nodeSelector:
  agentpool: userpool
tolerations: 
  - key: "sku"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
storage:
  dependenciesVolumeSize: 20Gi
  # I need a TB to store data
  dataVolumeSize: 1000Gi
  storageClass: azurefile
resources:
  # Make sure you get a GPU allocated
  limits:
    nvidia.com/gpu: 1
  # Each replica must have 16 cores and 32 GB of RAM, the cluster auto scaler will add nodes if needed
  requests:
    cpu: 16000m
    memory: 32Gi
```

## Connecting with port forwarding

Once the Gadgetron deployment is live, you can find the cluster ip address for the Gadgetron with something like:

```bash
kubectl get svc
```

And you can easily open a tunnel from your desktop to the gadgetron with something like:

```bash
kubectl port-forward svc/<helm release>-gadgetron 9002:9002
```

And then connect directly to `localhost:9002`.

## Connecting with SSH jump server

This repo also contains a helm chart and other artifacts for deploying an SSH jump server in the cluster and you can use this jump server to establish an SSH tunnel. Maintaining these tunnels can be cumbersome and **stunnel (see below) is an easier approach**. That said, an SSH jump server may be the only way to access from say an imaging device. 

### Deploy SSH jump server:

> Approach adopted from [https://github.com/kubernetes-contrib/jumpserver](https://github.com/kubernetes-contrib/jumpserver).

First generate some keys for the SSH server and store them in a Kubernetes secret. There is a script for doing this:

```bash
./generate_ssh_keys.sh
```

This script will by default generate RSA, ECDSA, and ED25519 keys. If you would like to restrict or expand the keys generated, add the desired algorithms as arguments, e.g.:

```bash
./generate_ssh_keys.sh rsa ed25519
```

Then store the public key for the user to connect, e.g.:

```bash
kubectl create secret generic sshkey --from-file=authorizedkeys=/home/<myuser>/.ssh/id_rsa.pub 
```

Replace the the public key path with the specific key that you would like to use. Before deploying the SSH jump server you should have two secrets (check with `kubectl get secrets`) in your cluster: `sshkey` and `ssh-server-keys`.

Then deploy the jump server:

```bash
helm install sshjump helm/sshjump
```

Or if you have given the keys other names with a custom ssh key secret:

```bash
helm install --set sshKeySecret=alternative-ssh-secret-name --set sshServerKeysSecret=alternative-keys-secret-name sshjump2 helm/sshjump/
```

### Connecting with SSH to the jump server

The jump sever enables the "standard" Gadgetron connection paradigm through an SSH tunnel. The Gadgetron instances themselves are not directly accessible. Discover the relvant IPs and open a tunnel with:

```bash
#Public (external) IP:
EXTERNALIP=$(kubectl get svc <sshd-jumpserver-svc> --output=json | jq -r .status.loadBalancer.ingress[0].ip)

#Internal (cluster) IP:
GTCLUSTERIP=$(kubectl get svc <gadgetron-frontend> --output=json | jq -r .spec.clusterIP)

#Open tunnel:
ssh -L 9022:${GTCLUSTERIP}:9002 root@${EXTERNALIP}
```

A simpler approach that should also work with most Kubernetes DNS schemes would be:

```bash
ssh -L 9022:<gadgetron-service-name>:9002 root@${EXTERNALIP}
```

## Connecting with stunnel

The repo contains a helm chart for deploying [stunnel](https://stunnel.org) for secure access to the Gadgetron in the cluster. To deploy the `stunnel` server, you must first have some secrets (pre-shared keys). You can generate those and store them as a secret in the cluster with:

```bash
cd stunnel
./create-stunnel-secrets.sh
```

This will create an `stunnel.secrets` file containing 10 client secrets. You can also supply your own file prior to running the script. After running the script confirm that you have an `stunnel` secret in the cluster with `kubectl get secrets`.

If you have deployed the Gadgetron in the cluster with a helm release name of say `gt1`, the DNS name of the gadgetron service would be `gt1-gadgetron` and you can deploy an `stunnel` to interface with that Gadgetron deployment by creating a `values.yaml` file:

```yaml
stunnel:
  secretName: stunnel
  connections:
    gadgetron:
      listenPort: 9002
      connectHost: gt1-gadgetron
      connectPort: 9002
service:
  dnsPrefix: mytunneldnsname
```
The `service.dnsPrefix` is optional, but when deployed in AKS, it will assign a DNS name to the public IP address of the `LoadBalancer` so that you can reference it with something like `mytunneldnsname.westus2.cloudapp.azure.com` instead of the IP address, which may change as you redeploy.

Then deploy the `stunnel` with:

```bash
helm upgrade --install -f values.yaml
```

On some other host on your (on-prem) network, you can then install `stunnel` and create an `stunnel.conf` file:

```
[gadgetron]
client = yes
accept = 9002
connect = <ip or dns name of tunnel service>:9002
PSKsecrets = stunnel.secrets
```

The `stunnel.secrets` file must contain one of the pre-shared secrets created with the `create-stunnel-secrets.sh`, e.g. it could look like:

```
client1:4ZYJY+HoIX1xxZM563VpppejPJNQ4S4Z
```

Start the stunnel with:

```bash
stunnel stunnel.conf
```

And you should now be able to connect to the Gadgetron from port 9002 on the host where you are running the `stunnel` client.

## Connecting with VPN (Azure)

You can use VPN to connect to the Gadgetron in the Kubernetes cluster, it is recommended that you establish a VPN point to site connection. Please consult the [Azure P2S VPN guide](https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-resource-manager-portal). The basic steps are:

1. Create a gateway subnet in your [AKS cluster network](https://docs.microsoft.com/azure/aks/concepts-network).
1. Create a VPN Gateway in the subnet.
1. Obtain/generate keys and [install client software](https://docs.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-configuration-azure-cert).
1. Connect securely using VPN connection.

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
