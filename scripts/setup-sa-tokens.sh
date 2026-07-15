#!/bin/bash

# create_sa_tokens: creates rhdh & k8s sa and their tokens
create_sa_tokens() {
  local namespace="$1"

  # k8s-sa is used for kubernetes plugins
  kubectl create serviceaccount k8s-sa -n "$namespace" >/dev/null 2>&1 || log "'k8s-sa' already exists."
  # rhdh-sa is used as static token for backstage
  kubectl create serviceaccount rhdh-sa -n "$namespace" >/dev/null 2>&1 || log "'rhdh-sa' already exists."
  # mcp-actions-sa is used for mcp actions in backstage
  kubectl create serviceaccount mcp-actions-sa -n "$namespace" >/dev/null 2>&1 || log "'mcp-actions-sa' already exists."

  # assigning the necessary roles
  log "Creating role binding for 'k8s-sa'..."
  kubectl create rolebinding k8s-admin-binding \
    --clusterrole=admin \
    --serviceaccount="$namespace:k8s-sa" \
    --namespace="$namespace" >/dev/null 2>&1 || log "Role binding already exists."
  kubectl create rolebinding k8s-reader-binding \
    --clusterrole=cluster-reader \
    --serviceaccount="$namespace:k8s-sa" \
    --namespace="$namespace" >/dev/null 2>&1 || log "Role binding already exists."

  log "Creating token for 'k8s-sa' (1 year)..."
  K8S_CLUSTER_TOKEN=$(kubectl create token k8s-sa -n "$namespace" --duration 8760h 2>/dev/null)
  log "Creating token for 'rhdh-sa' (1 year)..."
  RHDH_SA_TOKEN=$(kubectl create token rhdh-sa -n "$namespace" --duration 8760h 2>/dev/null)
  log "Creating token for 'mcp-actions-sa' (1 year)..."
  MCP_TOKEN=$(kubectl create token mcp-actions-sa -n "$namespace" --duration 8760h 2>/dev/null)

  export K8S_CLUSTER_TOKEN
  export RHDH_SA_TOKEN
  export MCP_TOKEN

  log "Service accounts and tokens created."
}

log "Creating k8s and RHDH SA tokens..."
create_sa_tokens "$RHDH_NAMESPACE"
