#!/bin/bash
log "Setting up secrets on $RHDH_NAMESPACE and $PAC_NAMESPACE"

SECRET_NAME="github-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=GITOPS_GIT_ORG="$GITOPS_GIT_ORG" \
    --from-literal=GITHUB_APP_APP_ID="$GITHUB_APP_APP_ID" \
    --from-literal=GITHUB_APP_CLIENT_ID="$GITHUB_APP_CLIENT_ID" \
    --from-literal=GITHUB_APP_CLIENT_SECRET="$GITHUB_APP_CLIENT_SECRET" \
    --from-literal=GITHUB_APP_WEBHOOK_URL="$GITHUB_APP_WEBHOOK_URL" \
    --from-literal=GITHUB_APP_WEBHOOK_SECRET="$GITHUB_APP_WEBHOOK_SECRET" \
    --from-literal=GITHUB_APP_PRIVATE_KEY="$GITHUB_APP_PRIVATE_KEY" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="lightspeed-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=OLLAMA_URL="$OLLAMA_URL" \
    --from-literal=OLLAMA_TOKEN="$OLLAMA_TOKEN" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="llama-stack-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=ENABLE_VLLM="true" \
    --from-literal=ENABLE_VALIDATION="true" \
    --from-literal=VLLM_URL="$VLLM_URL" \
    --from-literal=VLLM_API_KEY="$VLLM_API_KEY" \
    --from-literal=VALIDATION_PROVIDER="$VALIDATION_PROVIDER" \
    --from-literal=VALIDATION_MODEL_NAME="$VALIDATION_MODEL_NAME" \
    --from-literal=NOTEBOOKS_QUERY_PROVIDER_ID="$NOTEBOOKS_QUERY_PROVIDER_ID" \
    --from-literal=NOTEBOOKS_QUERY_MODEL="$NOTEBOOKS_QUERY_MODEL" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

if [[ -z "${KAGENTI_CLIENT_ID:-}" ]]; then
  KAGENTI_CLIENT_ID=$(kubectl get secret rossoctl-keycloak-client-secret -n "${KAGENTI_NAMESPACE}" -o jsonpath='{.data.client-id}' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -n "$KAGENTI_CLIENT_ID" ]]; then
    log "Auto-resolved KAGENTI_CLIENT_ID from rossoctl-keycloak-client-secret in ${KAGENTI_NAMESPACE} namespace."
  else
    log "Warning: KAGENTI_CLIENT_ID is not set and could not be auto-resolved from cluster. Using placeholder."
    KAGENTI_CLIENT_ID="not-configured"
  fi
fi

if [[ -z "${KAGENTI_CLIENT_SECRET:-}" ]]; then
  KAGENTI_CLIENT_SECRET=$(kubectl get secret rossoctl-keycloak-client-secret -n "${KAGENTI_NAMESPACE}" -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -n "$KAGENTI_CLIENT_SECRET" ]]; then
    log "Auto-resolved KAGENTI_CLIENT_SECRET from rossoctl-keycloak-client-secret in ${KAGENTI_NAMESPACE} namespace."
  else
    log "Warning: KAGENTI_CLIENT_SECRET is not set and could not be auto-resolved from cluster. Using placeholder."
    KAGENTI_CLIENT_SECRET="not-configured"
  fi
fi

SECRET_NAME="augment-secrets"
log "Creating $SECRET_NAME secret..."
SONATAFLOW_URL="http://agent-approval.${RHDH_NAMESPACE}.svc:80"
if [[ -z "${AGENT_APPROVAL_ENABLED:-}" ]]; then
  if [[ "${INSTALL_ORCHESTRATOR:-}" == "true" ]]; then
    AGENT_APPROVAL_ENABLED="true"
  else
    AGENT_APPROVAL_ENABLED="false"
  fi
