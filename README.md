# Lakeflow Connect — bundle demos

Companion Databricks Asset Bundle (DAB) examples showing different
ingestion patterns and compute modes available in
[Lakeflow Connect](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/),
side by side.

| Bundle | Source | Connector model | Compute | Notes |
|---|---|---|---|---|
| [`lakeflow-sqlserver-cdc`](./lakeflow-sqlserver-cdc) | SQL Server | **CDC** via ingestion gateway | Classic (gateway) + serverless (ingestion) | Requires a custom cluster policy (API only) |
| [`lakeflow-oracle-qbc-serverless`](./lakeflow-oracle-qbc-serverless) | Oracle | **Query-based** (cursor column) | Serverless | Default / recommended path |
| [`lakeflow-oracle-qbc-traditional`](./lakeflow-oracle-qbc-traditional) | Oracle | **Query-based** (cursor column) | Classic single-node | **Beta** — opt-in for private-network reachability |

## Why these bundles?

The SQL Server example walks through the **"(API only) custom policy"**
requirement from the [SQL Server pipeline docs](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/sql-server-pipeline#requirements)
— a policy that cannot be created through the workspace UI because it pins
`cluster_type=dlt`. The bundle ships with a small shell script that produces
this policy via the Cluster Policies REST API and a version-controlled JSON
of the required overrides.

The Oracle examples intentionally contrast that complexity. Oracle uses the
**query-based** connector, which does not require a gateway, staging volume,
or custom cluster policy — only a cursor column on the source table. The
two Oracle bundles share an identical `ingestion_definition` and differ only
in compute mode:

- **`-serverless`** — the default, recommended path. No `clusters:` block.
- **`-traditional`** — `serverless: false` plus an explicit single-node
  `clusters:` block. Beta + API-only per the docs; useful when serverless
  networking can't reach the source.

Together the bundles illustrate two orthogonal trade-offs: connector model
(continuous CDC vs. scheduled query-based) and compute mode (serverless vs.
classic).

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

## Quick start (any bundle)

```bash
cd lakeflow-sqlserver-cdc \
  # or lakeflow-oracle-qbc-serverless \
  # or lakeflow-oracle-qbc-traditional
cp .env.example .env
# edit .env
source .env
databricks bundle validate -t dev
databricks bundle deploy -t dev
```

See each bundle's README for full prerequisites, permissions, and source-side
setup steps.

## Shared conventions

All bundles share:

- **`presets.tags.project: lakeflow_connect_demo`** — propagates to every
  tag-capable resource for cost attribution in `system.billing.usage`.
- **`mode: development`** on the `dev` target — prefixes all resource names
  with `[dev <username>]` so multiple SAs can share a workspace without
  collisions.

Serverless variants additionally use a **`budget_policy_id`** variable on
the ingestion pipeline and the refresh job for serverless cost attribution
(pick your workspace's Budget Policy / Serverless Usage Policy UUID). The
`-traditional` Oracle variant skips this — budget policies attribute
serverless DBUs only.
