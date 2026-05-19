# AI tooling strategy

This repository currently prioritizes GitHub Copilot because it
provides the best latency and workflow fit for day-to-day vibe coding
in this template.

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
a **user-global** instructions layer via chezmoi. Each supported AI
CLI reads one file from the user's home directory before loading any
repository-specific instructions:

| Agent              | Chezmoi source                                 | Deployed to                          |
| ------------------ | ---------------------------------------------- | ------------------------------------ |
| GitHub Copilot CLI | `home/dot_copilot/copilot-instructions.md`     | `~/.copilot/copilot-instructions.md` |
| Codex CLI          | `home/dot_codex/AGENTS.md`                     | `~/.codex/AGENTS.md`                 |
| Claude Code        | `home/dot_claude/CLAUDE.md`                    | `~/.claude/CLAUDE.md`                |
| Gemini CLI         | `home/dot_gemini/GEMINI.md`                    | `~/.gemini/GEMINI.md`                |

**Precedence rule**: project-level instructions always take
precedence over the user-global file. Each user-global file opens
with an explicit deference paragraph stating this rule.

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
- Extract shared text into a neutral document only after benchmarks
  show that the Copilot-first workflow does not regress.
- When a rule uses a Copilot-specific feature name, document the
  underlying intent so other agents can map it to their own interaction
  model.

## Maintenance notes

- Treat this file as a human-facing strategy note, not as the primary
  instruction file for any agent.
- When updating AI guidance, review `README.md`,
  `.github/copilot-instructions.md`, `AGENTS.md`, `CLAUDE.md`,
  `GEMINI.md`, and the four user-global source files under
  `home/dot_copilot/`, `home/dot_codex/`, `home/dot_claude/`,
  and `home/dot_gemini/` together.
