---
type: guide
title: AI tooling strategy
description: Explains why this repository prioritizes GitHub Copilot for AI tooling and how its instruction-file layers relate to each other.
---

# AI tooling strategy

This repository currently prioritizes GitHub Copilot because it
provides the best latency and workflow fit for day-to-day vibe coding
in this repository.

## Canonical guidance

- [.github/copilot-instructions.md](../.github/copilot-instructions.md)
  is the canonical, fully detailed AI guide. Keep it complete enough
  for GitHub Copilot CLI and VS Code Copilot Chat.
- [AGENTS.md](../AGENTS.md) is a Codex compatibility entry point. It
  must stay self-contained for the rules that Codex needs immediately,
  then point to the canonical Copilot guide for the remaining detail.
- [CLAUDE.md](../CLAUDE.md) is a Claude Code compatibility entry point
  with the same role.
- [GEMINI.md](../GEMINI.md) is a Gemini CLI compatibility entry point
  with the same role.

## User-global instructions

In addition to the project-level layer above, this repository ships
a **user-global** instructions layer via chezmoi. Deployed text comes
from the shared template `home/.chezmoitemplates/ai-agent-user-global`,
and each per-agent `*.tmpl` calls it.

| Agent              | Chezmoi source                                                          | Deployed to                                                                 |
| ------------------ | ----------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| GitHub Copilot CLI | `home/dot_copilot/copilot-instructions.md.tmpl`                         | `~/.copilot/copilot-instructions.md`                                        |
| Codex CLI          | `home/dot_codex/AGENTS.md.tmpl`                                         | `~/.codex/AGENTS.md`                                                        |
| Claude Code        | `home/dot_claude/CLAUDE.md.tmpl`                                        | `~/.claude/CLAUDE.md`                                                       |
| Gemini CLI         | `home/dot_gemini/GEMINI.md.tmpl`                                        | `~/.gemini/GEMINI.md`                                                       |
| Antigravity CLI    | `home/dot_gemini/GEMINI.md.tmpl` and `home/dot_gemini/AGENTS.md`        | `~/.gemini/GEMINI.md` (shared body) and `~/.gemini/AGENTS.md` (pointer)     |
| OpenCode           | `home/dot_config/opencode/AGENTS.md.tmpl`                               | `~/.config/opencode/AGENTS.md`                                              |

Grok Build has no dedicated source. Its `[compat.claude]` layer,
enabled by default
(<https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/05-configuration.md>),
scans `~/.claude/CLAUDE*.md`, which `home/dot_claude/CLAUDE.md.tmpl`
deploys, so it inherits the Claude Code baseline. See roadmap #491.

**Precedence rule**: project-level instructions always take
precedence over the user-global file. Each shared-template body opens
with an explicit deference paragraph stating this rule. The
Antigravity pointer at `home/dot_gemini/AGENTS.md` does not repeat
that paragraph; it only points at `~/.gemini/GEMINI.md`.

Edit the shared template for cross-agent changes. Edit a single
`.tmpl` only for agent-specific wording.

The user-global layer is repository-independent and intentionally
smaller than the canonical `.github/copilot-instructions.md`. It
carries four sections available in any repository: Conversation
(language matching and autonomous/pause behavior), Commit rules
(Conventional Commits format and the bounded signing fallback
ladder), Coding standards, and Guardrails.

## Change policy

- Prefer preserving existing Copilot behavior over abstracting too
  early.
- Duplicate only the minimum guidance needed for non-Copilot agents to
  act safely and predictably.
- Edit the shared template for cross-agent changes. Edit one `.tmpl`
  only for agent-specific wording.
- When a rule uses a Copilot-specific feature name, document the
  underlying intent so other agents can map it to their own interaction
  model.

## Maintenance notes

- Treat this file as a human-facing strategy note, not as the primary
  instruction file for any agent.
- When updating AI guidance, review `README.md`,
  `.github/copilot-instructions.md`, `AGENTS.md`, `CLAUDE.md`,
  `GEMINI.md`, `home/.chezmoitemplates/ai-agent-user-global`, and the
  user-global sources under `home/dot_copilot/`, `home/dot_codex/`,
  `home/dot_claude/`, `home/dot_gemini/`, and
  `home/dot_config/opencode/` together. Those sources are `.tmpl`
  files plus `home/dot_gemini/AGENTS.md`.
