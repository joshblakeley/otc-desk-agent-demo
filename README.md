# otc-desk-agent-demo

A worked example of governing AI agents on Redpanda's Agentic Data Plane (ADP),
using a wholesale broker's trading desks as the domain.

One desk assistant answers questions about the trade book, prices, desk volumes
and counterparties. Two people ask it the same question and get different
answers: a desk head sees every desk, while a Rates broker sees only Rates trades
with client details masked, and is refused counterparty credit data outright.
Nothing about the agent, its prompt or its tools differs between them. Only
policy does, and all of that policy lives in this repo.

`make up` builds everything. All data is synthetic: the firm, counterparties,
trades and prices are invented, and every LEI starts with `DEMO`.

| Read | For |
|---|---|
| [WALKTHROUGH.md](WALKTHROUGH.md) | the session run of show |
| [docs/01-configure-and-manage.md](docs/01-configure-and-manage.md) | how the plane is configured and administered |
| [docs/02-policy.md](docs/02-policy.md) | the policy worked example, layer by layer |
| [docs/03-operations-and-integration.md](docs/03-operations-and-integration.md) | operations, identity and data integration |

## Architecture

```
person (desk head | Rates broker)
   │  signs in; identity travels with every call the agent makes for them
   ▼
desk-assistant ─── rollup-sql ──── desk.daily_volumes        aggregates, no counterparties
   │           └── refdata-sql ─── refdata.counterparties    credit limits, KYC
   ├─ trade-analyst ─── blotter-sql ── trades.blotter         authoritative trade store
   └─ pricing-analyst ─ pricing-sql ── market.latest_prices   indicative prices
```

The desk assistant is the only entry point; the specialists cannot be addressed
directly. Each MCP server logs into Postgres as its own least-privilege login, so
the orchestrator genuinely cannot read the blotter: it is not among its tools,
and its logins have no grant on it either way.

## Four checks on every tool call

| Check | Decides | Defined in | Depends on who asks? |
|---|---|---|---|
| Access policy (Cedar) | whether this agent, and this person, may call this tool at all | `config/policies/` | yes |
| MCP server guardrails | what a query may do (rows, time, statement shape) | `config/manifests/` | no |
| Data policy | which rows and fields come back | `config/manifests/blotter-sql.yaml` | yes |
| Database grant | what exists for this login | `config/sql/03-roles.sql` | no |

The database grant is the hard boundary; `make verify` proves it. The other three
sit in front of it in the gateway, which enforces them on every call whether it
comes from this agent, another agent or a person with an MCP client.

## Requirements

- `rpai` 0.2.x or newer (`brew install redpanda-data/tap/rpai`), plus `jq`,
  `curl`, `psql`, `python3` with PyYAML, `bash` and GNU `make`
- An ADP environment with an LLM provider configured
- Postgres reachable from the AI gateway over the public internet with TLS. The
  gateway refuses to dial private addresses, so tunnels and VPC-internal
  databases do not work.
- Two user accounts in the org. Service accounts do not work for this, because
  the gateway treats them as infrastructure rather than people.

## Setup

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

rpai stores credentials per organization, so the second person needs their own
credentials file as well as their own config. `AS=broker` on any target selects
it. Sign each identity in with `rpai auth login --no-browser` and open the URL in
a private window, so an existing browser session cannot sign in the wrong person.

`make diff` shows what applying the repo would change without applying it. Run
`make` with no arguments for every target.

## Known limits

Stated plainly so nobody has to discover them:

- Data policies target named users. Group targeting is not supported in this
  version, and a group-targeted policy refuses every call on its server.
- Budgets are per agent. Spend can be reported per user, but not capped per user.
- On SQL MCP servers, `readonly` disables the Execute tool only and
  `allowed_schemas` is advisory. Use a read-only database login, as here.
- Guardrails (PII, prompt attack) apply to LLM traffic, not to MCP tool traffic.
