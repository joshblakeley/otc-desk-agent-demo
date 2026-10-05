# Walkthrough

About 45 minutes plus questions, in four parts. Parts 1 and 2 are live; parts 3
and 4 walk through `docs/03-operations-and-integration.md`.

Before you start: `make preflight`, `make up`, `make verify`, then run `make
smoke` and `make credit` once so both identities are warm. Have three windows
open: this repo, a terminal, and the ADP console signed in as the desk head (and
a second browser profile signed in as the broker if you want to show the console
side by side).

## Part 1: Configure and manage (10 min)

1. **The repo is the configuration.** Open `config/`. Four MCP server manifests,
   one access policy, three prompts. Point out there is no credential anywhere:
   `dsn: ${secrets.OTC_DEMO_PG_BLOTTER_DSN}`.
2. **`make diff`.** Expect no drift: live matches the repo.
3. **Make a change.** In `config/prompts/system-prompt.md`, change "under 200
   words" to "under 150 words". Run `make diff`: one field on one resource. Run
   `make agent`: the agent is updated in place, not recreated.
4. **Show it landed.** In the console: the agent's prompt, then the audit log
   entry for the change.
5. Close the loop: in production, that diff runs on a pull request and a second
   person approves it (`docs/01`, "Change control").

## Part 2: Policy, worked example (15 min)

1. **Same question, two people.**

   ```bash
   make smoke
   ```

   It asks "Show me the largest trade on each desk on the last business day,
   with the counterparty and the client trader".

   | | Desk head | Rates broker |
   |---|---|---|
   | Desks returned | RATES, FXMM, CREDIT, ENERGY | RATES only |
   | Client trader | `r.ashby@northbridge.example` | `[redacted]` |
   | Counterparty LEI | `DEMO00NORTHBRIDGE001` | `****************R001` |

   `make book` prints the unshaped truth straight from SQL, for comparison.

2. **Show what produced it.** `config/manifests/blotter-sql.yaml`, the
   `data_policies` block: one row filter, two masks, one clamp. Nothing in the
   agent or prompt mentions any of it.

3. **Refused, not hidden.**

   ```bash
   make credit
   ```

   The desk head gets Northbridge Capital's limit headroom (750m limit, 612m
   used, review in 41 days). The broker is refused by access policy, and the
   agent quotes the refusal. Show `config/policies/rates-broker-no-refdata.yaml`:
   a five-line Cedar `forbid`.

4. **Fails closed.** `make break-schema`, then ask the broker again (`make ask
   AS=broker Q="Show me today's largest Rates trade with the client trader"`). The
   call is refused because the masked column is missing, rather than the email
   leaking under its new name. `make fix-schema`.

5. **The database underneath.** `make verify`: each login reaches its own schema,
   is denied the others, and cannot write.

6. **Monitoring.** In the console:
   - **Transcripts**: open both runs of the showcase question. Same delegation,
     same tool call, different shaped results; tokens and cost per turn.
   - **Audit log**: filter to the broker. The denied `McpServerTool.call` on
     `refdata-sql`, with the deciding policy named.
   - **Cost and usage**: spend for `desk-assistant`, by user, against its daily
     budget (`make spend`).
   - **Kill switch**: show where it is engaged, and say what it does. Do not trip
     it live.

## Part 3: Resilience and operations (10 min)

Walk `docs/03`: components, the fail-closed table, upgrades. Take the detailed
availability and failover questions in conversation.

## Part 4: Identity and data integrations (10 min)

Walk `docs/03`: identity (people, on-behalf-of, service accounts), downstream
authentication modes (per-user OAuth for systems that already hold
entitlements), the managed MCP catalog, and the golden-source pattern this repo
implements.

Close on **current limits**, the last section of `docs/03`.

## Other questions to try

```bash
make ask Q="Where is EUR IRS 10Y trading now versus our largest trade in it on the last business day?"
make ask Q="Which counterparties have KYC review due, and how much limit headroom do they have?"
make ask Q="How much voice-brokered volume did each desk do this week?"
make ask AS=broker Q="How much voice-brokered volume did each desk do this week?"   # aggregates: allowed
```
