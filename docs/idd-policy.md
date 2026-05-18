# IDD Policy Configuration

This repository uses the Issue-Driven Development (IDD) workflow
imported from
[`kurone-kito/idd-skill`](https://github.com/kurone-kito/idd-skill).
This page records the eleven policy decisions confirmed during the
onboarding flow (roadmap #95). The machine-readable mirror lives at
[`.github/idd/config.json`](../.github/idd/config.json); keep both in
sync when the policy changes.

The schema name for each field below comes from the upstream
[`idd-template/docs/onboarding/policy-decisions.md`](https://github.com/kurone-kito/idd-skill/blob/b64eab0d51a79bd3199740505f3b7843bc94a0d4/idd-template/docs/onboarding/policy-decisions.md)
so future IDD sessions can navigate between the human-readable record
and the upstream template without surprises.

## Merge Policy

**Policy**: `fully_autonomous_merge`

One trusted agent session may continue through the F2.5 / F3 handoff
gate after the normal claim, freshness, CI, advisory, and review gates
pass. The repository is single-maintainer, so worker credentials and
merge-capable credentials are intentionally the same scope; see the
[Credential Scope](#credential-scope) section for the explicit
boundary.

## PR Review Policy

**Profile**: `copilot-advisory` (distributed default).

GitHub Copilot is requested after review-fix pushes and before merge
freshness checks; it provides advisory state only. The repository
already wires CodeRabbit through
[`.coderabbit.yaml`](../.coderabbit.yaml) — both reviewers coexist.
Confirm Copilot Code Review is enabled in repository settings before
the first unattended run; if it is not, migrate to the `external-bot`
profile pointed at CodeRabbit and follow the edit-surface checklist
in [`docs/idd-review-policy-profiles.md`](./idd-review-policy-profiles.md).

## Review-Thread Resolution Policy

**Policy**: `fast-agent-resolve` (distributed default).

After an agent accepts and fixes feedback, rejects it with a recorded
rationale, or handles PATH B advisory feedback, the agent may resolve
the associated thread. This means "the agent acted on the thread", not
"the reviewer agreed". Suitable for the parallel-IDD goal because it
keeps the loop high-throughput.

## Critique-Loop Profile

**Profile**: distributed defaults from
[`docs/policy-constants.md`](./policy-constants.md). No repository
override.

## Claim Timing

- **`claim-stale-age`**: `12h` (shortened from the `24h` distributed
  default).
- **`claim-heartbeat-interval`**: `6h` (shortened from the `12h`
  distributed default).

Rationale: this repository runs lightweight CI (cspell, markdownlint,
bats, Pester, lua syntax). Stale-claim takeover cost is low because a
single maintainer can revalidate quickly, so a tighter clock keeps
parallel sessions from leaving idle claims sitting around half a day.

## CI Wait Policy

- **`ciWait.runningTimeout`**: `PT10M` (shortened from the `PT30M`
  distributed default).
- **`ciWait.generationTimeout`**: `PT10M` (distributed default).
- **`ciWait.rerunPolicy`**: `rerun-once` (distributed default).

Rationale: the longest CI job in this repo currently finishes in
~1 minute, so a 10-minute running timeout is generous without
stretching the loop wait. Keep the rerun policy on `rerun-once` to
absorb the occasional transient failure without re-running indefinitely.

## Credential Scope

- **Worker credentials**: maintainer-equivalent (`kurone-kito` repo
  access — read/write to issues, PRs, branches, commits).
- **Merge-capable credentials**: identical to worker credentials.

The single-maintainer topology intentionally collapses these two
scopes. Flag this section before any split-authority migration —
introducing `separate_merge_agent` later would require splitting the
credential model first.

## Helper Runtime Profile

**Profile**: `ephemeral-npx`.

The discover, suitability, review-snapshot, advisory-wait, and
pre-merge phases may invoke the helper manifest via:

```sh
npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/b64eab0d51a79bd3199740505f3b7843bc94a0d4 \
  idd-helper-bundle-manifest --profile ephemeral-npx
```

The tarball URL is pinned to the same upstream commit used as the
import baseline for `.github/instructions/` and `.claude/skills/`, so
the helper surface never drifts ahead of the checked-in templates.
Bump that commit deliberately whenever the IDD instructions are
re-imported; do **not** point the spec at a mutable `refs/heads/main`
ref. The companion prerequisite #96 pins Node.js 24.15.0 via
project-local [`.tool-versions`](../.tool-versions) /
[`.node-version`](../.node-version) / [`.nvmrc`](../.nvmrc) so `npx`
always resolves in a fresh worktree.

## Issue-Author Approval Gate

- **Gate posture**: `opted-out`.
- **`skipIssueAuthorApprovalGate`**: `true` (machine-readable mirror in
  [`.github/idd/config.json`](../.github/idd/config.json)).
- **`maintainer-approval-actors` policy**:
  `owners-and-maintainers-only` (recorded for future re-enablement;
  moot while the gate is opted out).
- **Approval signals**: not exercised while the gate is opted out.
- **`approvalSignals.readyLabelName`**: not configured (default `idd:ready`
  would apply if the gate is re-enabled later).
- **`approvalSignals.labelFreshnessMode`**: not configured (default
  `presence-only` would apply if the gate is re-enabled later).
- **Missing-approval behavior**: gate inactive — explicit-target runs
  and discovery may proceed without an approval signal.

Rationale: this is a single-maintainer dotfiles repository. The
issue-author approval gate exists to keep unattended agents from
auto-picking up issues filed by strangers; with only the maintainer
filing issues, the gate is overhead. Re-enable it (and create the
`idd:ready` label) before opening this repository to multi-author
collaboration.

## Issue-Authoring Companion

- **Status**: `installed` at `.claude/skills/issue-authoring/`.
- **`issueAuthoring.maxClarificationRounds`**: `3` (distributed
  default).

The companion drafts IDD-ready issues and roadmaps before the normal
Discover loop starts. See its
[bundled contract](../.claude/skills/issue-authoring/references/contract.md)
for the readiness buckets, output chooser, and approval boundary.

## Open follow-ups

The remaining work after onboarding lives in two roadmaps. The
specific entries below summarize what is still outstanding, what is
already wired up, and how the IDD CI wait actually behaves when a
required-check set is partial.

### Required status checks on `master`

Branch protection's `required_status_checks.contexts` currently lists
`lint` (from the Linting workflow) and `Lua syntax check` (from the
Test workflow). The remaining two jobs in the Test workflow —
`Bash tests (bats)` and `PowerShell tests (Pester)` — are not
required yet because they fail on `master` baseline for environmental
reasons (`chezmoi` missing on the Ubuntu runner; 13 Windows-only
Pester cases). Tracking:

- [`#109`](https://github.com/kurone-kito/dotfiles/issues/109) —
  install `chezmoi` in the Bash tests job and promote
  `Bash tests (bats)` to required.
- [`#110`](https://github.com/kurone-kito/dotfiles/issues/110) —
  resolve the 13 Pester failures and promote
  `PowerShell tests (Pester)` to required.

Both issues are children of roadmap
[`#107`](https://github.com/kurone-kito/dotfiles/issues/107).

This is **not** a "no CI gate" situation: per
`.github/instructions/idd-ci.instructions.md`, when an IDD run reaches
the shared CI wait, it builds the required-check set from rulesets
and branch protection. If neither source yields a check for the
current PR head, IDD stops and posts a hold for missing merge-gate
policy evidence — it does not silently merge. The current two-check
floor (`lint` + `Lua syntax check`) is therefore the active merge
gate, and the two pending promotions tighten it further.

### Issue authoring gate

The `idd:ready` and `status:authoring` repository labels exist (both
created via `gh label create` after onboarding). They are not
exercised today because the issue-author approval gate is opted out
(`skipIssueAuthorApprovalGate: true`); re-enabling the gate later
would activate the labels without needing new repository state.
[`.github/ISSUE_TEMPLATE/idd-task.yml`](../.github/ISSUE_TEMPLATE/idd-task.yml)
ships the structured form for hand-filed IDD tasks.

### PR review profile

GitHub Copilot Code Review is empirically active on this repository
— the bot has reviewed every onboarding-chain PR from
[`#102`](https://github.com/kurone-kito/dotfiles/pull/102) onward via
the `copilot-pull-request-reviewer` actor. The default
`copilot-advisory` profile is therefore satisfiable here; the earlier
"confirm Copilot Code Review is enabled" needs-decision is closed.
