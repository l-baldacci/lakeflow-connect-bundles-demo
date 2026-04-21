#!/usr/bin/env bash
# Create-or-update the custom cluster policy for the Lakeflow Connect SQL Server
# ingestion gateway. The policy pins cluster_type=dlt which cannot be set through
# the workspace UI — this script is the API-only workaround the docs call out at
# https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-pipeline#requirements
#
# Usage:
#   ./scripts/manage_policy.sh [policy-name] [profile]
#
# Defaults:
#   policy-name = lakeflow-sqlserver-gateway
#   profile     = DEFAULT (the active Databricks CLI profile)
#
# On success, prints the policy_id to stdout so it can be captured, e.g.:
#   export BUNDLE_VAR_policy_id=$(./scripts/manage_policy.sh)

set -euo pipefail

POLICY_NAME="${1:-lakeflow-sqlserver-gateway}"
PROFILE="${2:-DEFAULT}"
OVERRIDES_FILE="$(cd "$(dirname "$0")/.." && pwd)/policy/gateway_policy_overrides.json"

if [[ ! -f "$OVERRIDES_FILE" ]]; then
  echo "ERROR: overrides file not found: $OVERRIDES_FILE" >&2
  exit 1
fi

# The policy_family_definition_overrides field on the API is a JSON-encoded STRING,
# not a nested object — stringify the JSON file.
OVERRIDES_STR=$(jq -c . "$OVERRIDES_FILE" | jq -Rs .)

# Does a policy with this name already exist?
EXISTING_ID=$(databricks --profile "$PROFILE" cluster-policies list --output json \
  | jq -r --arg n "$POLICY_NAME" '.[] | select(.name==$n) | .policy_id' \
  | head -n1)

if [[ -n "$EXISTING_ID" ]]; then
  echo "Updating existing policy '$POLICY_NAME' ($EXISTING_ID)..." >&2
  databricks --profile "$PROFILE" cluster-policies edit --json "$(cat <<JSON
{
  "policy_id": "$EXISTING_ID",
  "name": "$POLICY_NAME",
  "policy_family_id": "job-cluster",
  "policy_family_definition_overrides": $OVERRIDES_STR
}
JSON
)" >/dev/null
  echo "$EXISTING_ID"
else
  echo "Creating new policy '$POLICY_NAME'..." >&2
  CREATED=$(databricks --profile "$PROFILE" cluster-policies create --json "$(cat <<JSON
{
  "name": "$POLICY_NAME",
  "policy_family_id": "job-cluster",
  "policy_family_definition_overrides": $OVERRIDES_STR
}
JSON
)" --output json)
  echo "$CREATED" | jq -r '.policy_id'
fi