fi
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=AUGMENT_PROVIDER="$AUGMENT_PROVIDER" \
    --from-literal=AUGMENT_LLAMA_STACK_URL="$AUGMENT_LLAMA_STACK_URL" \
    --from-literal=AUGMENT_MODEL="$AUGMENT_MODEL" \
    --from-literal=KAGENTI_BASE_URL="$KAGENTI_BASE_URL" \
    --from-literal=KAGENTI_NAMESPACE="$KAGENTI_NAMESPACE" \
    --from-literal=KAGENTI_TOKEN_ENDPOINT="$KAGENTI_TOKEN_ENDPOINT" \
    --from-literal=KAGENTI_CLIENT_ID="$KAGENTI_CLIENT_ID" \
    --from-literal=KAGENTI_CLIENT_SECRET="$KAGENTI_CLIENT_SECRET" \
    --from-literal=AGENT_APPROVAL_ENABLED="$AGENT_APPROVAL_ENABLED" \
    --from-literal=SONATAFLOW_URL="$SONATAFLOW_URL" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="kubernetes-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=K8S_CLUSTER_TOKEN="$K8S_CLUSTER_TOKEN" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="${ARGOCD_APP_NAME}-postgresql"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=postgres-password="$POSTGRESQL_POSTGRES_PASSWORD" \
    --from-literal=password="$POSTGRESQL_USER_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="quay-pull-secret"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=.dockerconfigjson="$QUAY_DOCKERCONFIGJSON" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="keycloak-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=KEYCLOAK_METADATA_URL="$KEYCLOAK_METADATA_URL" \
    --from-literal=KEYCLOAK_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
    --from-literal=KEYCLOAK_REALM="$KEYCLOAK_REALM" \
    --from-literal=KEYCLOAK_BASE_URL="$KEYCLOAK_BASE_URL" \
    --from-literal=KEYCLOAK_LOGIN_REALM="$KEYCLOAK_LOGIN_REALM" \
    --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

SECRET_NAME="rhdh-secrets"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=BACKEND_SECRET="$BACKEND_SECRET" \
    --from-literal=PERMISSION_ENABLED="${PERMISSION_ENABLED:-false}" \
    --from-literal=ADMIN_TOKEN="$RHDH_SA_TOKEN" \
    --from-literal=MCP_TOKEN="$MCP_TOKEN" \
    --from-literal=RHDH_BASE_URL="$RHDH_BASE_URL" \
    --from-literal=RHDH_CALLBACK_URL="$RHDH_CALLBACK_URL" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

# RBAC admin users ConfigMap — consumed via extraAppConfig by Backstage
log "Creating rbac-app-config ConfigMap..."
RBAC_SUPER_USERS_YAML="[]"
if [[ -n "${RBAC_ADMIN_USERS:-}" ]]; then
  RBAC_SUPER_USERS_YAML=""
  IFS=',' read -ra _RBAC_USERS <<< "$RBAC_ADMIN_USERS"
  for _u in "${_RBAC_USERS[@]}"; do
    _u=$(echo "$_u" | xargs)
    RBAC_SUPER_USERS_YAML+="
        - name: 'user:default/$_u'"
  done
fi
kubectl create configmap rbac-app-config \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=rbac-app-config.yaml="permission:
  rbac:
    admin:
      superUsers: $RBAC_SUPER_USERS_YAML
" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "rbac-app-config ConfigMap created successfully."

