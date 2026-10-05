# Agent and MCP policy: a worked information barrier

**Date:** 2026-10-05. **Checked against:** the ADP production environment, with
the commands in each section.

## ELI5

Two people ask the same helper the same question. One person is allowed to see
the whole trading book. The other is allowed to see one desk only, with some
names hidden, and no credit data at all. Rules outside the helper decide what
each person gets, so nobody can talk the helper into giving more.

## Four controls give two people different answers from one agent

An information barrier is a rule that keeps the data of one desk from another desk.
This document shows how you build one with four controls. The desk head sees the
whole book. The Rates broker sees Rates trades only, with no client contact
details and no counterparty credit data. Both people use the same agent, and
each control is a file in this repository that you can change and re-apply.

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

## Three settings decide which tools an agent can reach

Every MCP call from an agent goes through the AI gateway.

- **The servers that the agent lists.** `desk-assistant` lists `rollup-sql` and
  `refdata-sql`. `trade-analyst` lists `blotter-sql` only. An agent cannot call
  a server that it does not list (`scripts/render-agent.sh`).
- **The database login of each server.** Each server connects with its own
  login, and each login has a grant on one schema (`config/sql/03-roles.sql`).
- **The person who asks.** When an agent calls a tool for a person, the gateway
  checks the call as that person. The access policy and the data policy use that
  identity.

## Access policy: who can call which tool

