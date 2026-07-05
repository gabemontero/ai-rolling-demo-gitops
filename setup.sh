#!/bin/bash

# SCRIPTS_DIR: the scripts/ subdirectory relative to this file
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"

source "$SCRIPTS_DIR/common.sh"

source "$SCRIPTS_DIR/private-env"

# Recompute URL vars using the actual route name: {{ .Release.Name }}-backstage
# The release name equals ARGOCD_APP_NAME, so both namespace and app name affect the URL.
RHDH_BASE_URL="https://${ARGOCD_APP_NAME}-backstage-${RHDH_NAMESPACE}.${RHDH_CLUSTER_ROUTER_BASE}"
RHDH_CALLBACK_URL="${RHDH_BASE_URL}/api/auth/oidc/handler/frame"
export RHDH_BASE_URL RHDH_CALLBACK_URL

# check_tools: verifies that all required CLI tools are installed
check_tools() {
  local missing=()
  local tools=("oc" "kubectl" "yq" "openssl" "envsubst")

  if [[ "${SKIP_GITOPS_SETUP}" != "true" ]]; then
    tools+=("argocd")
  fi
  if [[ "${SKIP_PIPELINES_SETUP}" != "true" ]]; then
    tools+=("cosign")
  fi
  tools+=("helm")

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log "'$tool' is not installed or not in PATH."
      missing+=("$tool")
    else
      log "'$tool' is installed."
    fi
  done
  if (( ${#missing[@]} )); then
    log "Missing required tools: ${missing[*]}"
    log_fail
    exit 1
  fi
}

log "Setting Up Rolling Demo Environment..."
log "Checking if all required tools are installed..."
check_tools

# Validate required env vars
required_vars=(
  GITOPS_REPO_URL
  GITOPS_TARGET_REVISION
  RHDH_CLUSTER_ROUTER_BASE
  GITOPS_GIT_ORG
  GITHUB_APP_APP_ID
  GITHUB_APP_CLIENT_ID
  GITHUB_APP_CLIENT_SECRET
  GITHUB_APP_WEBHOOK_URL
  GITHUB_APP_WEBHOOK_SECRET
  GITHUB_APP_PRIVATE_KEY
  BACKEND_SECRET
  RHDH_CALLBACK_URL
  POSTGRESQL_POSTGRES_PASSWORD
  POSTGRESQL_USER_PASSWORD
  QUAY_DOCKERCONFIGJSON
  KEYCLOAK_METADATA_URL
  KEYCLOAK_CLIENT_ID
  KEYCLOAK_REALM
  KEYCLOAK_BASE_URL
  KEYCLOAK_LOGIN_REALM
  KEYCLOAK_CLIENT_SECRET
  VLLM_URL
  VLLM_API_KEY
  VALIDATION_PROVIDER
  VALIDATION_MODEL_NAME
)
if [[ "${SKIP_RHOAI_SETUP}" != "true" ]]; then
  required_vars+=(ODH_SETUP_DIR)
fi
if [[ "${SKIP_GITOPS_SETUP}" != "true" ]]; then
  required_vars+=(ARGOCD_USER)
fi
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    log "Error: $var is not set. Exiting..."
    log_fail
    exit 1
  fi
done

# skip operators and RHOAI installation if that's the case
if [[ "${SKIP_INSTALL_DEPS}" == "true" ]]; then
  log "SKIP_INSTALL_DEPS=true — skipping operator/instance installation."
else
  bash "$SCRIPTS_DIR/install-operators.sh"
fi
if [[ "${SKIP_RHOAI_SETUP}" == "true" ]]; then
  log "SKIP_RHOAI_SETUP=true — skipping ODH Kubeflow Model Registry setup."
else
  bash "$SCRIPTS_DIR/setup-rhoai.sh"
fi

# source other setup scripts to create namespaces, service accounts, secrets, and ArgoCD setup
if [[ "${SKIP_GITOPS_SETUP}" == "true" ]]; then
  log "SKIP_GITOPS_SETUP=true — skipping ArgoCD setup."
else
  source "$SCRIPTS_DIR/setup-argocd.sh"
fi
source "$SCRIPTS_DIR/setup-namespaces.sh"
source "$SCRIPTS_DIR/setup-sa-tokens.sh"
source "$SCRIPTS_DIR/setup-secrets.sh"

# install orchestrator infrastructure (Serverless + Serverless Logic operators)
if [[ "${INSTALL_ORCHESTRATOR}" == "true" ]]; then
  bash "$SCRIPTS_DIR/install-orchestrator-infra.sh"
else
  log "INSTALL_ORCHESTRATOR is not true — skipping orchestrator infrastructure."
fi

# deploy RHDH and configure pipelines
if [[ "${SKIP_PIPELINES_SETUP}" == "true" ]]; then
  log "SKIP_PIPELINES_SETUP=true — skipping Tekton Pipelines setup."
else
  bash "$SCRIPTS_DIR/setup-pipelines.sh"
fi
if [[ "${SKIP_GITOPS_SETUP}" == "true" ]]; then
  log "SKIP_GITOPS_SETUP=true — deploying RHDH via Helm (no ArgoCD)."
  if ! bash "$SCRIPTS_DIR/helm-install.sh"; then
    exit 1
  fi
else
  bash "$SCRIPTS_DIR/apply-argocd-application.sh"
fi

# deploy SonataFlow agent-approval workflow (requires orchestrator + RHDH running)
if [[ "${INSTALL_ORCHESTRATOR}" == "true" && -n "${AUGMENT_PLUGINS_DIR:-}" ]]; then
  bash "$SCRIPTS_DIR/deploy-agent-approval-workflow.sh"
else
  if [[ "${INSTALL_ORCHESTRATOR}" == "true" ]]; then
    log "AUGMENT_PLUGINS_DIR not set — skipping agent-approval workflow deployment."
  fi
fi

log "Rolling Demo Setup Completed Successfully!"
