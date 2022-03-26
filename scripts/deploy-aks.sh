#!/bin/bash

set -euo pipefail

system_node_vm_size="Standard_DS2_v2"
user_node_vm_size="Standard_F4s_v2"
cluster_location="westus2"

usage()
{
  cat << EOF

A script to deploy an example AKS cluster suitable for running the Gadgetron.

Usage: $0 [options]

Options:
  --name,-n <cluster name>            Name of cluster
  --location,-l <cluster location>    Location of cluster (default: ${cluster_location})
  --system-vm-size,-s <node size>     The size of the system VMs (default: ${system_node_vm_size})
  --user-vm-size,-u <node size>       The size of the user VMs (default: ${user_node_vm_size})
  -h, --help                          Brings up this menu
EOF
}

cluster_name=""
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    --name|-n)
      cluster_name="${2}"
      shift
      shift
      ;;
    --location|-l)
      cluster_location="${2}"
      shift
      shift
      ;;
    --system-vm-size|-s)
      system_node_vm_size="${2}"
      shift
      shift
      ;;
    --user-vm-size|-u)
      user_node_vm_size="${2}"
      shift
      shift
      ;;
    -h|--help)
      usage
      exit
      ;;
    *)
      echo "ERROR: unknown option \"$key\""
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$cluster_name" ]]; then
  echo "You must provide a cluster name"
  usage
  exit 1
fi

testEnvironmentName
loga_name="${cluster_name}-logs"
kubernetes_version="1.23.3"
system_nodepool_name="system"
user_nodepool_name="userpool"

if [[ -z "$(az account show --query "environmentName")" ]]; then
  echo "You are not logged in. Please use 'az login'"
  exit 1
fi

# This is the resource group where we will keep the main AKS related resources
az group create -l "$cluster_location" -n "$rg_name" > /dev/null

# Log analytics workspace for monitoring
az monitor log-analytics workspace create -n "$loga_name" -g "$rg_name" --sku "PerGB2018" > /dev/null
workspace_id="$(az monitor log-analytics workspace show -n "$loga_name" -g "$rg_name" | jq -r .id)"


# Is this a create or update?
if [[ -n "$(az aks list | jq --arg cluster "$cluster_name" '.[] | select(.name == $cluster)')" ]]; then
  echo "Cluster exists. Skipping."

  # Enable addons
  if [[ $(az aks show -n "$cluster_name" -g "$rg_name" | jq -r '.addonProfiles.omsagent.enabled') != "true" ]]; then
    az aks enable-addons -a monitoring -n "$cluster_name" -g "$rg_name" --workspace-resource-id "$workspace_id"
  fi
else
  az aks create \
    --resource-group "$rg_name" \
    --location "$cluster_location" \
    --name "$cluster_name" \
    --enable-addons monitoring \
    --workspace-resource-id "$workspace_id" \
    --kubernetes-version "$kubernetes_version" \
    --enable-cluster-autoscaler \
    --node-count 1 \
    --min-count 1 \
    --max-count 3 \
    --nodepool-name "$system_nodepool_name" \
    --node-vm-size "$system_node_vm_size" \
    --load-balancer-sku standard \
    --generate-ssh-keys
fi

az aks get-credentials -n "$cluster_name" -g "$rg_name" --overwrite-existing

# Does the pool exist, if so update, otherwise create
if [[ -n "$(az aks nodepool list --cluster-name "$cluster_name" -g "$rg_name" | jq --arg pool "$user_nodepool_name" '.[] | select(.name == $pool)')" ]]; then
    echo "Nodepool exists. Skipping."
else
    az aks nodepool add -n "$user_nodepool_name" --cluster-name "$cluster_name" -g "$rg_name" \
        --kubernetes-version "$kubernetes_version" \
        --enable-cluster-autoscaler \
        --node-count 1 \
        --min-count 0 \
        --max-count 10 \
        --node-vm-size "$user_node_vm_size" 
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set commonLabels.prometheus=monitor \
    --set nodeSelector.agentpool=system \
    --set prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.prometheus=monitor

helm upgrade --install --namespace monitoring prometheus-adapter prometheus-community/prometheus-adapter -f "$(dirname "$0")/../custom-metrics/custom-metrics.yaml" --set nodeSelector.agentpool=system 

for wait in {0..10}; do
    if kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 2>&1 >/dev/null; then
        break
    else
        if [[ "${wait}" == "10" ]]; then
            echo "Custom metrics failed to deploy"
            exit 1
        else
            sleep 10
        fi
    fi
done

storageServerSa="${cluster_name}sa"
storageServerSa="$(echo "$storageServerSa" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
az storage account create -n "$storageServerSa" -g "$rg_name" -l "$cluster_location"
kubectl create secret generic storageserversa --from-literal=connectionString="$(az storage account show-connection-string --name "$storageServerSa" | jq -r .connectionString)" --dry-run=client -o yaml | kubectl apply -f -
