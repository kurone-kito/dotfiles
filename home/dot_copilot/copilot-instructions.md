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
- **Prefer signed commits** by default, and try harder before
  falling back to unsigned:
  1. **Configured signing first.** Use whatever signing the
     repository or user already configures — typically GPG via
     `commit.gpgsign`, but a project may also opt in to persistent
     SSH signing (e.g., `gpg.format = ssh` plus a path-style
     `user.signingkey`). Respect that configuration as-is.
  2. **SSH fallback if the configured method is blocked.** When the
     configured signing (most often GPG) fails or hangs because of
     `pinentry`, missing TTY, `gpg-agent`, or a similar environment
     issue, make **one bounded attempt** using SSH signing for that
     commit only. Do **not** permanently change the user's signing
     configuration as part of this fallback. Prefer a project-blessed
     alias if one exists (some repositories expose `git commit-ssh`,
     `git tag-ssh`, `git rebase-ssh`, etc., which wrap a declared
     fallback key); otherwise use per-command flags such as
     `git -c gpg.format=ssh -c user.signingkey="<ssh-public-key>" commit -S`.
     If you start an SSH-signed rebase via such an alias, continue
     it with the alias's own `--continue` form (e.g.
     `git rebase-ssh --continue`) — plain `git rebase --continue`
     reverts to the configured primary signing.
  3. **SSH key discovery** — never assume a fixed key path such as
     `~/.ssh/id_ed25519`. Pick the key in this order:
     1. If `git config --get gpg.format` is already `ssh`, respect
        the existing `user.signingkey` and
        `gpg.ssh.defaultKeyCommand`.
     2. Else if `git config --get gpg.ssh.defaultKeyCommand` is set
        and produces a usable public key, use that key.
     3. Else use the first non-certificate public key reported by
        `ssh-add -L`. This works with hardware-backed keys and
        agents (1Password, Secretive, `gpg-agent --enable-ssh-support`,
        etc.) without needing a private key path.
     - Pass the entire `ssh-add -L` line — public key plus comment —
       as a single quoted value, since key comments contain spaces.
  4. **Treat SSH signing as best-effort.** GitHub only marks
     SSH-signed commits as **Verified** when the public key is
     registered as a *signing* key on the user's GitHub profile.
     The agent typically cannot verify that, so the commit may show
     as **Unverified** even though it is cryptographically signed.
  5. **Unsigned only as the last resort.** If both the configured
     signing method and the bounded SSH retry fail (no agent, no
     usable key, hardware touch timeout, unsupported Git/OpenSSH
     version, etc.), an unsigned commit is acceptable to avoid
     stalling progress.
  6. **Always report which path was taken** — configured signing,
     SSH fallback, or unsigned. When unsigned, disclose **both** the
     primary failure reason and why the SSH fallback did not succeed.

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
