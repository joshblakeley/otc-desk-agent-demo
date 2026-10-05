# Configure and manage the Agentic Data Plane

**Date:** 2026-10-05. **Checked against:** the ADP production environment and
`rpai` 0.2.42.

## ELI5

Everything that the agent can use is written down in files in this repository.
A tool compares the files with what is running and shows the difference. When
you approve the difference, the tool makes it real. So every change is a written
change that a second person can check before it goes live.

## Keep the configuration in Git and apply it with one command

You describe every agent, tool, policy and secret as a named resource. You keep
the resources in a Git repository, review a change as a pull request, and apply
it with `rpai`. The console and the API manage the same resources, so a change
from any surface shows in the others.

## Three surfaces manage the same resources

| Surface | Use it for |
|---|---|
| Manifest files with `rpai <kind> apply` | Change control, with the repository as the source of truth |
| The ADP console | Inspection, one-off changes, the audit log, transcripts and spend |
| The Connect-RPC and HTTP API | Automation from your own tooling |

Every resource has the same lifecycle: create, get, list, update and delete.
This demo uses these resources:

| Resource | In this demo | File |
|---|---|---|
| MCP server, with data policy | 4 SQL servers | `config/manifests/*.yaml` |
| Access policy (Cedar) | 2 grants for the agent, 1 `forbid` for the broker | `config/policies/*.yaml` |
| Agent, with subagents | `desk-assistant` | `config/prompts/`, rendered by `scripts/render-agent.sh` |
| Secret | 4 database connection strings | `env/secrets.env`, stored by `scripts/01-secret.sh` |
| Budget | 1 daily limit | `scripts/06-budget.sh` |
| Kill-switch policy | 2, on two signals | `config/killswitch/*.yaml`, applied by `scripts/07-killswitch.sh` |
| LLM provider | Already in the organization | Named in `env/production.env` |

Other resource types are guardrails, OAuth providers, OAuth clients and
triggers.

## A manifest round-trips between the console and Git

A manifest is the resource as `rpai <kind> get <name> -o yaml` prints it. So you
can export a resource from the console into Git, and apply a resource from Git.

```
config/*.yaml ──▶ rpai <kind> diff ──▶ shows the change, applies nothing
      │
      └────────▶ rpai <kind> apply ─▶ ADP API ─▶ AI gateway
                  (create or update)   (stores)   (enforces)
```

```bash
rpai mcp diff    -f config/manifests/   # what would change
rpai mcp apply   -f config/manifests/   # create if absent, else update what differs
rpai policy diff -f config/policies/
rpai agent diff  -f <rendered agent manifest>
```

`make diff` runs the three `diff` commands. `apply` and `diff` work on agents,
MCP servers, policies, LLM providers, OAuth providers, OAuth clients and
triggers. Kill-switch policies and budgets have no `apply` command yet, so the
scripts in `scripts/` use the API for them.

How `apply` behaves:

- **It updates fields, not resources.** `apply` changes only the fields that the
  manifest names and that differ from the live resource. A one-line prompt edit
  changes that prompt, and the agent continues to run.
- **It never deletes.** A resource that you remove from the repository stays in
  the environment. You remove it with an explicit `delete`, as in
  `scripts/99-teardown.sh`.
- **It refuses a stale write.** Each resource carries an etag (a version token).
  Two writers cannot overwrite each other without an error.
- **Git holds the history.** The plane stores the current state, not a history
  of versions. The repository records what changed, when, and who approved it.

## A pull-request check gives four-eyes change control

`diff` exits with a non-zero status when the live state differs from the
repository. So it works as a pull-request check:

```
pull request ──▶ CI runs make diff ──▶ diff posted on the PR
                 (service credential)        │
                                             ▼
                              second person approves
                                             │
                                             ▼
                              merge ──▶ CI runs make up
```

Every change to a prompt, a tool exposure or a policy then gets a second review.
It uses the review process that you already run for code. This repository does
not include the CI workflow file.

## Run the plane day to day

- `make status` lists the MCP servers, the agent and the broker's policy.
- `make stop-agent` and `make start-agent` pause and resume the agent.
- The **audit log** in the console records every runtime decision and every
  management change. A management entry shows who changed which resource, and
  when. Where the gateway has them, it adds redacted images of the resource
  before and after the change.
- **Transcripts** show each conversation: every call to a subagent, every tool
  call and its result, and the tokens and cost for each turn.
- **Cost and usage** shows spend by agent, model and person, against any budget.

## Credentials stay in the secret manager

A secret holds a credential for a source system. ADP stores secrets in the
secret manager of your cloud provider: AWS Secrets Manager or GCP Secret Manager.
The API accepts a secret value but never returns it. An MCP server refers to a
secret by name: `dsn: ${secrets.OTC_DEMO_PG_BLOTTER_DSN}`. No file in this
repository contains a credential.
