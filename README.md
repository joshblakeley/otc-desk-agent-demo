# otc-desk-agent-demo

This repository shows how you control what an AI agent can see and do on the
Redpanda Agentic Data Plane (ADP). Two people ask one agent the same question
and get different answers. The agent, its prompt and its tools are the same for
both people. Only policy differs, and all of that policy is in this repository.

The domain is the trading desks of a wholesale broker. A desk head sees the
largest trade on every desk. A Rates broker sees Rates trades only, with the
client trader redacted and the counterparty identifier masked. The access policy
refuses the broker all counterparty credit data.

`make up` builds everything. All data is synthetic. The firm, the counterparties,
the trades and the prices are invented. Every Legal Entity Identifier (LEI)
starts with `DEMO`.

| Document | Contents |
|---|---|
| [WALKTHROUGH.md](WALKTHROUGH.md) | The run of show for a live session |
| [docs/2026-10-05-configure-and-manage.md](docs/2026-10-05-configure-and-manage.md) | How you configure and administer the plane |
| [docs/2026-10-05-policy-worked-example.md](docs/2026-10-05-policy-worked-example.md) | The four controls on a tool call, with the configuration for each |
| [docs/2026-10-05-operations-and-integration.md](docs/2026-10-05-operations-and-integration.md) | Behaviour under failure, identity, and connections to source systems |

## One entry point, two subagents, four databases

```
person (desk head or Rates broker)
  │ signs in. The identity goes with every call that the agent makes.
  ▼
desk-assistant ──▶ rollup-sql ──▶ desk.daily_volumes
  │            │                    (aggregates, no counterparty columns)
  │            └─▶ refdata-sql ─▶ refdata.counterparties
  │                                 (credit limits, KYC status)
  ├─▶ trade-analyst ──▶ blotter-sql ──▶ trades.blotter
  │   (subagent)                         (the authoritative trade store)
  └─▶ pricing-analyst ─▶ pricing-sql ──▶ market.latest_prices
      (subagent)                         (indicative prices)
```

A subagent is an agent that only its parent agent can call. Each MCP server
connects to Postgres with its own database login. The desk assistant cannot read
the blotter, for two reasons. The blotter server is not in its tool list. Its
database logins have no grant on the blotter.

## Four controls on every tool call

```
tool call from desk-assistant, on behalf of a person
  │
  ▼  AI gateway
  access policy ──────── can this agent and this person call this tool?
  data policy (request)  clamp the arguments for this person
  guardrails ─────────── is this query inside the server limits?
  │
  ▼  SQL MCP server ──▶ Postgres
  │                     database grant: what this login can read
  ▼
  data policy (response) which rows and fields go back to this person?
  │
  ▼
response to the agent
```

| Control | Decides | Configuration | Changes with the person? |
|---|---|---|---|
| Access policy (Cedar) | Whether this agent and this person can call the tool | `config/policies/` | Yes |
| MCP server guardrails | What a query can do: rows, time, statement shape | `config/manifests/` | No |
| Data policy | Which rows and fields go back | `config/manifests/blotter-sql.yaml` | Yes |
| Database grant | What the login can read | `config/sql/03-roles.sql` | No |

The database grant is the hard boundary. `make verify` proves it. The AI gateway
applies the other three controls to every call. It applies them to this agent,
to other agents, and to people who use an MCP client directly.

## Tools and accounts that the demo needs

- `rpai` 0.2.x or newer (`brew install redpanda-data/tap/rpai`).
- `jq`, `curl`, `psql`, `python3` with PyYAML, `bash` and GNU `make`.
- An ADP environment with an LLM provider.
- A Postgres database that the AI gateway can reach over the public internet
  with TLS. The gateway refuses private addresses, so a tunnel or a database
  inside a private network does not work.
- Two user accounts in the organization. Service accounts do not work, because
  the gateway treats a service account as infrastructure, not as a person.

## Build and run the demo

```bash
cp env/production.env.example env/production.env && $EDITOR env/production.env
cp env/secrets.env.example     env/secrets.env     && $EDITOR env/secrets.env

rpai auth login                                    # as the desk head
RPAI_CONFIG=~/.rpai/broker RPAI_CREDENTIALS=~/.rpai/broker.credentials \
  rpai auth login                                  # as the broker

make preflight
make up            # safe to re-run after any edit
make verify        # each login reaches only its own data
make smoke         # the showcase question as both people
make credit        # the credit question: allowed, then refused
```

`rpai` stores one set of credentials for each organization. The second person
needs a separate credentials file and a separate configuration file. Add
`AS=broker` to any target to run it as the broker.

Sign in each person with `rpai auth login --no-browser`. Open the printed URL in
a private browser window. Otherwise, an existing browser session can sign in the
wrong person.

`make diff` shows what `make up` will change, and changes nothing. Run `make`
with no arguments to list every target.

## Limits that apply today

- Data policies target named users. Group targeting is not available. A data
  policy that targets a group refuses every call on its server.
- Budgets cap spend for each agent. Reports show spend for each person, but no
  budget caps it.
- On SQL MCP servers, `readonly` disables the Execute tool only, and the server
  does not enforce `allowed_schemas`. Use a read-only database login, as this
  repository does.
- Guardrails for personal data and prompt attacks apply to LLM traffic. They do
  not apply to MCP tool traffic.
