# User-global guidelines for AI agents

These instructions apply as **default guidance** across all
repositories and are loaded automatically by Gemini CLI from
`~/.gemini/GEMINI.md`.

**Repository-specific instructions and established repository
conventions always take precedence over this file.** If a repository
provides its own `GEMINI.md`, `.github/instructions/*.md`, or similar
guidance, follow those rules wherever they differ from or extend this
file.

## Conversation

- The conversational language should match the user's language. For
  example, if the user speaks in Japanese, respond in Japanese.
- However, comments and documentation should be written in English
  unless there is a clear context otherwise.
- Continue autonomously for low-risk work, but pause and ask a
  concise question when uncertainty or hidden risk makes the next
  step unsafe. When that pause is needed, provide one or more
  recommended response options.

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
- **Prefer signed commits** by default, and follow this bounded
  ladder rather than going straight to unsigned. Each step is **at
  most one attempt**; the whole ladder is **at most three signing
  attempts** per commit. Never loop on hardware-touch prompts.

  1. **Configured signing first.** Use whatever signing the
     repository or user already configures — typically GPG via
     `commit.gpgsign`, but a project may also opt in to persistent
     SSH signing (e.g., `gpg.format = ssh` plus a path-style
     `user.signingkey`). Respect that configuration as-is.

  2. **Classify the failure by category** (do not rely on exact
     English/locale strings — read the category from stderr):
     - **(P) pinentry / TTY** — explicit mention of `pinentry`,
       "no pinentry", `Inappropriate ioctl for device`, "no tty",
       batchmode-input, or an interactive passphrase prompt that
       did not resolve.
     - **(C) configuration / non-transient** — secret key missing,
       unusable, unavailable, or passphrase rejected.
     - **(A) agent-suspect** — agent / socket / IPC errors, or a
       generic `signing failed: Timeout` (any locale) without
       pinentry evidence.
     - **(U) unclear** — the command runner timed out with no
       useful stderr.

  3. **Optional gpg-agent restart (only for categories A and U).**
     Run **`gpgconf --kill gpg-agent`** once and retry the original
     signing exactly once. **Skip this step entirely** if any of
     the following holds, and proceed straight to step 4:
     - `gpgconf` is not on `PATH` (minimal CI / container images);
     - `$SSH_AUTH_SOCK` resolves to gpg-agent's SSH socket
       (compare with `gpgconf --list-dirs agent-ssh-socket`) —
       killing the agent there would also break the SSH fallback;
     - the environment is clearly non-interactive CI where
       repairing local agent state is not worth the latency.

     Restart is bounded recovery, **not** harmless: it drops
     cached passphrases and may force a fresh prompt. Do it once
     or not at all.

  4. **SSH fallback (one bounded attempt).** Allowed for any
     category, including (C). When picking the command:
     - Prefer a project-blessed alias if one exists (some
       repositories expose `git commit-ssh` / `tag-ssh` /
       `rebase-ssh` which wrap a declared fallback key with
       `-c gpg.format=ssh -c user.signingkey=<abs-path> -c
       commit.gpgsign=true`). Do **not** assume the alias exists
       in every repo.
     - Otherwise use per-command flags:
       `git -c gpg.format=ssh -c user.signingkey="<ssh-public-key>" commit -S`.
     - If you start an SSH-signed rebase via such an alias,
       continue it with the alias's own `--continue` form
       (e.g. `git rebase-ssh --continue`); plain
       `git rebase --continue` reverts to the configured primary
       signing.

     Do **not** permanently change the user's signing
     configuration as part of this fallback.

  5. **SSH key discovery** — never assume a fixed key path, and
     never invent one. Pick the key in this order, and skip the
     SSH fallback entirely if none of these yield a usable key:
     1. If `git config --get gpg.format` is already `ssh`, respect
        the existing `user.signingkey` and
        `gpg.ssh.defaultKeyCommand`.
     2. Else if `git config --get gpg.ssh.defaultKeyCommand` is
        set and produces a usable public key, use that key.
     3. Else use the first non-certificate public key reported by
        `ssh-add -L`. This works with hardware-backed keys and
        agents (1Password, Secretive, `gpg-agent --enable-ssh-support`,
        etc.) without needing a private key path.
     - Pass the entire `ssh-add -L` line — public key plus
       comment — as a single quoted value, since key comments
       contain spaces.

  6. **Treat SSH signing as best-effort.** GitHub only marks
     SSH-signed commits as **Verified** when the public key is
     registered as a *signing* key on the user's GitHub profile.
     The agent typically cannot verify that, so the commit may
     show as **Unverified** even though it is cryptographically
     signed.

  7. **Unsigned commit is the accepted final fallback.** If both
     GPG (with or without an agent restart) and the bounded SSH
     attempt fail — no agent, no usable key, hardware-touch
     timeout, unsupported Git/OpenSSH version, missing keyring,
     etc. — create an unsigned commit so that work is not blocked
     by signing failures alone.

  8. **Always report which path was taken** — configured signing,
     gpg-agent restart + retry, SSH fallback (alias or transient),
     or unsigned. When unsigned, disclose **every** underlying
     failure (configured-signing cause, whether the agent restart
     was attempted or skipped + why, and the SSH cause or the
     reason no SSH key was usable) so the user can repair the
     environment.

  In CI / clearly non-interactive automation, prefer the shortest
  path: try the configured signing once, then a single SSH attempt
  if a fallback key is configured, then unsigned. Skip the
  gpg-agent restart entirely — `gpg-agent` in CI is rarely worth
  reviving and may not even exist.

  Do **not** recommend `pinentry-mode loopback` as part of
  automated recovery; it is a setup/policy decision that requires
  non-interactive passphrase access.

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