# Augment agent definitions ConfigMap — consumed via extraAppConfig by Backstage.
# When AUGMENT_PROVIDER=llamastack (or unset), inject FantaCo multi-agent definitions.
# When AUGMENT_PROVIDER=kagenti, leave empty so kagenti auto-discovery is not overridden.
log "Creating augment-agents-app-config ConfigMap..."
if [[ "${AUGMENT_PROVIDER:-llamastack}" != "kagenti" ]]; then
  AUGMENT_AGENTS_YAML=$(cat <<'AGENTS_EOF'
augment:
  defaultAgent: router
  maxAgentTurns: 10
  agents:
    router:
      name: "FantaCo Router"
      instructions: |
        You are a customer service router for FantaCo. Classify the user's
        question and transfer to the appropriate specialist agent.

        Transfer rules:
        - Legal questions (software licenses, embargoes, privacy/PII,
          contracts, policies, compliance) -> transfer to Legal
        - Technical support (OpenShift/Kubernetes, deployment, permissions,
          performance, FantaCo products like CloudSync or TechGear Pro,
          troubleshooting) -> transfer to Software Support
        - HR questions (benefits, health care, vacation/PTO, retirement,
          workspaces, office facilities, bonuses, compensation, perks,
          participation requirements) -> transfer to Human Resources.
          If the question mentions "workspaces at FantaCo", ALWAYS transfer
          to Human Resources.
        - Sales questions (territories, leads, discounting, quotas, CRM,
          brand guidelines, expenses, escalations, performance metrics)
          -> transfer to Sales
        - Procurement questions (competitive bidding, vendor evaluation,
          ethics, transparency, spending limits, approval processes)
          -> transfer to Procurement

        Always transfer to the most appropriate specialist. Do not answer
        the question yourself.
      handoffs:
        - legal
        - support
        - hr
        - sales
        - procurement
    legal:
      name: "Legal"
      handoffDescription: "Handles questions about software licenses, embargoes, privacy/PII, contracts, policies, procedures, or compliance"
      instructions: |
        You are FantaCo's Legal department specialist. Based on the relevant
        documents in the knowledge base, help with the user's legal query.
        Provide a helpful response based on the documents found. If no
        relevant documents are found, provide general guidance.
      enableRAG: true
    support:
      name: "Software Support"
      handoffDescription: "Handles technical support questions about OpenShift/Kubernetes, application deployment, permissions, resource utilization, performance, and FantaCo products (CloudSync, TechGear Pro)"
      instructions: |
        You are FantaCo's Software Support specialist. Based on the relevant
        documents in the knowledge base, help with the user's technical
        support query. Provide a helpful response based on the documents
        found. If no relevant documents are found, provide general guidance.
      enableRAG: true
    hr:
      name: "Human Resources"
      handoffDescription: "Handles questions about employee benefits, health care, vacation/PTO, retirement plans, workspaces, office facilities, work environment, bonuses, compensation, and perks"
      instructions: |
        You are FantaCo's Human Resources specialist. Based on the relevant
        documents in the knowledge base, help with the user's HR query.

        FantaCo's benefits are organized into categories:
        - bare necessities: workspace, health care, vacation/PTO, retirement
        - beyond the basics: music, parties, activities, food services,
          driving services, bonuses
        - caveats: participation requirements

        Try to narrow the response to details from the relevant sub-section
        of the benefits document when possible.

        Provide a helpful response based on the documents found. If no
        relevant documents are found, provide general guidance.
      enableRAG: true
    sales:
      name: "Sales"
      handoffDescription: "Handles questions about sales territories, lead assignments, discounting, deal approval, quotas, sales compensation, CRM systems, brand guidelines, expenses, escalations, and performance metrics"
      instructions: |
        You are FantaCo's Sales specialist. Based on the relevant documents
        in the knowledge base, help with the user's sales query.

        FantaCo's sales operation manual covers:
        - geographic territories
        - lead assignments
        - discounting and deal approval
        - quotas and compensation
        - CRM systems
        - brands and communications
        - expenses and escalations
        - performance and compliance

        Try to narrow the response to details from the relevant sub-section
        of the sales document when possible.

        Provide a helpful response based on the documents found. If no
        relevant documents are found, provide general guidance.
      enableRAG: true
    procurement:
      name: "Procurement"
      handoffDescription: "Handles questions about competitive bidding, vendor evaluation, procurement ethics, transparency, spending limits, and approval processes"
      instructions: |
        You are FantaCo's Procurement specialist. Based on the relevant
        documents in the knowledge base, help with the user's procurement
        query.

        FantaCo's procurement policies cover:
        - competitive bidding
        - vendor evaluation and categorization
        - ethics and transparency
        - review processes
        - spending limits

        Try to narrow the response to details from the relevant sub-section
        of the procurement document when possible.

        Provide a helpful response based on the documents found. If no
        relevant documents are found, provide general guidance.
      enableRAG: true
AGENTS_EOF
)
else
  AUGMENT_AGENTS_YAML="{}"