An access policy is a Cedar statement that permits or forbids an action. A
[Cedar](https://www.cedarpolicy.com/) statement names a principal, an action and
a resource. A principal is a user, a group or an agent. Actions include
`McpServerTool.call`, `LLMProvider.invoke`, `Agent.invoke`, and create, read,
update and delete on each resource type. The gateway asks two questions of
every tool call.

**Can this agent call the tool?** A new agent has no grants. Without a grant,
the agent cannot open a session on an MCP server or call a model, and it answers
with no tools. `config/policies/desk-assistant-mcp.yaml` grants the agent its
four servers and no others:

```cedar
permit(
  principal == Agent::"desk-assistant",
  action in [Action::"McpServer.initialize", Action::"McpServer.ping",
             Action::"McpServer.tools_list", Action::"McpServerTool.call"],
  resource
) when {
  resource in [McpServer::"blotter-sql", McpServer::"pricing-sql",
               McpServer::"refdata-sql", McpServer::"rollup-sql"]
};
```

`config/policies/desk-assistant-llm.yaml` grants one LLM provider. A managed
ceiling forbids every agent to create credentials or to administer OAuth,
whatever grants it has.

**Can this person call the tool?** The gateway also checks each tool call as the
person. `config/policies/rates-broker-no-refdata.yaml`:

```cedar
forbid(
  principal == User::"<broker>",
  action == Action::"McpServerTool.call",
  resource in McpServer::"refdata-sql"
);
```

- A `forbid` always wins over a `permit`. This one removes one action from one
  person, whatever roles the person has and through whichever agent.
- The gateway decides before the call reaches the MCP server. The agent gets a
  permission error, and its prompt tells it to quote the error exactly.
- The error names the policy that decided, for example `denied by policy
  "policies/rates-broker-no-refdata"`. The audit log records the same decision.

To see it, run `make credit`. The desk head gets the credit headroom for
Northbridge Capital. The agent quotes the refusal for the broker.

## MCP server guardrails: what a query can do

Every server in `config/manifests/` has these guardrails:

```yaml
guardrails:
  readonly: true            # disables the Execute tool
  max_rows_default: 60
  max_rows_limit: 500
  query_timeout: 20s
  blocked_patterns:         # regex, checked on every statement
    - '(?i)\b(DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b'
    - '(?i)\b(INSERT|UPDATE|DELETE|MERGE|COPY)\b'
    - '(?i)\bset_config\b'
```

Guardrails apply to every caller. They limit what a query can do, but they are
not the access boundary. The database grant is the boundary.

One test shows why you need both. Before the `set_config` pattern was in place,
a query called `set_config` and turned off the read-only default of its login
session. The pattern now blocks that query. Without the pattern, the login
still had no write grant, so Postgres refused any write.

To see it, run this command:

```bash
rpai mcp tools call blotter-sql query \
  --args '{"query":"SELECT set_config($$default_transaction_read_only$$,$$off$$,false)"}'
```

The server returns `query blocked by pattern: (?i)\bset_config\b`.

## Data policy: which rows and fields go back

A data policy shapes the arguments and the results of a tool call for named
people. This one is on `blotter-sql`, for the broker only:

```yaml
data_policies:
  - display_name: Rates desk — information barrier
    tools: [query]
    principals: [User:<broker>]
    shaping:
      request:
        clamps:
          - { json_path: $.max_rows, maximum: 25 }
      response:
        row_filters:
          - { path: $.records, expression: '@.desk == "RATES"' }
        field_actions:
          rules:
            - selector: { json_path: $.records.client_trader_email }
              mask: { redact: { placeholder: '[redacted]' } }
              absence_safe: false
            - selector: { json_path: $.records.counterparty_lei }
              mask: { partial: { keep_last: 4, mask_char: '*' } }
```

- **Request shaping** limits the tool arguments before the call. A clamp is a
  bound on one argument. The tool schema that the agent sees shows the clamp.
- **Response shaping** acts on the result before the model sees it. It filters
  rows, and it keeps, drops or masks fields. A mask can redact, show part of
  the value, hash it, or replace a pattern.
- **Missing data fails closed.** A row without the filtered field is dropped. A
  masked field that is missing from the response, with `absence_safe: false`,
  withholds the whole response. So a renamed column cannot pass through under
  its new name. `make break-schema` shows this.
- **Several matching policies combine.** The result is the most restrictive of
  the matching policies.
- **You can preview a policy before you save it.** `scripts/03-mcp.sh` previews
  the broker's policy against a sample response on every apply. It stops if a
  rule does not act as written.

To see it, run `make smoke`, then `make book` for the unshaped result from SQL.

## Database grant: the hard boundary

`make verify` connects as each of the four logins. It proves that each login
reads its own schema, gets "permission denied" on the others, and cannot write.
The gateway controls are in front of this boundary. They do not replace it.

## Contain an agent and cap its cost

A kill switch is a per-agent stop control. When a person or a policy engages it,
the gateway refuses the MCP, LLM and agent-to-agent traffic of that agent. The
switch stays on until a person releases it. `make kill-status` shows its state.

A kill-switch policy watches one signal for one agent. It records, notifies or
engages the switch when the signal goes above a threshold. The two policies in
`config/killswitch/` watch different signals:

| Policy | Signal | Counts | Highest mode |
|---|---|---|---|
| `deny-rate-burst` | Data-policy deny rate | Requests that break a clamp | Enforce |
| `policy-error-burst` | Evaluation error rate | Responses withheld because a rule cannot apply | Warn |

```yaml
name: deny-rate-burst
spec:
  signal: KILL_SWITCH_POLICY_SIGNAL_DATAPOLICY_DENY_RATE
  burst:
    threshold: 0.2
    confidence: BURST_CONFIDENCE_95
  mode: KILL_SWITCH_POLICY_MODE_SHADOW
```

A burst of denials can mean that a manipulated prompt pushes at the limits. The
safe response is to contain the agent, then investigate. A burst of evaluation
errors means that the data is still protected, but the agent no longer works for
the people that a policy covers. That is a fault in configuration, so this
signal can notify but cannot engage the kill switch.

How the detector decides:

- **The window is 5 minutes, and a window needs 10 calls.** The API reports both
  values (`window: 300s`, `minObservations: 10`). A window with fewer calls
  never fires.
- **The BURST detector fires on a sudden spike.** It fires when the lower
  confidence bound of the rate in a window is above the threshold. A DRIFT
  detector adds up evidence across windows, to catch a slow increase.
- **A rehearsal fired as configured.** `make drill` withheld 24 of 24 calls in
  one window (measured, 2026-10-05). The firing showed a statistic of 0.749
  against a threshold of 0.2.

The mode is a rollout ladder:

```
SHADOW ────────────▶ WARN ───────────────▶ ENFORCE
record a firing      also notify            also engage the kill switch
(start here)                                (not for evaluation errors)
```

Review the firings with `make firings` before you promote a policy. Promote it
with `KILLSWITCH_MODE=enforce make killswitch`.

A budget is a spend limit for one agent over a day, a week or a month. When the
agent reaches its budget, the gateway refuses its LLM calls until the period
resets. `scripts/06-budget.sh` sets the budget, and `make spend` shows the spend.

## Evidence for every decision

| Record | Contents |
|---|---|
| Audit log | Every decision: the person, the agent, the resource, permitted or denied, and the deciding policy. Management changes too. The format is OCSF (Open Cybersecurity Schema Framework). |
| Transcripts | Each conversation: calls to subagents, tool calls and results, tokens and cost for each turn |
| Cost and usage | Spend by agent, person, model and provider |

The gateway writes the audit log to a Redpanda topic in the data plane and
archives it to Iceberg. You can stream the topic to a SIEM, or query the archive
where it is.
