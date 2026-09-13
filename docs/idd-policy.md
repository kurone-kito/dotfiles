---
type: reference
title: IDD Policy Configuration
description: Records this repository's confirmed IDD policy decisions alongside their machine-readable mirror in .github/idd/config.json.
---

# IDD Policy Configuration

This repository uses the Issue-Driven Development (IDD) workflow
imported from
[`kurone-kito/idd-skill`](https://github.com/kurone-kito/idd-skill).
This page records the policy decisions confirmed during the
onboarding flow (roadmap #95), the 0.4.0 re-import (roadmap #144), the
0.5.0/0.6.0 re-import (roadmap #239), the 0.7.0 re-import
(roadmap #292), the 0.9.0 re-import (roadmap #380), and the 0.11.0
re-import (roadmap #419). The machine-readable mirror lives at
[`.github/idd/config.json`](../.github/idd/config.json); keep both in
sync when the policy changes.

The schema name for each field below comes from the upstream
[`idd-template/docs/onboarding/policy-decisions.md`](https://github.com/kurone-kito/idd-skill/blob/1f90787ebf4021673ce6e5eb69741df331fd2037/idd-template/docs/onboarding/policy-decisions.md)
so future IDD sessions can navigate between the human-readable record
and the upstream template without surprises.

**Pinned upstream commit**: `1f90787ebf4021673ce6e5eb69741df331fd2037`
(abbreviated `1f90787`; tag `v0.11.0`), confirmed as the current latest
tag and audited by roadmap #419's final-verification track
([`#425`](https://github.com/kurone-kito/dotfiles/issues/425)), which
supersedes the `v0.9.0`-round pin recorded by roadmap #380's schema-audit
track (#381). Roadmap #419's five resync tracks (#420-#424) each
brought their own file scope from `v0.9.0` to `v0.11.0` -- schema/config
(#420, PR #427), `.github/instructions/`/`lite/` (#421, PR #430),
docs/githooks/scripts/lint-config (#422, PR #431), CI workflow +
helper-runtime pin (#424, PR #429), and companion skills (#423, PR #428)
-- while its sixth track, #389 (PR #426), added the new
critique-telemetry-hook consumer rather than resyncing an existing
file scope. This final-verification track (#425) then confirmed the
pin and swept the Divergence Register and deferred-upstream-issues
ledger below.
The `v0.9.0` pin (`d005098bf3a54a27ac79b22fb5eeb88186d235c6`) was itself
audited by roadmap #380's schema-audit track (#381), superseding the
`v0.7.0`-round pin recorded by roadmap #292's #293, which itself
superseded the 0.5.0/0.6.0-round pin recorded by roadmap #239's #234;
the paragraphs below preserve that `v0.7.0`-round verification detail as
a historical record.
The advisory-convergence fix chain (upstream
[#2050](https://github.com/kurone-kito/idd-skill/issues/2050) /
[#2054](https://github.com/kurone-kito/idd-skill/pull/2054) /
[#2056](https://github.com/kurone-kito/idd-skill/issues/2056), merged
via [PR #2116](https://github.com/kurone-kito/idd-skill/pull/2116))
was confirmed present at `f51a8bb` by reading the actual source, not
only the schema: `src/scripts/review-clause.mts` defines a `reviewId`
field on `AdvisoryConvergenceReviewClause` (gated on `matchesHead`,
scoping Clause 1's thread evidence to the specific triggering review),
and `src/scripts/advisory-convergence.mts` computes the report's
`review.satisfied` as a disposition-aware caller-side override
(`hasValidReviewAck` / `itemCountClauseSatisfied`, bound to
`review.reviewId`) rather than the raw mechanical
`matchesHead && itemCount === 0 && suppressedCount === 0` check
`review-clause.mts` alone computes.

`iddVersion` in [`.github/idd/config.json`](../.github/idd/config.json)
is now `0.11.0` — roadmap #419's schema/config-audit track
([`#420`](https://github.com/kurone-kito/dotfiles/issues/420)) bumped
it from `0.9.0` directly (see [New 0.10.0/0.11.0 Schema
Keys](#new-01000110-schema-keys) below for that round's own
verification detail). It had previously read `0.9.0`, bumped by
roadmap #380's schema-audit track
([`#381`](https://github.com/kurone-kito/dotfiles/issues/381)) (`idd-doctor`
from the `v0.9.0` tarball reports no
`mergePolicyAck` warning and no schema errors against the bumped
config), a different sequencing from the `v0.7.0` round below, whose
final-verification track (#298) bumped `iddVersion` only once every
sibling track had landed. That `v0.7.0`-round detail is preserved here
as historical record: roadmap #292's final-verification track (#298)
bumped `iddVersion` to `0.7.0` once every sibling track landed,
mirroring how the prior round's schema-audit track (#234) also left
`iddVersion` unchanged until #238 bumped it. At that time,
`.github/idd/config.json` already validated
cleanly against the fetched `v0.7.0` `policy.schema.json`
(`npx ajv-cli validate --spec=draft2020`: valid) and via `idd-doctor`
run from the `v0.7.0` tarball directly (`PASS .github/idd/config.json
validates against policy.schema.json`; 3 warnings in a worktree with
`core.hooksPath` already wired, none a correctness break:
toolchain-residue x2 is byte-identical to the same run against the
`v0.6.0` tarball, and the third (branch-protection) reads differently
only because `idd-doctor`'s own diagnostic wording/logic changed
between the two tags, not because of any schema or configuration
change -- a same-tree comparison isolates that wording difference from
configuration state, so this specific conclusion holds regardless of
what the live configuration was at the time. #410 separately
established that, for the unchanged `v0.7.0`/`v0.9.0` check logic
specifically, live configuration is what determines whether it reports
a `WARN` during this historical #293 window: the master ruleset's
required-status-checks rule was itself temporarily absent then
(unrelated to which of those two versions ran) -- see the dedicated
`idd-doctor` findings section below for that
separate, config-side finding; #307's own review caught and fixed a
fourth, transient command-mismatch pair unrelated to the pin -- see
that same section).

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
[`docs/policy-constants.md`](./policy-constants.md) for the C-phase and
E10 loop-guard constants (`cPhaseLowSeveritySkipAfter`,
`e10NoProgressHoldAfter`). `critiqueLoop.delegate` itself is a
repository override, not a distributed default: `command:
"coderabbit-critique"`, `mode: "combined"` (#407, restoring the same
shape #368 originally shipped and #381 removed — see the
[`critiqueLoop.delegate`](#genuinely-new-in-070) row below for the full
history). `command` is a bare, `PATH`-resolved name. A Windows-resolvable
launcher, `home/dot_local/bin/executable_coderabbit-critique.cmd`
(#411, following up on PR #408's review discussion), lets a
native-Windows agent host resolve that same bare name via `PATHEXT`
lookup: it dispatches to the `.ps1` twin (preferring `pwsh`, falling
back to `powershell.exe`), so a Windows C1 pass now runs the delegate
the same as a POSIX host instead of falling through to the per-agent
mechanism under `combined`.

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
npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/1f90787ebf4021673ce6e5eb69741df331fd2037 \
  idd-helper-bundle-manifest --profile ephemeral-npx
```

The tarball URL is normally pinned to the same upstream commit used as
the import baseline for `.github/instructions/` and `.claude/skills/`,
so the helper surface never drifts ahead of the checked-in templates —
bump that commit deliberately whenever the IDD instructions are
re-imported, and do **not** point the spec at a mutable
`refs/heads/main` ref. Roadmap #292's schema-audit track (#293) bumped
this pin to `v0.7.0` (`f51a8bb73a47452eff5799e8a27251b660ba4ae0`,
confirmed working via `idd-doctor`, `ajv-cli`, and
`idd-helper-bundle-manifest` against this repository) ahead of the
instructions/skills re-import landing, opening a **transitional skew
window** where audited helper commands resolved against the `v0.7.0`
schema while `.github/instructions/` and `.claude/skills/` themselves
stayed on the prior `v0.6.0`-round import. That window closed once
roadmap #292's sibling tracks re-imported both surfaces to the same
`v0.7.0` baseline — #294 for `.github/instructions/` (PR #305), #297
for the `.claude/skills/issue-authoring/` companion bundle (PR #306)
(#295 covered the remaining docs/profiles/githooks/scripts file set,
not `.claude/skills/`). #298's final verification sweep confirmed the
pin, the instructions, and the skills bundle now all track `v0.7.0`
uniformly.

Roadmap #380's docs track
([`#383`](https://github.com/kurone-kito/dotfiles/issues/383)) bumped
this same pin to `v0.9.0`
(`d005098bf3a54a27ac79b22fb5eeb88186d235c6`).
[`#382`](https://github.com/kurone-kito/dotfiles/issues/382) had
already moved `.github/instructions/` to the same baseline, so this
bump did not open a fresh skew window there; `.claude/skills/` (the
issue-authoring companion bundle) opened the same kind of transitional
skew window the `v0.7.0` round saw between #293 and #298, until
[`#386`](https://github.com/kurone-kito/dotfiles/issues/386) (PR #398)
closed it by moving the whole bundle -- `SKILL.md`,
`references/contract.md`, `references/draft-patterns.md`, and
`references/workflow-boundary.md` -- to the same `v0.9.0` baseline.
This repository's final-verification track
([`#387`](https://github.com/kurone-kito/dotfiles/issues/387))
confirmed the pin, the instructions, and the skills bundle now all
track `v0.9.0` uniformly, mirroring #298's role in the prior round.

Roadmap #419's CI-workflow/helper-runtime-pin-bump track
([`#424`](https://github.com/kurone-kito/dotfiles/issues/424)) bumped
this same pin to `v0.11.0`
(`1f90787ebf4021673ce6e5eb69741df331fd2037`), closing the known,
accepted transitional gap PR #427's review flagged for roadmap #419's
schema/config-audit track (#420): that track intentionally bumped
`iddVersion` to `0.11.0` in `.github/idd/config.json` before this pin
followed, so a manual `idd-doctor`/`idd-helper-bundle-manifest`
invocation at the still-`v0.9.0` pin briefly reported a genuine
`additionalProperties` schema `ERROR` against the bumped config (no
`.github/workflows/` check runs that command as a required status
check, so the gap was never live-blocking). This track's own edit
surface is this section, `.github/workflows/idd-advisory-convergence.yml`,
`.github/workflows/idd-advisory-convergence-comment.yml`,
`.github/workflows/post-merge-cleanup.yml`, and `docs/customization.md`
— it deliberately does **not** touch the **Pinned upstream commit**
paragraph near the top of this page, which historically tracked the
overall `.github/instructions/`/`.claude/skills/` template-import
baseline as one unit, rather than the helper-runtime invocation pin
specifically. That framing is itself now provisional: Track E (#423,
already merged) resynced `.claude/skills/` to `v0.11.0` independently,
so as of this track the paragraph's `v0.9.0` value accurately describes
only `.github/instructions/`'s own baseline (pending Track B/#421)
until Track G's (#425) final-verification sweep reconciles the
wording -- per #420's own note above, updating that paragraph
(mirroring how it already records the `v0.7.0` → `v0.9.0` round) is
that track's job, run once every other track under roadmap #419 has
merged. `idd-doctor` re-run from the
`v0.11.0` tarball against this repository's current state reports the same two
pre-existing `WARN`s already documented in [`idd-doctor`
findings](#idd-doctor-findings) and no new finding.
The companion prerequisite #96 pins Node.js ~~24.15.0~~ via
project-local [`.tool-versions`](../.tool-versions) /
[`.node-version`](../.node-version) / [`.nvmrc`](../.nvmrc) so `npx`
always resolves in a fresh worktree.
_(We've since updated to the latest LTS version)_

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

## Spec-Audit Companion

- **Status**: `installed` at `.claude/skills/idd-spec-audit/`, adopted
  during the `v0.11.0` re-import (roadmap #419, track #423). Upstream
  graduated this companion the same way `issue-authoring` was
  distributed, in the `v0.10.0` round.

This companion runs a read-only, N-parallel-pass semantic audit of the
instruction corpus (`.github/instructions/**`, the `issue-authoring`
bundle, and every installed agent entry file) for leaked session
context, cross-file contradictions, fresh-memory completability gaps,
automation blockers, and restatement-discipline drift — a semantic
check this repository's own byte-level lint/spell tooling does not
cover. It never edits a file or mutates an issue; findings
route back through the normal issue-authoring flow (or this
installation's manual issue-filing process when that companion is not
installed). See its
[SKILL.md](../.claude/skills/idd-spec-audit/SKILL.md) for the five rule
sets and execution model.

## Issue Scope

**Policy**: `roadmap-first` (migrated from `roadmap`, confirmed by
roadmap #144).

`roadmap-first`'s upstream-documented semantics prefer roadmap-linked
candidates and fall back to orphan discovery (A0-O) when the roadmap
path yields no viable candidate. This repository's
**`orphanFirstPolicy`** stays `none` (the distributed default), which
does **not** disable that fallback: per
`.github/instructions/idd-discover.instructions.md`'s A0-O section,
both `none` and `maintainer-approved` continue with A0-O — `none` only
means A0-O applies no extra approval gate before passing candidates to
A3.5 (the gate that `maintainer-approved` adds instead). In this
repository, when the roadmap path yields no viable, startable,
unclaimed candidate, A0-O runs and every discovered orphan issue that
passes A3's ordinary readiness checks becomes a candidate, with no
additional gate.

`public-disabled` is the one `orphanFirstPolicy` value that actually
skips A0-O outright, for a public repository or when visibility cannot
be determined (private/internal repositories behave the same as
`none`) — since this repository is public, moving to `public-disabled`
would be the change that disables the fallback here; moving to
`maintainer-approved` instead adds an orphan-specific approval gate on
top of the fallback that already runs under `none`.

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
git config --local core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
```

Any environment that starts from a fresh clone per task (a coding
agent, an ephemeral container, a throwaway checkout) never inherits
this setting and must run it as an environment-setup step, not a
one-time human action. Confirm it took effect with `idd-doctor`, which
reports an **enabled-but-inert** finding when `worktreeGuard.enabled`
is `true` but `core.hooksPath` is not pointed at `.githooks`. Bypass
the guard for a single intentional commit or push with `--no-verify`.

## Post-Merge Cleanup Automation

[`.github/workflows/post-merge-cleanup.yml`](../.github/workflows/post-merge-cleanup.yml)
(#223) runs the F4 comment-cleanup step server-side on every merged PR,
via a `pull_request_target: closed` trigger filtered to
`merged == true` (or an explicit `workflow_dispatch`, additionally
re-verified against `gh pr view` before it runs `--apply`, since the
dispatch input itself is not otherwise constrained to a merged PR). It
invokes the pinned `ephemeral-npx`
`idd-audit-pr-cleanup --pr <N> --apply --skip-claim-check --format json`
CLI and posts the same `<!-- idd-cleanup-evidence: ... -->` comment an
agent's manual F4 step would, skipping the post when a prior evidence
comment already exists.

This backstops the manual, agent-run F4 step documented under
[`idd-doctor` findings](#idd-doctor-findings): #220 found that most of
one session's merges skipped F4 by hand, growing a 35-PR backlog before
this workflow existed. With the workflow wired, every future merge
gets cleanup evidence within minutes regardless of whether the merging
agent ran F4 itself; the agent's own F4 step still runs first when
present and simply finds nothing left to do (duplicate-success-record
skip rule in
[`docs/idd-comment-minimization.md`](idd-comment-minimization.md)).

`runs-on: ubuntu-latest` follows this repository's own
`idd-advisory-convergence.yml` convention rather than upstream's
`ubuntu-slim`, matching how this repository already runs its other
npx+gh workflows. The `actions/checkout` / `actions/setup-node` steps
keep upstream's pinned-commit-SHA choices rather than this repository's
usual floating major-version tags, since this workflow's elevated
`pull_request_target` permissions warrant the same supply-chain
hardening upstream already applied. The trust-model invariants that
actually gate those permissions (no `ref:` override, no PR-head
execution, merged-only guard including the `workflow_dispatch`
re-verification, least-privilege `permissions:`) are preserved from
upstream.

## Advisory Bot Logins

**`advisoryBotLogins`**:
`["copilot-pull-request-reviewer[bot]", "coderabbitai[bot]", "chatgpt-codex-connector[bot]"]`.

The first two logins were confirmed against live review events on
[PR #193](https://github.com/kurone-kito/dotfiles/pull/193), which
carries review activity from both bots. `chatgpt-codex-connector[bot]`
was confirmed on
[PR #374](https://github.com/kurone-kito/dotfiles/pull/374), which
received a Codex usage-limit notice from that login. Settle/wait
([`idd-advisory-wait.instructions.md`](../.github/instructions/idd-advisory-wait.instructions.md))
stays Copilot-only regardless of this list — **`advisoryWait.primaryBotLogin`**
and **`advisoryWait.secondaryBotLogin`** are left unset, so every
configured login here (including a non-review notice) is dispositioned
on arrival but never gates the advisory-wait clock.

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
**`ciGate.externalChecks.waivable`**:
`[{ "selector": "idd-advisory-convergence" }]`. **`authorityPolicy`**
and **`maxValidity`** are left unset (distributed defaults
`owners-and-maintainers-only` and `PT24H`).

This prepares the waiver path for roadmap #144's #149 (hosting the
`idd-advisory-convergence` workflow as a required status check) and is
harmless while that check does not yet exist — no selector currently
matches anything, so no waiver can be issued or consumed.

## New 0.4.0 Schema Keys Left at Default

Confirmed at their distributed defaults rather than given an explicit
`.github/idd/config.json` entry (roadmap #144), except where the
Status column below records an explicit override. Each key's row
(Status and, where relevant, Notes) is the single place a future
status flip needs to change.

| Key | Status | Notes |
| --- | --- | --- |
| `advisoryWait.convergenceScope` | default: `all-prs` | |
| `advisoryWait.sameHeadRerollCap` | default: `2` | |
| `advisoryWait.recoveryCycleCap` | default: `2` | |
| `advisoryWait.terminalWindow` | default: `PT12H` | |
| `mergeGate.soloCodeownerAdminFallback` | default: `auto-admin-retry` | This repository is solo-maintainer (`trustedMarkerActors: ["kurone-kito"]` only) with `mergePolicy: fully_autonomous_merge`, exactly the topology this key governs, and the distributed default (F3 retries once with `gh pr merge --admin` when the sole blocker is the solo-CODEOWNER self-approval deadlock) matches this repository's existing autonomous-merge intent. Recorded here as a deliberate confirmation, not an oversight. Separately confirmed (#325): `gh pr merge --admin` — whether reached via F3's automated `auto-admin-retry` fallback when it is eligible, or invoked manually by an operator/agent as a last resort for a different blocker type — additionally depends on the `master`-covering ruleset granting the caller bypass eligibility; without a `bypass_actors` entry that yields `current_user_can_bypass != "never"`, `--admin` fails outright with a "Repository rule violations found" error regardless of which rule is actually blocking. This is a separate, more general precondition and does not change the automated fallback's own solo-CODEOWNER-only eligibility scope (`isEligibleForSoloCodeownerAdminFallback` in `idd-skill`'s `idd-merge-execute.mts` still gates on `codeownerSelfApproval.status === 'clear'`). As of 2026-08-30 this repository's `master`-covering ruleset (`gh api repos/kurone-kito/dotfiles/rulesets/18861545`) has `bypass_actors: []` and `current_user_can_bypass: "never"`, confirmed during the PR #324 session and re-confirmed live during the PR #328 merge the same day. Verified manual escape when this is hit: temporarily `gh api --method PUT repos/kurone-kito/dotfiles/rulesets/18861545` (or the GitHub web UI ruleset editor) to add a scoped `bypass_actors` entry, retry the merge, then immediately remove the entry and confirm restoration with `gh api repos/kurone-kito/dotfiles/rulesets/18861545 --jq '{bypass_actors, current_user_can_bypass}'` matching the pre-edit state. For the operator's own future consideration only, not decided here: a **permanent** entry of the same kind verified above (`bypass_mode: "always"`) would avoid this manual edit each time, but it would also permanently weaken every rule on this ruleset for admin actions (deletion protection, non-fast-forward protection, every required status check, and the Copilot code-review requirement (`copilot_code_review`) — this ruleset's `pull_request` rule itself currently sets `require_code_owner_review: false`), not only the admin-merge case; a narrower `bypass_mode: "pull_request"` entry (see `docs/permissions.md`'s "Pull-request-only ruleset bypass") would scope that trade-off to pull-request merges instead, but whether it alone suffices for `--admin` was not verified this session — a blast-radius trade-off for the operator to decide separately. |
| `ciGate.trustEmptyProtectionReads` | **explicit: `true`** (was default `false` at #146) | Confirmed at its `false` default in #146, but now set to `true` in `.github/idd/config.json` — see [Required status checks on `master`](#required-status-checks-on-master) for why the fail-closed default became unworkable once `idd-ci.instructions.md` started treating an untrusted `404` on the classic branch-protection read the same as a `403` (post-#146 exception). |

## New 0.5.0/0.6.0 Schema Keys Left at Default

Audited by roadmap #239's policy-schema track (#234): a structural diff
of `schemas/policy.schema.json` between the prior 0.4.0-round pin
(imported by roadmap #144, 1242 commits past the `v0.4.0` tag but still
376 commits behind the `v0.5.0` tag) and `v0.6.0`
(`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`) found only three genuinely
new properties; everything else the issue's starting inventory listed
already existed structurally at the pin (only their JSON Schema
`description` text was added later) and is confirmed unchanged at
`v0.6.0`. Per the roadmap's confirmed operator decision, every key
below stayed at its distributed default as of #234 itself —
`.github/idd/config.json` was unchanged by that issue. Each key's row
in the table below (Status and, where relevant, Notes) is the single
place a later status flip needs to change; see the
[0.4.0 section](#new-040-schema-keys-left-at-default) above for the
same convention. `.github/idd/config.json` was
re-validated against the fetched `v0.6.0` schema with `ajv-cli validate
--spec=draft2020` (passed) and with `idd-doctor` run from the pinned
`v0.6.0` tarball itself (`result: passed`,
`PASS .github/idd/config.json validates against policy.schema.json`,
the same four pre-existing warnings as before) — no correctness break
found as part of #234's own audit.

### Genuinely new in 0.5.0/0.6.0

| Key | Status | Notes |
| --- | --- | --- |
| `advisoryWait.exemptBotAuthoredPrs` | default: `false` (0.6.0) | Opt-in claimless-waiver exemption letting a bot-authored PR with no claim history pass advisory-convergence as `not_applicable` without a per-PR maintainer waiver. Left at default: this repository's dependency-update PRs (Dependabot) are handled by existing merge automation, and enabling a bot-authorship exemption is a deliberate future decision, not something to adopt silently alongside a docs audit. |
| `ciGate.trustSourcePinnedRequiredChecks` | **explicit: `true`** (was default `false`; 0.5.0 key, flipped in a same-day follow-up) | Changed from the `false` default during this round — see [Required status checks on `master`](#required-status-checks-on-master) for the incident that made this reachable. Opt-in trust for a required check whose ruleset/branch-protection entry is source-pinned to a specific GitHub App/integration (`app_id`/`integration_id`). After the `master` ruleset's `required_status_checks` rule was restored following an accidental removal (see below), every entry came back pinned to `integration_id: 15368`. The operator verified out-of-band via `gh api app/15368` and live check-run `app.id` fields on a merged PR that `15368` is GitHub's own `github-actions` App — the sole producer of every workflow-based check this repository requires — so this key was flipped to `true` per the schema's documented human-authorized-decision path, rather than left at the fail-closed default. |
| `helperRuntime.packageSpec` | default: unset (0.5.0) | Optional pinned npm spec/tarball/commit archive overriding the mutable main-archive fallback for `package-manager`/`ephemeral-npx` helper invocations. This repository already pins every helper invocation explicitly per command (see [Helper Runtime Profile](#helper-runtime-profile)) via the `npx --package <tarball-url>` form, so this key would be redundant with the existing per-invocation pinning convention. |

### Confirmed pre-existing (unchanged since the 0.4.0-round pin)

The following inventory keys already existed structurally before this
round; each is documented with its confirmed default in
[`docs/policy-constants.md`](./policy-constants.md), reconfirmed
unchanged at `v0.6.0`:

- **`advisoryWait.secondaryBotLogin`**: unset. Already recorded as
  intentionally unset in [Advisory Bot Logins](#advisory-bot-logins)
  (0.4.0 round) — reconfirmed here that this decision still holds and
  applies unchanged at `v0.6.0`.
- **`advisoryWait.capExhaustedRoute`**: `phase-specific` (schema enum
  `["phase-specific", "hold"]`; this repository leaves it unset at that
  default) — E14 skips the wait and proceeds to E15, while F2/F3 still
  hold for a maintainer. See
  [Advisory Review Defaults](./policy-constants.md#advisory-review-defaults).
- **`advisoryWait.requestCap`**: `30`. **`advisoryWait.pendingWindow`**:
  `PT30M`. **`advisoryWait.settledWindow`**: `PT10M`.
  **`advisoryWait.pollInterval`**: `PT2M`. See
  [Advisory Review Defaults](./policy-constants.md#advisory-review-defaults).
- **`ciGate.externalChecks.advisory`** / **`ciGate.externalChecks.waivable`**:
  selector lists, both already configurable and already exercised for
  `waivable` in this repository (see
  [CI Gate External Check Waivers](#ci-gate-external-check-waivers));
  `advisory` is unset (empty by default). The 0.6.0 claimless-waiver
  feature (a claim-id `none` sentinel plus a `--claimless`
  authoring-CLI flag) is a helper/protocol-level capability, not an
  additional schema key — its only schema surface is
  `advisoryWait.exemptBotAuthoredPrs` above.
- **`discover.activeClaimPreScanBatchSize`**: `10`. See
  [Concurrent Session Defaults](./policy-constants.md#concurrent-session-defaults).
- **`claim.verifySettleDelay`**: `PT5S`. See
  [Critique And Review Loop Defaults](./policy-constants.md#critique-and-review-loop-defaults).
- **`critiqueLoop.cPhaseLowSeveritySkipAfter`**: `3`.
  **`critiqueLoop.e10NoProgressHoldAfter`**: `3`. See
  [Critique And Review Loop Defaults](./policy-constants.md#critique-and-review-loop-defaults).
- **`reviewEscalation.changesRequestedFirstEscalation`**: `PT24H`.
  **`reviewEscalation.changesRequestedSecondEscalation`**: `PT48H`.
  See
  [Critique And Review Loop Defaults](./policy-constants.md#critique-and-review-loop-defaults).

### Not a schema key this round

- **`instructionProfile`**: confirmed still **not** a property of
  `schemas/policy.schema.json` at `v0.6.0` — the root schema object
  keeps `additionalProperties: false` and defines no such key anywhere
  in the schema tree. This remains not-yet-implemented upstream, not
  merely "not chosen"; do not set this key (already recorded in
  [`docs/idd-workflow.md`](./idd-workflow.md#lite-instruction-profile-opt-in)
  and [`docs/customization.md`](./customization.md)).
- **`CI_RUNNER_LABEL`**: a repository Actions _variable_ consumed by
  `idd-advisory-convergence.yml`, not a `.github/idd/config.json` /
  `policy.schema.json` key. No entry needed in this schema-focused
  section; its actual adoption is deferred to #237 (the
  workflow-reconciliation track), which owns workflow YAML and
  repository settings.

## New 0.7.0 Schema Keys Left at Default

Audited by roadmap #292's schema-audit track (#293): a direct diff of
`schemas/policy.schema.json` and `schemas/advisory-convergence.schema.json`
between the `v0.6.0` pin
(`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`) and `v0.7.0`
(`f51a8bb73a47452eff5799e8a27251b660ba4ae0`), re-verified against the
fetched schema text rather than trusted from the issue's own drafted
inventory (which mis-attributed one description change — see
[Description-only changes](#description-only-changes) below).
`policy.schema.json` gained two genuinely new top-level keys
(`authoringLanguage`, `critiqueLoop.delegate`); both stayed at their
distributed default as of this track. `.github/idd/config.json` was
unchanged by this audit. See the
[0.4.0](#new-040-schema-keys-left-at-default) and
[0.5.0/0.6.0](#new-050060-schema-keys-left-at-default) sections above
for the same convention. A later issue (#368) adopted
`critiqueLoop.delegate` after that audit; the table row below records
the explicit value and does not rewrite this track's historical
result.

### Genuinely new in 0.7.0

| Key | Status | Notes |
| --- | --- | --- |
| `authoringLanguage` | `"en"` (explicit, #381, roadmap #380; was `default: unset` through the `v0.7.0` round) | Optional top-level BCP-47 tag (or the literal `match-source`) selecting the prose language for newly-authored issue/PR bodies; absent behaves as `en`. Not currently read by discover/claim; read by PR-submit and issue-authoring. #381 set it explicitly to `"en"` in `.github/idd/config.json`; this repository already authored issues and PRs in English under the prior unset default, so the explicit value is a no-op in practice and never changes the fixed-English autopilot-suitability/effort footer or any HTML-comment marker regardless of this setting. |
| `critiqueLoop.delegate` | explicit again (#407; was reverted to unset by #381, roadmap #380; was explicit: set from #368 through the `v0.7.0` round) | Optional object (`command` required, `mode`: `fallback` (default) \| `combined` \| `on-success` \| `never`) letting a repository point the C1 self-review pass at an external command instead of (or alongside) the per-agent critique table. #368 adopted `command: "coderabbit-critique"`, `mode: "combined"` as a repository-local temporary substitute for the user-global `$XDG_CONFIG_HOME/idd-skill/config.json` delegate, since the `v0.7.0` pin could not yet read that file. `v0.9.0` gained user-global-config inheritance for this key, so #381 removed the repository-local `critiqueLoop` object from `.github/idd/config.json` entirely, predicting C1 would fall through to the already-deployed user-global source of truth (`home/dot_config/idd-skill/config.json.tmpl`, still pointing at the same `coderabbit-critique` wrapper by absolute, shell-quoted path -- not a bare PATH-resolved name, unlike the repo-local key below) instead of a second, repository-local copy. #407 found that prediction did not hold operationally: the pinned `v0.9.0` template's own C1 procedure text (`.github/instructions/idd-work.instructions.md`) never itself walks an executing agent through the user-global fallback resolution order -- that detail lives one hop away in `docs/idd-workflow.md`'s "User-global critique delegate default" subsection -- so every C1 pass since #381 merged silently ran without CodeRabbit-delegate coverage. #407 re-added the same `command: "coderabbit-critique"`, `mode: "combined"` object to `.github/idd/config.json` as an interim, repository-owned fix that restores coverage without depending on the upstream template gap being closed. |

### Advisory-convergence report schema (not a policy key)

`schemas/advisory-convergence.schema.json` describes the shape of the
`idd-advisory-convergence` gate's own report output, not a
`.github/idd/config.json` policy key — nothing below is adopted or
left at a default, since there is no config surface to set. Recorded
here per the issue's audit scope:

- **`reviewId`** (new required string field on the `review` object):
  the matched primary-bot review's own GraphQL node id, read only when
  `matchesHead` is true (empty otherwise). Binds Clause 1's
  itemCount-half thread evidence to the _specific_ triggering review
  via each thread's originating comment's `pullRequestReview.id`, per
  idd-skill #2050 — confirmed present in `review-clause.mts` source,
  per the **Pinned upstream commit** confirmation near the top of this
  page.
- **`review.itemCount`** gained a `"minimum": 0` constraint (tightened
  from a bare `["integer", "null"]` type). No behavioral change for
  this repository; purely a schema-strictness tightening.
- **`review.satisfied`**'s description changed from a purely mechanical
  `matchesHead && itemCount === 0 && suppressedCount === 0` check to a
  disposition-aware one, matching the `advisory-convergence.mts`
  caller-side override confirmed in source above.
- **`nextActions`** (new required top-level array field on the report
  object, idd-skill #2143): a structured next-action catalog (stable
  token + one-line English summary + command/phase pointer) mirroring
  the stderr `--assert` failure block, empty exactly when `ready` is
  true, and never feeding `ready` itself. **Consumer conclusion**: no
  file under `.github/instructions/`, `.github/workflows/`, or
  `.claude/skills/` in this repository reads or surfaces this field —
  it is diagnostic output for a human or agent reading a failed run,
  not a new gate, and this repository has no such consumer to add.
  (The unrelated `--next-action` CLI flag on
  `post-idd-marker`/`live-status-digest.mjs`, documented in
  [`docs/idd-comment-minimization.md`](idd-comment-minimization.md),
  is a status-digest field name collision only — it predates this
  schema field and reads nothing from it.)
- **`already-satisfied-via-review-ack`** (new enum value on
  `sameHeadReroll.ineligibleReasons`, alongside the existing
  `review-item-count-not-positive`): reported when the reroll gate's
  own eligibility check finds the review already satisfied via a
  valid, HEAD-matching review-ack marker rather than a positive item
  count. No config-key action needed; it is a new report value, not a
  new policy input.

### Description-only changes

Both re-verified against the fetched `v0.7.0` schema text directly, no
shape change in either case:

- **`reviewPolicy`**'s description gained a clause documenting that
  `advisory-convergence` reads it: `human-required`/`no-advisory` make
  the check `not_applicable`; other values keep today's
  Copilot/`primaryBotLogin` applicability. This repository's
  `copilot-advisory` profile (see [PR Review Policy](#pr-review-policy))
  already falls in the unaffected branch.
- **`worktreeGuard.enabled`**'s description was reworded for precision
  (references `idd-doctor`'s `--strict` flag by name, clarifies
  enforcement stays local with no CI step). This repository's existing
  [Worktree Guard](#worktree-guard) decision is unaffected.
- **Correction to the issue's own drafted inventory**: the issue body
  claimed "`ready`'s own description gained a clause" (a suppressed-
  count/review-ack edge case). Re-reading the fetched `v0.7.0` schema
  directly shows the top-level `ready` property's description is
  byte-identical to `v0.6.0`; the changed description described in the
  issue actually belongs to `sameHeadReroll.eligible` (see
  `already-satisfied-via-review-ack` above), not `ready`. Recorded here
  as the corrected attribution, per the issue's own instruction to
  re-verify against the actual schema rather than trust the drafted
  inventory.

## New 0.10.0/0.11.0 Schema Keys

Audited by roadmap #419's schema/config-audit track
([`#420`](https://github.com/kurone-kito/dotfiles/issues/420)): a
direct diff of `schemas/policy.schema.json` between the `v0.9.0` pin
(`d005098bf3a54a27ac79b22fb5eeb88186d235c6`) and `v0.11.0`
(`1f90787ebf4021673ce6e5eb69741df331fd2037`), re-verified against the
fetched schema text. Upstream shipped two releases in this window --
`v0.10.0` and `v0.11.0` -- and `policy.schema.json` gained 7 genuinely
new top-level/nested keys across both. `.github/idd/config.json` was
updated by this track: `iddVersion` now reads `"0.11.0"`, and the file
was re-validated with `ajv-cli validate --spec=draft2020` against the
fetched `v0.11.0` schema (passed) and with a pinned `idd-doctor` run
from the `v0.11.0` tarball itself (`result: passed`, the same two
`WARN`s already documented in [`idd-doctor`
findings](#idd-doctor-findings) -- no new finding). See the
[0.4.0](#new-040-schema-keys-left-at-default),
[0.5.0/0.6.0](#new-050060-schema-keys-left-at-default), and
[0.7.0](#new-070-schema-keys-left-at-default) sections above for the
same convention.

### Genuinely new in 0.10.0/0.11.0

| Key | Status | Notes |
| --- | --- | --- |
| `issueAuthoring.journalIssue` | **explicit: `"kurone-kito/dotfiles#380"`** | Owner-confirmed before #419 was authored (see #419's "Decisions confirmed before authoring"): formalizes the already-in-use ad hoc authoring-journal practice for a standalone authoring set with no existing issue or anchor. |
| `labels.untrustedLabelerLogins` | **explicit: `["coderabbitai[bot]"]`** | `coderabbitai[bot]` is confirmed active (`.coderabbit.yaml`'s `issue_enrichment.labeling.auto_apply_labels: true`; its most recent repo-wide `labeled` event is 2026-09-12). `reviewpad[bot]` -- present in this repository's historical label-event actor list -- was checked and excluded: its latest `labeled` event is 2023-10-21 (issue #77), roughly three years stale, and no `.reviewpad*` configuration file exists anywhere in the repository. Schema-supported metadata only; no distributed enforcement (CI guard generation) reads this list yet, per the key's own schema description. |
| `worktreeGuard.refuseBaseBranchCommits` | **explicit: `true`** | Owner-confirmed (#419): catches a session that skips B1 entirely and commits directly on `master`, a gap the existing `branchPatterns` check does not cover. **Wired as of Track C (#422)**: `.githooks/_idd-worktree-guard.sh` now parses this key and refuses a commit/push made from the primary worktree while `HEAD` matches the configured `developmentBranch`; `.githooks/pre-commit`/`.githooks/pre-push` already sourced the guard script and call `idd_worktree_guard_check` unchanged, so no separate wrapper edit was needed. Behaviorally confirmed in a disposable scratch clone with `core.hooksPath` wired: a direct commit on `master` is refused, `--no-verify` still bypasses it. This closes the transitional-skew-window this row previously recorded (the same pattern the 0.7.0/0.9.0 rounds above recorded for `.claude/skills/` gaps). |
| `upstreamEscalation.enabled` | **explicit: `true`** | Owner-confirmed (#419): this repository's owner also maintains `kurone-kito/idd-skill` upstream, the exact scenario this feature bridges. **Partially wired as of Track E (#423)**: `.claude/skills/issue-authoring/references/contract.md`'s `upstream-candidate` marker/label binding rules now gate on this key (confirmed by grep). `.github/instructions/` still has no consumer -- Track B (#421, instructions resync) is expected to add that half. Same transitional-skew-window caveat as the row above, now narrower. |
| `critiqueLoop.telemetryHook` | **explicit: `{"command": "idd-critique-telemetry"}`** | Introduced among the upstream `v0.10.0` opt-in toggles (not `v0.11.0`-only, per #419's own background section). Cross-referenced from #389/PR #426's own review: wiring this key into `.github/idd/config.json` there would have paired it with this repository's then-still-`0.9.0` `iddVersion` (the `v0.9.0` schema has no `telemetryHook` property, `additionalProperties: false`), so adoption was deferred to this issue instead. Bare command name (`idd-critique-telemetry`), matching the sibling `critiqueLoop.delegate.command` entry's own PATH-relative convention; PR #426 already shipped the resolving launcher (`home/dot_local/bin/executable_idd-critique-telemetry` plus `.ps1`/`.cmd` Windows launchers). **Not yet behaviorally wired** in the instruction files for the same Track B reason as the two rows above -- the C-phase procedure text itself does not yet walk an executing agent through invoking this hook (mirroring the `critiqueLoop.delegate` gap #407 already found and fixed for a different key). |
| `critiqueLoop.deferAfterRounds` | default: unset | Owner-confirmed (#419) to stay at its distributed default (`15`) this round -- no repository-specific override adopted. |
| `issueAuthoring.heartbeatCoalesceWindow` | default: unset | Owner-confirmed (#419) to stay at its distributed default (`PT2M`) this round -- no repository-specific override adopted. |

This round intentionally does **not** update the **Pinned upstream
commit** paragraph near the top of this page or this file's other
tarball-URL citations -- per roadmap #419's own track split, updating
this page's historical pin narrative (mirroring how it recorded the
`v0.7.0` -> `v0.9.0` round) is Track G's (#425) final-verification-sweep
job, run once every other track (#420-#424, #389) has merged. This
track's edit surface is `.github/idd/config.json` and this section
alone. (Separately, `.github/workflows/` pins and the
`ephemeral-npx`-profile helper-runtime invocation pin are Track D's
(#424) scope, not this page's.)

**Known, accepted transitional gap, now closed (Copilot review, PR #427;
closure confirmed by Track D/#424).** This track intentionally
bumped `iddVersion` to `0.11.0` before Track D (#424) bumped this
repository's `ephemeral-npx` helper-runtime invocation pin off
`v0.9.0` (`d005098bf3a54a27ac79b22fb5eeb88186d235c6`, at the time still
cited throughout [Helper Runtime Profile](#helper-runtime-profile) and
every helper invocation in `.github/workflows/`). Consequence, verified
directly at the time: running this repository's own documented
`idd-doctor` invocation at the still-`v0.9.0` pin against the config
this track produced a genuine `ERROR`
(`$: additional property "upstreamEscalation" not allowed`, and
similarly for the other four new top-level/nested keys) rather than
only the two pre-existing `WARN`s -- the `v0.9.0` schema's
`additionalProperties: false` rejected all five new keys outright. This
was expected and did **not** block merging this PR or any sibling
track: no `.github/workflows/` check ran `ajv`/`idd-doctor` as a
required status check (confirmed by repository-wide grep before this
track was selected), so the gap was visible only to a human or agent
manually running the `v0.9.0`-pinned command by hand. **Track D (#424)
has since landed**, bumping the Helper Runtime Profile pin and every
`.github/workflows/` helper invocation to `v0.11.0` and closing this
gap -- see that section for the current pin. This passage is kept as a
historical record of the transitional-gap pattern, not as current
validation guidance.

### Report-shape schemas audited (not policy keys)

Six report-output schemas changed shape between `v0.9.0` and `v0.11.0`.
None is a `.github/idd/config.json` policy key -- these describe helper
JSON _output_, not configuration _input_ -- so nothing below is adopted
or left at a default; recorded here per this issue's own audit
instruction. For each, every new/changed field name was grepped across
`.github/`, `docs/`, and `scripts/`: **no local consumer found** in any
case, since this repository only invokes these helpers as opaque `npx`
CLI commands and never parses their JSON output against a hardcoded
field name in checked-in code.

| Schema | New/changed fields | Consumer conclusion |
| --- | --- | --- |
| `disposition-non-review-notices.schema.json` | `staleSkipped` (array; `noticeId`, `botLogin`, `reason`) | No local consumer |
| `post-idd-marker.schema.json` | Description-only change; no new field | N/A |
| `pre-merge-readiness.schema.json` | `claimIdentityInstalledAt`, `identityUnresolvedRequiredCheckNames`, `preDowngradeStatus`, `runId`, `stale`, `staleSelfWaiver` (CI-check-identity-spoofing closures; `checkSelector`/`createdAt`/`expiresAt`/`waiverClaimId`/`waiverEvidence` already existed at `v0.9.0` and are excluded from this "new fields" list) | No local consumer for these new fields. Narrower than a blanket claim (Copilot review, PR #427): `idd-pre-merge.instructions.md`'s F2 procedure already reads several of the pre-existing `waiverEvidence` fields (`valid`, `headSha`, `claimId`, `expiresAt`) -- unrelated to this round's genuinely-new fields, which remain unconsumed. |
| `token-cost-sample.schema.json` | `toolCallCount`, `turnCount` | No local consumer |
| `token-cost-snapshot.schema.json` | `toolCallCount`, `turnCount` (aggregated) | No local consumer |
| `advisory-convergence.schema.json` | `waiver.autoWaiverValid` (kurone-kito/idd-skill#2657; unconditional bootstrap-auto-waiver disjunct) | No local consumer |

## Divergence Register

Every intentional deviation from the pinned upstream template carries
a `dotfiles-divergence: <slug>` marker at its point of use -- an HTML
comment (`<!-- ... -->`) in Markdown/YAML/instruction files, a line
comment (`// ...`) in JavaScript -- so a future re-import can detect
and preserve it instead of silently reverting to upstream's default.
Current slugs:

| Slug                                 | What it marks                                                                                                                                                                                                                                                                                                                                                                                                           | Introduced by                                  |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `claim-timing`                       | The `12h`/`6h` claim-stale-age/heartbeat-interval override, in place of the `24h`/`12h` distributed defaults                                                                                                                                                                                                                                                                                                            | #145, #196, #232, #233, #294, #295, #382, #383, #421, #422 |
| `cleanup-evidence-dedup-recheck`     | The corrected "Double-posting is prevented by..." paragraph in `docs/idd-comment-minimization.md` (double-checked locking: a mandatory, freshly-fetched re-check of the trusted-author `idd-cleanup-evidence` record immediately before each side's own POST call, not a single early check) and the matching literal re-check command added to `idd-merge.instructions.md`'s F4 step. Upstream's `v0.9.0` template still describes the single-check "prevented by" framing this round found racy (CodeRabbit, PR #396); the correction narrows the duplicate-comment window and explicitly documents the residual race (GitHub REST comments have no compare-and-swap) as accepted risk rather than closing it outright. | #397, #421, #422, #424                        |
| `helper-profile-ephemeral-npx`       | This repository's `ephemeral-npx` helper profile, where docs describe a different upstream-default profile inline                                                                                                                                                                                                                                                                                                       | #196, #233, #295, #383, #424                   |
| `installed-bundle-reference-routing` | The issue-authoring companion's reference routing, adapted for an installed-bundle (not source-repo) stance                                                                                                                                                                                                                                                                                                             | #147, #235, #297, #386, #423                   |
| `local-docs-index`                   | The "Local pages" table `docs/index.md` appends below upstream's generated OKF table, covering this repository's own locally-authored, non-upstream `docs/` pages upstream's generator has no knowledge of. The row's original retirement trigger -- the synced pages gaining OKF frontmatter of their own -- held as of the `v0.7.0` baseline already; the `v0.9.0` round (#383) adopted the generated table itself, so this row now marks only the residual local-page extension, not a whole-file exclusion | #283, #383                                     |
| `master-branch`                      | `master` in place of upstream's `main` as the integration branch name                                                                                                                                                                                                                                                                                                                                                   | #145, #196, #232, #233, #237, #294, #295, #296, #382, #383, #384, #421, #422, #424 |
| `needs-triage-label`                 | The `status:needs-triage` A3 readiness-exclusion bullet in `idd-discover.instructions.md`, skipping a human-filed intake report until it is rewritten into IDD-ready form -- a dotfiles-specific addition with no upstream equivalent. Two marker instances: the A3 bullet itself and its mirror in A0-O's readiness parenthetical (the orphan-first fallback path re-states A3's bullets inline rather than referencing them, so both copies need the marker)                                     | #415, #421                                     |
| `onboarding-doc-trim`                | The deliberate exclusion of `docs/onboarding/placeholders.md` and `docs/onboarding/policy-decisions.md` (self-corrupt after placeholder substitution), linking to the pinned upstream copies instead. Through the `v0.7.0` round, upstream's generated `docs/index.md` was excluded wholesale for the same reason (its table links both trimmed pages); the `v0.9.0` round (#383) adopted that generated table instead, omitting only the two rows that would have linked the trimmed pages -- see `local-docs-index` above | #145, #196, #233, #295, #383, #422             |
| `signing-ladder`                     | The GPG -> SSH -> unsigned commit-signing fallback ladder, a dotfiles-specific addition with no upstream equivalent                                                                                                                                                                                                                                                                                                     | #145, #232, #294, #382, #421                   |
| `vendored-file-header`               | The corrected header on `scripts/minimize-superseded-markers.mjs`, since this repository has no build step to regenerate it from a TypeScript source                                                                                                                                                                                                                                                                    | #196, #233, #383, #422                         |
| `worktree-guard-wiring-note`         | Documents that this repository ships every Worktree Guard enforcing component together (opt-in config surface, `.githooks/` hook set, `idd-doctor`'s enabled-but-inert check) instead of upstream's generic "config surface only" framing, since `core.hooksPath` wiring is still a required per-clone step                                                                                                             | #233, #295, #383, #424                         |
| `lite-telemetry-parity`              | `docs/idd-workflow.md`'s note that `lite/idd-work-lite.instructions.md` actually invokes `critiqueLoop.telemetryHook` from its own C1/C2/C4 steps, unlike the stock-template's "lite profile does not invoke this hook" framing (byte-identical to the `v0.11.0` pin) -- the hook call itself was added to the lite file during #421's own review-fix round; this note documents that local behavioral departure from the stock "full-profile-only" description                                | #421, #422                                     |
| `ci-companion-topology`              | `.github/instructions/idd-ci.instructions.md`'s corrected rerun-mechanics passage describing the `idd-advisory-convergence-comment.yml` companion-refresh topology, in place of upstream's own still-stale `v0.11.0` template text (filed upstream as [`kurone-kito/idd-skill#2966`](https://github.com/kurone-kito/idd-skill/issues/2966); see the deferred-upstream-issues ledger below)                                       | #421, #425                                     |

**Resolved this round**: `cleanup-evidence-untrusted-check-gap`
(introduced by #233) tracked a caveat that
`post-merge-cleanup.yml`'s duplicate-evidence-comment check matched on
the marker prefix alone without verifying the commenting author. #237
ported upstream's trust-scoped dedup check (an existing
`<!-- idd-cleanup-evidence: ... -->` comment now only counts as a
duplicate when its author is `github-actions[bot]` or a
`trustedMarkerActors` login), closing the gap and restoring parity
with upstream's original trusted-author framing. The marker and
caveat text were removed from
[`docs/idd-comment-minimization.md`](idd-comment-minimization.md) as
part of #238's final verification sweep, since the local behavior no
longer diverges from upstream.

**Reaffirmed at the v0.7.0 round**: roadmap #292's re-import (#293-#297)
touched files carrying seven of the eight registered markers; the table
above now attributes each accordingly (PR #302/#303/#304/#305/#306 file
lists cross-referenced against each slug's live marker instances). #298's
final verification sweep additionally confirmed every registered slug
still has at least one live, findable marker instance in the repository
(a repository-wide grep, not a visual spot-check) — none has silently
reverted to upstream's default. `vendored-file-header`
(`scripts/minimize-superseded-markers.mjs`) was not touched by any of
this round's five PRs, so it carries no new attribution; its marker is
still present and correct.

**Reaffirmed this round (v0.9.0, 2026-09-09)**: roadmap #380's six
tracks (#381-#386) were cross-referenced against each of the then-9
registered slugs' live marker instances (before #397 added the tenth,
`cleanup-evidence-dedup-recheck`, above) using the same method as the
`v0.7.0` round above (each track's merged-PR file list diffed against
the files carrying each marker). Track #382 (`.github/instructions/`
re-import, PR #395) additionally touched `claim-timing`,
`master-branch`, and `signing-ladder` markers that the table had not
yet attributed to it; track #384 (CI workflow pin bump, PR #392)
additionally touched the `master-branch` markers in
`idd-advisory-convergence.yml`/`idd-advisory-convergence-comment.yml`;
track #386 (issue-authoring companion re-import, PR #398) touched the
`installed-bundle-reference-routing` markers in `SKILL.md` and
`references/contract.md`. The table above now attributes all three.
Tracks #381 (schema-audit, PR #391) and #385 (opt-in feature adoption,
PR #394) touched only `.github/idd/config.json`, which carries no
divergence marker, so neither gains a new attribution.
`vendored-file-header` (`scripts/minimize-superseded-markers.mjs`) was
not touched by a file diff in any of this round's six PRs either, but
unlike the `v0.7.0` round, track #383 actively re-verified this file
against the pinned `v0.9.0` source while auditing the deferred-upstream
items below: upstream's own
`idd-template/scripts/minimize-superseded-markers.mjs` is
byte-identical between `v0.7.0` and `v0.9.0` (independently
reconfirmed here), and the local file's body past its
deliberately-diverged header (`scripts/minimize-superseded-markers.mjs:2-10`,
the `vendored-file-header` divergence itself) matches that upstream
body exactly, so no local code update was needed. The header
correction itself is **not** byte-identical to upstream by design and
must stay that way -- a future re-import overwriting it with
upstream's own shorter auto-generated-file notice would be a
regression, not a sync. Its existing `#383` attribution reflects that
verification-only basis rather than a content diff. A
repository-wide `dotfiles-divergence` grep confirms every registered
slug still has at least one live, findable marker instance — none has
silently reverted to upstream's default. Track #387 performed the
initial full verification, which covered the then-9-slug register.
Tracks #397 and #415 each later added a new slug, and #415 re-ran the
same repository-wide grep against its own updated, now-11-slug
register (including its own `needs-triage-label` slug's two marker
instances) while editing this paragraph, and the check still holds.
(Worded as an evergreen check rather than a fixed count -- see the
Divergence Register table above for the current, authoritative count
and list.)

**Reaffirmed this round (v0.11.0, 2026-09-13)**: roadmap #419's six
tracks (#420-#424, #389) were cross-referenced against each of the 11
registered slugs' live marker instances the same way as the two prior
rounds above, using each track's own merged-PR file list (see each
track's PR number cited below) diffed against the files carrying each
marker. Track #421 (`.github/instructions/`/`lite/`
re-import, PR #430) touched `claim-timing`, `cleanup-evidence-dedup-recheck`,
`master-branch`, `needs-triage-label`, and `signing-ladder` markers;
Track #422 (docs/githooks/scripts/lint-config resync, PR #431) touched
`claim-timing`, `cleanup-evidence-dedup-recheck`, `master-branch`,
`onboarding-doc-trim`, and `vendored-file-header`; Track #423
(companion skills resync, PR #428) touched `installed-bundle-reference-routing`;
Track #424 (CI workflow + helper-runtime pin bump, PR #429) touched
`cleanup-evidence-dedup-recheck`, `helper-profile-ephemeral-npx`,
`master-branch`, and `worktree-guard-wiring-note`. Tracks #420
(schema/config audit, PR #427) and #389 (critique-telemetry-hook
consumer, PR #426) touched no divergence-marker-carrying file, so
neither gains a new attribution. `local-docs-index` (`docs/index.md`)
was not touched by any of this round's six PRs either, but a fresh
repository-wide `dotfiles-divergence` grep (this round, #425) confirms
its marker -- and every other then-registered slug's marker -- still
has at least one live, findable instance; none has silently reverted
to upstream's default.

**Register completeness gap found and closed (Copilot review of this
PR, dotfiles#432)**: the grep pass above was scoped to the **11
already-registered** slugs, not to every distinct `dotfiles-divergence:
<slug>` string actually present in the repository -- an unbiased
repo-wide search (`grep -rho 'dotfiles-divergence: [a-z-]*'` over the
same file set, deduplicated) is the check that actually proves
completeness, and running it found a **twelfth live slug**,
`lite-telemetry-parity` (`docs/idd-workflow.md`), that predates this
round (added alongside Track #421's own review-fix round, marked
during Track #422's own PR #431 review-fix round) but had never
gained its own Register row. Added above, attributed to #421/#422 per
the marker's own history. Separately, this same review round surfaced
a **thirteenth**, brand-new slug this track itself adds:
`ci-companion-topology` (`.github/instructions/idd-ci.instructions.md`),
marking the local rerun-mechanics correction the deferred-upstream-issues
ledger below (`kurone-kito/idd-skill#2966`) explains is still absent
from upstream's own template -- also added above. The Register now
carries **13** slugs; the unbiased repo-wide search is the
authoritative completeness check for any future round, not a grep
scoped to a remembered list.

## Open follow-ups

The remaining work after onboarding lives in two roadmaps. The
specific entries below summarize what is still outstanding, what is
already wired up, and how the IDD CI wait actually behaves when a
required-check set is partial.

### Required status checks on `master`

`master`'s merge gate currently comes from a default-branch ruleset
matching `~DEFAULT_BRANCH`; classic branch protection is not
configured today, though the CI wait unions both sources if that
changes. The ruleset's `required_status_checks` rule lists five
required check contexts, spanning the Linting and Test workflows plus
the advisory-convergence gate added by #149: `lint`,
`Lua syntax check`, `Bash tests (bats)`, `PowerShell tests (Pester)`,
and `idd-advisory-convergence`. `PowerShell 5.1 tests (Pester)` (#166)
is deliberately **not** on this list -- advisory only, per that
issue's explicit scope, while the leg proves stable.

[`#109`](https://github.com/kurone-kito/dotfiles/issues/109) and
[`#110`](https://github.com/kurone-kito/dotfiles/issues/110) (children
of roadmap [`#107`](https://github.com/kurone-kito/dotfiles/issues/107))
had already fixed the environmental failures blocking
`Bash tests (bats)` and `PowerShell tests (Pester)` from being
promoted (`chezmoi` missing on the Ubuntu runner; 13 Windows-only
Pester cases), but closed without evidence that the actual promotion
ran. [`#163`](https://github.com/kurone-kito/dotfiles/issues/163)
registered the original four contexts on the ruleset directly; #149
added the fifth.

Per `.github/instructions/idd-ci.instructions.md`, when an IDD run
reaches the shared CI wait, it builds the required-check set from
rulesets and branch protection; if neither source yields a
required-check set at all, IDD stops and posts a hold for missing
merge-gate policy evidence rather than silently merging. The
five-check ruleset above is now that required set.

**2026-08-12 incident.** The ruleset's `required_status_checks` rule
was found entirely absent (all five contexts gone; the other four
ruleset rules — `deletion`, `non_fast_forward`, `pull_request`,
`copilot_code_review` — were untouched) while #234's PR was in D4/F2.
Ruleset history (`gh api repos/{owner}/{repo}/rulesets/18861545/history`)
showed the rule present through the 2026-07-25 version and gone as of
2026-08-02T02:31:54+09:00, roughly a minute before an unrelated PR
merged — most likely an editing side effect while consolidating
branch-protection settings into the ruleset, not a deliberate policy
change. The maintainer restored it via the GitHub UI the same day.
The **restored** rule differs from the original in one respect: every
entry now carries `integration_id: 15368` (source-pinned to a specific
GitHub App), which the original bare-context rule did not have — see
`ciGate.trustSourcePinnedRequiredChecks` above for how this repository
resolved the resulting fail-closed gate ambiguity.

**Same-day follow-up: `trustEmptyProtectionReads`.** Once the ruleset
gate above was fixed, the very next roadmap #239 track (#235) hit a
second, independent fail-closed gate at F2: `idd-ci.instructions.md`'s
required-check discovery treats an untrusted `404` on the classic
branch-protection read (`GET
/repos/{owner}/{repo}/branches/master/protection`) the same as a
`403` and refuses to proceed unless
`ciGate.trustEmptyProtectionReads: true` is set. This repository has
never configured classic branch protection — the `404` reads
`{"message":"Branch not protected"}`, and the repository is public
with the querying token holding `ADMIN` permission, so there is no
plausible permission-hiding explanation for the `404`; it is
genuinely empty. #146 (0.4.0 round) left this key at its `false`
default without anticipating that a later `idd-ci.instructions.md`
hardening pass would turn the classic-protection read into a hard F2
blocker rather than an `idd-doctor` warning. This round flips it to
`true`, which is why the [New 0.4.0 Schema Keys Left at
Default](#new-040-schema-keys-left-at-default) entry above now
records the change instead of the original `false`.

**Scheduled drift guard (#249).** The 2026-08-12 incident sat
undetected for 11 days because nothing re-checked the ruleset between
its silent removal and the unrelated IDD run that happened to hit the
F2 merge-gate hold.
[`.github/workflows/ruleset-required-checks-guard.yml`](../.github/workflows/ruleset-required-checks-guard.yml)
closes that gap: a daily scheduled job (plus `workflow_dispatch`) calls
the `rules/branches/master` effective-rules read — a lighter-weight
endpoint than the `/rulesets` summary/detail pair `idd-ci.instructions.md`'s
required-check discovery unions with classic branch protection, and one
that does not require the elevated `administration` permission those
need — asserts the `required_status_checks` rule is present, and fails
loudly — naming the missing and/or unexpected contexts — if its context
set drifts from the five contexts listed above. It intentionally checks
only the ruleset side of that union; classic branch protection is
unconfigured on `master` today (see the `trustEmptyProtectionReads`
note above), so this is not currently a coverage gap. The
expected-context list lives in
[`scripts/check-ruleset-drift.sh`](../scripts/check-ruleset-drift.sh)'s
`default_expected_contexts` function, which carries a comment pointing
back to this section; update both together whenever a required context
is added or removed.

A red X on the scheduled run alone depends on someone checking the
Actions tab or having reliable GitHub run-failure email notifications
configured — a 2026-08-17 incident saw the guard correctly report
`conclusion: failure` once daily for 4 consecutive days with zero human
response before a maintainer restored the rule after being told
directly. The workflow now escalates beyond that red X:

- **On failure**, it searches for an open issue with the fixed,
  greppable title `ci: master ruleset required_status_checks drift
  detected`. If none exists, it opens one (creating the `bug` label
  first if the repository doesn't already have it) naming the missing
  and/or unexpected contexts and linking the failed run. If one is
  already open, it comments on that issue instead of opening a second
  one, so repeated daily failures for the same drift don't spam new
  issues.
- **On success**, it looks for that same tracking issue; if one is
  still open, it closes it with a comment confirming the rule matches
  again and linking the passing run.

The drift-comparison logic (the rule-count check and the missing/extra
context diff) lives in
[`scripts/check-ruleset-drift.sh`](../scripts/check-ruleset-drift.sh),
which takes already-fetched rules JSON (via a file argument or stdin)
so it is directly unit-testable against fixture JSON —
[`tests/bash/ruleset-drift-check.bats`](../tests/bash/ruleset-drift-check.bats)
covers the matching, missing-context, extra-context, and zero-rule
cases — without mutating the real `master` ruleset. The tracking-issue
find/escalate/recover logic (including the de-duplication behavior)
lives in
[`scripts/escalate-ruleset-drift.sh`](../scripts/escalate-ruleset-drift.sh),
covered against a stubbed `gh` binary by
[`tests/bash/ruleset-drift-escalation.bats`](../tests/bash/ruleset-drift-escalation.bats),
so this behavior is verified without ever creating, commenting on, or
closing an issue in the live repository. The workflow's `permissions:`
block now includes `issues: write` (alongside `contents: read`) so it
can create, comment on, and close that tracking issue.

### `idd-doctor` findings

A full `idd-doctor` run (pinned `ephemeral-npx` spec) now exits
`result: passed` with two `WARN`s in a worktree that has already
wired `core.hooksPath` (three on a fresh clone that has not — see that
bullet below) and no `ERROR`. The two `WARN`s in the hooksPath-wired
case read, verbatim:

```text
WARN  toolchain residue detected for marker prefix "dotfiles": .github/idd/config.json "fix-validate" contains "markdownlint-cli2"
WARN  toolchain residue detected for marker prefix "dotfiles": overview project commands table "fix-validate" contains "markdownlint-cli2"
```

A fresh clone (`core.hooksPath` unset) additionally emits this third
line:

```text
WARN  worktreeGuard.enabled is true but the commit/push guard is not active in this environment (core.hooksPath = (unset)); B1 primary-worktree commits will NOT be blocked here. Wire it with: git config core.hooksPath .githooks && chmod +x .githooks/pre-commit .githooks/pre-push — or, if an existing hook manager already owns core.hooksPath here, chain each hook to the corresponding .githooks/* script instead of repointing directly; see ONBOARDING.md's "Coexisting with an existing hook manager" section
```

Each bullet below currently reflects either a live warning, an
environment-dependent one that only shows on a fresh clone, or (struck
through) one this round found and already fixed -- none is a defect
needing further action. #218 resolved the
one finding that was a genuine `ERROR` (the `idd-task.yml` placeholder
syntax) by reformatting it; the remaining findings are accepted noise,
recorded
here so #150's kind of verification sweep does not have to
rediscover them:

- **Toolchain residue, `markdownlint-cli2`** (two instances: the
  config command table and the overview project-commands table): a
  false-positive pattern match against the pinned upstream commit's
  own toolchain, which happens to use the same tool, not a residual
  upstream-marker-prefix string. `idd-doctor`'s toolchain-residue
  scanner has no per-finding waiver flag (confirmed via
  `idd-doctor --help` while investigating #218), so this is accepted
  as permanent noise rather than suppressed.
- ~~**Command mismatch between `.github/idd/config.json` and the
  overview project-commands table**~~ (two instances:
  `pre-push-validate` and `post-fix-validate`) -- traced to commit
  `b749315` (#280, 2026-08-15), which added a `-CI` flag to
  `config.json`'s two `Invoke-Pester` invocations so a genuine Pester
  test failure propagates to the process exit code instead of being
  silently swallowed (the same fix #269 already applied to the CI
  workflow job), but did not update the mirrored table in
  `.github/instructions/idd-overview-core.instructions.md`'s Project
  commands section. Predates and is unrelated to the `v0.7.0`
  re-import; #293 already noted it as non-blocking noise (see the
  "Pinned upstream commit" note above), since that file's own text
  states `config.json`'s `commands` object overrides the table when
  present -- config.json currently exists and validates, so live
  behavior was already correct. #307's review caught the sharper
  point: `config.json`-absent-or-invalid is exactly this table's own
  documented fallback condition, so the un-flagged table command would
  silently reintroduce the test-failure-masking bug `b749315` fixed, in
  that fallback path specifically. Fixed directly in #307 by adding
  `-CI` to both table rows -- no longer a live `idd-doctor` finding.
- **`worktreeGuard.enabled` is true but `core.hooksPath` is unset in
  this environment**: expected on any fresh clone that has not yet run
  the wiring step documented in [Worktree Guard](#worktree-guard) --
  `core.hooksPath` is local, per-clone config that #148 could not ship
  in a commit. Not a repository defect; wire it per-clone as needed.
  (This warning did not surface during #298's own `idd-doctor` run
  because that run's worktree had already inherited `core.hooksPath`
  from the primary clone -- environment state, not evidence the
  condition no longer exists.)
- ~~**Branch protection reads differently at `v0.7.0`**~~ (superseded
  by #410): this bullet used to record a live `WARN` ("branch
  protection is enabled but no required status checks are configured
  on master"), reworded at `v0.7.0` from the `v0.6.0`-era "Branch
  protection not readable for `kurone-kito/dotfiles:master`" -- #293
  confirmed that particular reword was an `idd-doctor`
  wording/logic-only change, not a schema or configuration one. #410
  re-ran the same check under the now-pinned `v0.9.0` tarball
  (`d005098`) and found it now reports `PASS  required status checks
  configured on master (5, strict=false)` instead, with no `WARN` for
  this check at all (the same run still emits the two toolchain-residue
  `WARN`s quoted above; only the branch-protection check itself dropped
  its `WARN`. Separately, the `v0.7.0` tarball's own schema-validation
  `ERROR` against
  today's `.github/idd/config.json` is unrelated noise -- the config
  has grown keys the `v0.7.0` schema predates -- and does not affect
  this specific check). Unlike the `v0.6.0`-to-`v0.7.0` reword, #410
  traced this second shift to an **actual repository configuration
  change**, not a further `idd-doctor` wording/logic change, confirmed
  four ways: a direct diff of the branch-protection check's own source
  in `src/scripts/idd-doctor.mts` shows its `WARN`-vs-`PASS` message
  logic is unchanged between the `f51a8bb` (`v0.7.0`) and `d005098`
  (`v0.9.0`) tarballs (`v0.9.0` only adds an unrelated, additive
  Rulesets-only-trust-gap diagnostic that this repository's own
  `ciGate.trustEmptyProtectionReads: true` setting keeps from firing);
  an A/B run of both pinned tarballs against the identical current
  tree reports the exact same `PASS` line from both -- corroborating,
  though not by itself proving, that this shift is not a
  version-dependent artifact of the current checks-present state (only
  the source diff above rules out a wording-only change specifically
  on the `WARN` branch, since an unchanged `PASS`-path message would
  read identically either way); the classic branch-protection read
  (`GET
  .../branches/master/protection`) still returns `404 "Branch not
  protected"`, unchanged; and the `master`-covering ruleset (`id:
  18861545`, `name: main`) currently carries a
  `required_status_checks` rule with the same five contexts already
  documented under
  [Required status checks on `master`](#required-status-checks-on-master).
  That section's own Scheduled drift guard paragraph already records
  the underlying cause: a 2026-08-17 incident silently dropped the
  rule again and went unfixed through four daily guard failures before
  a maintainer restored it after being told directly. The ruleset's own
  version history pins the exact window: the rule was present at
  version 46376052 (2026-08-13T08:24:49+09:00, the earlier
  2026-08-02-to-2026-08-12/13 incident's own restoration), absent again
  as of version 46702184 (2026-08-17T08:35:02+09:00), briefly restored
  with a malformed context list at version 47133893
  (2026-08-21T06:33:16+09:00, contexts read `do_not_enforce_on_create`
  and `strict_required_status_checks_policy` -- parameter names, not
  check names, evidently pasted into the wrong field), and correctly
  restored with the same five contexts a minute later at version
  47133963 (2026-08-21T06:34:42+09:00), where it has remained since.
  #293's own open-to-close window (2026-08-19T04:07Z to
  2026-08-20T01:36Z) fell entirely inside that already-recorded
  2026-08-17 absence window, so its `WARN` was a true, contemporaneous
  read of a branch that genuinely lacked required status checks at
  that moment (the other four rules -- `deletion`, `non_fast_forward`,
  `pull_request`, `copilot_code_review` -- stayed active throughout;
  only `required_status_checks` was missing, so the branch was not
  entirely unprotected), not a wording artifact.
  **`ciGate.trustEmptyProtectionReads`** stays `true` (see
  [Required status checks on `master`](#required-status-checks-on-master)).
  `idd-doctor`'s own branch-protection check (confirmed via its
  `src/scripts/idd-doctor.mts` source) reads `rules/branches/{branch}`
  and the classic `branches/{branch}/protection` payload, and passes
  this same flag to both -- a separate consumer of the flag from
  `idd-ci.instructions.md`'s own required-check-discovery contract,
  which instead reads the `/rulesets` summary/detail pair plus classic
  protection for the unrelated D4/F2 CI-gate purpose, and never reads
  `rules/branches/{branch}` at all. The flag played no role in this
  particular shift because `idd-doctor`'s `rules/branches/{branch}`
  read itself now returns a genuine, populated `200` (confirmed live:
  `gh api repos/kurone-kito/dotfiles/rules/branches/master` lists
  `required_status_checks` among its rules) rather than an empty
  result needing the trust flag at all; the flag still applies to the
  classic read, which remains empty/`404` as always.
- **Post-merge cleanup backlog** (new since the roadmap's original
  pin, resolved by #220): the check flags merged PRs missing a
  `<!-- idd-cleanup-evidence: ... -->` comment, which requires running
  `idd-audit-pr-cleanup` and posting the marker regardless of whether
  the run finds anything to minimize -- a `clean` result (no
  candidates) still needs its own evidence comment, or the check keeps
  flagging the PR. The backlog existed because this repository's F4
  step is a manual, agent-run part of the merge sequence with no
  server-side backstop, so most of this session's merges skipped it.
  #220 cleared the existing 35-PR backlog by running the pinned
  `ephemeral-npx` `idd-audit-pr-cleanup` CLI in apply mode, under the
  active claim, against every flagged PR, and posting the evidence
  comment by hand; `idd-doctor` now reports zero backlog PRs. #223
  closed the regrowth gap by wiring the server-side
  [`post-merge-cleanup.yml`](#post-merge-cleanup-automation) workflow,
  adapted from upstream's `vendored-node`-profile original for
  `ephemeral-npx` the same way #149 adapted
  `idd-advisory-convergence.yml`.

`.github/ISSUE_TEMPLATE/idd-task.yml`'s `proposed_change` and
`acceptance_criteria` textarea placeholders formerly used
double-curly-brace hint text (`{{path}}`, `{{outcome}}`, `{{section}}`,
`{{evidence}}`) that coincidentally matched `idd-doctor`'s unresolved
IDD-import-placeholder scanner, which does not distinguish a GitHub
issue-form placeholder hint from a real unresolved template token
sharing the same `{{...}}` syntax. #218 reformatted the four to
angle-bracket hints (`<path>`, `<outcome>`, `<section>`, `<evidence>`),
matching the `acceptance_criteria` field's pre-existing
`<pattern>` / `<file>` convention in the same file, which clears the
`ERROR` without changing the hint-text UX. #238's residue sweep found
one more instance #218 missed -- the `background` field's placeholder
(`{{file or feature}}`, `{{observed state}}`, `{{PR or thread link}}`,
`{{root cause}}`) -- and reformatted it the same way.
`.github/ISSUE_TEMPLATE/idd-task.yml` is inside `idd-doctor`'s scanned
file set (it is not one of the excluded prefixes in the upstream
`idd-skill` package's `checkPlaceholders` function -- this repository
does not vendor `scripts/idd-doctor.mjs` itself under the
`ephemeral-npx` helper profile, only the compiled binary the pinned
tarball ships); the scanner still missed this instance because its
placeholder regex only matches a single `[A-Za-z0-9_-]+` token between
`{{` and `}}` -- the same pattern #218's four single-word hints
(`{{path}}`, `{{outcome}}`, etc.) matched. This field's multi-word
hints (`{{file or feature}}`, etc.) contain spaces, so the regex never
matched them at all, independent of which directory the file lives
in. A plain
repository-wide `{{` grep is still necessary to catch this class
going forward.

`checkReleaseTagDrift` and `checkDependencyVersionDrift` stay silent
in this repository, as expected (no git tags exist here, and there is
no `pnpm-lock.yaml`).

**Reaffirmed this round (v0.11.0, 2026-09-13, #425)**: a fresh
`idd-doctor` run under the now-pinned `1f90787` (`v0.11.0`) tarball,
against this track's own merged state, reports `result: passed (2
warning(s))` with exactly the same two `markdownlint-cli2`
toolchain-residue `WARN`s quoted above (worktree already had
`core.hooksPath` wired) and no new finding -- no regression and no new
gap introduced by roadmap #419's six tracks.

### `idd-onboard --verify` findings

A full `idd-onboard --verify` run (originally pinned `v0.6.0` source
tree, `--profile ephemeral-npx`; re-run by #298 against the pinned
`v0.7.0` source tree with the same profile) exits `blocking: true` with
two finding classes; both are expected, not defects, recorded here so a
future verification sweep does not have to rediscover them:

- **`manifestCompleteness.missingTarget`**: at the `v0.6.0` and `v0.7.0`
  runs, `docs/index.md`, `docs/onboarding/placeholders.md`, and
  `docs/onboarding/policy-decisions.md`. All three were deliberate
  exclusions recorded in the
  [Divergence Register](#divergence-register)'s `onboarding-doc-trim`
  entry (the two `onboarding/` pages are self-corrupting once
  substituted and stay linked to the pinned upstream copies instead;
  `docs/index.md` was evaluated and skipped by #233 for the same
  reason -- broken relative links to those same two pages). **Resolved
  for `docs/index.md` at the `v0.9.0` round (#383)**: this repository
  now imports upstream's generated `docs/index.md` table with only the
  two `onboarding/` rows themselves removed (see the `onboarding-doc-trim`
  and `local-docs-index` Register entries below), so a fresh verify run
  reports only the two `onboarding/` pages as `missingTarget` going
  forward, not three.
- **`placeholderResidue`**: at the `v0.6.0` pin, six known-placeholder
  tokens, seven raw `{{...}}` occurrences, in `docs/customization.md`
  -- one occurrence of each of the six tokens is inside the
  [placeholder mapping table](customization.md) that documents the
  onboarding substitution mechanism itself (for example, the table
  literally shows `{{REPO_NAME}}` as the template-side name for the
  live `dotfiles` value; six table rows, six occurrences), plus a
  seventh, second `{{REPO_NAME}}` occurrence outside the table, in a
  synchronization-example sentence ("Template copies use placeholders
  like `{{REPO_NAME}}` to support ..."). Both forms are the same
  documentation-as-example usage, just in prose instead of a table
  cell. A fresh run against #298's own current tree surfaces an
  additional hit this section never previously recorded: this same
  worked-example prose, right here in this bullet, itself quotes the
  placeholder token by name to describe `docs/customization.md`'s
  occurrences -- three raw `{{...}}` occurrences of its own, which the
  scanner matches as plain text with the same false-positive blindness.
  **This is not new at the `v0.7.0` pin**: re-running the `v0.6.0`-pinned
  tool against the identical current tree reports the exact same
  `docs/idd-policy.md` hit, confirmed by direct A/B invocation of both
  pinned tarballs against this file's current content. The
  previously-documented finding above (`docs/customization.md` only)
  simply predates this explanatory paragraph's own addition to
  `docs/idd-policy.md` and was never re-verified against the file's own
  content until #298's sweep -- an existing documentation-staleness gap
  this round happened to catch, not a v0.6.0-vs-v0.7.0 pin difference.
  Deliberately not restating an exact occurrence count for either file
  here: a live count goes stale the moment this section's own prose
  changes (as happened during #298's own PR #307 review, more than
  once) -- read the raw count directly with an occurrence-counting form
  (for example `grep -o '{{TOKEN}}' <file> | wc -l`; a plain `grep -c`
  counts matching _lines_, not occurrences, and undercounts if more
  than one instance ever lands on the same line) rather than trusting
  any number recorded here. `docs/customization.md`'s own occurrences
  are confirmed unchanged and still present by manual grep. Both files'
  occurrences are the same documentation-as-example non-issue.
  `idd-onboard --verify`'s residue scanner matches raw `{{...}}`
  occurrences as plain text anywhere in a scanned file and cannot
  distinguish either usage from genuine unresolved residue -- the same
  false-positive shape as the `markdownlint-cli2` toolchain-residue
  warnings above. `idd-doctor`'s own, separately-scoped placeholder
  check (`no unresolved {{...}} placeholders in IDD-managed files`)
  passes clean at both pins, and a manual repository-wide grep scoped
  to the IDD-managed surface (`.github/instructions/`,
  `.github/workflows/` excluding `${{ ... }}` Actions expressions,
  `docs/idd-*`, `docs/onboarding/`, `.claude/skills/`) found no other
  unexplained `{{...}}` residue as of this round (see
  `.github/ISSUE_TEMPLATE/idd-task.yml`'s fix above for the one
  genuine instance found and fixed, prior to this round).
  **Updated at the `v0.9.0` round (#383)**: the newly-imported
  `docs/onboarding/project-tuning.md` (one of the two new `v0.9.0`
  onboarding pages) carries two more raw `{{TRUSTED_MARKER_ACTOR}}`
  occurrences of the same documentation-as-example shape (one in
  prose, one as pinned-link text describing the placeholder itself),
  flagged by a chatgpt-codex-connector review comment on #383's PR.
  Same disposition as the two files above: a fresh `idd-onboard
  --verify` run now reports this file too under `placeholderResidue`,
  and that is expected, not a defect -- `idd-doctor`'s
  separately-scoped check still passes clean since it targets genuine
  unresolved substitution, not literal documentation-as-example
  mentions.

**Updated at the `v0.11.0` round (#425)**: a fresh `idd-onboard
--verify` run (`v0.11.0`/`1f90787` source tree against this track's own
merged target) reports `blocking: true` `placeholderResidue` on exactly
two files, and `missingTarget: [docs/onboarding/placeholders.md,
docs/onboarding/policy-decisions.md]` (the already-expected
`onboarding-doc-trim` exclusion, and the only `manifestCompleteness`
finding) with an empty `staleImportSignal`. `docs/customization.md` and
`docs/onboarding/project-tuning.md` no longer appear in the residue
list at all -- both are on `idd-onboard --substitute`'s own
placeholder-reference meta-doc skip-list, and `--verify` now applies
the same skip-list, so their previously-documented documentation-as-example
occurrences are no longer flagged (an improvement in the tool itself,
not a regression: their raw `{{...}}` occurrences are still present and
unchanged by manual grep). `docs/idd-policy.md` still reports its own
known documentation-as-example occurrences of `{{REPO_NAME}}`,
`{{TRUSTED_MARKER_ACTOR}}`, and one `{{TOKEN}}` unknown-token hit, all
inside this very explanatory section -- unchanged in kind from prior
rounds. **Deliberately not restating an exact occurrence count here**,
per this section's own established practice above: naming a literal
count in this paragraph would itself add a fresh raw `{{...}}`
occurrence of that same token every time this text is edited, making
any recorded number stale, or wrong, the moment it is written (a live
count goes stale the moment this section's own prose changes; read it
directly with an occurrence-counting form, e.g. `grep -o
'{{TOKEN}}' <file> | wc -l`, rather than trusting any number recorded
here). **One genuinely new instance this round**:
`docs/idd-design-rationale.md` now also carries one raw
`{{PROJECT_MARKER_PREFIX}}` occurrence, added during roadmap #419's
Track B re-import cycle (dotfiles#430) as a worked-example marker
literal (`` `<!-- {{PROJECT_MARKER_PREFIX}}-authoring-defer-source:
review-fix-loop-cutoff -->` ``) illustrating the review-fix-loop-cutoff
auto-release exception -- the same documentation-as-example
non-issue shape as every instance above, confirmed by direct
inspection of the cited passage. `idd-doctor`'s own, separately-scoped
placeholder check still passes clean at `v0.11.0` (see above), so this
is not a regression, only a new instance of the same known
false-positive class -- recorded here so a future sweep does not have
to rediscover it.

### Shared lint/settings config parity

Confirmed by #298: `.cspell.config.yml`, `.markdownlint-cli2.yaml`,
`.markdownlint.yml`, and `.claude/settings.json` show **no upstream
diff between the `v0.6.0` and `v0.7.0` tags** -- all four are
byte-identical in `idd-template/` across the two pins (direct tarball
diff, both fetched fresh). No upstream drift landed this round; nothing
to reconcile for the `v0.7.0` re-import itself.

Diffing the local repository's own copies against the upstream
`v0.7.0` template shows all four differ from upstream, but each is
expected, by-design divergence -- **not the same mechanism for all
four**, so treat them as two groups:

- `.cspell.config.yml`, `.markdownlint-cli2.yaml`, and
  `.markdownlint.yml` are part of the core `--import` file set;
  `docs/customization.md`'s "Documentation lint compatibility" section
  documents that `idd-onboard --import` never overwrites an existing
  target file whose content differs (reported under
  `blockedOverwrites` instead), so these three are meant to be
  hand-reconciled per repository need, never byte-identical to
  upstream.
- `.claude/settings.json` is not part of the core import at all --
  `docs/onboarding/template-distribution.md` explicitly lists it among
  the files the core `idd-template-core-files` set excludes by design
  (alongside `scripts/minimize-superseded-markers.mjs` and
  `.github/workflows/idd-advisory-convergence.yml`). `idd-onboard
  --import` therefore never attempts to copy or overwrite it in either
  direction; its local divergence from upstream's own
  `.claude/settings.json` template copy is simply out of `--import`'s
  scope, not a `blockedOverwrites` case.

One genuine gap surfaced by this comparison, **pre-existing rather than
newly appeared** (confirmed present in upstream
`idd-template/.markdownlint.yml` at both `v0.6.0` and `v0.7.0`, so it
did not "appear since" the prior round -- it has simply gone
unabsorbed since at least the `v0.6.0` round): the local
`.markdownlint.yml` was missing upstream's `table-column-style: false`
override entirely. Recorded here as a follow-up per this issue's own
instruction, rather than adopted unilaterally -- relaxing
markdownlint's table-column-alignment rule is a deliberate lint-policy
decision, not a mechanical sync, and this repository's tables
(Divergence Register included) relied on manual alignment. **Resolved
at the `v0.9.0` round (#383)**: `.markdownlint.yml` is now a wholesale
copy of upstream's `v0.9.0` file (closing #314's adopt decision), so
`table-column-style: false` is present and this gap no longer exists;
kept here as the historical record of when and why it was deferred.

### PR #291 regression check (`idd-advisory-convergence`)

Issue #296's PR #303 already built and ran the concrete regression
check this round's acceptance criteria call for: the real PR #291 (not
a synthetic fixture matching its shape) against both the old and new
pin, contrasted directly:

```console
$ npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/0a9c90dc277e05e0d7d96f1b09d79ff668860cc6 \
    idd-advisory-convergence --pr 291 --assert
# review.satisfied: false, converged: false, ready: false (exit 1)

$ npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/f51a8bb73a47452eff5799e8a27251b660ba4ae0 \
    idd-advisory-convergence --pr 291 --assert
# review.satisfied: true, converged: true, ready: true (exit 0)
```

Full command transcripts and JSON output: PR #303's body, "Decisions
recorded" §2. Same PR, same live GitHub state, only the pinned helper
commit differs — `review.satisfied`/`converged`/`ready` all flip
`false` -> `true`, confirming the advisory-convergence fix is live in
this repository's required CI the moment `v0.7.0` is the pin.

This is real GitHub state, not a constructed fixture -- stronger
evidence than the synthetic fixture the issue's own wording anticipated
building "if #296 did not include it." #296 already included it, so
this issue (#298) does not rebuild it; this section records that the
criterion is satisfied by that existing evidence.

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

### Upstream template issues deferred to the next re-import

Each item below is carried verbatim from a vendored/re-imported
upstream file at the pin recorded alongside it; this repository chose
not to fix any of them ad hoc, since the relevant track's scope was
re-import/verification, not an editorial rewrite of upstream's own
prose or vendored code. Every item below is now filed individually
against `kurone-kito/idd-skill` (see each bullet's own citation and the
round-summary note after the list); resolve any that remain unfixed
upstream locally the next time the affected file is re-imported:

- (`v0.9.0`, `d005098bf3a54a27ac79b22fb5eeb88186d235c6`, originally
  flagged at `v0.6.0` (`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`) by
  [`#233`](https://github.com/kurone-kito/dotfiles/issues/233), carried
  forward again by [`#383`](https://github.com/kurone-kito/dotfiles/issues/383),
  confirmed byte-identical against the pinned source at each round)
  `docs/idd-helper-scripts.md`'s "Package-manager / ephemeral-npx
  command" sections (claim-approval-gate, claim-lock, branch-name,
  select-desynced-index, emit-marker, post-idd-marker, and others)
  show only the `ephemeral-npx` `npx` literal invocation under a
  heading that also names the `package-manager` profile, which
  contradicts the `package-manager` profile's own contract elsewhere
  in the same file ("do not fall back to ad hoc `npx` in this mode").
  **Filed upstream** at the `v0.11.0` round (roadmap #419's Track G,
  #425):
  [`kurone-kito/idd-skill#2956`](https://github.com/kurone-kito/idd-skill/issues/2956).
- (`v0.9.0`, `d005098bf3a54a27ac79b22fb5eeb88186d235c6`, originally
  flagged at `v0.6.0` (`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`) by
  [`#233`](https://github.com/kurone-kito/dotfiles/issues/233), carried
  forward again by [`#383`](https://github.com/kurone-kito/dotfiles/issues/383),
  confirmed byte-identical against the pinned source at each round)
  `scripts/minimize-superseded-markers.mjs`'s `runGh` error handler
  (`String(e.stderr?.toString?.() ?? e.message ?? 'unknown error')`)
  treats an empty-but-defined `stderr` string as present because `??`
  only falls through on `null`/`undefined`, so a `gh` timeout with no
  stderr output loses `error.message`'s useful timeout text (see the
  `vendored-file-header` divergence above). **Filed upstream** at the
  `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2957`](https://github.com/kurone-kito/idd-skill/issues/2957).
- (`v0.9.0`, `d005098bf3a54a27ac79b22fb5eeb88186d235c6`, newly flagged
  this round by a Copilot review comment on #383's PR, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `docs/onboarding/template-distribution.md`'s
  ["`.gitattributes` linguist-generated
  convention"](onboarding/template-distribution.md#gitattributes-linguist-generated-convention-vendored-node)
  section tells `vendored-node`-profile adopters to mark their copied
  helper files `linguist-generated=true`, while
  `docs/onboarding/optional-host-setup.md`'s ["mark the vendored helper
  bundle
  `linguist-vendored`"](onboarding/optional-host-setup.md#optional--mark-the-vendored-helper-bundle-linguist-vendored)
  section recommends `linguist-vendored` for the same copied files and
  explicitly frames the two attributes as semantically distinct
  ("generated = first-party build output, vendored = copied third-party
  code"). The two adopter-facing recommendations conflict for the exact
  same file set; not fixed ad hoc here since doing so would mean
  rewriting one of two verbatim-imported upstream files, which is
  outside this track's re-import/verification scope. **Filed
  upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2958`](https://github.com/kurone-kito/idd-skill/issues/2958).
- (`v0.9.0`, `d005098bf3a54a27ac79b22fb5eeb88186d235c6`, newly flagged
  this round by a Copilot review comment on #383's PR, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import)
  [`docs/onboarding/template-distribution.md`'s "Option
  A"](onboarding/template-distribution.md) `gh api` fetch loop queries
  `repos/kurone-kito/idd-skill/contents/idd-template/${FILE}` with no
  `?ref=` query parameter, so it resolves whatever the source
  repository's default branch currently is at fetch time rather than
  the pinned tag/commit the surrounding guidance otherwise insists on
  ("keep imports pinned" applies everywhere else in this same file).
  Not fixed ad hoc here for the same reason as the item above. **Filed
  upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2959`](https://github.com/kurone-kito/idd-skill/issues/2959).
- (`v0.9.0`, `d005098bf3a54a27ac79b22fb5eeb88186d235c6`, newly flagged
  this round by a CodeRabbit review comment on #383's PR, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import)
  [`docs/idd-concept-ownership.md`](idd-concept-ownership.md)'s
  ownership-and-mutation row for `advisory-wait` / `advisory-wait-recovery`
  markers omits `advisory-reroll`, while the lifecycle-transition table
  further down the same file lists `advisory-reroll:` alongside those
  two in its own "Superseded / minimized" row. `advisory-reroll` is a
  real, still-supported marker kind elsewhere in this file set
  (`idd-helper-scripts.md`, `idd-review-fix.instructions.md`), so the
  ownership row's omission is inconsistent with the rest of the same
  document. Not fixed ad hoc here for the same reason as the two items
  above. **Filed upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2960`](https://github.com/kurone-kito/idd-skill/issues/2960).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by the
  `coderabbit-critique` C1 delegate on #422's re-import cycle, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `docs/policy-constants.md`'s "Near-ceiling
  exception" paragraph describes the **always-resident review/merge
  instruction floor** as `bundle-core`, `bundle-review-triage-phase`,
  `bundle-review-fix-phase`, and `bundle-merge-phase` members that
  "load on every F-phase session". Per the bundle-budget table earlier
  in the same file, `bundle-core` loads alongside every phase bundle
  (not only F-phase), `bundle-review-triage-phase` and
  `bundle-review-fix-phase` are the E-phase review bundles (E1-E8 and
  E9-E15 respectively), and only `bundle-merge-phase` is F-phase-only
  (F1-F5) — apparently a stale carry-over from the pre-split
  `bundle-review`/`bundle-merge` wording this same paragraph used at
  `v0.9.0`. Not fixed ad hoc here for the same reason as the items
  above. **Filed upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2961`](https://github.com/kurone-kito/idd-skill/issues/2961).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit PR review comment on #422's re-import cycle, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `scripts/minimize-superseded-markers.mjs`'s
  `printTable` counts line omits the `deadlineSkipped` counter that
  `runMinimize` increments, so a `--format table` run under
  `--deadline-ms` can display fewer accounted-for items than the item
  list without disclosing that the pass hit its wall-clock budget.
  Not fixed ad hoc here for the same reason as the items above. **Filed
  upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2962`](https://github.com/kurone-kito/idd-skill/issues/2962).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit PR review comment on #422's re-import cycle, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `docs/idd-autonomy-contract.md`'s
  Stage 1/2 owner-marker section computes the canonical set snapshot
  digest by sorting `<owner>/<repo>#<number>:<body-sha256>` lines in
  "ascending issue-number order" — for a hypothetical set spanning more
  than one repository, two repositories can both contain the same
  issue number, so an issue-number-only sort key is not deterministic
  across repository boundaries. CodeRabbit's own suggested fix (sort by
  canonical repository identity first, then issue number) belongs in
  the upstream template, not this vendored copy. **Filed upstream** at
  the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2963`](https://github.com/kurone-kito/idd-skill/issues/2963).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit PR review comment on #422's re-import cycle, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `docs/idd-helper-scripts.md`'s signed-commit
  merge-wrapper recovery procedure sends `SIGTERM` to bare recorded PIDs
  with no separate liveness/identity check beyond the sub-second
  snapshot-then-signal gap the same paragraph already reasons about; a
  child reparented before the snapshot, or an exited PID reused by an
  unrelated process outside that gap, is out of scope for this
  vendored copy to redesign. The same recovery procedure separately
  waits up to 30 seconds for **each** recorded PID individually to
  exit, rather than tracking one shared 30-second deadline across the
  whole recorded set — a process tree with several recorded PIDs (the
  git parent plus descendants) can therefore exceed the documented
  overall 30-second termination-wait bound. Not fixed ad hoc here for
  the same reason as the item above. **Filed upstream** (both gaps,
  same recovery procedure) at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2964`](https://github.com/kurone-kito/idd-skill/issues/2964).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit PR review comment on #422's re-import cycle, confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import) `docs/onboarding/issue-mediated-bootstrap.md`'s
  "Authoring-bucket marker" cross-reference links
  `idd-skill/blob/main/skills/issue-authoring/references/contract.md`
  — an unpinned `/main/` URL, contradicting this same file's own
  "keep imports pinned to a released tag or commit" guidance elsewhere
  (the direct-commit bootstrap exception a few lines above does not
  cover this particular link). The same file's `authoring-bucket:
  needs-decision` marker-handling instruction separately uses
  `labels.blockedByHumanLabelName` for both issue publication and label
  creation, even though the surrounding prose is specifically about the
  `needs-decision` marker case and should use
  `labels.needsDecisionLabelName` for those two steps instead. **Filed
  upstream** (both gaps, same file) at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2965`](https://github.com/kurone-kito/idd-skill/issues/2965).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged
  during roadmap #419's Track B re-import cycle (dotfiles#430) while
  reconciling a stale-handoff finding from dotfiles#429; verified
  directly against upstream's own `v0.11.0` source)
  **upstream's own** `idd-template/.github/instructions/idd-ci.instructions.md`
  rerun-mechanics passage still describes `idd-advisory-convergence` as
  firing directly on `pull_request` plus
  `pull_request_review`/`pull_request_review_comment`, even though
  upstream's own `v0.11.0` `idd-advisory-convergence.yml` already moved
  `pull_request_review` off to a separate non-required companion
  workflow (`idd-advisory-convergence-comment.yml`,
  kurone-kito/idd-skill#2657) in the same release -- the instruction
  text was never updated to match its own workflow's `v0.11.0` change.
  **This repository's own copy is not affected**: dotfiles#430 already
  corrected the local
  [`.github/instructions/idd-ci.instructions.md`](../.github/instructions/idd-ci.instructions.md)
  to describe the companion-refresh topology instead, now marked
  `<!-- dotfiles-divergence: ci-companion-topology -->` (added this
  round, #425, closing the gap Codex's review of this same PR
  flagged: the correction differed from the pinned source with no
  registered marker, so a future re-import could have silently
  reverted it to upstream's still-stale text). **Filed upstream** at
  the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2966`](https://github.com/kurone-kito/idd-skill/issues/2966).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged
  during roadmap #419's Track B re-import cycle (dotfiles#430), confirmed
  byte-identical to the pinned source, not introduced by this
  repository's re-import)
  [`.github/instructions/idd-merge.instructions.md`](../.github/instructions/idd-merge.instructions.md)'s
  in-flight `post-merge-cleanup.yml` wait ("Either way, continue to the
  rule below unchanged") does not itself distinguish a wait that
  observed the run reach a terminal state from one whose bounded budget
  expired while the run was still in flight. This repository's own
  `cleanup-evidence-dedup-recheck` divergence substantially mitigates
  the risk locally (a mandatory, freshly-fetched re-check immediately
  before each side's own POST call), but upstream's own generic text
  has no equivalent for adopters without that local addition. **Filed
  upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2967`](https://github.com/kurone-kito/idd-skill/issues/2967).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, a recurring
  pattern surfaced across several independent bot-review findings
  during roadmap #419's Track B re-import cycle (dotfiles#430), each
  verified upstream-verbatim on both the standard and `lite/` sides,
  not introduced by this repository's re-import) at least five
  confirmed instances of a standard `.github/instructions/*.instructions.md`
  passage with no counterpart in its `lite/` variant:
  `idd-review-fix.instructions.md`'s E14 `#2327` stale-request-recovery
  branch (and
  `lite/idd-advisory-wait-lite.instructions.md`'s stale "F2/F3-only"
  scope claim it contradicts); `idd-pr-submit.instructions.md`'s D1-D3
  CI-job dispatch-only staging gate; `idd-work.instructions.md`'s B2.2
  example field-name verification step; `idd-review-fix.instructions.md`'s
  E10 third escalation tier; and, flagged as the highest-priority
  instance given the corruption risk, `idd-work.instructions.md`'s Step
  3 instruction to `cd` into the new worktree before the manual/no-hook
  `install-deps` run, missing from `lite/idd-work-lite.instructions.md`'s
  equivalent step. No full systematic `lite`-vs-standard audit has run
  yet; each instance above surfaced incidentally through unrelated bot
  review. **Filed upstream** (requesting both the five fixes and a full
  systematic audit) at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2968`](https://github.com/kurone-kito/idd-skill/issues/2968).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged
  during roadmap #419's Track B re-import cycle (dotfiles#430, rounds
  11-12), confirmed byte-identical to the pinned source, not introduced
  by this repository's re-import)
  [`.github/instructions/idd-claim.instructions.md`](../.github/instructions/idd-claim.instructions.md)
  has at least two bare `node scripts/...`-only invocations with no
  named `ephemeral-npx`/`package-manager` facade form shown alongside
  them (the activation-nonce `--record-tokens` instruction, and the
  worktree-local lock file's `claim-lock.mjs --acquire` instruction),
  unlike most other helper invocations in the same file set.
  [`.github/instructions/idd-merge.instructions.md`](../.github/instructions/idd-merge.instructions.md)'s
  F3 Gate checklist separately requires helper-only-shaped evidence
  fields (`f3Outcome`, `blockers[]`) even when the explicitly-permitted
  manual fallback path is in use, with no defined manual equivalent for
  either field. **Filed upstream** (both gaps) at the `v0.11.0` round
  (#425):
  [`kurone-kito/idd-skill#2969`](https://github.com/kurone-kito/idd-skill/issues/2969).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit review comment during roadmap #419's Track E companion-skills
  resync (dotfiles#428), confirmed genuine and verbatim upstream content,
  not introduced by this repository's resync)
  `skills/idd-spec-audit/SKILL.md` contradicts itself on whether
  `docs/idd-autonomy-contract.md`
  is authoritative over instruction files: an earlier passage says the
  instruction file wins on disagreement (the contract is a comparison
  baseline only), while a later passage calls the contract "R4's closed
  source of truth" -- the opposite precedence, which could cause an
  auditor to report genuine contract drift as an instruction defect.
  No registered local-divergence marker covers a substantive content
  correction to this vendored companion-skill file, so this was routed
  here rather than fixed ad hoc during the resync. **Filed upstream** at
  the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2970`](https://github.com/kurone-kito/idd-skill/issues/2970).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by a
  CodeRabbit review comment during roadmap #419's Track E companion-skills
  resync (dotfiles#428), confirmed genuine and verbatim upstream content,
  not introduced by this repository's resync)
  `skills/issue-authoring/references/contract.md`'s "Authoring-bucket
  marker" section binding
  rules hardcode the bare literal `status:blocked-by-human` in two
  places, without the "the configured `blocked-by-human` label (default
  `status:blocked-by-human`)" qualifier used consistently elsewhere in
  the same file -- a repository that configured a different label name
  would find these two passages describing the wrong literal string.
  **Filed upstream** at the `v0.11.0` round (#425):
  [`kurone-kito/idd-skill#2971`](https://github.com/kurone-kito/idd-skill/issues/2971).
- (`v0.11.0`, `1f90787ebf4021673ce6e5eb69741df331fd2037`, flagged by
  CodeRabbit review comments during roadmap #419's Track E
  companion-skills resync (dotfiles#428), confirmed genuine and verbatim
  upstream content -- the review-fix-loop-cutoff auto-release exception
  itself already shipped via kurone-kito/idd-skill#2864/#2877/#2891, all
  closed; this is about two gaps remaining in the shipped feature, not a
  request to revert it -- not introduced by this repository's resync)
  `skills/issue-authoring/references/workflow-boundary.md`'s Stage 2
  release procedure never gates the exception's own "single target, no
  anchor, no sibling" condition inline before the first label removal
  -- that condition is stated only in `contract.md`'s definition and in
  this file's disconnected "Handoff to execution" summary, so a
  multi-target set could remove the marked target's label while sibling
  targets remain held. `contract.md`'s own provenance check (`#2877`)
  separately verifies only that the target's body is unchanged since
  Stage 1 acquire, never that the defer-source marker was actually
  emitted by the real `idd-review-triage.instructions.md` round-count
  cutoff rather than ordinary Stage 1 draft content. No registered
  local-divergence marker covers a substantive redesign of vendored
  protocol logic mid-resync, so both gaps were routed here rather than
  fixed ad hoc. **Filed upstream** (both gaps) at the `v0.11.0` round
  (#425):
  [`kurone-kito/idd-skill#2972`](https://github.com/kurone-kito/idd-skill/issues/2972).

**Filed this round (v0.11.0, 2026-09-13)**: all 17 items above --
the 5 originally-authored deferred items plus 5 more confirmed during
roadmap #419's Track C re-import cycle (dotfiles#431) and 7 more
surfaced across Tracks B and E's own review-fix cycles (dotfiles#430,
dotfiles#428) -- are now filed as individual issues at
`kurone-kito/idd-skill` (`kurone-kito/idd-skill#2956`-`#2972`),
replacing the "carried forward again" framing this section previously
used. Each filed issue cites its confirmed-present-at-`v0.11.0`
evidence directly; this section keeps the local historical record
(origin, prior rounds, confirmation basis) alongside each citation.

**Resolved this round**: the `docs/idd-concept-ownership.md` vs.
`.github/instructions/idd-overview-appendix.instructions.md`
disagreement over who removes the `needs-decision` label (`v0.7.0`,
flagged by #294, dispositioned by #298) is fixed upstream as of
`v0.9.0` -- confirmed the concept-ownership matrix's "Branch" and
`status:needs-decision` rows now read "a later worker session removes
`status:needs-decision` once a qualifying human decision resolves the
hold (`idd-overview-appendix.instructions.md`'s Needs-decision claim
release paragraph)", matching the appendix exactly. Removed from this
list by #383; no `dotfiles-divergence` marker was ever needed since
neither file required a local edit.
