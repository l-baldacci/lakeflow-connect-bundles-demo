# Lakeflow Connect — Oracle ingestion (query-based)

A minimal Databricks Asset Bundle (DAB) that ingests from an Oracle database
into Unity Catalog using **Lakeflow Connect's query-based connector**.

Companion to [`lakeflow-sqlserver-bundle`](../lakeflow-sqlserver-bundle) — same
pattern, but with one crucial architectural difference.

---

## SQL Server vs. Oracle: what's different

| | SQL Server (CDC) | **Oracle (query-based)** |
|---|---|---|
| Connector type | CDC via binlog + change tracking | Query-based with cursor column |
| Ingestion gateway | **Yes** — classic compute cluster | **No** |
| Custom cluster policy (API only) | **Yes** — `cluster_type=dlt` | **No — not applicable** |
| Staging volume | Yes | No |
| Run model | Continuous gateway + scheduled ingestion | Scheduled only |
| Deletion tracking | Native via CDC | Via `deletion_condition` expression |
| Source load impact | Low (reads binlog) | Higher (runs SELECT on source) |

Because Oracle uses the query-based connector, the "custom policy (API only)"
caveat from the SQL Server docs **does not apply** here. The bundle is
significantly simpler: one pipeline, one job, no policy management script.

---

## Repo layout

```
.
├── databricks.yml
├── resources/
│   ├── pipeline.yml      # Query-based ingestion pipeline
│   └── job.yml           # Hourly refresh job
├── .env.example          # Template for bundle variables
└── .gitignore
```

---

## Prerequisites

1. Databricks workspace with Unity Catalog + serverless compute enabled.
2. An existing **Unity Catalog foreign catalog** federating the Oracle source
   (Lakehouse Federation). You can confirm with:
   ```bash
   databricks catalogs get <foreign-catalog> --profile <profile>
   ```
3. `USE_CONNECTION` on the underlying connection, plus `USE_CATALOG` and
   `SELECT` on the foreign catalog/schema.
4. A source table with:
   - **A cursor column**: a monotonically increasing `TIMESTAMP` or `NUMBER`
     column (e.g., `updated_at`, `id`). Required.
   - **A primary key**: used to dedupe/upsert rows on each run.

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
- An **ingestion pipeline** (`lb_oracle_ingestion`) — serverless, query-based.
- An **hourly refresh job** — pipeline_task that runs the ingestion pipeline.

Trigger the first run manually (the job runs hourly):

```bash
databricks pipelines start-update <pipeline-id> --profile <profile>
```

Or wait up to an hour for the scheduled trigger.

---

## How query-based ingestion works

On each pipeline run, the connector:

1. Reads the stored high-water mark of the cursor column from the last run.
2. Queries the source: `SELECT * FROM <table> WHERE <cursor_col> > <last_value>`.
3. Upserts the results into the destination streaming table, keyed on the
   primary key.
4. Updates the stored high-water mark to the new max cursor value.

Rows with `NULL` cursor values are **not ingested** — if you have
soft-deleted rows, use the `deletion_condition` field (e.g.,
`deletion_condition: 'deleted_at IS NOT NULL'`).

---

## Why query-based and not CDC for Oracle?

Lakeflow Connect's Oracle connector is currently query-based (Public Preview).
That's intentional:

- **Oracle LogMiner / GoldenGate** require privileged source-side setup
  (supplemental logging, archive log mode, dedicated user) that most customers
  haven't done.
- **Query-based** runs from Databricks alone, using the existing UC
  connection + foreign catalog.
- **Trade-off**: source DB sees SELECT load during each run; you only capture
  the latest state of changed rows, not every intermediate mutation.

For Oracle sources that *do* need true CDC (mutation-by-mutation replay), the
recommended path is GoldenGate → Kafka → Delta, not Lakeflow Connect.

---

## References

- [Query-based connectors overview](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-overview)
- [Create a query-based ingestion pipeline](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-pipeline)
- [Query-based connector reference](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-reference)
- [Query-based limitations](https://docs.databricks.com/aws/en/ingestion/lakeflow-connect/query-based-limits)
