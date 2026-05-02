# User-global guidelines for AI agents

These instructions apply as **default guidance** across all
repositories and are loaded automatically by GitHub Copilot CLI
from `~/.copilot/copilot-instructions.md`.

**Repository-specific instructions and established repository
conventions always take precedence over this file.** If a
repository provides its own `.github/copilot-instructions.md`,
`AGENTS.md`, or similar guidance, follow those rules wherever
they differ from or extend this file.

## Conversation

- The conversational language should match the user's language.
  For example, if the user speaks in Japanese, respond in Japanese.
- However, comments and documentation should be written in English
  unless there is a clear context otherwise.
- If uncertainties, concerns, or other implementation issues arise
  while running in Agent mode, promptly switch to Plan mode and ask
  the user questions. In such cases, provide one or more recommended
  response options.
- Outside GitHub Copilot, interpret the `Agent mode` and `Plan mode`
  wording by intent: continue autonomously for low-risk work, but
  pause and ask a concise question when uncertainty or hidden risk
  makes the next step unsafe. When that pause is needed, provide one
  or more recommended response options.

## Commit rules

Follow
[Conventional Commits](https://www.conventionalcommits.org/) unless
the repository specifies a different convention.

- Use the format: `<type>[optional scope]: <description>`
- Write from the **user's perspective** — briefly state what this
  commit solves or improves
- Write in **lowercase**, imperative mood (e.g., "add", not "Added")
- Keep the subject line under **72 characters**; do **not** end with
  a period
- Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`,
  `chore`, `ci`, `build`, `perf`
- Include a body when the subject line alone is not self-explanatory;
  the body should address **why**, **context**, and **what changed**
- Append `!` after the type/scope for breaking changes and add a
  `BREAKING CHANGE:` footer
- Keep each commit **atomic** — one logical change per commit;
  separate refactoring, formatting, and dependency updates from
  behavior changes

## Coding standards

When the repository does not define its own conventions, prefer
these defaults:

- **Line endings**: LF
- **Trailing whitespace**: trimmed (except in Markdown where
  trailing spaces may be significant)
- **Final newline**: always present
- **File naming**: lowercase with hyphens unless constrained by a
  platform convention (e.g., `Makefile`, `Dockerfile`)

## Guardrails

- **Do not** modify community documents (CODE_OF_CONDUCT,
  CONTRIBUTING) without explicit approval
- **Do not** claim tests or commands succeeded if they were not
  actually run
