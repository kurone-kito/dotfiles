---
type: guide
title: Re-importing the user-global IDD payload
description: Records how a re-import keeps this repository's chezmoi copy of the IDD user-global payload in step with a pinned idd-skill commit, and which local seams it must not overwrite.
---

# Re-importing the user-global IDD payload

Once #648 lands, this repository vendors the IDD user-global payload and its
two skill bundles (`issue-authoring` and `idd-spec-audit`) into the chezmoi
source, so that other repositories can activate IDD from the home directory.
This page records how a later re-import keeps that copy in step with upstream,
and which local seams it must not overwrite.

The page complements the upstream installation guides and does not restate
their install steps. Read these at the pinned commit first:

- [User-global installation](https://github.com/kurone-kito/idd-skill/blob/e4d425ee28b1893dd45c4996b2506619018c4b2b/docs/user-global-install.md)
- [IDD onboarding](https://github.com/kurone-kito/idd-skill/blob/e4d425ee28b1893dd45c4996b2506619018c4b2b/idd-template/ONBOARDING.md)

## Pinned upstream commit

The payload is pinned to idd-skill commit `e4d425ee28b1893dd45c4996b2506619018c4b2b`
(tag `v0.16.0`, an annotated tag that dereferences to this commit). The package
version at that commit is `0.16.0`, which is the `<version>` used below. A
re-import changes that pin on purpose, and updates this page in the same change.

## Re-import procedure

1. Stage the install in an isolated root, not in the operator's home directory.
   - Use an empty directory as `HOME`, with these directories created first:
     `.local/share`, `.claude`, `.agents` and `.config`, because the default
     harness list includes OpenCode. Also create each of `XDG_DATA_HOME` and
     `XDG_CONFIG_HOME` that is a qualified root, because the installer does not
     create those roots, and the parent of a qualified `CODEX_HOME`. The
     installer refuses a missing parent before it writes anything.
   - Unset `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `CODEX_HOME`, or point each
     at a path under that root. A qualified value of any of them overrides the
     `HOME` default, and the shell defaults in this repository keep an inherited
     value of the first two.
   - Install from a checkout of the pinned commit, as the upstream installation
     guide describes. Stop unless the installer exits 0. Exit 1 means the run was
     refused before any write or failed after a clean plan, and exit 2 is a usage
     error.
2. Compare the staging tree with the chezmoi source, path by path:

   | Staging tree | chezmoi source | Deploys to |
   | --- | --- | --- |
   | `<data root>/<version>/` | `home/dot_local/share/idd-skill/<version>/` | `~/.local/share/idd-skill/<version>/` |
   | `<data root>/current` (a link to `<version>`) | `home/dot_local/share/idd-skill/symlink_current` | the same link |
   | `~/.claude/skills/issue-authoring/`, `~/.claude/skills/idd-spec-audit/` | `home/dot_claude/skills/issue-authoring/`, `home/dot_claude/skills/idd-spec-audit/` | the same paths |
   | `~/.agents/skills/issue-authoring/`, `~/.agents/skills/idd-spec-audit/` | `home/dot_agents/skills/issue-authoring/`, `home/dot_agents/skills/idd-spec-audit/` | the same paths |

   Chezmoi encodes a leading dot in a source name as `dot_`. The payload's
   `.github/instructions/` files, for example, are `dot_github/instructions/`
   under `home/dot_local/share/idd-skill/<version>/`. Compare each staged path
   after applying that mapping.

   The data root is `~/.local/share/idd-skill`, or `$XDG_DATA_HOME/idd-skill`
   when `XDG_DATA_HOME` is a qualified root. The chezmoi sources always deploy to
   `~/.local/share/idd-skill`. When `XDG_DATA_HOME` is a qualified root other than
   `~/.local/share`, #648 links `$XDG_DATA_HOME/idd-skill` to that deployed tree.

   Skip `receipt.json`, which chezmoi does not deploy. The installer also edits
   three harness entry files, and chezmoi does not render those edits:
   - `~/.claude/CLAUDE.md`, from `home/dot_claude/CLAUDE.md.tmpl`;
   - `$CODEX_HOME/AGENTS.md` when `CODEX_HOME` is a qualified root, otherwise
     `~/.codex/AGENTS.md`, from `home/dot_codex/AGENTS.md.tmpl`;
   - `opencode.json` under `$XDG_CONFIG_HOME/opencode/` when `XDG_CONFIG_HOME`
     is a qualified root, otherwise under `~/.config/opencode/`. It has no
     chezmoi source.

   The wiring that chezmoi adds to the first two is tracked by #649.

   Until #648 lands, the chezmoi sources in the table do not exist. This page
   describes the sources that it will create.
3. Update the chezmoi source where payload or skill-tree bytes differ. If
   `user-global/entry.md` differs, also update each copy of it listed under
   Preserved seams, in the same change. A file that exists on one side only is
   also a difference:
   - a file that the staging tree adds inside the payload or a skill tree is
     added to the source;
   - a file that the source has and the staging tree lacks is removed only after
     the maintainer decides so.
4. Check the other preserved seams separately, because they are not part of the
   comparison in step 2. If an upstream change would alter what one of them
   depends on, for example a policy key that the config seam would need to
   carry, do not change that seam in the re-import. Stop, record the change on
   the tracking issue, and wait for the maintainer's decision. The copies of the
   entry text are not covered by this stop rule, because step 3 updates them.
5. When the pin changes, the new version is a new directory, and the `current`
   link moves to it in the same change. Update the pin on this page and on the
   tracking issue together. Each `{{ include ... }}` path to `user-global/entry.md`
   in the copies moves to the new version too. The entry-copy test in
   `tests/bash/opencode-instruction-profiles.bats` reads the version from
   `symlink_current`, and it fails while a copy still names an older version.
   The old version directory is removed only after the maintainer decides so.
   - On Windows, `current` is a directory junction that
     `home/run_after_83-link-idd-skill-xdg-data.ps1` creates at
     `~/.local/share/idd-skill/current` when `chezmoi apply` runs it, whatever
     `XDG_DATA_HOME` is set to. The version that junction names is set in three
     places that must agree: the `$version` constant in that script, the content
     of `home/dot_local/share/idd-skill/symlink_current`, and the version
     literals in `tests/powershell/link-idd-skill-xdg-data.Tests.ps1`. Before
     `chezmoi apply` deploys the new version, remove the old junction with a
     non-recursive command, for example
     `cmd /c --% rmdir "%USERPROFILE%\.local\share\idd-skill\current"`
     in PowerShell. The
     script never replaces an existing `current`: it reports a link to another
     version and leaves it in place, so the old junction stays until it is
     removed.

The tracking issue is the issue that tracks the re-import. Today that is
roadmap #643.

## Preserved seams

These local parts of the chezmoi source are not replaced by the payload. Apart
from the copies of the entry text, which follow the payload file, they stay as
they are during a re-import:

- The four copies of the entry text, which #649 introduces. Each is a managed
  block whose body matches `user-global/entry.md` byte for byte:
  `home/dot_codex/AGENTS.md.tmpl`, `home/dot_copilot/copilot-instructions.md.tmpl`,
  `home/dot_gemini/GEMINI.md.tmpl`, and the extended OpenCode render of
  `home/dot_config/opencode/AGENTS.md.tmpl`. The Copilot CLI and Gemini copies
  are inlined, because upstream does not wire those harnesses. The Claude
  template imports the deployed file instead, and the compact OpenCode render
  carries no copy.
- The deployment note after the link line in each of the five renders: the four
  copies and the Claude import. The `node` fallback in the entry text needs
  `$PAYLOAD/scripts/`, which this payload does not have, so the note tells the
  agent to run `~/.local/bin/idd-activation` instead, or on Windows
  `~/.local/bin/idd-activation.cmd`, which runs the PowerShell twin with the
  execution policy bypassed. The note sits outside the managed block, so each
  copy stays byte-identical to `entry.md`.
- `home/dot_config/idd-skill/config.json.tmpl` keeps only the CodeRabbit critique
  delegate and the telemetry hook. Upstream dogfood policy keys are not copied
  into it.
- The OpenCode compact routing is introduced by #649. It is the `## IDD workflow`
  section of `home/.chezmoitemplates/opencode-compact-instructions`, and only the
  compact render carries it. This repository adds no
  `opencode.json` source, because a second `instructions` entry would load the
  activation entry twice.
- The repo-local IDD corpus (`.github/instructions/`, `.claude/skills/`,
  `docs/idd-*`, and `.github/idd/config.json`) is not replaced by the payload.
  The user-global payload and the repo-local import are separate.
- The repo-local pin is a separate decision, tracked in issue #642.

## Outside this procedure

- Running the installer against the live home directory. Chezmoi owns those
  bytes. The installer also writes `receipt.json` in the data root, which lists
  every path it wrote. Its `--uninstall` refuses the whole run, before any
  removal, when a listed file or link no longer matches its receipt entry. A
  live-home run would therefore leave state that chezmoi cannot manage.
- Deploying `receipt.json`.
