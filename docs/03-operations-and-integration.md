# 3. Operations, identity and data integration

## Components

| Component | Role |
|---|---|
| AI gateway | the single enforcement point: authenticates every caller, evaluates access and data policy, applies guardrails, budgets and kill switches, and proxies MCP, LLM and agent-to-agent traffic |
| ADP API | management plane for resources and policies; distributes policy to the gateways |
| Agent runtime | runs managed agents; each agent reaches tools and models only through the gateway |
| Postgres | resource and policy state |
| Redpanda | audit-log and telemetry topics, archived to Iceberg |

Deployment is **BYOC** (bring your own cloud) on AWS or GCP: the data plane,
including the gateway, runs in your cloud account. Tool calls, tool results and
audit records stay there; prompts and responses leave it only to reach the LLM
provider you configure.

## Behaviour under failure: fail closed by default

| Situation | Behaviour |
|---|---|
| Gateway has not yet loaded policy (for example a fresh start) | refuses calls until it has |
| A masked field is missing from a tool response (`absence_safe: false`) | refuses the call |
| A row is missing the field a row filter tests | drops the row |
| A data policy targets a group (unsupported in this version) | refuses every call on that server |
| Kill switch engaged | refuses the agent's MCP, LLM and agent-to-agent traffic |
| Unknown or invalid identity | refuses |

Upgrades are delivered by Redpanda as versioned releases, rolled out
progressively and verified by automated end-to-end tests at each stage.
Resource definitions, policy and data are unaffected by an upgrade.

## Identity

- **People** sign in through Redpanda Cloud, which can federate to your identity
  provider over SSO (OIDC). Redpanda Cloud group membership arrives in the token
  and is available to access policies (`principal in Group::"…"`).
- **Agents acting for a person** carry that person's identity to every tool call.
  The gateway evaluates access and data policy as the person, so an agent can
  never reach more than the person asking.
- **Service accounts** authenticate machine clients and autonomous agents, which
  are governed by policies naming them as principal.
- **External MCP clients** (IDEs, desktop assistants) authenticate against the
  gateway's own OAuth authorization server.

## Connecting to downstream systems

How an MCP server authenticates to the system behind it is set per server:

| Mode | Use |
|---|---|
| None | public or network-restricted endpoints |
| Static key | a secret-held API key or connection string (this demo) |
| Token passthrough | forward the caller's token where the downstream trusts the same issuer |
| Service-account OAuth | one shared OAuth client for the server |
| Per-user OAuth | each person connects their own account once; tokens are held encrypted in the gateway's token vault, so the downstream system applies its own entitlements per person |

Per-user OAuth is the pattern for authoritative systems that already hold
entitlements: the agent then acts with exactly the permissions the person has in
that system.

## Data integrations

- **Managed MCP servers**, configured rather than built. The SQL server supports
  Postgres, MySQL, SQL Server, ClickHouse, Snowflake, Databricks and Trino. Others
  include ServiceNow, Salesforce, Jira, Slack, Okta, MongoDB, Kafka, Google
  Workspace and Zendesk, plus a generic OpenAPI server that turns an existing REST
  API into tools.
- **Your own MCP servers** register as remote servers and get the same access
  policy, data policy, audit and kill switch as managed ones.
- **Egress firewall.** MCP destinations in private, internal and metadata address
  ranges are refused, so a tool definition cannot be used to reach the cluster's
  own network.

### Pattern for golden-source systems

1. A dedicated, read-only login per data product, granted only what that product
   exposes (`config/sql/03-roles.sql`).
2. One MCP server per login, so exposure is decided by which servers an agent
   lists.
3. Per-person shaping in data policy, or per-user OAuth where the source system
   already enforces entitlements.
4. Prefer views that compute (scores, aggregates, headroom) over letting the
   model calculate. The answer is then reproducible and auditable.

## What good looks like in a regulated production environment

- Every agent, tool exposure and policy is defined in Git and applied through a
  reviewed pull request.
- Database and API credentials are least privilege and held only in the secret
  manager.
- Person-level controls (who may call which tool, who may see which rows and
  fields) are written as policy, not as prompt instructions.
- Every agent has a budget and a kill-switch policy, starting in shadow mode and
  promoted to enforce once its thresholds are tuned.
- The audit log is streamed to your SIEM; transcripts are retained for review.

## Current limits

- Data policies target named users; group targeting is not yet supported.
- Budgets cap spend per agent; per-user spend is reported, not capped.
- SQL MCP `readonly` disables the Execute tool only, and `allowed_schemas` is
  advisory. Enforce read-only access with the database login.
- Guardrails (PII, prompt attack) apply to LLM traffic, not to MCP tool traffic.
- Deployment targets are AWS and GCP.
