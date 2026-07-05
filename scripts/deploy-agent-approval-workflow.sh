#!/bin/bash

# deploy-agent-approval-workflow.sh: deploys the SonataFlow agent-approval
# workflow CR from the local rhdh-plugins clone. Only runs when
# INSTALL_ORCHESTRATOR=true and AUGMENT_PLUGINS_DIR is set.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPTS_DIR/common.sh"

WORKFLOW_SUBPATH="workspaces/augment/workflows/agent-approval"

deploy_agent_approval_workflow() {
  local workflow_dir="${AUGMENT_PLUGINS_DIR:?AUGMENT_PLUGINS_DIR must be set when deploying agent-approval workflow}/${WORKFLOW_SUBPATH}"
  local rhdh_namespace="${RHDH_NAMESPACE:-rolling-demo-ns}"
  local argocd_app_name="${ARGOCD_APP_NAME:-rolling-demo}"
  local backstage_backend="http://${argocd_app_name}-backstage.${rhdh_namespace}.svc.cluster.local:7007"

  if [[ ! -d "$workflow_dir" ]]; then
    log "Workflow directory not found: $workflow_dir"
    log_fail
    exit 1
  fi

  local sw_file="$workflow_dir/agent-approval.sw.yaml"
  local props_file="$workflow_dir/application.properties"
  local schema_file="$workflow_dir/schemas/agent-approval-input.json"
  local spec_file="$workflow_dir/specs/augment-agent-lifecycle.yaml"

  for f in "$sw_file" "$props_file" "$schema_file" "$spec_file"; do
    if [[ ! -f "$f" ]]; then
      log "Required workflow file not found: $f"
      log_fail
      exit 1
    fi
  done

  # Derive OIDC base URL and token path from KAGENTI_TOKEN_ENDPOINT
  # e.g. https://keycloak.example.com/realms/kagenti/protocol/openid-connect/token
  #   -> base: https://keycloak.example.com
  #   -> path: /realms/kagenti/protocol/openid-connect/token
  local kagenti_token_endpoint="${KAGENTI_TOKEN_ENDPOINT:-}"
  local oidc_base_url="" oidc_token_path=""
  if [[ -n "$kagenti_token_endpoint" ]]; then
    oidc_token_path="/${kagenti_token_endpoint#*//*.*/}"
    oidc_base_url="${kagenti_token_endpoint%%/realms/*}"
  fi

  log "Deploying agent-approval SonataFlow workflow to namespace '$rhdh_namespace'..."

  # Create ConfigMap with application.properties (runtime config for the workflow)
  local cm_name="agent-approval-props"
  log "Creating ConfigMap '$cm_name' with workflow runtime properties..."
  kubectl create configmap "$cm_name" \
    --namespace="$rhdh_namespace" \
    --from-file=application.properties="$props_file" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null

  # Build the SonataFlow CR with embedded flow, schema, and OpenAPI spec
  if ! kubectl apply -f - <<EOF
apiVersion: sonataflow.org/v1alpha08
kind: SonataFlow
metadata:
  name: agent-approval
  namespace: ${rhdh_namespace}
  annotations:
    sonataflow.org/description: "Agent lifecycle approval workflow for RHDH Augment"
    sonataflow.org/version: "0.1.0"
  labels:
    app: agent-approval
    sonataflow.org/workflow-app: agent-approval
spec:
  flow:
$(yq '.' "$sw_file" | sed 's/^/    /')
  resources:
    - name: schemas/agent-approval-input.json
      content: |
$(sed 's/^/        /' "$schema_file")
    - name: specs/augment-agent-lifecycle.yaml
      content: |
$(sed 's/^/        /' "$spec_file")
  podTemplate:
    container:
      env:
        - name: NOTIFICATIONS_URL
          value: "${backstage_backend}/api/notifications"
        - name: AUGMENT_BACKEND_URL
          value: "${backstage_backend}/api/augment"
        - name: OIDC_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: augment-secrets
              key: KAGENTI_CLIENT_ID
        - name: OIDC_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: augment-secrets
              key: KAGENTI_CLIENT_SECRET
        - name: OIDC_AUTH_SERVER_URL
          value: "${oidc_base_url}"
        - name: OIDC_TOKEN_PATH
          value: "${oidc_token_path}"
      volumeMounts:
        - name: workflow-props
          mountPath: /deployments/config
    volumes:
      - name: workflow-props
        configMap:
          name: ${cm_name}
EOF
  then
    log "Failed to apply SonataFlow agent-approval CR."
    log_fail
    exit 1
  fi

  log "SonataFlow agent-approval workflow deployed successfully."
}

deploy_agent_approval_workflow
