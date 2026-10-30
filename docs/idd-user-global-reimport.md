---
type: guide
title: Re-importing the user-global IDD payload
description: Records how a re-import keeps this repository's chezmoi copy of the IDD user-global payload in step with a pinned idd-skill commit, and which local seams it must not overwrite.
---

# Re-importing the user-global IDD payload

This repository vendors the IDD user-global payload and its two skill bundles
(`issue-authoring` and `idd-spec-audit`) into the chezmoi source, so that other
repositories can activate IDD from the home directory. This page records how a
later re-import keeps that copy in step with upstream, and which local seams it
must not overwrite.

The page complements the upstream installation guides and does not restate
their install steps. Read these at the pinned commit first:

- [User-global installation](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/docs/user-global-install.md)
- [IDD onboarding](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/ONBOARDING.md)

## Pinned upstream commit

The payload is pinned to idd-skill commit `77befdd4030757464bed7f31c7dfe6d0a404a18b`
(tag `v0.17.0`, annotated tag object `1f91a0d13397dbcbf94f44c8201a2b5618bb1060`).
The package version at that commit is `0.17.0`, which is the `<version>` used
below. A re-import changes that pin on purpose, and updates this page in the
same change.

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

   The table describes the deployed chezmoi sources; the XDG data-root bridge
   and harness wiring are maintained separately from the upstream payload.
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
     of `home/dot_local/share/idd-skill/symlink_current`, and the test's version
     source in `tests/powershell/link-idd-skill-xdg-data.Tests.ps1`. During
     `chezmoi apply`, the script advances an existing junction or symbolic link
     only when it resolves to a previous version directory under the managed
     data root and that directory contains `user-global/entry.md`. It leaves a
     real `current` directory and links to unrelated targets in place. If
     creating the replacement junction fails, the script tries to restore the
     previous target as a junction and warns. The Pester tests cover the
     managed-version advance, recovery from junction-creation failure and
     protections for unrelated paths, so the prior junction does not need to
     be removed manually.
6. Pass the source consistency check before any live deployment. The
   inventory `.github/idd/user-global-source.json` records the upstream commit,
   tag, tag object and archive SHA-256, and the SHA-256 of every file in the
   payload and in both skill trees, taken from the staging tree of step 1. Run
   the checker against the candidate chezmoi source:

   ```sh
   python3 -I scripts/check-idd-runtime-pins.py --source-root <candidate-checkout>
   ```

   The check is read-only. It fails with `FAIL <path>: <reason>` lines when the
   file sets or digests differ from the inventory, when the selected pointer
   (`symlink_current`), the Windows `$version`, a wrapper pin, a versioned
   harness-entry reference, `iddVersion`, or `helperRuntime.packageSpec` names a
   different release or commit, or when the inventory itself is malformed or
   names a path outside its source root. A retained older release directory
   does not fail it. The Bats suite `tests/bash/idd-runtime-pins.bats` reads the
   release and the commit from the inventory, so a re-import needs no edit there.

   Regenerate the inventory from the staging tree, and update the pins, the
   affected references and the copies listed under Preserved seams in the same
   reviewed change. A failing candidate goes back to step 1 for preparation.
   Do not apply it to the home directory.

   This check establishes source consistency only. It does not make
   `chezmoi apply` transactional, it does not show that a deployed home matches
   the source, and it does not prove runtime compatibility. Those need the
   deployment checks and the global-only lifecycle verification on a real pull
   request.

The tracking issue for this re-import is #675.

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
  copies and the Claude import. It records that this setup deploys
  `idd-activation` to `~/.local/bin` and directs readers to the upstream entry's
  platform-specific fallback commands. The note sits outside the managed block,
  so each copy stays byte-identical to `entry.md`.
- `home/run_after_83-link-idd-skill-xdg-data.ps1` owns the Windows `current`
  junction update. It advances only a link to a prior managed payload version
  with an `entry.md` marker; a real directory or unrelated target is preserved.
  If replacement fails, it tries to restore the previous target as a junction
  so recovery does not require symbolic-link privilege. Keep this
  repository-specific behavior and its Pester coverage outside the versioned
  upstream payload during later re-imports.
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

## Global-only lifecycle verification (#682)

This section records the deployment and activation evidence for the first
repository lifecycle that runs on the deployed v0.17.0 user-global payload, for
roadmap #674. The readiness, advisory-check, and F4 results are recorded in
the sections that follow, only as they are observed. Until they are recorded, the
global-only profile is not recorded as verified.

- Run date: 2026-10-29 (UTC).
- Issue: #682. Pull request: #693.
- Pull request head: `2cf45647b6ef2de880e9003880540f1387bcd8db`. Merge
  commit: `b7afcdf145c336e2c66c67e3f51ee17d3a1c9c88`.
- Payload version: 0.17.0, pinned to commit
  `77befdd4030757464bed7f31c7dfe6d0a404a18b`. The home directory was updated
  by `chezmoi apply` from this source, not by the upstream installer.
- Deployed copy: `~/.local/share/idd-skill/current` resolves to
  `~/.local/share/idd-skill/0.17.0`. All 80 scoped files (68 payload files
  and 12 skill files under `~/.claude/skills/` and `~/.agents/skills/`) match
  the SHA-256 inventory in `.github/idd/user-global-source.json`.
  `scripts/check-idd-runtime-pins.py` reports the source as consistent.
  `chezmoi status` was not used, because it prompts for a secret-manager
  unlock.
- Isolation: the primary-checkout run used the deployed home. Issue #682 names
  the primary checkout for `idd-activation`, but it does not name the deployed
  home. The isolated data root run is recorded below, as the issue's proposed
  change requires.

