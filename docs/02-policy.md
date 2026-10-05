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

Two questions are asked of every tool call: may this **agent** call it, and may
the **person** it is acting for?

**The agent.** New agents are granted nothing. Until it has a grant, an agent
cannot open a session on an MCP server or call a model, and answers with no
tools at all. `config/policies/desk-assistant-mcp.yaml` grants exactly its four
servers:

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

and `desk-assistant-llm.yaml` grants one LLM provider. A managed ceiling stops
any agent from minting credentials or administering OAuth, whatever it is granted.

**The person.** When the agent calls a tool on someone's behalf, the call is also
evaluated as that person. `config/policies/rates-broker-no-refdata.yaml`:

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
- The refusal names the deciding policy, for example `denied by policy
  "policies/rates-broker-no-refdata"`, and the same appears in the audit log.

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
    - '(?i)\bset_config\b'
```

These apply to everyone. They narrow what a query may do; they are not the
access boundary. That is layer 4. An example of why both matter: in testing, a
`SELECT set_config('default_transaction_read_only', 'off', false)` passed the
first patterns and switched off the login's read-only session default. The
`set_config` pattern now blocks it, and had it not, the login's SELECT-only grants
would still have refused any write.

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
  agent-to-agent traffic immediately, until a person releases it (`make
  kill-status`).
- **Kill-switch policies.** Watch a signal and trip or flag automatically.
  `config/killswitch/deny-rate-burst.yaml`:

  ```yaml
  name: deny-rate-burst
  spec:
    signal: KILL_SWITCH_POLICY_SIGNAL_DATAPOLICY_DENY_RATE
    burst:
      threshold: 0.2
      confidence: BURST_CONFIDENCE_95
    mode: KILL_SWITCH_POLICY_MODE_SHADOW
  ```

  The two policies here watch different things:

  | Policy | Signal | Counts | Ceiling |
  |---|---|---|---|
  | `deny-rate-burst` | data-policy deny rate | requests refused for asking outside a person's bounds (a clamp violated) | enforce |
  | `policy-error-burst` | evaluation error rate | responses withheld because a rule could not be applied, e.g. a renamed masked column | warn |

  A burst of denials suggests something pushing at the edges, such as a
  manipulated prompt, so contain first and investigate second. A burst of
  evaluation errors means the data is still protected but the agent has stopped
  working for the people a policy covers; that is a configuration fault, so the
  signal can flag but never engage the kill switch.
  - **Signals:** data-policy deny rate, guardrail block rate, or evaluation
    error rate.
  - **Detectors:** BURST fires when the lower confidence bound of a 5-minute
    window's rate exceeds the threshold, so 3 denials in 5 calls stays quiet
    and 12 in 12 fires. DRIFT accumulates evidence across windows to catch a
    slow creep. Windows with fewer than 10 calls are skipped.
  - **Modes, as a rollout ladder:** SHADOW records a firing and nothing else;
    WARN also notifies; ENFORCE also engages the kill switch. Start in shadow,
    review the firings (`make firings`), then promote with
    `KILLSWITCH_MODE=enforce make killswitch`.
  - `make drill` breaks the masked column, sends a burst of broker questions
    through the agent, and waits for `policy-error-burst` to record a firing.
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
