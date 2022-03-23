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
  --verbose, -v                       Verbose output
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
    --verbose|-v)
      verbose=1
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


rg_name="${cluster_name}-rg"
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
