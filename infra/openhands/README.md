# OpenHands (z.ai) — autonomous agent on your box

OpenHands is an open-source autonomous coding agent. Unlike GitHub Copilot it
routes models through **LiteLLM**, so it can use **your z.ai key/model**. It does
**not** run the Squad framework — it inherits the squad's conventions via
`.openhands/microagents/repo.md` (always loaded), and wears each role as a "hat".

## Run locally

```bash
cd infra/openhands
cp .env.example .env          # set LLM_API_KEY (rotate the leaked z.ai key first!)
docker compose up             # UI → http://localhost:3311
```
Point it at a project checkout (mount it / open it in the UI), give it a task, and it
works in a sandboxed runtime container and proposes a diff/PR.

## Model / endpoint
- `LLM_MODEL=openai/glm-4.6` + `LLM_BASE_URL=https://api.z.ai/api/paas/v4` → LiteLLM's
  OpenAI-compatible path to z.ai. Confirm the current model name + endpoint in the z.ai console.
- Alternatively use z.ai's Anthropic-compatible endpoint with the `anthropic/…` model form.

## Autonomous issue → PR (optional)
OpenHands has a GitHub resolver (App/Action) that can pick up labeled issues and open
draft PRs — the open-source analogue of Copilot coding agent, but on **your** model.
Run it on the **normal self-hosted runner** (see below); pass the z.ai key from a repo
secret (`Z_AI_API_KEY`), never inline.

## How the squad maps in
| Squad | OpenHands |
|-------|-----------|
| multi-agent roles + routing | single agent + `.openhands/microagents/` |
| charters / `.copilot/skills` | repo microagent (`repo.md`) + keyword microagents |
| `squad:{member}` issue labels | one resolver; encode role focus in the task prompt |

You inherit the *knowledge*, not the orchestration. If you need true multi-role
parallelism, keep the squad on Claude Code and use OpenHands for autonomous single-agent runs.

> Versions/endpoints drift — verify image tags (OpenHands) and base URL/model (z.ai) against current docs.
