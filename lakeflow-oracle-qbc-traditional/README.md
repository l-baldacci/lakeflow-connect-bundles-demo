# Lakeflow Connect — Oracle ingestion (query-based, classic compute)

A Databricks Asset Bundle (DAB) that ingests from an Oracle database into
Unity Catalog using **Lakeflow Connect's query-based connector** on
**classic compute** (non-serverless).

Companion to [`lakeflow-oracle-qbc-serverless`](../lakeflow-oracle-qbc-serverless)
— same connector and same ingestion definition, swapped onto a single-node
classic cluster.

---

## ⚠️ Beta — read this first

Per the [query-based connectors overview](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-overview):

> Classic compute is supported in Beta, but only using APIs.
> Databricks recommends using serverless compute.

"API only" means the workspace UI has no toggle to put a query-based
ingestion pipeline on classic compute — but the Pipelines REST API
accepts the configuration, and a DAB is a thin YAML layer over that
API. So expressing it in `pipeline.yml` is the supported path.

**Use this bundle only if** the serverless compute network can't reach
your Oracle source (private VPC, instance-profile auth, on-prem behind
peering, etc.). Otherwise prefer the serverless variant — fewer moving
parts, faster cold start, and no Beta caveat.

---

## Serverless vs. classic — at a glance

| | [`-serverless`](../lakeflow-oracle-qbc-serverless) | **`-traditional` (this bundle)** |
|---|---|---|
| `serverless` flag | (default true) | **`false`** |
| `clusters:` block | none | single-node, `num_workers: 0` |
| Cold start per trigger | seconds | ~2–5 min cluster boot |
| Cost attribution | `budget_policy_id` (serverless DBUs) | cluster tags only |
| Network reach | serverless egress / PrivateLink | customer-managed VPC, instance profiles |
| GA status | GA | **Beta** |

The `ingestion_definition` (foreign catalog, cursor column, primary key,
destination) is **identical** between the two — the only difference is
how the pipeline is computed.

---

## Repo layout

```
.
├── databricks.yml
├── resources/
│   ├── pipeline.yml      # serverless: false + single-node clusters block
│   └── job.yml           # Hourly refresh job
├── .env.example
└── .gitignore
```

---

## Prerequisites

1. Databricks workspace with Unity Catalog.
2. Permission to create classic Lakeflow Declarative Pipelines clusters
   in the target workspace.
3. An existing **Unity Catalog foreign catalog** federating the Oracle
   source (Lakehouse Federation):
   ```bash
   databricks catalogs get <foreign-catalog> --profile <profile>
   ```
4. `USE_CONNECTION` on the underlying connection, plus `USE_CATALOG` and
   `SELECT` on the foreign catalog/schema.
5. A source table with a cursor column (monotonically increasing
   `TIMESTAMP` or `NUMBER`) and a primary key.

---

## Deploy

```bash
cp .env.example .env
# edit .env with your catalog, schema, table, cursor column, primary key
source .env
databricks bundle validate -t dev
databricks bundle deploy -t dev
```

The first deploy creates:

- An **ingestion pipeline** — query-based, single-node classic cluster.
- An **hourly refresh job** — pipeline_task that runs the ingestion.

Trigger the first run manually:

```bash
databricks pipelines start-update <pipeline-id> --profile <profile>
```

---

## Single-node cluster — why and when to change it

The bundle ships with a single-node cluster (`num_workers: 0` plus the
standard `singleNode` profile + `ResourceClass=SingleNode` tag). That's
intentional for a **demo / functional test**: query-based ingestion of a
small table doesn't need parallelism, and a single driver-only node is
cheap and easy to reason about.

For a real workload, edit `resources/pipeline.yml` and replace
`num_workers: 0` with an `autoscale:` block:

```yaml
clusters:
  - label: default
    node_type_id: ${var.node_type_id}
    autoscale:
      min_workers: 1
      max_workers: 4
      mode: ENHANCED
```

(Drop the `singleNode` `spark_conf` and `ResourceClass` tag at the same
time — those only belong on the single-node form.)

---

## Why classic compute at all?

Serverless is the default and recommended path for query-based
connectors. Classic compute exists for the cases where serverless
networking can't reach the source database — typically:

- **Private network** Oracle instances (VPC peering, Direct Connect,
  Transit Gateway).
- **Instance-profile authentication** (e.g., IAM-role-based access to a
  database in the same account).
- **Egress controls** that haven't yet been extended to serverless
  compute.

If you don't need any of those, use the
[`-serverless`](../lakeflow-oracle-qbc-serverless) bundle.

---

## References

- [Query-based connectors overview](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-overview)
  — see "Compute options".
- [Create a query-based ingestion pipeline](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-pipeline)
- [Pipelines clusters — single-node config](https://docs.databricks.com/aws/en/compute/configure#single-node-or-multi-node-compute)
