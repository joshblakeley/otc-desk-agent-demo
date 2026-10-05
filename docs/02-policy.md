# 2. Agent and MCP policy: a worked example

The scenario is an information barrier. A desk head may see the whole book; a
Rates broker may see Rates trades only, may not see client contact details, and
may not see counterparty credit data at all. Both use the same agent.

## How tools are exposed to agents

An agent reaches data only through MCP servers, and every MCP call passes through
the AI gateway. Exposure is decided in three places:

1. **Which servers an agent has.** `desk-assistant` lists `rollup-sql` and
   `refdata-sql`; `trade-analyst` lists only `blotter-sql`. An agent cannot call a
   server it does not list (`scripts/render-agent.sh`).
2. **What the server's login can see.** Each server connects with its own
   database login, granted one schema (`config/sql/03-roles.sql`).
3. **Who is asking.** When an agent calls a tool on someone's behalf, the gateway
   evaluates the call as that person. The access policy and data policy below
   key off that identity.

## Layer 1: access policy (Cedar)

`config/policies/rates-broker-no-refdata.yaml`:

```cedar
forbid(
  principal == User::"<broker>",
  action == Action::"McpServerTool.call",
  resource in McpServer::"refdata-sql"
);
```

- Policies are [Cedar](https://www.cedarpolicy.com/) statements over principals
  (users, groups, agents), actions (for example `McpServerTool.call`,
  `LLMProvider.invoke`, `Agent.invoke`, and create/read/update/delete on every
  resource) and resources (MCP servers and their tools, agents, LLM providers…).
- `forbid` always overrides `permit`. Here it removes one capability from one
  person, whatever roles they hold and whichever agent they come through.
- Evaluation is in the gateway, before the call reaches the MCP server. A refused
  call returns a permission error to the agent, and the prompt instructs it to
  report that verbatim.
- New agents are granted nothing. Access for an agent acting autonomously, such
  as a scheduled trigger with no person behind it, is written as an explicit
  policy naming the agent as principal. A managed ceiling stops any agent from
  minting credentials or administering OAuth, whatever it is granted.

## Layer 2: MCP server guardrails

Every server in `config/manifests/` carries:

```yaml
guardrails:
  readonly: true            # disables the Execute tool
  max_rows_default: 60
  max_rows_limit: 500
  query_timeout: 20s
  blocked_patterns:         # regex, checked on every statement
    - '(?i)\b(DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE)\b'
    - '(?i)\b(INSERT|UPDATE|DELETE|MERGE|COPY)\b'
```

These apply to everyone. They narrow what a query may do; they are not the
access boundary. That is layer 4.

## Layer 3: data policy

On `blotter-sql`, for the broker only:

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

- **Request shaping** clamps or rewrites tool arguments before the call. The
  clamp is also reflected in the tool schema the agent sees.
- **Response shaping** filters rows and keeps, drops or masks fields (redact,
  partial, hash or pattern) after the call and before the model sees anything.
- **Fails closed.** A record without the filtered field is dropped. A masked
  field that is missing from the response, with `absence_safe: false`, refuses
  the whole call rather than letting a renamed column through (`make
  break-schema` shows this). Several policies matching one call combine to the
  most restrictive outcome.
- Policies can be previewed against a sample response before saving;
  `scripts/03-mcp.sh` does this on every apply and fails if a rule does not
  behave as written.

## Layer 4: the database grant

`make verify` connects as each login and proves it reaches its own schema and
nothing else, and that writes are refused. The gateway layers sit in front of
this boundary; they do not replace it.

## Containment and cost

- **Kill switch.** Each agent has one. Engaging it cuts the agent's MCP, LLM and
  agent-to-agent traffic immediately. Kill-switch policies can trip it
  automatically on a guardrail block rate, a data-policy deny rate or an
  evaluation error rate, in shadow, warn or enforce mode.
- **Budgets.** A daily, weekly or monthly spend limit per agent. Once it is
  reached, LLM calls are refused until the period resets (`scripts/06-budget.sh`,
  `make spend`).

## Monitoring

| Evidence | Shows |
|---|---|
| Audit log | every decision (who, which agent, which resource, permitted or denied, which policy decided) plus management changes; OCSF-formatted |
| Transcripts | each conversation end to end: delegations, tool calls and results, tokens and cost per turn |
| Cost and usage | spend by agent, user, model and provider |

The audit log is written to a Redpanda topic in the data plane and archived to
Iceberg, so it can be streamed to a SIEM or queried in place.
