# Lakeflow Connect — SQL Server ingestion with a custom cluster policy

A minimal, working Databricks Asset Bundle (DAB) that ingests a SQL Server
table via **Lakeflow Connect** and demonstrates how to **apply a custom
cluster policy to the ingestion gateway**.

The gateway requires a cluster policy whose `cluster_type` override is pinned
to `dlt`. That cluster type cannot be selected in the workspace UI, so the
policy has to be created through the REST API, CLI, SDK, or Terraform —
which is what the docs mean by *"custom policy (API only)"*:

> <https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-pipeline#requirements>

This bundle pairs the DAB (for the pipeline and gateway) with a small shell
script (for the API-only policy), so the whole stack is reproducible and
version-controlled.

---

## Repo layout

```
.
├── databricks.yml                   # Bundle root + variables + targets
├── resources/
│   ├── pipeline.yml                 # Gateway + ingestion pipeline
│   └── job.yml                      # Daily refresh job
├── policy/
│   └── gateway_policy_overrides.json  # Policy-family override payload
├── scripts/
│   └── manage_policy.sh             # Create/update the policy via the API
├── .env.example                     # Template for bundle variables
└── .gitignore
```

---

## Prerequisites

1. Databricks workspace with:
   - Unity Catalog enabled
   - Serverless compute enabled
   - A Unity Catalog **Connection** to SQL Server already created
     (see [Configure Microsoft SQL Server for ingestion](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-source-setup))
2. Databricks CLI ≥ `0.260` and `jq` installed locally:
   ```bash
   brew install databricks jq      # macOS
   databricks auth login --host https://<your-workspace>.cloud.databricks.com
   ```
3. An identity (user or service principal) with:
   - `CREATE` on cluster policies (admin) — needed **once** to create the policy
   - `USE CATALOG`, `USE SCHEMA`, `CREATE TABLE`, `CREATE VOLUME` on the
     destination schema
   - `USE CONNECTION` on the SQL Server UC connection

---

## Step 1 — Create the custom cluster policy (API only)

The policy uses the `job-cluster` policy family and adds the overrides
required by Lakeflow Connect:

```json
{
  "cluster_type":        { "type": "fixed",     "value": "dlt" },
  "num_workers":         { "type": "unlimited", "defaultValue": 1, "isOptional": true },
  "runtime_engine":      { "type": "fixed",     "value": "STANDARD", "hidden": true },
  "driver_node_type_id": { "type": "fixed",     "value": "r5n.16xlarge" },
  "node_type_id":        { "type": "fixed",     "value": "m5n.large" }
}
```

Create it with the shell script:

```bash
./scripts/manage_policy.sh lakeflow-sqlserver-gateway
```

The script is **idempotent**: if a policy with that name already exists it is
updated in place, otherwise it is created. The `policy_id` is printed to stdout.

> **Why this has to be a script instead of a DAB resource:** DABs do not yet
> support `cluster_policies` as a first-class resource type. Keeping the
> CLI call in a versioned shell script means the policy overrides stay in
> git alongside the pipeline definitions.

---

## Step 2 — Configure bundle variables

```bash
cp .env.example .env
# edit .env with your connection, catalog, schema, table names
source .env
```

The `policy_id` is **hard-coded in `databricks.yml`** — the policy is
treated as a pre-existing workspace input, created once by a platform
admin and referenced by every bundle that needs it. To target a
different workspace, re-run the policy script there and update the
`policy_id` default in `databricks.yml` (or override with
`BUNDLE_VAR_policy_id=<id>`).

---

## Step 3 — Deploy

```bash
databricks bundle validate -t dev
databricks bundle deploy   -t dev
```

This creates:

- A **gateway** pipeline (`sqlserver-gateway`) whose cluster uses the custom
  policy — you can confirm by clicking the pipeline → Settings → Compute.
- An **ingestion** pipeline (`sqlserver-ingestion-pipeline`) that reads the
  staged data and MERGEs into the destination tables.
- A **daily job** that triggers the ingestion pipeline (the gateway itself
  runs continuously).

Kick off the first run:

```bash
databricks bundle run sqlserver_ingestion_refresh -t dev
```

Then in the workspace: **Data Ingestion → SQL Server → sqlserver-ingestion-pipeline**
to watch the tables fill in.

---

## Step 4 — (Optional) Grant the policy to a service principal

If the pipeline is going to be deployed by a service principal rather than
an admin, grant `CAN_USE` on the policy so the SP can create the gateway
cluster:

```bash
POLICY_ID=$(./scripts/manage_policy.sh)
databricks permissions set cluster-policies "$POLICY_ID" --json '{
  "access_control_list": [
    {"service_principal_name": "<sp-application-id>", "permission_level": "CAN_USE"}
  ]
}'
```

---

## Teardown

```bash
databricks bundle destroy -t dev
# Policy is not managed by the bundle — delete explicitly if desired:
POLICY_ID=$(databricks cluster-policies list --output json \
  | jq -r '.[] | select(.name=="lakeflow-sqlserver-gateway") | .policy_id')
databricks cluster-policies delete --policy-id "$POLICY_ID"
```

---

## Why these specific policy overrides?

| Override               | Value          | Why                                                                 |
| ---------------------- | -------------- | ------------------------------------------------------------------- |
| `cluster_type`         | `dlt`          | The gateway runs as a Lakeflow Declarative Pipelines cluster.        |
| `num_workers`          | unlimited      | Gateway workload is driver-bound; workers rarely need to scale.     |
| `runtime_engine`       | `STANDARD`     | Photon is not supported for the gateway.                            |
| `driver_node_type_id`  | `r5n.16xlarge` | ≥ 8 cores is required for efficient CDC extraction.                 |
| `node_type_id`         | `m5n.large`    | Smallest worker is fine — worker size has no effect on throughput.  |

Adjust `driver_node_type_id` downward for small databases or upward for
heavy CDC volumes; keep workers small.

---

## References

- [SQL Server pipeline requirements](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-pipeline#requirements)
- [Cluster Policies API — create](https://docs.databricks.com/api/workspace/clusterpolicies/create)
- [DAB `pipeline.ingestion_definition` reference](https://docs.databricks.com/aws/en/dev-tools/bundles/resources#pipelineingestion_definition)
