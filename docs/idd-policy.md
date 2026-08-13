# IDD Policy Configuration

This repository uses the Issue-Driven Development (IDD) workflow
imported from
[`kurone-kito/idd-skill`](https://github.com/kurone-kito/idd-skill).
This page records the policy decisions confirmed during the
onboarding flow (roadmap #95), the 0.4.0 re-import (roadmap #144), and
the 0.5.0/0.6.0 re-import (roadmap #239). The machine-readable mirror
lives at
[`.github/idd/config.json`](../.github/idd/config.json); keep both in
sync when the policy changes.

The schema name for each field below comes from the upstream
[`idd-template/docs/onboarding/policy-decisions.md`](https://github.com/kurone-kito/idd-skill/blob/0a9c90dc277e05e0d7d96f1b09d79ff668860cc6/idd-template/docs/onboarding/policy-decisions.md)
so future IDD sessions can navigate between the human-readable record
and the upstream template without surprises.

**Pinned upstream commit**: `0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`
(abbreviated `0a9c90d`; tag `v0.6.0`), audited by roadmap #239's
0.5.0/0.6.0 policy-schema track (#234), which supersedes the 0.4.0-round
pin imported by roadmap #144. `iddVersion` in
[`.github/idd/config.json`](../.github/idd/config.json) is `0.6.0`,
bumped by roadmap #239's own final-verification track (#238), which
also re-validated `.github/idd/config.json` against the pinned
`v0.6.0` `policy.schema.json` (`npx ajv-cli validate --spec=draft2020`:
valid).

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
npx --yes --package https://codeload.github.com/kurone-kito/idd-skill/tar.gz/0a9c90dc277e05e0d7d96f1b09d79ff668860cc6 \
  idd-helper-bundle-manifest --profile ephemeral-npx
```

The tarball URL is normally pinned to the same upstream commit used as
the import baseline for `.github/instructions/` and `.claude/skills/`,
so the helper surface never drifts ahead of the checked-in templates —
bump that commit deliberately whenever the IDD instructions are
re-imported, and do **not** point the spec at a mutable
`refs/heads/main` ref. Roadmap #239's schema-audit track (#234) bumped
this pin to `v0.6.0` (`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`,
confirmed working via `idd-doctor` and `idd-helper-bundle-manifest`
against this repository) ahead of the instructions/skills re-import
landing, opening a **transitional skew window** where audited helper
commands resolved against the `v0.6.0` schema while
`.github/instructions/` and `.claude/skills/` themselves stayed on the
prior 0.4.0-round import. That window closed once roadmap #239's
sibling tracks re-imported both surfaces to the same `v0.6.0` baseline
— #232 for `.github/instructions/`, #235 for the
`.claude/skills/issue-authoring/` companion bundle (#233 covers the
remaining docs/profiles/githooks/scripts file set, not
`.claude/skills/`) — so the pin, the instructions, and the skills
bundle all track `v0.6.0` uniformly as of #238's final verification
sweep.
The companion prerequisite #96 pins Node.js 24.15.0 via
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
`["copilot-pull-request-reviewer[bot]", "coderabbitai[bot]"]`.

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
`.github/idd/config.json` entry (roadmap #144). **One post-#146
exception**: `ciGate.trustEmptyProtectionReads` was confirmed at its
`false` default here but has since been flipped to an explicit `true`
— see the note immediately after this list, not the bullets below.

- **`advisoryWait.convergenceScope`**: `all-prs`
- **`advisoryWait.sameHeadRerollCap`**: `2`
- **`advisoryWait.recoveryCycleCap`**: `2`
- **`advisoryWait.terminalWindow`**: `PT12H`
- **`mergeGate.soloCodeownerAdminFallback`**: `auto-admin-retry` — this
  repository is solo-maintainer (`trustedMarkerActors: ["kurone-kito"]`
  only) with `mergePolicy: fully_autonomous_merge`, exactly the
  topology this key governs, and the distributed default (F3 retries
  once with `gh pr merge --admin` when the sole blocker is the
  solo-CODEOWNER self-approval deadlock) matches this repository's
  existing autonomous-merge intent. Recorded here as a deliberate
  confirmation, not an oversight.

**Post-#146 exception: `ciGate.trustEmptyProtectionReads`.** Confirmed
at its `false` default in #146, but now set to `true` in
`.github/idd/config.json` — see
[Required status checks on `master`](#required-status-checks-on-master)
for why the fail-closed default became unworkable once
`idd-ci.instructions.md` started treating an untrusted `404` on the
classic branch-protection read the same as a `403`.

## New 0.5.0/0.6.0 Schema Keys Left at Default

Audited by roadmap #239's policy-schema track (#234): a structural diff
of `schemas/policy.schema.json` between the prior 0.4.0-round pin
(imported by roadmap #144, 1242 commits past the `v0.4.0` tag but still
376 commits behind the `v0.5.0` tag) and `v0.6.0`
(`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6`) found only three genuinely
new properties; everything else the issue's starting inventory listed
already existed structurally at the pin (only their JSON Schema
`description` text was added later) and is confirmed unchanged at
`v0.6.0`. Per the roadmap's confirmed operator decision,
every key below stayed at its distributed default as of #234 itself —
`.github/idd/config.json` was unchanged by that issue. **One exception
landed immediately afterward**: `ciGate.trustSourcePinnedRequiredChecks`
was flipped to `true` in a same-day follow-up once the `master` ruleset
gained a source-pinned entry (see
[Required status checks on `master`](#required-status-checks-on-master)
for the incident and its own entry below for the rationale) — every
other key in this section remains at its distributed default.
`.github/idd/config.json` was re-validated against the fetched
`v0.6.0` schema with `ajv-cli validate --spec=draft2020` (passed) and
with `idd-doctor` run from the pinned `v0.6.0` tarball itself
(`result: passed`,
`PASS .github/idd/config.json validates against policy.schema.json`,
the same four pre-existing warnings as before) — no correctness break
found as part of #234's own audit.

### Genuinely new in 0.5.0/0.6.0

- **`advisoryWait.exemptBotAuthoredPrs`**: `false` (0.6.0). Opt-in
  claimless-waiver exemption letting a bot-authored PR with no claim
  history pass advisory-convergence as `not_applicable` without a
  per-PR maintainer waiver. Left at default: this repository's
  dependency-update PRs (Dependabot) are handled by existing merge
  automation, and enabling a bot-authorship exemption is a deliberate
  future decision, not something to adopt silently alongside a docs
  audit.
- **`ciGate.trustSourcePinnedRequiredChecks`**: `true` (0.5.0 key;
  changed from the `false` default during this round — see
  [Required status checks on `master`](#required-status-checks-on-master)
  for the incident that made this reachable). Opt-in trust for a
  required check whose ruleset/branch-protection entry is source-pinned
  to a specific GitHub App/integration (`app_id`/`integration_id`).
  After the `master` ruleset's `required_status_checks` rule was
  restored following an accidental removal (see below), every entry
  came back pinned to `integration_id: 15368`. The operator verified
  out-of-band via `gh api app/15368` and live check-run `app.id` fields
  on a merged PR that `15368` is GitHub's own `github-actions` App —
  the sole producer of every workflow-based check this repository
  requires — so this key was flipped to `true` per the schema's
  documented human-authorized-decision path, rather than left at the
  fail-closed default.
- **`helperRuntime.packageSpec`**: unset (0.5.0). Optional pinned npm
  spec/tarball/commit archive overriding the mutable main-archive
  fallback for `package-manager`/`ephemeral-npx` helper invocations.
  This repository already pins every helper invocation explicitly per
  command (see [Helper Runtime Profile](#helper-runtime-profile)) via
  the `npx --package <tarball-url>` form, so this key would be
  redundant with the existing per-invocation pinning convention.

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
- **`CI_RUNNER_LABEL`**: a repository Actions *variable* consumed by
  `idd-advisory-convergence.yml`, not a `.github/idd/config.json` /
  `policy.schema.json` key. No entry needed in this schema-focused
  section; its actual adoption is deferred to #237 (the
  workflow-reconciliation track), which owns workflow YAML and
  repository settings.

## Divergence Register

Every intentional deviation from the pinned upstream template carries
a `dotfiles-divergence: <slug>` marker at its point of use -- an HTML
comment (`<!-- ... -->`) in Markdown/YAML/instruction files, a line
comment (`// ...`) in JavaScript -- so a future re-import can detect
and preserve it instead of silently reverting to upstream's default.
Current slugs:

| Slug                                 | What it marks                                                                                                                                                                                                                                                                                                                                                                                                           | Introduced by                |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| `claim-timing`                       | The `12h`/`6h` claim-stale-age/heartbeat-interval override, in place of the `24h`/`12h` distributed defaults                                                                                                                                                                                                                                                                                                            | #145, #196, #232, #233       |
| `helper-profile-ephemeral-npx`       | This repository's `ephemeral-npx` helper profile, where docs describe a different upstream-default profile inline                                                                                                                                                                                                                                                                                                       | #196, #233                   |
| `installed-bundle-reference-routing` | The issue-authoring companion's reference routing, adapted for an installed-bundle (not source-repo) stance                                                                                                                                                                                                                                                                                                             | #147, #235                   |
| `master-branch`                      | `master` in place of upstream's `main` as the integration branch name                                                                                                                                                                                                                                                                                                                                                   | #145, #196, #232, #233, #237 |
| `onboarding-doc-trim`                | The deliberate exclusion of `docs/onboarding/placeholders.md` and `docs/onboarding/policy-decisions.md` (self-corrupt after placeholder substitution), linking to the pinned upstream copies instead. `docs/index.md` (a new upstream `v0.6.0` generated page) is also excluded, for the same reason: its generated table links both trimmed onboarding pages, so adopting it verbatim would ship broken relative links | #145, #196, #233             |
| `signing-ladder`                     | The GPG -> SSH -> unsigned commit-signing fallback ladder, a dotfiles-specific addition with no upstream equivalent                                                                                                                                                                                                                                                                                                     | #145, #232                   |
| `vendored-file-header`               | The corrected header on `scripts/minimize-superseded-markers.mjs`, since this repository has no build step to regenerate it from a TypeScript source                                                                                                                                                                                                                                                                    | #196, #233                   |
| `worktree-guard-wiring-note`         | Documents that this repository ships every Worktree Guard enforcing component together (opt-in config surface, `.githooks/` hook set, `idd-doctor`'s enabled-but-inert check) instead of upstream's generic "config surface only" framing, since `core.hooksPath` wiring is still a required per-clone step                                                                                                             | #233                         |

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

### `idd-doctor` findings

A full `idd-doctor` run (pinned `ephemeral-npx` spec) now exits
`result: passed` with four `WARN`s and no `ERROR`; each below is
expected, not a defect. #218 resolved the one finding that was a
genuine `ERROR` (the `idd-task.yml` placeholder syntax) by
reformatting it; the remaining findings are accepted noise, recorded
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
- **`worktreeGuard.enabled` is true but `core.hooksPath` is unset in
  this environment**: expected on any fresh clone that has not yet run
  the wiring step documented in [Worktree Guard](#worktree-guard) --
  `core.hooksPath` is local, per-clone config that #148 could not ship
  in a commit. Not a repository defect; wire it per-clone as needed.
- **Branch protection not readable for `kurone-kito/dotfiles:master`**:
  expected. This repository's merge gate comes from a ruleset, not
  classic branch protection, so the classic-protection read returns
  empty/`404`. **`ciGate.trustEmptyProtectionReads`** is now `true`
  (changed from the `false` default confirmed in #146 — see
  [Required status checks on `master`](#required-status-checks-on-master)
  for why), so this read is trusted as genuinely empty rather than
  failing closed.
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
file set (it is not one of the excluded prefixes in
`checkPlaceholders`); the scanner still missed this instance because
its regex (`findPlaceholders` in `scripts/idd-doctor.mjs`) only
matches a single `[A-Za-z0-9_-]+` token between `{{` and `}}` -- the
same pattern #218's four single-word hints (`{{path}}`, `{{outcome}}`,
etc.) matched. This field's multi-word hints (`{{file or feature}}`,
etc.) contain spaces, so the regex never matched them at all,
independent of which directory the file lives in. A plain
repository-wide `{{` grep is still necessary to catch this class
going forward.

`checkReleaseTagDrift` and `checkDependencyVersionDrift` stay silent
in this repository, as expected (no git tags exist here, and there is
no `pnpm-lock.yaml`).

### `idd-onboard --verify` findings

A full `idd-onboard --verify` run (pinned `v0.6.0` source tree,
`--profile ephemeral-npx`) exits `blocking: true` with two finding
classes; both are expected, not defects, recorded here so a future
verification sweep does not have to rediscover them:

- **`manifestCompleteness.missingTarget`**: `docs/index.md`,
  `docs/onboarding/placeholders.md`, and
  `docs/onboarding/policy-decisions.md`. All three are deliberate
  exclusions already recorded in the
  [Divergence Register](#divergence-register)'s `onboarding-doc-trim`
  entry (the two `onboarding/` pages are self-corrupting once
  substituted and stay linked to the pinned upstream copies instead;
  `docs/index.md` was evaluated and skipped by #233 for the same
  reason -- see that entry).
- **`placeholderResidue`**: six known-placeholder tokens, seven raw
  `{{...}}` occurrences, in `docs/customization.md` -- five inside the
  [placeholder mapping table](customization.md) that documents the
  onboarding substitution mechanism itself (for example, the table
  literally shows `{{REPO_NAME}}` as the template-side name for the
  live `dotfiles` value), plus one more `{{REPO_NAME}}` mention outside
  the table, in a synchronization-example sentence ("Template copies
  use placeholders like `{{REPO_NAME}}` to support ..."). Both forms
  are the same documentation-as-example usage, just in prose instead
  of a table cell. `idd-onboard --verify`'s residue scanner matches
  the seven known placeholder names as plain text anywhere in the
  file and cannot distinguish either usage from genuine unresolved
  residue -- the same false-positive shape as the `markdownlint-cli2`
  toolchain-residue warnings above.
  `idd-doctor`'s own, separately-scoped placeholder check (`no
  unresolved {{...}} placeholders in IDD-managed files`) passes
  clean, and a manual repository-wide grep for the `.github/`,
  `.claude/`, `docs/`, `scripts/`, and `profiles/` surface found no
  other unexplained `{{...}}` residue as of this round (see
  `.github/ISSUE_TEMPLATE/idd-task.yml`'s fix above for the one
  genuine instance found and fixed).

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

The [`#233`](https://github.com/kurone-kito/dotfiles/issues/233)
v0.6.0 re-sync carried these two items verbatim from upstream
(confirmed byte-identical against the pinned
`0a9c90dc277e05e0d7d96f1b09d79ff668860cc6` source); both are review
findings this repository chose not to fix ad hoc, since that issue's
scope is placeholder substitution plus the registered divergence
hunks, not an editorial rewrite of upstream's own prose or vendored
code:

- `docs/idd-helper-scripts.md`'s "Package-manager / ephemeral-npx
  command" sections (claim-approval-gate, claim-lock, branch-name,
  select-desynced-index, emit-marker, post-idd-marker, and others)
  show only the `ephemeral-npx` `npx` literal invocation under a
  heading that also names the `package-manager` profile, which
  contradicts the `package-manager` profile's own contract elsewhere
  in the same file ("do not fall back to ad hoc `npx` in this mode").
  File this ambiguity upstream against `kurone-kito/idd-skill`, or
  resolve it locally the next time this file is re-imported.
- `scripts/minimize-superseded-markers.mjs`'s `runGh` error handler
  (`String(e.stderr?.toString?.() ?? e.message ?? 'unknown error')`)
  treats an empty-but-defined `stderr` string as present because `??`
  only falls through on `null`/`undefined`, so a `gh` timeout with no
  stderr output loses `error.message`'s useful timeout text. File this
  upstream, or fix it locally the next time this vendored file is
  re-imported (see the `vendored-file-header` divergence above).
