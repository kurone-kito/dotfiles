# IDD Policy Configuration

This repository uses the Issue-Driven Development (IDD) workflow
imported from
[`kurone-kito/idd-skill`](https://github.com/kurone-kito/idd-skill).
This page records the policy decisions confirmed during the
onboarding flow (roadmap #95) and the 0.4.0 re-import (roadmap #144).
The machine-readable mirror lives at
[`.github/idd/config.json`](../.github/idd/config.json); keep both in
sync when the policy changes.

The schema name for each field below comes from the upstream
[`idd-template/docs/onboarding/policy-decisions.md`](https://github.com/kurone-kito/idd-skill/blob/4e8c7043edcb00dd8447dee83e7a17e5b2604d5d/idd-template/docs/onboarding/policy-decisions.md)
so future IDD sessions can navigate between the human-readable record
and the upstream template without surprises.

**Pinned upstream commit**: `4e8c7043edcb00dd8447dee83e7a17e5b2604d5d`
(abbreviated `4e8c704`; `git describe`: `v0.4.0-1242-g4e8c7043`),
imported by roadmap #144. `iddVersion` in
[`.github/idd/config.json`](../.github/idd/config.json) is bumped
separately, by #150's final verification sweep.

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
npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/4e8c7043edcb00dd8447dee83e7a17e5b2604d5d \
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

## Issue Scope

**Policy**: `roadmap-first` (migrated from `roadmap`, confirmed by
roadmap #144).

`roadmap-first`'s upstream-documented semantics prefer roadmap-linked
candidates and fall back to orphan discovery (A0-O) when none are
ready — but this repository's **`orphanFirstPolicy`** stays `none`
(distributed default), which disables the orphan fallback path
outright. In this repository, no orphan-discovery fallback runs;
`roadmap-first` behaves identically to `roadmap` until
`orphanFirstPolicy` is deliberately loosened to
`maintainer-approved` or `public-disabled`.

## Worktree Guard

**`worktreeGuard.enabled`**: `true`. **`worktreeGuard.branchPatterns`**:
not set (distributed default `["issue/*", "roadmap-audit/*"]`).

Once a clone wires `core.hooksPath` (below), the shipped `.githooks/`
hooks refuse a commit or push made from the **primary** worktree while
`HEAD` is on an implementation branch (`issue/*` or `roadmap-audit/*`),
enforcing the B1 disposable-worktree rule locally — CI cannot detect
this class of violation, since it leaves no trace in pushed history
and CI checks out a detached `HEAD`.

`core.hooksPath` is local, per-clone git config; it is never committed,
so a clone that skips this step stays unenforced even with
`worktreeGuard.enabled: true`. Every clone must wire it once:

```sh
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
```

Any environment that starts from a fresh clone per task (a coding
agent, an ephemeral container, a throwaway checkout) never inherits
this setting and must run it as an environment-setup step, not a
one-time human action. Confirm it took effect with `idd-doctor`, which
reports an **enabled-but-inert** finding when `worktreeGuard.enabled`
is `true` but `core.hooksPath` is not pointed at `.githooks`. Bypass
the guard for a single intentional commit or push with `--no-verify`.

## Advisory Bot Logins

**`advisoryBotLogins`**: `["copilot-pull-request-reviewer[bot]",
"coderabbitai[bot]"]`.

Both logins were confirmed against live review events on
[PR #193](https://github.com/kurone-kito/dotfiles/pull/193), which
carries review activity from both bots. Settle/wait
([`idd-advisory-wait.instructions.md`](../.github/instructions/idd-advisory-wait.instructions.md))
stays Copilot-only regardless of this list — **`advisoryWait.primaryBotLogin`**
and **`advisoryWait.secondaryBotLogin`** are left unset, so CodeRabbit
reviews are dispositioned on arrival via this list but never gate the
advisory-wait clock.

## Autopilot Suitability

**`autopilotSuitability.floor`**: `3` (explicit default; `enabled` left
unset, default `true`).

Discovery considers issues whose authored autopilot-suitability score
is `>= 3`; lower-scored candidates route to a human. Advisory
ranking/routing hint only — never bypasses the A4.5/A5 safety gates.

## Workshop Example Repository

**`workshop.exampleRepository`**: `""` (distributed default — disables
the `idd-doctor` cross-check that expects an example repository's
README to back-link to `docs/workshop/`; this repository has no such
directory).

## CI Gate External Check Waivers

**`ciGate.externalCheckWaivers.mode`**: `maintainer-authorized`.
**`ciGate.externalChecks.waivable`**: `[{ "selector":
"idd-advisory-convergence" }]`. **`authorityPolicy`** and
**`maxValidity`** are left unset (distributed defaults
`owners-and-maintainers-only` and `PT24H`).

This prepares the waiver path for roadmap #144's #149 (hosting the
`idd-advisory-convergence` workflow as a required status check) and is
harmless while that check does not yet exist — no selector currently
matches anything, so no waiver can be issued or consumed.

## New 0.4.0 Schema Keys Left at Default

Confirmed at their distributed defaults rather than given an explicit
`.github/idd/config.json` entry (roadmap #144):

- **`advisoryWait.convergenceScope`**: `all-prs`
- **`advisoryWait.sameHeadRerollCap`**: `2`
- **`advisoryWait.recoveryCycleCap`**: `2`
- **`advisoryWait.terminalWindow`**: `PT12H`
- **`ciGate.trustEmptyProtectionReads`**: `false`
- **`mergeGate.soloCodeownerAdminFallback`**: `auto-admin-retry` — this
  repository is solo-maintainer (`trustedMarkerActors: ["kurone-kito"]`
  only) with `mergePolicy: fully_autonomous_merge`, exactly the
  topology this key governs, and the distributed default (F3 retries
  once with `gh pr merge --admin` when the sole blocker is the
  solo-CODEOWNER self-approval deadlock) matches this repository's
  existing autonomous-merge intent. Recorded here as a deliberate
  confirmation, not an oversight.

## Divergence Register

Every intentional deviation from the pinned upstream template carries
a `dotfiles-divergence: <slug>` marker at its point of use -- an HTML
comment (`<!-- ... -->`) in Markdown/YAML/instruction files, a line
comment (`// ...`) in JavaScript -- so a future re-import can detect
and preserve it instead of silently reverting to upstream's default.
Current slugs:

| Slug                                 | What it marks                                                                                                                                                                                        | Introduced by |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| `claim-timing`                       | The `12h`/`6h` claim-stale-age/heartbeat-interval override, in place of the `24h`/`12h` distributed defaults                                                                                         | #145, #196    |
| `helper-profile-ephemeral-npx`       | This repository's `ephemeral-npx` helper profile, where docs describe a different upstream-default profile inline                                                                                    | #196          |
| `installed-bundle-reference-routing` | The issue-authoring companion's reference routing, adapted for an installed-bundle (not source-repo) stance                                                                                          | #147          |
| `master-branch`                      | `master` in place of upstream's `main` as the integration branch name                                                                                                                                | #145, #196    |
| `onboarding-doc-trim`                | The deliberate exclusion of `docs/onboarding/placeholders.md` and `docs/onboarding/policy-decisions.md` (self-corrupt after placeholder substitution), linking to the pinned upstream copies instead | #145, #196    |
| `signing-ladder`                     | The GPG -> SSH -> unsigned commit-signing fallback ladder, a dotfiles-specific addition with no upstream equivalent                                                                                  | #145          |
| `vendored-file-header`               | The corrected header on `scripts/minimize-superseded-markers.mjs`, since this repository has no build step to regenerate it from a TypeScript source                                                 | #196          |

## Open follow-ups

The remaining work after onboarding lives in two roadmaps. The
specific entries below summarize what is still outstanding, what is
already wired up, and how the IDD CI wait actually behaves when a
required-check set is partial.

### Required status checks on `master`

`master`'s merge gate currently comes from a default-branch ruleset
matching `~DEFAULT_BRANCH`; classic branch protection is not
configured today, though the CI wait unions both sources if that
changes. The ruleset's `required_status_checks` rule lists four
required check contexts, spanning the Linting and Test workflows:
`lint`, `Lua syntax check`, `Bash tests (bats)`, and
`PowerShell tests (Pester)`.

[`#109`](https://github.com/kurone-kito/dotfiles/issues/109) and
[`#110`](https://github.com/kurone-kito/dotfiles/issues/110) (children
of roadmap [`#107`](https://github.com/kurone-kito/dotfiles/issues/107))
had already fixed the environmental failures blocking
`Bash tests (bats)` and `PowerShell tests (Pester)` from being
promoted (`chezmoi` missing on the Ubuntu runner; 13 Windows-only
Pester cases), but closed without evidence that the actual promotion
ran. [`#163`](https://github.com/kurone-kito/dotfiles/issues/163)
registered all four contexts on the ruleset directly.

Per `.github/instructions/idd-ci.instructions.md`, when an IDD run
reaches the shared CI wait, it builds the required-check set from
rulesets and branch protection; if neither source yields a
required-check set at all, IDD stops and posts a hold for missing
merge-gate policy evidence rather than silently merging. The
four-check ruleset above is now that required set.

### Issue authoring gate

The `idd:ready` and `status:authoring` repository labels exist (both
created via `gh label create` after onboarding). They are not
exercised today because the issue-author approval gate is opted out
(`skipIssueAuthorApprovalGate: true`); re-enabling the gate later
would activate the labels without needing new repository state.
[`.github/ISSUE_TEMPLATE/idd-task.yml`](../.github/ISSUE_TEMPLATE/idd-task.yml)
ships the structured form for hand-filed IDD tasks.

Roadmap #144 additionally confirmed the 0.4.0 default label taxonomy:
`roadmap` (already existed), `status:blocked-by-human`, and
`status:needs-decision` (both created by #146). `.github/idd/config.json`
does not set `labels.*`, since all three use the schema's distributed
default names.

### PR review profile

GitHub Copilot Code Review is empirically active on this repository
— the bot has reviewed every onboarding-chain PR from
[`#102`](https://github.com/kurone-kito/dotfiles/pull/102) onward via
the `copilot-pull-request-reviewer` actor. The default
`copilot-advisory` profile is therefore satisfiable here; the earlier
"confirm Copilot Code Review is enabled" needs-decision is closed.