fi
kubectl create configmap augment-agents-app-config \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=augment-agents-app-config.yaml="$AUGMENT_AGENTS_YAML" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "augment-agents-app-config ConfigMap created successfully."

SECRET_NAME="ai-rh-developer-hub-env"
log "Creating $SECRET_NAME secret..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=NODE_TLS_REJECT_UNAUTHORIZED="0" \
    --from-literal=RHDH_TOKEN="$RHDH_SA_TOKEN" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."

if [[ "${SKIP_GITOPS_SETUP}" == "true" ]]; then
  log "SKIP_GITOPS_SETUP=true — skipping argocd-secrets."
else
  SECRET_NAME="argocd-secrets"
  log "Creating $SECRET_NAME secret..."
  kubectl create secret generic "$SECRET_NAME" \
      --namespace="$RHDH_NAMESPACE" \
      --from-literal=ARGOCD_USER="$ARGOCD_USER" \
      --from-literal=ARGOCD_PASSWORD="$ARGOCD_PASSWORD" \
      --from-literal=ARGOCD_HOSTNAME="$ARGOCD_HOSTNAME" \
      --from-literal=ARGOCD_API_TOKEN="$ARGOCD_API_TOKEN" \
      --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
  log "Secret $SECRET_NAME created successfully."
fi

# only create pipeline-as-code-secret and lightspeed-postgres-info secrets if
# this is not a secondary instance, as they are only needed for the initial RHDH
# instance in the cluster, and not for any additional RHDH instances we might want
# to deploy in the same cluster
if [[ "${IS_SECONDARY_INSTANCE}" != "true" ]]; then
  if [[ "${SKIP_PIPELINES_SETUP}" == "true" ]]; then
    log "SKIP_PIPELINES_SETUP=true — skipping pipelines-as-code-secret."
  else
    SECRET_NAME="pipelines-as-code-secret"
    log "Creating $SECRET_NAME secret..."
    kubectl create secret generic "$SECRET_NAME" \
        --namespace="$PAC_NAMESPACE" \
        --from-literal=github-application-id="$GITHUB_APP_APP_ID" \
        --from-literal=github-private-key="$GITHUB_APP_PRIVATE_KEY" \
        --from-literal=webhook.secret="$GITHUB_APP_WEBHOOK_SECRET" \
        --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
    log "Secret $SECRET_NAME created successfully."
  fi

  SECRET_NAME="lightspeed-postgres-info"
  log "Creating $SECRET_NAME secret in $LIGHTSPEED_POSTGRES_NAMESPACE..."
  kubectl create secret generic "$SECRET_NAME" \
      --namespace="$LIGHTSPEED_POSTGRES_NAMESPACE" \
      --from-literal=namespace="$LIGHTSPEED_POSTGRES_NAMESPACE" \
      --from-literal=user="$LIGHTSPEED_POSTGRES_USER" \
      --from-literal=password="$LIGHTSPEED_POSTGRES_PASSWORD" \
      --from-literal=db-name="$LIGHTSPEED_POSTGRES_DB" \
      --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
  log "Secret $SECRET_NAME created successfully."
fi

SECRET_NAME="lightspeed-postgres-info"
log "Creating $SECRET_NAME secret in $RHDH_NAMESPACE..."
kubectl create secret generic "$SECRET_NAME" \
    --namespace="$RHDH_NAMESPACE" \
    --from-literal=namespace="$LIGHTSPEED_POSTGRES_NAMESPACE" \
    --from-literal=user="$LIGHTSPEED_POSTGRES_USER" \
    --from-literal=password="$LIGHTSPEED_POSTGRES_PASSWORD" \
    --from-literal=db-name="$LIGHTSPEED_POSTGRES_DB" \
    --dry-run=client -o yaml | kubectl apply --filename - --overwrite=true >/dev/null
log "Secret $SECRET_NAME created successfully."
