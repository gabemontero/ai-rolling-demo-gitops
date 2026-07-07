#!/bin/bash

# helm-install.sh: deploys RHDH via Helm directly (no ArgoCD).
# Used when SKIP_GITOPS_SETUP=true as an alternative to apply-argocd-application.sh.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPTS_DIR/common.sh"

POLL_INTERVAL=10
DEPLOY_TIMEOUT=900
EXPECTED_CONTAINERS=3

# wait_for_deployment: waits for the RHDH deployment to reach the expected
# container count and complete its rollout. The deployment goes through two
# revisions — the initial one from Helm, then a second once the dynamic-plugins
# init container finishes and the pod spec is updated to include the sidecar
# containers. This function watches for that final state.
wait_for_deployment() {
  local namespace="$1"
  local deploy_name="$2"
  local elapsed=0

  log "Waiting for deployment '$deploy_name' to appear..."
  while (( elapsed < DEPLOY_TIMEOUT )); do
    if kubectl get deployment "$deploy_name" -n "$namespace" >/dev/null 2>&1; then
      break
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  if ! kubectl get deployment "$deploy_name" -n "$namespace" >/dev/null 2>&1; then
    log "Timed out waiting for deployment '$deploy_name' to appear."
    log_fail
    return 1
  fi

  log "Waiting for deployment to reach $EXPECTED_CONTAINERS containers..."
  while (( elapsed < DEPLOY_TIMEOUT )); do
    local container_count
    container_count=$(kubectl get deployment "$deploy_name" -n "$namespace" \
      -o jsonpath='{.spec.template.spec.containers}' 2>/dev/null | jq 'length' 2>/dev/null)
    if [[ "$container_count" -ge "$EXPECTED_CONTAINERS" ]]; then
      log "Deployment has $container_count containers — waiting for rollout to complete..."
      break
    fi
    log "Deployment has ${container_count:-0}/$EXPECTED_CONTAINERS containers. Waiting..."
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  log "Running rollout status watch..."
  local remaining=$((DEPLOY_TIMEOUT - elapsed))
  if (( remaining < 300 )); then
    remaining=300
  fi
  if ! kubectl rollout status deployment/"$deploy_name" -n "$namespace" --timeout="${remaining}s"; then
    log "Deployment rollout did not complete in time."
    log_fail
    return 1
  fi
  log "Deployment '$deploy_name' is fully rolled out."
}

helm_install_rhdh() {
  local rhdh_namespace="${RHDH_NAMESPACE:-rolling-demo-ns}"
  local argocd_app_name="${ARGOCD_APP_NAME:-rolling-demo}"
  local chart_dir="$GITOPS_DIR/charts/rhdh"
  local deploy_name="${argocd_app_name}-backstage"

  log "Adding RHDH Helm repository..."
  if ! helm repo add rhdh https://redhat-developer.github.io/rhdh-chart/ 2>&1 | grep -v "already exists" ; then
    log "Failed to add RHDH Helm repo."
    log_fail
    exit 1
  fi
  helm repo update rhdh >/dev/null 2>&1

  log "Building Helm chart dependencies..."
  if ! helm dependency build "$chart_dir"; then
    log "Failed to build Helm dependencies."
    log_fail
    exit 1
  fi

  log "Installing/upgrading RHDH Helm release '$argocd_app_name' in namespace '$rhdh_namespace'..."
  local helm_args=(
    upgrade --install "$argocd_app_name" "$chart_dir"
    --namespace "$rhdh_namespace"
    --create-namespace
    --set "global.clusterRouterBase=$RHDH_CLUSTER_ROUTER_BASE"
    --set "global.isSecondaryInstance=${IS_SECONDARY_INSTANCE:-false}"
    --set "rhoai.enabled=false"
    --timeout 10m
  )

  if [[ "${INSTALL_ORCHESTRATOR}" == "true" ]]; then
    helm_args+=(--set "orchestrator.enabled=true")
    helm_args+=(--set "backstage.orchestrator.enabled=true")
  fi

  if ! helm "${helm_args[@]}"; then
    log "Helm install/upgrade failed."
    log_fail
    exit 1
  fi
  log "Helm release applied. Waiting for RHDH deployment to stabilize..."

  if ! wait_for_deployment "$rhdh_namespace" "$deploy_name"; then
    exit 1
  fi
  log "RHDH Helm release deployed successfully."
}

helm_install_rhdh
