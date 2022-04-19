# Azure Kubernetes Service (AKS) for Gadgetron

These instructions follow the basic AKS setup instructions with a few variations to enable easy deployment of the [Gadgetron](https://github.com/gadgetron/gadgetron).

The installations are assuming you are on Linux or in Windows Subsystem for Linux (WSL), but they should work (possibly with minor tweaks) on other platforms.

## Pre-requisites

1. [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
1. `kubectl`, which can be installed with `az aks install-cli`.
1. `helm` (version 3). Follow the standard [helm install instructions](https://helm.sh/docs/intro/install/).

## Deploy AKS cluster

```bash
# Some settings
resourceGroupName="my-gadgetron-resource-group"
clusterName="mygadgetroncluster"
location="westus2"
vmSize="Standard_F4"
maxNodeCount="10"

# First create a resource group
az group create --name $resourceGroupName --location $location

# Now create the AKS cluster and enable the cluster autoscaler
az aks create \
  --resource-group $resourceGroupName \
  --name $clusterName \
  --node-count 1 \
  --node-vm-size $vmSize \
  --vm-set-type VirtualMachineScaleSets \
  --load-balancer-sku standard \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count $maxNodeCount \
  --enable-managed-identity \
  --generate-ssh-keys
```

Get credentials:

```bash
az aks get-credentials --resource-group $resourceGroupName --name $clusterName
```

Make sure you can communicate with the cluster, e.g.:

```bash
kubectl get nodes
```

## Add and use new node pool

To add a node pool with a specific VM size, e.g. `Standard_D14_v2`:

```bash
az aks nodepool add \
  --resource-group $resourceGroupName \
  --cluster-name $clusterName \
  --name mynodepool \
  --node-vm-size Standard_D14_v2 \
  --node-count 1 \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 
```

If you are adding a GPU node pool, please follow instructions on [GPU clusters](https://docs.microsoft.com/en-us/azure/aks/gpu-cluster). Specifically, add appropriate custom headers and taints to the node pools:

```
az aks nodepool add \
  --resource-group $resourceGroupName \
  --cluster-name $clusterName \
  --name mynodepool \
  --node-vm-size Standard_NC6s_v3 \
  --node-count 1 \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3 \
  --node-taints sku=gpu:NoSchedule \
  --aks-custom-headers UseGPUDedicatedVHD=true
```

And then to deploy a new gagetron deployment to that node pool:

```
helm install --set nodeSelector.agentpool=mynodepool mygadgetrondeployment helm/gadgetron/
```

If this is a GPU node pool, you need to add tolerances for the applied taints, see for example [test_values.yml](scripts/test_values.yml).

To delete the node pool, first remove any deployment on the node pool and then:

```bash
az aks nodepool delete \
  --resource-group $resourceGroupName \
  --cluster-name $clusterName \
  --name mynodepool
```

## Logging with Log Analytics

When you are using AKS, you can easily monitor your Gadgetron deployment using [Azure Monitor Container Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview). When you [enable Container Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-onboard), all telemetry and logs with be collected in a [Log Analytics Workspace](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace), where you can use the [Kusto query language](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/concepts/) to explore and aggregate data. Please consult the [Container Insights documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview).

To connect an existing cluster to Azure Monitor, enable the monitoring add-on:

```bash
az aks enable-addons -a monitoring -n <cluster name> -g <cluster resource group> --workspace-resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<workspace rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace name>"
```

Once logs start flowing into the workspace you can aggregate with something like:

```kusto
let contIds = ContainerInventory | where ContainerHostname startswith "nameof-deployment-gadgetron" | distinct ContainerID | project ContainerID;
ContainerLog | where ContainerID in (contIds) | order by TimeGenerated desc | project ContainerID, LogEntry
```

In addition to aggregating logs, you have the ability to monitor metrics (e.g. CPU or memory consumption). Check the [documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview) for details.