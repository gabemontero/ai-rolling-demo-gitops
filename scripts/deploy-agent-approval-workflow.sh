#!/bin/bash

# deploy-agent-approval-workflow.sh: deploys the SonataFlow agent-approval
# workflow CR using the local workflow files in workflows/agent-approval/.
# Only runs when INSTALL_ORCHESTRATOR=true.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"

source "$SCRIPTS_DIR/common.sh"

deploy_agent_approval_workflow() {
  local workflow_dir="${REPO_ROOT}/workflows/agent-approval"
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

  # Read the RHDH static token from rhdh-secrets for workflow → RHDH API auth.
  # The workflow passes this token as a regular Authorization header parameter
  # (no OIDC client needed).
  local admin_token
  admin_token=$(kubectl get secret rhdh-secrets --namespace="$rhdh_namespace" \
    -o jsonpath='{.data.ADMIN_TOKEN}' 2>/dev/null | base64 -d) || true
  if [[ -z "$admin_token" ]]; then
    log "WARNING: ADMIN_TOKEN not found in rhdh-secrets — workflow API calls will fail auth."
  fi
  local auth_token_bearer="Bearer ${admin_token}"

  log "Deploying agent-approval SonataFlow workflow to namespace '$rhdh_namespace'..."

  # Create ConfigMap with application.properties (runtime config for the workflow)
  local cm_name="agent-approval-props"
  log "Creating ConfigMap '$cm_name' with workflow runtime properties..."
  kubectl create configmap "$cm_name" \
    --namespace="$rhdh_namespace" \
    --from-file=application.properties="$props_file" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null

  # Create ConfigMaps with workflow resources (separate to avoid duplicate mount paths)
  local schema_cm_name="agent-approval-schemas"
  log "Creating ConfigMap '$schema_cm_name' with input schema..."
  kubectl create configmap "$schema_cm_name" \
    --namespace="$rhdh_namespace" \
    --from-file=agent-approval-input.json="$schema_file" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null

  # Download the shared notifications OpenAPI spec referenced by workflow functions
  local notifications_spec_url="https://raw.githubusercontent.com/rhdhorchestrator/serverless-workflows/main/workflows/shared/specs/notifications-openapi.yaml"
  log "Downloading notifications OpenAPI spec..."
  local notifications_tmp
  notifications_tmp=$(mktemp)
  if ! curl -sL "$notifications_spec_url" -o "$notifications_tmp" || [[ ! -s "$notifications_tmp" ]]; then
    log "Failed to download notifications spec from $notifications_spec_url"
    rm -f "$notifications_tmp"
    log_fail
    exit 1
  fi

  # Strip security schemes and add Authorization as a regular header parameter
  # so the workflow can pass the static RHDH token via function arguments.
  local notifications_patched
  notifications_patched=$(mktemp)
  yq 'del(.security, .components.securitySchemes)
    | del(.paths[][].security)
    | (.paths."/api/notifications".post.parameters) = [{"name": "Authorization", "in": "header", "required": true, "schema": {"type": "string"}}]
  ' "$notifications_tmp" > "$notifications_patched"
  mv "$notifications_patched" "$notifications_tmp"

  local spec_cm_name="agent-approval-specs"
  log "Creating ConfigMap '$spec_cm_name' with OpenAPI specs..."
  kubectl create configmap "$spec_cm_name" \
    --namespace="$rhdh_namespace" \
    --from-file=augment-agent-lifecycle.yaml="$spec_file" \
    --from-file=notifications-openapi.yaml="$notifications_tmp" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
  rm -f "$notifications_tmp"

  # Strip top-level metadata fields from the workflow YAML that the CRD
  # does not accept under spec.flow (id, name, description, version,
  # specVersion, extensions). Only the workflow body belongs in spec.flow.
  # Also rewrite the notifications function operation from the extension alias
  # (notifications#op) to a local spec path (specs/notifications-openapi.yaml#op)
  # since the CRD does not support the extensions/workflow-uri-definitions feature.
  local flow_body
  export AUTH_TOKEN_BEARER="$auth_token_bearer"
  flow_body=$(yq 'del(.id, .name, .description, .version, .specVersion, .extensions)
    | (.functions[] | select(.operation == "notifications#createNotification") | .operation) = "specs/notifications-openapi.yaml#createNotification"
    | (.functions[] | select(.operation == "augment#promoteAgent") | .operation) = "specs/augment-agent-lifecycle.yaml#promoteAgent"
    | (.functions[] | select(.operation == "augment#demoteAgent") | .operation) = "specs/augment-agent-lifecycle.yaml#demoteAgent"
    | (.states[].actions[]? | select(.functionRef.refName == "createNotification" or .functionRef.refName == "promoteAgent" or .functionRef.refName == "demoteAgent") | .functionRef.arguments.Authorization) = ("\"" + strenv(AUTH_TOKEN_BEARER) + "\"")' "$sw_file")
  unset AUTH_TOKEN_BEARER

  # Build the SonataFlow CR with embedded flow and ConfigMap resource refs
  if ! kubectl apply -f - <<EOF
apiVersion: sonataflow.org/v1alpha08
kind: SonataFlow
metadata:
  name: agent-approval
  namespace: ${rhdh_namespace}
  annotations:
    sonataflow.org/description: "Agent lifecycle approval workflow for RHDH Augment"
    sonataflow.org/version: "0.1.0"
    sonataflow.org/profile: dev
  labels:
    app: agent-approval
    sonataflow.org/workflow-app: agent-approval
spec:
  flow:
$(echo "$flow_body" | sed 's/^/    /')
  resources:
    configMaps:
      - configMap:
          name: ${schema_cm_name}
        workflowPath: schemas
      - configMap:
          name: ${spec_cm_name}
        workflowPath: specs
  podTemplate:
    container:
      env:
        - name: NOTIFICATIONS_URL
          value: "${backstage_backend}"
        - name: AUGMENT_BACKEND_URL
          value: "${backstage_backend}/api/augment"
        - name: QUARKUS_TLS_TRUST_ALL
          value: "true"
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
