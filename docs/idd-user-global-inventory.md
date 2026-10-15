---
type: reference
title: IDD User-Global Install Inventory
description: Records the paths the idd-skill v0.16.0 user-global installer writes, captured from one isolated installer run at commit e4d425ee, as the reference for the v0.16.0 payload vendoring and re-import tracks.
tags: [user-global, install, inventory, idd]
---

# IDD User-Global Install Inventory

This page records what the upstream `idd-skill` v0.16.0 user-global
installer writes. The list below is the captured output of one installer run
at commit `e4d425ee28b1893dd45c4996b2506619018c4b2b`, in a disposable HOME.
The [run record](#run-record) gives the conditions and the checks. The
vendoring track (#648) and the re-import procedure (#647) use this page as
their reference. It is not the chezmoi source, and it does not change any
chezmoi template under `home/`.

## Source

| Item                    | Value                                                                                               |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| Repository              | `kurone-kito/idd-skill`                                                                             |
| Tag                     | `v0.16.0` (tag object `0506889e9a9cc9a58232e59397f2298351823fe4`)                                   |
| Commit                  | `e4d425ee28b1893dd45c4996b2506619018c4b2b`                                                          |
| Archive                 | `https://codeload.github.com/kurone-kito/idd-skill/tar.gz/e4d425ee28b1893dd45c4996b2506619018c4b2b` |
| Archive size and digest | 10,306,947 bytes; SHA-256 `9bdfb4448a2638ac90cc1d7cfb182e480c01501f7be22fad199ef190cc2d0062`       |

Sources read: `docs/user-global-install.md`;
`scripts/user-global-install.mjs` (generated from
`src/scripts/user-global-install.mts`); `scripts/user-global-paths.mjs`;
`scripts/user-global-entry-files.mjs`; `scripts/user-global-receipt.mjs`;
`scripts/idd-activation.mjs`; `scripts/idd-onboard.mjs`;
`audit/sync-manifest.json` (block `idd-template-core-files`);
`skills/issue-authoring/`; `skills/idd-spec-audit/`;
`idd-template/user-global/entry.md`; and `package.json` (version `0.16.0`).

## Run record

Conditions of the run:

- The archive named in [Source](#source) was downloaded and checked against
  its SHA-256 digest. It was unpacked into a fresh, empty scratch directory,
  and the installer was run from that tree. No other command from the archive
  was run.
- `HOME` was `<run-home>`, the `home/` directory under a fresh `mktemp -d`
  directory. `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, and
  `XDG_STATE_HOME` were `<run-home>/.config`, `<run-home>/.local/share`,
  `<run-home>/.cache`, and `<run-home>/.local/state`, which are the default
  locations under that HOME. `CODEX_HOME` was unset. The environment was
  cleared with `env -i`, and `PATH` held Node.js 24.21.0 and the system
  directories. No chezmoi command was run.
- The operator's real home directory was not used. Before and after the run,
  its install roots and the three entry-file paths were recorded (existence,
  size, and SHA-256), and none of them changed.

The command, as run in each step (`$UPSTREAM` is the unpacked tree,
`$RUN_HOME` is `<run-home>`, and `$NODE_BIN` is the `bin` directory of
Node.js 24.21.0):

```sh
cd "$UPSTREAM" && env -i HOME="$RUN_HOME" PATH="$NODE_BIN:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$RUN_HOME/.config" XDG_DATA_HOME="$RUN_HOME/.local/share" \
  XDG_CACHE_HOME="$RUN_HOME/.cache" XDG_STATE_HOME="$RUN_HOME/.local/state" \
  node scripts/idd-onboard.mjs --install-user-global
```

Step 1, empty HOME. The command was first run against an empty `<run-home>`.
It exited 1 and wrote nothing. Its stderr, with the run directory written as
`<run-home>`, was:

```text
idd-onboard: refuse: install refused before any write; nothing was written: the parent <run-home>/.local/share of <run-home>/.local/share/idd-skill does not exist, and the installer does not create it; nothing was written; the parent <run-home>/.claude of <run-home>/.claude/skills does not exist, and the installer does not create it; nothing was written; the parent <run-home>/.agents of <run-home>/.agents/skills does not exist, and the installer does not create it; nothing was written; <run-home>/.config/opencode does not exist, and its parent chain is incomplete; the installer creates a harness directory only as a leaf whose parent exists; nothing was written
```

Step 2, preconditions. The message names three missing parents,
`<run-home>/.local/share`, `<run-home>/.claude`, and `<run-home>/.agents`. It
reports `<run-home>/.config/opencode` as having an incomplete parent chain.
The four parent directories, including `<run-home>/.config`, were then created
with `mkdir -p`. The `mkdir -p` also created `<run-home>/.local`, the parent of
`<run-home>/.local/share`. Nothing else was created before the run.

Step 3, install. The same command exited 0 and wrote nothing to stderr. Its
stdout had 110 lines beginning with `create`, one per receipt entry, with the
`current` link among them. It then printed the helper-install hints,
`npm install -g @kurone-kito/idd-skill@0.16.0` and
`pnpm add -g @kurone-kito/idd-skill@0.16.0`. The installer prints these hints
but does not run them.

Checks on the run:

- The sorted relative paths under `<run-home>`, taken with the `find` command
  in [Checking a later run](#checking-a-later-run), are identical to the list
  in this page: 111 lines, no difference.
- The receipt is version 1 and has 110 entries: 27 directories, 82 files, and
  one link. It does not list `receipt.json` itself. The three entry files are
  recorded as `file`.
- `current` is a symbolic link whose target is the absolute path
  `<run-home>/.local/share/idd-skill/0.16.0`.
- The 79 payload and skill files (67 payload files, including
  `user-global/entry.md`, and 12 skill files) are byte-identical, by SHA-256,
  to the upstream files they were copied from.
- `.claude/CLAUDE.md` holds the managed block with the `@` import line.
  `.codex/AGENTS.md` holds the managed block around the entry text, byte for
  byte. `.config/opencode/opencode.json` has the three-line form.

## Assumptions

The list holds only when all of the following are true before the run:

- `$HOME` is an absolute path that does not start with `//`, and the
  directories under [Preconditions](#preconditions-for-an-isolated-home) exist.
- `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `CODEX_HOME` are unset or are not
  qualified roots, so the defaults apply. The run set the XDG variables to
  the default locations under its HOME, which gives the same layout.
- The harness list is the default: all three harnesses, `claude`, `codex`,
  and `opencode`.
- No entry file, `.codex/`, `.config/opencode/`, or skill file exists yet.

An existing entry file is edited rather than created. The receipt then
records it as `managed-block` or `json-instruction`, not as `file`.

Chezmoi overlap: this repository's `home/dot_claude/CLAUDE.md.tmpl` and
`home/dot_codex/AGENTS.md.tmpl` render `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md`. On a machine where chezmoi has applied them, the
installer adds one managed block to each file and does not create them.
OpenCode's entry is `opencode.json`, so the `AGENTS.md` that
`home/dot_config/opencode/AGENTS.md.tmpl` renders is not an installer target.

## Preconditions for an isolated HOME

- `HOME` must be an absolute path that does not start with `//`.
- These directories must already exist. The installer never creates the
  directory above a root or a harness directory. Below each root it creates
  each missing directory with one non-recursive mkdir, parents first. A
  missing parent refuses the whole run before any write:
  - `$HOME/.local/share`, the parent of the data root, so `$HOME/.local`
    must exist too;
  - `$HOME/.claude`, the parent of the Claude skill root, required even when
    only Codex CLI is selected;
  - `$HOME/.agents`, the parent of the agent skill root, required even when
    only Claude Code is selected;
  - `$HOME/.config`, the parent of the OpenCode directory, required whenever
    OpenCode is selected, which is the default.
- An empty `HOME` is therefore not enough, as the empty-HOME step of the
  [run record](#run-record) shows. The installer creates
  `.local/share/idd-skill/`, `.claude/skills/`, `.agents/skills/`, `.codex/`,
  and `.config/opencode/` itself.
- If `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, or `CODEX_HOME` is a qualified root,
  the same rule applies to its parent directory. This page assumes they are
  unset, or set to the default locations under `HOME`, as in the run. The
  upstream statement is in
  [`docs/user-global-install.md`](https://github.com/kurone-kito/idd-skill/blob/e4d425ee28b1893dd45c4996b2506619018c4b2b/docs/user-global-install.md#preconditions).

## What the installer writes

| Item           | Location (relative to `$HOME`)                                                                             | Kind                                            |
| -------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Data root      | `.local/share/idd-skill/`                                                                                  | directory, created                              |
| Payload        | `.local/share/idd-skill/0.16.0/` and the 67 files under it                                                 | directories and files, created                  |
| Current link   | `.local/share/idd-skill/current`, a symbolic link to the absolute path `$HOME/.local/share/idd-skill/0.16.0` | symbolic link, created                          |
| Receipt        | `.local/share/idd-skill/receipt.json`                                                                      | file, installer artifact                        |
| Claude skills  | `.claude/skills/` with `issue-authoring/` and `idd-spec-audit/`                                            | directories and files, created                  |
| Agent skills   | `.agents/skills/` with `issue-authoring/` and `idd-spec-audit/`                                            | directories and files, created                  |
| Claude entry   | `.claude/CLAUDE.md`                                                                                        | file, created                                   |
| Codex entry    | `.codex/AGENTS.md`                                                                                         | file, created, and directory `.codex/` created  |
| OpenCode entry | `.config/opencode/opencode.json`                                                                           | file, created, and directory `.config/opencode/` created |

- `$CODEX_HOME` replaces `.codex` when it is a qualified root, and
  `$XDG_CONFIG_HOME` replaces `.config` when it is a qualified root.
- A fresh install records each entry file as a whole file. The receipt lists
  every created path except `receipt.json` itself.
- The installer does not copy `scripts/` helpers.

## Payload

The payload is the 66 paths of the `idd-template-core-files` block in
`audit/sync-manifest.json`, with the `idd-template/` prefix removed, plus
`user-global/entry.md`. That is 67 files.

- It includes `.github/instructions/lite/` (11 files) and
  `user-global/entry.md`.
- It contains no `scripts/` directory. Three shell files sit under
  `.githooks/` (`_idd-worktree-guard.sh`, `pre-commit`, `pre-push`), so the
  precise statement is "no `scripts/` directory".
- `receipt.json` is written by the installer and is not part of the payload.
  It is an installer artifact, not a chezmoi target.

## Entry-file contents

The gated entry text is `<data root>/current/user-global/entry.md`. Each
entry file is created whole when it does not exist, and the receipt records
it as `file`.

- `.claude/CLAUDE.md` holds one managed block: the begin marker
  `<!-- idd-skill:user-global:begin -->`, then the line
  `@<HOME>/.local/share/idd-skill/current/user-global/entry.md`, then the end
  marker `<!-- idd-skill:user-global:end -->`.
- `.codex/AGENTS.md` holds the same two markers around the text of
  `user-global/entry.md`.
- `.config/opencode/opencode.json` is written as this document, with a final
  newline:

```json
{
  "instructions": ["<HOME>/.local/share/idd-skill/current/user-global/entry.md"]
}
```

When the file already exists, the installer edits it in place. A Markdown
file gets its managed block added or replaced. `opencode.json` gets one
string in its `instructions` array. The receipt then records
`managed-block` or `json-instruction`.

## Windows

Planning checks the version pattern, then calls `assertRealChain`, which
requires the no-follow and nonblocking open flags before any write. A
platform without them refuses with nothing written. Windows is such a
platform, and `docs/user-global-install.md` says the installer refuses there
before any write.

## What the 111 entries are

- Payload: the 66 `paths` of the `idd-template-core-files` block in
  `audit/sync-manifest.json`, with the `idd-template/` prefix removed, plus
  `user-global/entry.md`. That is 67 files.
- Skill trees: every regular file under `skills/issue-authoring/` (4 files)
  and `skills/idd-spec-audit/` (2 files), for each of the two skill roots.
  That is 12 files.
- Other files: `CLAUDE.md`, `AGENTS.md`, and `opencode.json` in their harness
  directories, the `current` link, and `receipt.json` in the data root. That
  is 5 entries.
- Directories: every directory the run creates. The data root and its
  `0.16.0/` version directory, plus 13 payload subdirectories, make 15. Each
  skill root holds 5 (itself, two skill directories, and two `references/`
  directories), so both roots make 10. The harness directories `.codex/` and
  `.config/opencode/` make 2. That is 27 directories.

Totals: 67 + 12 + 5 = 84 files and links, and 27 directories, so the list has
111 entries. These counts match the run record: its receipt has 110 entries,
and `receipt.json`, which the receipt does not list, makes 111. Sorting uses
`LC_ALL=C` (byte order), so `SKILL.md` sorts before `references/` (uppercase
before lowercase). A locale sort such as `ja_JP.utf8` puts `references/` first.

## Sorted path list

This is the captured output of the run in the [run record](#run-record). The
paths are relative to `<run-home>`. One path is on each line. A trailing `/`
marks a directory. The `current` entry is a symbolic link. `receipt.json` and
the three entry files are regular files.

```text
.agents/skills/
.agents/skills/idd-spec-audit/
.agents/skills/idd-spec-audit/SKILL.md
.agents/skills/idd-spec-audit/references/
.agents/skills/idd-spec-audit/references/report-template.md
.agents/skills/issue-authoring/
.agents/skills/issue-authoring/SKILL.md
.agents/skills/issue-authoring/references/
.agents/skills/issue-authoring/references/contract.md
.agents/skills/issue-authoring/references/draft-patterns.md
.agents/skills/issue-authoring/references/workflow-boundary.md
.claude/CLAUDE.md
.claude/skills/
.claude/skills/idd-spec-audit/
.claude/skills/idd-spec-audit/SKILL.md
.claude/skills/idd-spec-audit/references/
.claude/skills/idd-spec-audit/references/report-template.md
.claude/skills/issue-authoring/
.claude/skills/issue-authoring/SKILL.md
.claude/skills/issue-authoring/references/
.claude/skills/issue-authoring/references/contract.md
.claude/skills/issue-authoring/references/draft-patterns.md
.claude/skills/issue-authoring/references/workflow-boundary.md
.codex/
.codex/AGENTS.md
.config/opencode/
.config/opencode/opencode.json
.local/share/idd-skill/
.local/share/idd-skill/0.16.0/
.local/share/idd-skill/0.16.0/.cspell.config.yml
.local/share/idd-skill/0.16.0/.githooks/
.local/share/idd-skill/0.16.0/.githooks/_idd-worktree-guard.sh
.local/share/idd-skill/0.16.0/.githooks/pre-commit
.local/share/idd-skill/0.16.0/.githooks/pre-push
.local/share/idd-skill/0.16.0/.github/
.local/share/idd-skill/0.16.0/.github/idd/
.local/share/idd-skill/0.16.0/.github/idd/config.json
.local/share/idd-skill/0.16.0/.github/instructions/
.local/share/idd-skill/0.16.0/.github/instructions/idd-advisory-wait.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-ci.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-claim.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-discover.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-merge-handoff.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-merge.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-orchestrator.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-overview-appendix.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-overview-core.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-pr-submit.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-pre-merge.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-resume-stall.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-resume.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-review-fix.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-review-snapshot.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-review-triage.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-roadmap-audit.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-suitability.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/idd-work.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-advisory-wait-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-ci-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-claim-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-merge-handoff-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-pr-submit-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-pre-merge-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-resume-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-resume-stall-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-review-fix-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-review-snapshot-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/instructions/lite/idd-work-lite.instructions.md
.local/share/idd-skill/0.16.0/.github/workflows/
.local/share/idd-skill/0.16.0/.github/workflows/post-merge-cleanup.yml
.local/share/idd-skill/0.16.0/.markdownlint-cli2.yaml
.local/share/idd-skill/0.16.0/.markdownlint.yml
.local/share/idd-skill/0.16.0/docs/
.local/share/idd-skill/0.16.0/docs/concepts.md
.local/share/idd-skill/0.16.0/docs/customization.md
.local/share/idd-skill/0.16.0/docs/getting-started.md
.local/share/idd-skill/0.16.0/docs/global-only-profile.md
.local/share/idd-skill/0.16.0/docs/idd-advisory-wait-shell-fallback.md
.local/share/idd-skill/0.16.0/docs/idd-autonomy-contract.md
.local/share/idd-skill/0.16.0/docs/idd-comment-minimization.md
.local/share/idd-skill/0.16.0/docs/idd-concept-ownership.md
.local/share/idd-skill/0.16.0/docs/idd-design-rationale.md
.local/share/idd-skill/0.16.0/docs/idd-helper-scripts.md
.local/share/idd-skill/0.16.0/docs/idd-resume-detail.md
.local/share/idd-skill/0.16.0/docs/idd-review-policy-profiles.md
.local/share/idd-skill/0.16.0/docs/idd-workflow.md
.local/share/idd-skill/0.16.0/docs/index.md
.local/share/idd-skill/0.16.0/docs/onboarding/
.local/share/idd-skill/0.16.0/docs/onboarding/agent-entry-and-verification.md
.local/share/idd-skill/0.16.0/docs/onboarding/issue-mediated-bootstrap.md
.local/share/idd-skill/0.16.0/docs/onboarding/optional-host-setup.md
.local/share/idd-skill/0.16.0/docs/onboarding/placeholders.md
.local/share/idd-skill/0.16.0/docs/onboarding/policy-decisions.md
.local/share/idd-skill/0.16.0/docs/onboarding/project-tuning.md
.local/share/idd-skill/0.16.0/docs/onboarding/template-distribution.md
.local/share/idd-skill/0.16.0/docs/permissions.md
.local/share/idd-skill/0.16.0/docs/policy-constants.md
.local/share/idd-skill/0.16.0/docs/reference.md
.local/share/idd-skill/0.16.0/profiles/
.local/share/idd-skill/0.16.0/profiles/README.md
.local/share/idd-skill/0.16.0/profiles/external-bot/
.local/share/idd-skill/0.16.0/profiles/external-bot/README.md
.local/share/idd-skill/0.16.0/profiles/human-required/
.local/share/idd-skill/0.16.0/profiles/human-required/README.md
.local/share/idd-skill/0.16.0/profiles/no-advisory/
.local/share/idd-skill/0.16.0/profiles/no-advisory/README.md
.local/share/idd-skill/0.16.0/user-global/
.local/share/idd-skill/0.16.0/user-global/entry.md
.local/share/idd-skill/current
.local/share/idd-skill/receipt.json
```

## Checking a later run

To repeat the capture, first create an empty `RUN_HOME` (for example with
`mktemp -d`). Then create the four parent directories that the
[Preconditions](#preconditions-for-an-isolated-home) section names, with
`mkdir -p`, which also creates `$HOME/.local`. Then run the command from the
[run record](#run-record) from a checkout of the upstream commit. Finally, list
the created paths with GNU `find` from the same HOME:

```sh
cd "$RUN_HOME" && find .local/share/idd-skill .claude/skills \
  .agents/skills .codex .config/opencode .claude/CLAUDE.md \
  \( -type d -printf '%p/\n' \) -o -printf '%p\n' | LC_ALL=C sort
```

The output should equal the list above line for line. The receipt should list
the same paths except `receipt.json` itself.
