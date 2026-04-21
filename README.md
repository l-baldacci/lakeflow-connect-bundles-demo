# Lakeflow Connect — bundle demos

Two companion Databricks Asset Bundle (DAB) examples showing **two different
ingestion patterns** available in [Lakeflow Connect](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/),
side by side.

| Bundle | Source type | Connector model | Complexity |
|---|---|---|---|
| [`lakeflow-sqlserver-bundle`](./lakeflow-sqlserver-bundle) | SQL Server | **CDC** (change data capture) via ingestion gateway | Higher — requires a custom cluster policy (API only) |
| [`lakeflow-oracle-bundle`](./lakeflow-oracle-bundle) | Oracle | **Query-based** (cursor column) | Lower — no gateway, no custom policy |

## Why two bundles?

The SQL Server example walks through the **"(API only) custom policy"**
requirement from the [SQL Server pipeline docs](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-pipeline#requirements)
— a policy that cannot be created through the workspace UI because it pins
`cluster_type=dlt`. The bundle ships with a small shell script that produces
this policy via the Cluster Policies REST API and a version-controlled JSON
of the required overrides.

The Oracle example intentionally contrasts that complexity. Oracle uses the
**query-based** connector, which does not require a gateway, staging volume,
or custom cluster policy — only a cursor column on the source table.

Together the two bundles illustrate the architectural trade-off you make per
source: continuous CDC capture (lower source load, richer event stream) vs.
scheduled query-based (higher source load, simpler operation).

## Contents per bundle

Each bundle is self-contained with its own README:

- `databricks.yml` — bundle root, variables, presets (tags), targets
- `resources/pipeline.yml` — ingestion pipeline(s)
- `resources/job.yml` — scheduled refresh job
- `.env.example` — template for bundle variables
- `.gitignore` — excludes `.env`, `.databricks/` artifacts

SQL Server only:

- `policy/gateway_policy_overrides.json` — the policy-family override payload
- `scripts/manage_policy.sh` — idempotent create-or-update via REST API

## Quick start (either bundle)

```bash
cd lakeflow-sqlserver-bundle   # or lakeflow-oracle-bundle
cp .env.example .env
# edit .env
source .env
databricks bundle validate -t dev
databricks bundle deploy -t dev
```

See each bundle's README for full prerequisites, permissions, and source-side
setup steps.

## Shared conventions

Both bundles share:

- **`presets.tags.project: lakeflow_connect_demo`** — propagates to every
  tag-capable resource for cost attribution in `system.billing.usage`.
- **`budget_policy_id`** variable on the ingestion pipeline and the refresh
  job for serverless cost attribution (pick your workspace's
  Budget Policy / Serverless Usage Policy UUID).
- **`mode: development`** on the `dev` target — prefixes all resource names
  with `[dev <username>]` so multiple SAs can share a workspace without
  collisions.