## Activation and policy

`~/.local/bin/idd-activation` on the primary checkout returned:

- `active`: `true`
- `tier`: `repository-local`
- `reason`: `repository-policy-minimal-import`
- `instructionsRoot`: `~/.local/share/idd-skill/current`, which resolves to
  the 0.17.0 payload above.

`idd-effective-config` reports these repository-local values:

- `mergePolicy`: `fully_autonomous_merge`
- `autopilotSuitability.floor`: `3`
- `issueScope`: `roadmap-first`
- `orphanFirstPolicy`: `none`
- `helperRuntime.profile`: `ephemeral-npx`
- `helperRuntime.packageSpec`: the codeload archive of commit
  `77befdd4030757464bed7f31c7dfe6d0a404a18b`

## Required checks

The `main` ruleset requires five contexts: `lint`, `Lua syntax check`,
`Bash tests (bats)`, `PowerShell tests (Pester)`, and
`idd-advisory-convergence`. With `--global-only`, `pre-merge-readiness` leaves
out only `idd-advisory-convergence` and keeps the four CI contexts. The ruleset
was not changed.

## Isolated data root run

The issue's proposed change asks for the v0.17.0 verification commands in an
isolated data root. The run copied the deployed payload into a temporary
`XDG_DATA_HOME` root, checked its 68 files against the inventory (no mismatch),
and ran the commands with that root:

- `idd-activation`: `active` is `true`, `tier` is `repository-local`, `reason`
  is `repository-policy-minimal-import`, and `instructionsRoot` is under the
  isolated `idd-skill/current`, which resolves to the copied 0.17.0 payload.
- `idd-effective-config`: the same six repository-local values as above.

The copy came from the deployed home. The upstream installer was not run for
this record.

## Readiness and advisory check

Interim observation on pull request #693 at head
`3938597b691528837332d17cc9a0bb9b0cdc38e9`. That is not the merged head, so
it is not the final readiness result. The interim values are:

- `pre-merge-readiness --global-only`: the CI and advisory-wait gates pass. The
  helper's required list holds the four CI contexts (`lint`, `Lua syntax
  check`, `Bash tests (bats)`, and `PowerShell tests (Pester)`), and
  `idd-advisory-convergence` is not in it. Disposition evidence is complete, no
  review thread is unresolved, no comment is unreplied, the closing set is #682,
  the branch is clean, and the claim matches.
- Still open at that head: the review watermark (`review-currency`) and the
  60-minute secondary quiet window after the last activity. Readiness therefore
  had not passed at this head. The merge gate is not this interim observation.
  The final-head result is recorded below.
- `idd-advisory-convergence`: `pass` on head `3938597`. The first run failed
  before the Copilot dispositions were posted. The check does not re-run on
  comments, so the failed job was rerun once.

## Final-head readiness

This section records the readiness result on the merged head
`2cf45647b6ef2de880e9003880540f1387bcd8db`. The run was made on 2026-10-30
(UTC), after the merge. It used the helper package pinned in
`helperRuntime.packageSpec`:

```sh
npx --yes \
  --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/77befdd4030757464bed7f31c7dfe6d0a404a18b \
  idd-pre-merge-readiness --pr 693 --claim-issue 682 --global-only
```

The run exited with status 0 and made one run only. Its stdout holds the
fields below. Their values are quoted verbatim, and the other fields are
omitted:

```json
{
  "ready": false,
  "prHeadSha": "2cf45647b6ef2de880e9003880540f1387bcd8db",
  "blockers": [
    {
      "gate": "review-currency",
      "detail": "comparisonRoute is \"return-to-e1\" (expected \"proceed\"): newer-activity"
    },
    {
      "gate": "claim-ownership",
      "detail": "claim ownership does not match (reason=\"missing-active-claim\")"
    },
    {
      "gate": "disposition-evidence",
      "detail": "dispositionEvidence.route is \"return-to-e1\" (expected \"proceed\"), blockingCount=1 (expected 0)"
    }
  ]
}
```

The `prHeadSha` value equals the merged head named above. The
`claim-ownership` blocker is reported while the issue #682 live-status digest
reads `Claim` `none`. The `unclaimed-by` comment 6497895642
(2026-10-29T13:24:14Z) released that claim. This record adds no interpretation
of the three blockers.

The check-run conclusions, the merge, and the F4 comments are not this
readiness result. The run did not use `--claimless`.

## F4 outcome

The F4 result for issue #682 is recorded on that issue, after the merge:

- The `idd-f4-head-proof` marker (version 2, comment 6497814928) names pull
  request 693, claim `0c9aa02f-63cd-47bf-8aed-992efde83814`, branch
  `issue/682-test-idd-verify-real-global-only-idd`, head and branch tip
  `2cf45647b6ef2de880e9003880540f1387bcd8db`, and merge commit
  `b7afcdf145c336e2c66c67e3f51ee17d3a1c9c88`.
- The live-status digest (comment 6497886505) reads `Phase` `F4 complete`,
  `Claim` `none`, `Branch` `none`, `Open blockers` `none`, and
  `Authoritative by` merge `b7afcdf145c336e2c66c67e3f51ee17d3a1c9c88`.

Neither comment states that a server-side cleanup workflow ran, so this record
does not state that.

## Verification status

The global-only profile is verified only when the quoted readiness result has
`ready` true and the F4 outcome is present. The final-head readiness result has
`ready` false, so the profile is not verified. The failing evidence is the
three blockers quoted above. The F4 outcome is present, but it does not change
the readiness result.

The interim observation above is not the final-head result. This record does
not state that roadmap #674 is complete.
