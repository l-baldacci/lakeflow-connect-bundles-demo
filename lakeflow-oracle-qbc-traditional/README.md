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
ingestion pipeline on classic compute. The **Pipelines REST API does
accept the configuration** (we verified by direct POST against
`e2-demo-field-eng`, pipeline `b60e2695-9eaf-42d0-bdcc-5b55ecad9aa4`),
but two integration gaps mean a DAB-driven deploy is not yet end-to-end:

1. **Terraform provider client-side validation** rejects the
   `serverless: false` + `clusters` + `ingestion_definition`
   combination with `"You cannot provide cluster settings when using
   serverless compute"`, even though the rendered request body in
   `bundle.tf.json` correctly sets `serverless: false`. The provider's
   schema validation hasn't caught up to the API. Workaround: deploy
   the pipeline by direct API call until the
   [databricks/databricks](https://github.com/databricks/terraform-provider-databricks)
   provider ships an updated schema for ingestion-pipeline cluster
   blocks.
2. **Runtime Foreign Catalog API** — the pipeline cluster boots fine
   (~8 min cold start) and Lakeflow Connect's analysis stage starts,
   but `GET_TABLE_SCHEMA` calls against the source foreign catalog
   fail with
   `[QUERY_BASED_CONNECTOR_SOURCE_API_ERROR]`. The same source table
   resolves cleanly through `DESCRIBE` on a SQL warehouse — the runtime
   uses a separate code path that may not yet be wired up alongside
   classic compute.

**Use this bundle only if** the serverless compute network can't reach
your Oracle source (private VPC, instance-profile auth, on-prem behind
peering, etc.) **and** you've confirmed the two gaps above are
resolved in your workspace. Otherwise prefer the serverless variant —
fewer moving parts, faster cold start, and no Beta caveat.

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
