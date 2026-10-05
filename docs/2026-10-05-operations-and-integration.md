# Operations, identity and connections to source systems

**Date:** 2026-10-05. **Checked against:** the ADP production environment. This
page describes behaviour on that date.

## ELI5

The part that checks every request runs in your own cloud account. When it is
not sure, it says no. People sign in with the company login that they already
use. The helper always acts as the person who asked, so it can never see more
than that person can.

## Run the plane in your account, with fail-closed defaults

Use this page to plan a production deployment in a regulated environment. It
covers:

- What runs where, and how the plane behaves when something fails.
- How the identity of a person reaches each tool call.
- How the plane connects to your source systems.
- What good looks like, and the limits that apply today.

## The AI gateway is the one enforcement point

```
your cloud account (BYOC data plane)
┌──────────────────────────────────────────────────────┐
│ person or MCP client ─┐                              │
│                       ▼                              │
│ agent runtime ───▶ AI gateway ──▶ MCP servers        │
│ (managed agents)    ▲    │             │             │
│                     │    │             ▼             │
│ ADP API ────────────┘    │        your systems       │
│ (resources, policy)      │                           │
│                          └───────────────────────────┼──▶ LLM provider
│ Redpanda topics: audit log ──▶ Iceberg archive       │
└──────────────────────────────────────────────────────┘
```

BYOC (bring your own cloud) means that the data plane runs in your AWS or GCP
account. The AI gateway authenticates every caller and applies every policy. It
proxies all MCP, LLM and agent-to-agent traffic. Managed agents reach tools and
models through the gateway only. The ADP API stores resources and policy in
Postgres and sends policy to the gateways.

Tool calls, tool results and audit records stay in your account. Prompts and
responses leave the account only to reach the LLM provider that you configure.

## The plane fails closed

| Situation | Behaviour |
|---|---|
| The gateway has no policy loaded yet, for example at a fresh start | It refuses calls until it loads policy |
| A masked field is missing from a tool response (`absence_safe: false`) | It withholds the response |
| A row has no value for the field that a row filter tests | It drops the row |
| A data policy targets a group, which is not available today | It refuses every call on that server |
| The kill switch of an agent is on | It refuses the MCP, LLM and agent-to-agent traffic of that agent |
| The identity is unknown or not valid | It refuses the call |

Redpanda delivers upgrades as versioned releases. Each release rolls out in
stages, with automated end-to-end tests at each stage. An upgrade does not change
your resource definitions, your policy or your data.

## Identity goes with every tool call

- **People** sign in through Redpanda Cloud. Redpanda Cloud can federate to your
  identity provider over OIDC single sign-on. Group membership in Redpanda
  Cloud arrives in the token, and access policies can use it.
- **An agent that acts for a person** carries that identity to every tool call.
  The gateway checks access policy and data policy as the person. So an agent
  never reaches more than the person who asked.
- **Service accounts** authenticate machine clients and autonomous agents. An
  access policy names the agent as the principal.
- **External MCP clients**, such as an IDE or a desktop assistant, authenticate
  with the OAuth authorization server of the gateway.

## Each MCP server authenticates to its system in one of five ways

| Mode | Use it for |
|---|---|
| None | Public endpoints, or endpoints that the network restricts |
| Static key | An API key or connection string in a secret, as in this demo |
| Token passthrough | Systems that trust the same token issuer as the caller |
| Service-account OAuth | One shared OAuth client for the server |
| Per-user OAuth | Systems that apply their own entitlements for each person |

With per-user OAuth, each person connects their own account one time. The
gateway keeps the tokens encrypted in its token vault. The source system then
applies its own entitlements, so the agent acts with the permissions of the
person in that system.

## Connect to source systems without new code

- **Managed MCP servers** need configuration only. The SQL server connects to
  Postgres, MySQL, SQL Server, ClickHouse, Snowflake, Databricks and Trino.
- **Other managed servers** include ServiceNow, Salesforce, Jira, Slack, Okta,
  MongoDB, Kafka, Google Workspace and Zendesk.
- **The OpenAPI server** turns an existing REST API into tools.
- **Your own MCP servers** register as remote servers. They get the same access
  policy, data policy, audit and kill switch as managed servers.
- **The egress firewall** refuses MCP destinations in private, internal and
  cloud-metadata address ranges. So a tool definition cannot reach the network
  of the cluster.

### Expose an authoritative source system in four steps

1. Create a read-only login for each data product, with a grant on only what
   that product exposes (`config/sql/03-roles.sql`).
2. Create one MCP server for each login, so the server list of an agent decides
   its exposure.
3. Shape results for each person with a data policy, or use per-user OAuth where
   the source system already applies entitlements.
4. Do calculations in views (scores, aggregates, headroom), not in the model, so
   that each answer is reproducible and auditable.

## What good looks like in a regulated production environment

- Every agent, tool exposure and policy is in Git, and a reviewed pull request
  applies each change.
- Each database and API credential has least privilege and is in the secret
  manager only.
- Policy, not a prompt, sets the controls for each person: which tools the
  person can call, and which rows and fields the person can see.
- Every agent has a budget and kill-switch policies. Each policy starts in
  shadow mode and moves to enforce when its thresholds are tuned.
- The audit log streams to your SIEM, and you keep the transcripts for review.

## Limits that apply today

- Data policies target named users. Group targeting is not available.
- Budgets cap spend for each agent. Reports show spend for each person, but no
  budget caps it.
- On SQL MCP servers, `readonly` disables the Execute tool only, and the server
  does not enforce `allowed_schemas`. Use a read-only database login.
- Guardrails for personal data and prompt attacks apply to LLM traffic, not to
  MCP tool traffic.
- The data plane runs on AWS and GCP.
