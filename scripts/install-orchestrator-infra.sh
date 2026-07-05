#!/bin/bash

# install-orchestrator-infra.sh: installs the RHDH orchestrator infrastructure
# chart, which provisions the Serverless and Serverless Logic operators.
# Only runs when INSTALL_ORCHESTRATOR=true.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPTS_DIR/common.sh"

ORCHESTRATOR_INFRA_CHART="oci://quay.io/rhdh/orchestrator-infra-chart"
ORCHESTRATOR_INFRA_RELEASE="orchestrator-infra"

install_orchestrator_infra() {
  local version="${ORCHESTRATOR_INFRA_VERSION:?ORCHESTRATOR_INFRA_VERSION must be set when INSTALL_ORCHESTRATOR=true}"

  if helm status "$ORCHESTRATOR_INFRA_RELEASE" >/dev/null 2>&1; then
    log "Orchestrator infra release '$ORCHESTRATOR_INFRA_RELEASE' already installed — upgrading..."
  else
    log "Installing orchestrator infrastructure (Serverless + Serverless Logic operators)..."
  fi

  if ! helm upgrade --install "$ORCHESTRATOR_INFRA_RELEASE" "$ORCHESTRATOR_INFRA_CHART" \
      --version "$version" \
      --set serverlessLogicOperator.subscription.spec.installPlanApproval=Automatic \
      --set serverlessOperator.subscription.spec.installPlanApproval=Automatic \
      --timeout 10m \
      --wait; then
    log "Failed to install orchestrator infrastructure chart."
    log_fail
    exit 1
  fi
  log "Orchestrator infrastructure installed successfully."

  log "Waiting for SonataFlow CRD to be registered by the Serverless Logic Operator..."
  local elapsed=0
  local crd_timeout=300
  while (( elapsed < crd_timeout )); do
    if kubectl api-resources --api-group=sonataflow.org 2>/dev/null | grep -q SonataFlowPlatform; then
      log "SonataFlow CRD is available."
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    log "Still waiting for SonataFlow CRD... (${elapsed}s/${crd_timeout}s)"
  done
  log "Timed out waiting for SonataFlow CRD after ${crd_timeout}s."
  log_fail
  exit 1
}

install_orchestrator_infra
