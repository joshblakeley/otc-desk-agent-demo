#!/usr/bin/env bash
# Print the agent manifest on stdout, with prompts read from config/prompts/.
#
# Prompts stay as markdown files because that is where they are edited and
# reviewed. This assembles them into one manifest for `rpai agent apply -f -`.

. "$(dirname "$0")/_lib.sh"
cd "$ROOT"

python3 - "$AGENT_NAME" "$AGENT_DISPLAY_NAME" "$LLM_MODEL" "$LLM_PROVIDER" \
          "$MCP_BLOTTER" "$MCP_PRICING" "$MCP_REFDATA" "$MCP_ROLLUP" "$ENV" <<'PY'
import sys, yaml, pathlib

def _str(dumper, data):
    style = "|" if "\n" in data else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)
yaml.add_representer(str, _str)

(name, display, model, provider, blotter, pricing, refdata, rollup, env) = sys.argv[1:10]
read = lambda p: pathlib.Path(p).read_text()

doc = {
    "@type": "type.googleapis.com/redpanda.api.adp.v1alpha1.Agent",
    "name": name,
    "display_name": display,
    "description": "Single entry point for desk questions. Answers volume and counterparty questions itself; hands trade questions to trade-analyst and price questions to pricing-analyst.",
    "tags": {"demo": "otc-desk", "owner": "otc-desk-agent-demo", "env": env},
    "managed": {
        "spec": {
            "model": model,
            "llm_provider": provider,
            "system_prompt": read("config/prompts/system-prompt.md"),
            # The orchestrator's own servers. Each specialist's are chosen
            # independently, so the orchestrator cannot reach the blotter.
            "mcp_servers": [rollup, refdata],
            "subagents": {
                # The description is the routing rule the orchestrator reads.
                "trade-analyst": {
                    "description": "Questions about individual executed trades: sizes, prices, venues, brokers, counterparties on a trade, status. Reads the trade blotter.",
                    "system_prompt": read("config/prompts/subagents/trade-analyst.md"),
                    "mcp_servers": [blotter],
                },
                "pricing-analyst": {
                    "description": "Questions about where a market is now: indicative bid, offer and mid, and comparing a traded price with the current mid.",
                    "system_prompt": read("config/prompts/subagents/pricing-analyst.md"),
                    "mcp_servers": [pricing],
                },
            },
            "max_iterations": 12,
        }
    },
}
print(yaml.dump(doc, sort_keys=False, default_flow_style=False, width=100, allow_unicode=True))
PY
