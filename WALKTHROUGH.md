# Run of show: an ADP capabilities walkthrough

This run of show takes about 45 minutes plus questions (estimated). You show the
configuration and the policy controls live. You then talk through operations and
integration from
[docs/2026-10-05-operations-and-integration.md](docs/2026-10-05-operations-and-integration.md).

## Prepare the environment before the session

1. Run `make preflight`, `make up` and `make verify`.
2. Run `make smoke` and `make credit` one time, so both identities are warm.
   `make smoke` took 69 seconds and `make credit` took 22 seconds (measured,
   2026-10-05).
3. Run `make drill` at least 15 minutes before the session, so a kill-switch
   firing is ready to show. In two runs, the firing appeared within 10 minutes
   of the burst (measured, 2026-10-05).
4. Open three windows: this repository, a terminal, and the ADP console as the
   desk head.
5. If you want to show the console for both people, sign in the broker in a
   second browser profile.

## Show that the repository is the configuration (10 minutes)

1. Open `config/`. Show the four MCP server manifests, the three access
   policies, the two kill-switch policies and the three prompts.
2. Show that no file contains a credential:
   `dsn: ${secrets.OTC_DEMO_PG_BLOTTER_DSN}`.
3. Run `make diff`. Expect no drift, because the live state matches the
   repository.
4. In `config/prompts/system-prompt.md`, change "under 200 words" to "under 150
   words".
5. Run `make diff`. It shows one changed field on one resource.
6. Run `make agent`. The agent updates in place and continues to run.
7. In the console, show the new prompt and the audit log entry for the change.
8. Explain that in production, the same diff runs on a pull request and a second
   person approves it. See "A pull-request check gives four-eyes change control"
   in [docs/2026-10-05-configure-and-manage.md](docs/2026-10-05-configure-and-manage.md).
9. After the session, change the prompt back, so `make diff` is clean.

## Show the four controls with two people (15 minutes)

1. Run `make smoke`. It asks both people: "Show me the largest trade on each desk
   on the last business day, with the counterparty and the client trader."

   | | Desk head | Rates broker |
   |---|---|---|
   | Desks returned | RATES, FXMM, CREDIT, ENERGY | RATES only |
   | Client trader | `r.ashby@northbridge.example` | `[redacted]` |
   | Counterparty LEI | `DEMO00NORTHBRIDGE001` | `****************E001` |

2. Run `make book` to show the unshaped result from SQL.
3. Open the `data_policies` block in `config/manifests/blotter-sql.yaml`. It has
   one row filter, two masks and one clamp. The agent and the prompts do not
   mention them.
4. Run `make credit`. The desk head gets the headroom for Northbridge Capital:
   a 750m limit with 612m used, from the seed data in
   `config/sql/04-seed-refdata.sql`.
5. Show the answer for the broker. The access policy refused the call, and the
   agent quotes the error, which names the deciding policy.
6. Open `config/policies/rates-broker-no-refdata.yaml`, a five-line Cedar
   `forbid`. Then open `desk-assistant-mcp.yaml`, which grants the agent its
   four servers and no others.
7. Run `make break-schema`, then ask as the broker:
   `make ask AS=broker Q="Show me today's largest Rates trade with the client trader"`.
8. Show that the gateway withholds the response, because the masked column is
   missing. The email does not pass through under the new column name.
9. Run `make fix-schema`.
10. Run `make verify`. Each login reads its own schema, gets "permission denied"
    on the others, and cannot write.

## Show the evidence in the console (5 minutes)

1. **Transcripts.** Open both runs of the showcase question. The delegation and
   the tool call are the same, but the shaped results differ. Each turn shows
   its tokens and cost.
2. **Audit log.** Filter to the broker. Show the denied `McpServerTool.call` on
   `refdata-sql` and the deciding policy.
3. **Cost and usage.** Show the spend for `desk-assistant` by person, against
   its daily budget. `make spend` shows the same values.
4. **Kill switch.** Open the two files in `config/killswitch/`. Run `make
   firings` to show the firing from the rehearsal.
5. Point at the window, the observed rate, the statistic against its threshold,
   and the mode `SHADOW`. In shadow mode, the firing stopped nothing.
6. Explain the ladder from shadow through warn to enforce. Do not trip the kill
   switch in enforce mode during the session.

## Talk through operations and integration (15 minutes)

Use
[docs/2026-10-05-operations-and-integration.md](docs/2026-10-05-operations-and-integration.md):

1. Resilience: the components diagram, the fail-closed table and upgrades.
   Take detailed availability and failover questions in conversation.
2. Identity: people, agents that act for a person, and service accounts.
3. Source systems: the five authentication modes and the managed MCP servers.
4. The four steps to expose an authoritative source system.
5. Close on "Limits that apply today", the last section.

## More questions to ask the agent

```bash
make ask Q="Where is EUR IRS 10Y trading now versus our largest trade in it on the last business day?"
make ask Q="Which counterparties have KYC review due, and how much limit headroom do they have?"
make ask Q="How much voice-brokered volume did each desk do this week?"
make ask AS=broker Q="How much voice-brokered volume did each desk do this week?"   # aggregates: allowed
```
