# Guidelines for AI Agents

A collection of configuration files that we use.

When contributing to this repository using AI agents, adhere to the
following guidelines to ensure high-quality contributions that align with
the project's standards and practices:

## Repository architecture

This repository is a **git worktree** of
[kurone-kito/dotfiles](https://github.com/kurone-kito/dotfiles),
checked out on the `migrate-to-chezmoi` branch. The directory name
`dotfiles.migrate-to-chezmoi` reflects the branch name, not a
separate repository.

- **Remote origin:** `kurone-kito/dotfiles`
- **Branch:** `migrate-to-chezmoi`
- **CI badges and workflow URLs** correctly reference
  `kurone-kito/dotfiles`

Do not treat this as a standalone repository or suggest renaming
remote URLs or badge links.

## Tooling priority and compatibility

This repository is intentionally optimized for GitHub Copilot CLI and
VS Code Copilot Chat because they are the primary tools used for
day-to-day work and benchmarking.

`AGENTS.md` and `CLAUDE.md` exist as lightweight compatibility entry
points for Codex and Claude Code. Keep this file as the canonical,
fully detailed guide unless benchmark results justify a more neutral
layout.

## Conversation

- The conversational language should match the user's language.
  For example, if the user speaks in Japanese, respond in Japanese.
- However, comments and documentation should be written in English unless
  there is a clear context otherwise.
- If uncertainties, concerns, or other implementation issues arise while
  running in Agent mode, promptly switch to Plan mode and ask the user
  questions. In such cases, provide one or more recommended response
  options.
- Outside GitHub Copilot, interpret the `Agent mode` and `Plan mode`
  wording by intent: continue autonomously for low-risk work, but pause
  and ask a concise question when uncertainty or hidden risk makes the
  next step unsafe. When that pause is needed, provide one or more
  recommended response options.

## Commit rules

This project follows
[Conventional Commits](https://www.conventionalcommits.org/).
A `.gitmessage` template is available at the repository root for
guidance when writing commit messages.

### Format

```txt
<type>[optional scope]: <user-facing description>

<body: address purpose, context, and what changed>

[optional footer(s)]
```

### Subject line

- Use the format: `<type>[optional scope]: <description>`
- Write from the **user's perspective** — briefly state what this
  commit solves or improves for the end user or developer
- Write in **lowercase**, imperative mood (e.g., "add", not "added")
- Keep the subject line under **72 characters**
- Do **not** end with a period

### Types

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`,
`chore`, `ci`, `build`, `perf`

### Scopes

- Optional, in parentheses: `feat(ci):`, `fix(lint):`, `docs(readme):`
- Keep scopes **lowercase**, short, and consistent
- Use the directory or component name that best describes the area

### Body (line 3+)

The body should address three aspects:

- **Why** — the purpose or motivation behind the change
- **Context** — what was needed, the situation or constraint
- **What changed** — the concrete action taken

Prefer the **why → context → change** order when practical.
Write these as **natural prose** — weave the aspects into
coherent sentences rather than using labeled sections. Labeled
sections (`Why:` / `Context:` / `Change:`) are acceptable only
when explicit paragraph separation improves clarity.

Omit any aspect whose information **cannot be reliably inferred**.
If the subject line is self-explanatory, the body may be omitted
entirely. **Breaking changes must always include a body.**

Wrap body lines at **72 characters**.

### Breaking changes

- Append `!` after the type/scope: `feat!: remove deprecated endpoint`
- Add a `BREAKING CHANGE:` trailer in the footer with a detailed
  explanation of what breaks and migration steps

### Footers / trailers

- `Closes #<issue>` / `Refs #<issue>` — link to issues
- `Co-authored-by: Name <email>` — credit co-authors
- `BREAKING CHANGE: <description>` — detail the breaking change

### Atomic commits

Keep each commit as **small and focused** as possible:

- **One logical change per commit** — if the subject line needs "and",
  consider splitting
- **Separate refactoring** from behavior changes
- **Separate formatting/style** changes from logic changes
- **Separate dependency updates** from code changes
- When in doubt, prefer smaller commits that are easy to review,
  revert, and bisect

### Signing fallback

This repository configures **GPG** signing for commits and tags via
`home/dot_config/git/config.tmpl`. When AI agents create commits and
the configured GPG signing fails or hangs (`pinentry`, missing TTY,
`gpg-agent`, or similar environment issues), follow this ladder
rather than going straight to unsigned:

1. Make **one bounded retry** with transient SSH signing for that
   commit only:
   `git -c gpg.format=ssh -c user.signingkey="<ssh-public-key>" commit -S`.
   Do **not** edit `home/dot_config/git/config.tmpl` or any other
   chezmoi-managed git template to enable SSH signing — the fallback
   must never persist.
2. Pick the SSH key without assuming a fixed path such as
   `~/.ssh/id_ed25519`:
   1. respect existing SSH-signing config if `git config --get
      gpg.format` is already `ssh`,
   2. else use a usable public key from
      `git config --get gpg.ssh.defaultKeyCommand`,
   3. else use the first non-certificate public key from
      `ssh-add -L`. Pass the entire line, including the comment, as
      a single quoted argument value.
3. Treat SSH signing as **best-effort** — GitHub may still mark the
   commit **Unverified** if the key is not registered as a *signing*
   key on the user's GitHub profile.
4. If SSH signing also fails or no key is available, an unsigned
   commit is acceptable as a final resort.
5. Always **report which path was used** (GPG, SSH fallback, or
   unsigned). When unsigned, disclose both the GPG failure and why
   SSH fallback did not succeed.

### Examples

#### Good — single-line (trivial change)

```txt
fix: correct typo in feature request template
```

#### Good — prose body

```txt
feat(ci): add concurrency settings to lint workflow

Parallel lint runs on the same branch waste resources and
cause race conditions in status checks. GitHub Actions
supports concurrency groups that automatically cancel
redundant runs, so add a concurrency group keyed on branch
name with cancel-in-progress enabled.

Refs #42
```

#### Good — breaking change

```txt
feat!: require node 20 as minimum version

Node 18 reaches end-of-life and lacks native fetch support
used by the new HTTP client. All production environments
have already been upgraded to node 20+, so update the
engines field and CI matrix to require node >= 20.

BREAKING CHANGE: drop support for node 16 and 18. Users
must upgrade to node 20 or later.
Closes #108
```

#### Bad — vague, developer-centric

```txt
fix: update code
```

#### Bad — too large / non-atomic

```txt
feat: add auth system and refactor database layer and update docs
```

## Coding Standards

- **Indentation**: 2 spaces (enforced by `.editorconfig`)
- **Line endings**: LF only (enforced by `.editorconfig` and
  `.gitattributes`)
- **Trailing whitespace**: trimmed (except in Markdown)
- **Final newline**: always present
- **File naming**: lowercase with hyphens (e.g., `feature-request.yml`)
  unless constrained by a platform convention (e.g., `CONTRIBUTING.md`)

### PowerShell profile

Scripts under `home/dot_config/powershell/conf.d/` are deployed on
**all platforms** (Windows, Linux, macOS) and loaded by both
**PowerShell 5 (Desktop)** and **PowerShell 7+ (Core)** through the
profile loader shim. Follow these rules when adding or modifying
conf.d scripts:

- **Cross-platform by default** — every conf.d script must either
  work portably or include an OS guard. Windows-only env vars
  (`$env:LOCALAPPDATA`, `$env:ProgramFiles`,
  `${env:ProgramFiles(x86)}`) are `$null` on Unix; test or guard
  before use.
- **OS guard pattern (PS5-safe)** — use `$IsWindows -eq $false`
  (not `-not $IsWindows`). In PS5 `$IsWindows` is `$null`;
  `$null -eq $false` evaluates to `$false`, so the guard correctly
  allows PS5 (which is always Windows) to continue.
- **Path-list separators** — use `[IO.Path]::PathSeparator` instead
  of a hardcoded `;` or `:` when splitting or joining path-list
  environment variables (e.g., `PATH`, `MISE_TRUSTED_CONFIG_PATHS`).
- **PS5 compatibility traps**:
  - `Join-Path` accepts only **2 arguments** — use nested calls
  - PSReadLine is v2.0 — `PredictionSource` requires a version
    guard (`(Get-Module PSReadLine).Version -ge '2.2.0'`)
  - `$IsWindows` / `$IsLinux` / `$IsMacOS` do **not exist** in PS5
- **Reference patterns**: `60-venv.ps1` (cross-platform path
  search), `00-env.ps1` (PSReadLine version guard), `01-path.ps1`
  (OS guard + portable separator)

## Testing

This project uses platform-specific test frameworks for the chezmoi
scripts:

- **Bash**: [bats-core](https://github.com/bats-core/bats-core) with
  bats-support, bats-assert, and bats-file (git submodules under
  `tests/bash/helpers/`)
- **PowerShell**: [Pester 5+](https://pester.dev/)

### Running tests

Bash (Linux/macOS/WSL):

```bash
git submodule update --init --recursive
tests/bash/helpers/bats-core/bin/bats tests/bash/
```

PowerShell (Windows):

```powershell
Invoke-Pester tests/powershell/ -Output Detailed
```

On non-Windows `pwsh`, Windows-only Pester scopes are skipped. The
authoritative full PowerShell run remains Windows local execution and
Windows CI.

### When to run

- **After modifying** any script template in `home/` (especially
  `run_onchange_after_*.tmpl` files)
- **Before committing** script changes — verify that existing tests
  still pass
- **After adding** a new script — add corresponding tests and fixtures

### Test strategy

Tests use **pre-rendered fixtures** (hardcoded test data) rather than
chezmoi template rendering. Fixtures live in:

- `tests/bash/fixtures/`
- `tests/powershell/fixtures/`

Each fixture mirrors the final rendered script with sample profile data.
This isolates tests from chezmoi's template engine and
`chezmoi.toml` configuration.

CI runs both suites on every push and pull request
(`.github/workflows/test.yml`).

## Guardrails

- **Do not** modify community documents (CODE_OF_CONDUCT, CONTRIBUTING)
  without explicit approval
