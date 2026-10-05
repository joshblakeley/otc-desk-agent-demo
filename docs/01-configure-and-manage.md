# 1. Configure and manage

## Everything is a resource

ADP is configured as a set of named resources, each with the same lifecycle
(create, get, list, update, delete) across three equivalent surfaces:

| Surface | Use it for |
|---|---|
| Declarative manifests + `rpai <kind> apply` | change control: the repo is the source of truth |
| The ADP console | inspection, ad-hoc changes, the audit log, transcripts and spend |
| Connect-RPC / HTTP API | automation and integration with your own tooling |

The resources this demo uses:

| Resource | Here | File |
|---|---|---|
| MCP server (with data policy) | 4 SQL servers | `config/manifests/*.yaml` |
| Access policy (Cedar) | the agent's two scoped grants, one forbid for the broker | `config/policies/*.yaml` |
| Agent (with subagents) | desk-assistant | rendered from `config/prompts/` by `scripts/render-agent.sh` |
| Secret | 4 database DSNs | built from `env/secrets.env` by `scripts/01-secret.sh` |
| Budget | 1 daily limit | `scripts/06-budget.sh` |
| Kill-switch policy | 2: data-policy deny rate, evaluation error rate | `config/killswitch/*.yaml`, applied by `scripts/07-killswitch.sh` |
| LLM provider | pre-existing | referenced by name in `env/production.env` |

Others available: guardrails, OAuth providers and clients, triggers.

## Manifests

A manifest is the resource exactly as `rpai <kind> get <name> -o yaml` prints it,
so anything built in the console can be exported into Git and anything in Git can
be applied.

```bash
rpai mcp diff    -f config/manifests/   # what would change
rpai mcp apply   -f config/manifests/   # create if absent, else update what differs
rpai policy diff -f config/policies/
rpai agent diff  -f <rendered agent manifest>
```

`make diff` runs all three. `apply` and `diff` cover agents, MCP servers,
policies, LLM providers, OAuth providers and clients, and triggers. Behaviour
worth knowing:

- **Field-level reconcile.** Only fields named in the manifest and different from
  live are updated. Editing one line of a prompt changes that prompt and nothing
  else, and the agent is not recreated.
- **No prune.** A resource removed from the repo is not deleted from the
  environment. Removal is an explicit `delete` (see `scripts/99-teardown.sh`).
- **Optimistic concurrency.** Resources carry an etag, so two writers cannot
  silently overwrite each other.
- **History lives in Git.** The plane holds current state, not a version
  history, so the repository is the record of what changed, when and who
  approved it.

## Change control

Because `diff` exits non-zero on drift, it slots into a pull-request check: CI runs
`make diff` with a service credential and posts the output on the PR, a second
person approves it, and the merge applies it. That gives four-eyes review over
every agent prompt, tool exposure and policy change, using the review process you
already run for code.

## Day-to-day administration

- `make status`: what is running.
- `make stop-agent` / `make start-agent`: pause and resume an agent.
- The console's **audit log** records management changes (who changed which
  resource, and when) alongside every runtime decision, with redacted
  before/after images of the resource where available.
- **Transcripts** show each conversation: every delegation to a specialist, every
  tool call and its result, and tokens and cost per turn.
- **Cost and usage** shows spend by agent, model and user against any budgets.

## Secrets

Credentials for downstream systems are stored as secrets in the cloud provider's
secret manager (AWS Secrets Manager or GCP Secret Manager in your account for
BYOC). They are write-only through the API, so nobody can read a value back, and
an MCP server refers to one by name: `dsn: ${secrets.OTC_DEMO_PG_BLOTTER_DSN}`.
Nothing in this repository contains a credential.
