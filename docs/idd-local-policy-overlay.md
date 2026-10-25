---
type: reference
title: Repository-specific IDD policy overlay
description: Records local IDD behavior and its disposition against the installed upstream instruction set.
tags: [idd, policy, customization]
---

# Repository-specific IDD policy overlay

This document keeps dotfiles-specific IDD behavior visible
independently of the copied instruction tree. Active entry files follow
the `idd-activation` result and its `instructionsRoot` first. This
overlay records repository policy and comparison results. A row marked
upstream-equivalent relies on v0.17.0; a retained row remains a dotfiles
rule until a separate reviewed change retires it.

## Pinned comparison and inventory

The local comparison pins upstream v0.14.0 at
`ae16f497434a5023dfaa28f965fc2af92ebf055d` and v0.17.0 at
`77befdd4030757464bed7f31c7dfe6d0a404a18b`. For each tracked local
instruction or skill file, the source path and materialization mode
come from that tag's `audit/sync-manifest.json`. Concreted replacements
were applied before comparing content.

The inventory contains **35 tracked files**. The issue-authoring report
template matches both materialized sources. The merge-handoff file
matches v0.14.0; its v0.17.0 differences are recorded below. All other
local changes are assigned to the divergence rows, including unmarked
subordinate paragraphs in the same sections. The file-to-source map
follows:

| Local file | v0.14.0 source | v0.17.0 source | Local behavior disposition |
| --- | --- | --- | --- |
| .claude/skills/idd-spec-audit/SKILL.md | skills/idd-spec-audit/SKILL.md (exact) | skills/idd-spec-audit/SKILL.md (exact) | See **installed-bundle-reference-routing** |
| .claude/skills/idd-spec-audit/references/report-template.md | skills/idd-spec-audit/references/report-template.md (exact) | skills/idd-spec-audit/references/report-template.md (exact) | Materialized content matches both pinned sources. |
| .claude/skills/issue-authoring/SKILL.md | skills/issue-authoring/SKILL.md (exact) | skills/issue-authoring/SKILL.md (exact) | See **explicit-human-release**, **helper-profile-ephemeral-npx**, **installed-bundle-reference-routing** |
| .claude/skills/issue-authoring/references/contract.md | skills/issue-authoring/references/contract.md (exact) | skills/issue-authoring/references/contract.md (exact) | See **explicit-human-release**, **helper-profile-ephemeral-npx**, **installed-bundle-reference-routing**, **session-offset-direct-index**, **subagent-process-cleanup** |
| .claude/skills/issue-authoring/references/draft-patterns.md | skills/issue-authoring/references/draft-patterns.md (exact) | skills/issue-authoring/references/draft-patterns.md (exact) | See **helper-profile-ephemeral-npx** |
| .claude/skills/issue-authoring/references/workflow-boundary.md | skills/issue-authoring/references/workflow-boundary.md (exact) | skills/issue-authoring/references/workflow-boundary.md (exact) | See **explicit-human-release**, **helper-profile-ephemeral-npx** |
| .github/instructions/idd-advisory-wait.instructions.md | idd-template/.github/instructions/idd-advisory-wait.instructions.md (exact) | idd-template/.github/instructions/idd-advisory-wait.instructions.md (exact) | See **advisory-response-schema** |
| .github/instructions/idd-ci.instructions.md | idd-template/.github/instructions/idd-ci.instructions.md (exact) | idd-template/.github/instructions/idd-ci.instructions.md (exact) | See **local-pr-target-ci-provenance**, **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-claim.instructions.md | idd-template/.github/instructions/idd-claim.instructions.md (exact) | idd-template/.github/instructions/idd-claim.instructions.md (exact) | See **helper-profile-ephemeral-npx**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-discover.instructions.md | idd-template/.github/instructions/idd-discover.instructions.md (concreted) | idd-template/.github/instructions/idd-discover.instructions.md (concreted) | See **cross-roadmap-discovery**, **explicit-target-parked-check**, **helper-profile-ephemeral-npx**, **needs-triage-label**, **reviewed-v014-safety-corrections**, **session-offset-direct-index** |
| .github/instructions/idd-merge-handoff.instructions.md | idd-template/.github/instructions/idd-merge-handoff.instructions.md (exact) | idd-template/.github/instructions/idd-merge-handoff.instructions.md (differs; see the [unmarked merge-handoff delta](#unmarked-merge-handoff-delta)) | See the [unmarked merge-handoff delta](#unmarked-merge-handoff-delta). |
| .github/instructions/idd-merge.instructions.md | idd-template/.github/instructions/idd-merge.instructions.md (exact) | idd-template/.github/instructions/idd-merge.instructions.md (exact) | See **post-switch-ancestry-reset-guard**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-overview-appendix.instructions.md | idd-template/.github/instructions/idd-overview-appendix.instructions.md (concreted) | idd-template/.github/instructions/idd-overview-appendix.instructions.md (concreted) | See **master-branch**, **signing-ladder** |
| .github/instructions/idd-overview-core.instructions.md | idd-template/.github/instructions/idd-overview-core.instructions.md (concreted) | idd-template/.github/instructions/idd-overview-core.instructions.md (concreted) | See **master-branch**, **queued-validation-commands** |
| .github/instructions/idd-pr-submit.instructions.md | idd-template/.github/instructions/idd-pr-submit.instructions.md (exact) | idd-template/.github/instructions/idd-pr-submit.instructions.md (exact) | See **explicit-human-release**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-pre-merge.instructions.md | idd-template/.github/instructions/idd-pre-merge.instructions.md (exact) | idd-template/.github/instructions/idd-pre-merge.instructions.md (exact) | See **post-switch-ancestry-reset-guard** |
| .github/instructions/idd-resume-stall.instructions.md | idd-template/.github/instructions/idd-resume-stall.instructions.md (exact) | idd-template/.github/instructions/idd-resume-stall.instructions.md (exact) | See **helper-profile-ephemeral-npx** |
| .github/instructions/idd-resume.instructions.md | idd-template/.github/instructions/idd-resume.instructions.md (exact) | idd-template/.github/instructions/idd-resume.instructions.md (exact) | See **helper-profile-ephemeral-npx**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-review-fix.instructions.md | idd-template/.github/instructions/idd-review-fix.instructions.md (exact) | idd-template/.github/instructions/idd-review-fix.instructions.md (exact) | See **reviewed-v014-safety-corrections** |
| .github/instructions/idd-review-snapshot.instructions.md | idd-template/.github/instructions/idd-review-snapshot.instructions.md (exact) | idd-template/.github/instructions/idd-review-snapshot.instructions.md (exact) | See **e1-stale-recovery-cap-route**, **helper-profile-ephemeral-npx**, **local-pr-target-ci-provenance**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-review-triage.instructions.md | idd-template/.github/instructions/idd-review-triage.instructions.md (concreted) | idd-template/.github/instructions/idd-review-triage.instructions.md (concreted) | See **explicit-human-release**, **review-triage-usercontent-reconstruction** |
| .github/instructions/idd-roadmap-audit.instructions.md | idd-template/.github/instructions/idd-roadmap-audit.instructions.md (concreted) | idd-template/.github/instructions/idd-roadmap-audit.instructions.md (concreted) | See **helper-profile-ephemeral-npx**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-suitability.instructions.md | idd-template/.github/instructions/idd-suitability.instructions.md (concreted) | idd-template/.github/instructions/idd-suitability.instructions.md (concreted) | See **blocked-by-human-staleness**, **reviewed-v014-safety-corrections** |
| .github/instructions/idd-work.instructions.md | idd-template/.github/instructions/idd-work.instructions.md (concreted) | idd-template/.github/instructions/idd-work.instructions.md (concreted) | See **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-advisory-wait-lite.instructions.md | idd-template/.github/instructions/lite/idd-advisory-wait-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-advisory-wait-lite.instructions.md (exact) | See **advisory-response-schema**, **e1-stale-recovery-cap-route**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-ci-lite.instructions.md | idd-template/.github/instructions/lite/idd-ci-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-ci-lite.instructions.md (exact) | See **local-pr-target-ci-provenance**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-claim-lite.instructions.md | idd-template/.github/instructions/lite/idd-claim-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-claim-lite.instructions.md (exact) | See **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-merge-handoff-lite.instructions.md | idd-template/.github/instructions/lite/idd-merge-handoff-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-merge-handoff-lite.instructions.md (exact) | See **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-pr-submit-lite.instructions.md | idd-template/.github/instructions/lite/idd-pr-submit-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-pr-submit-lite.instructions.md (exact) | See **explicit-human-release**, **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-pre-merge-lite.instructions.md | idd-template/.github/instructions/lite/idd-pre-merge-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-pre-merge-lite.instructions.md (exact) | See **helper-profile-ephemeral-npx**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-resume-lite.instructions.md | idd-template/.github/instructions/lite/idd-resume-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-resume-lite.instructions.md (exact) | See **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-resume-stall-lite.instructions.md | idd-template/.github/instructions/lite/idd-resume-stall-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-resume-stall-lite.instructions.md (exact) | See **helper-profile-ephemeral-npx**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-review-fix-lite.instructions.md | idd-template/.github/instructions/lite/idd-review-fix-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-review-fix-lite.instructions.md (exact) | See **master-branch**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-review-snapshot-lite.instructions.md | idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md (exact) | See **e1-stale-recovery-cap-route**, **lite-e1-advisory-outcome-deferral**, **local-pr-target-ci-provenance**, **reviewed-v014-safety-corrections** |
| .github/instructions/lite/idd-work-lite.instructions.md | idd-template/.github/instructions/lite/idd-work-lite.instructions.md (exact) | idd-template/.github/instructions/lite/idd-work-lite.instructions.md (exact) | See **master-branch** |

The v0.17.0 tree adds `claim-orchestrator.instructions.md` and
`idd-orchestrator.instructions.md`, neither of which is in this local
inventory. #679 does not import them. After activation routes to the
installed v0.17.0 payload, its inventory supplies those files.

## Unmarked merge-handoff delta

The local merge-handoff file is byte-identical to v0.14.0. It differs
from v0.17.0 at the pinned source path
`idd-template/.github/instructions/idd-merge-handoff.instructions.md`:

- **Retain the local F2.5 claim gate.** Before a mutation in F2.5, the
  active claim must use this session's claim ID. With no active claim,
  continue only through the configured `separate_merge_agent` actor
  path or `fully_autonomous_merge` policy path; stop on every other
  path. Keep this gate as a repository safety rule.
- **Apply the v0.17.0 decision-rule-touch note while the local file is
  active.** A touched waiver decision-rule file
  (`waiver.decisionRuleFilesTouched: true`) is not itself a stop. A
  ready F2 verdict clears only the advisory gate and leaves merge-policy
  routing to decide; an unready verdict holds. When activation routes to
  the v0.17.0 payload, its own F2.5 file supplies this behavior.
- **Treat the wording changes as editorial.** The local v0.14.0 wording
  uses `also carry` and `just established` where v0.17.0 uses `carry`
  and `established`. They do not change the rule's behavior and need no
  separate policy to retain.

## Divergence disposition crosswalk

The register contains 25 distinct slugs. The [detailed Divergence
Register](idd-policy.md#divergence-register) retains each description,
marker site, and introduction history. This crosswalk identifies whether
v0.17.0 supplies the behavior or dotfiles retains it.

| Slug | v0.17.0 comparison | Retirement disposition |
| --- | --- | --- |
| advisory-response-schema | Full and lite advisory-wait instructions list all 24 required schema fields: [full](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-advisory-wait.instructions.md) and [lite](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-advisory-wait-lite.instructions.md). | The runtime rule is upstream-equivalent. Keep the local fixture and Bats regression check as repository test coverage. |
| helper-profile-ephemeral-npx | v0.17.0 supports the profile family, but cannot supply this repository's chosen package spec, pin, and command resolution. | Retain the configured ephemeral-npx profile in [IDD config](../.github/idd/config.json) and its [helper command guide](idd-helper-scripts.md). |
| installed-bundle-reference-routing | The upstream companion's source-repository links do not describe this repository's installed-bundle layout. | Retain guidance that resolves references from the installed .claude/skills/ bundle and target repository documentation. |
| local-docs-index | No upstream counterpart for dotfiles-authored documentation pages. | Retain the local-page supplement in docs/index.md; it is repository navigation, not imported instruction content. |
| local-pr-target-ci-provenance | No equivalent gate was found in the v0.17.0 instruction files for event type, actor type, exact PR association, and reviewed-head SHA. | Retain the exact provenance checks in the local CI/review rules and workflow. |
| cross-roadmap-discovery | v0.17.0 implements --all-roadmaps, legacy roots, and union-of-leaves traversal in [Discover](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-discover.instructions.md). | Upstream-equivalent; no overlay behavior needs to be copied. |
| lite-e1-advisory-outcome-deferral | v0.17.0 routes incomplete E1 through E14/E15 and returns through E1 in [lite review snapshot](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md), with the outcome table in [lite advisory wait](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-advisory-wait-lite.instructions.md). | Upstream-equivalent. |
| reviewed-v014-safety-corrections | This is a compound set: v0.17.0 supplies many corrections, but not every stricter dotfiles gate. See the clause-by-clause table below. | Retain only the residual local safeguards listed below; rely on cited v0.17.0 clauses for adopted behavior. |
| explicit-target-parked-check | v0.17.0 A0-T checks target labels and readiness but does not apply --parked-issues membership to a direct non-roadmap target. | Retain the fail-closed direct-target parked check; do not widen the candidate set on a failed or incomplete read. |
| e1-stale-recovery-cap-route | v0.17.0 full and lite E1 preconditions both honor capExhaustedRoute: [full](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-review-snapshot.instructions.md) and [lite](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md). | Upstream-equivalent. |
| explicit-human-release | v0.17.0 retains a narrow review-fix-loop-cutoff auto-release exception and hardens hidden-marker enumeration in the authoring helper. | Retain dotfiles' stricter rule: every held set still requires an explicit human release request. The helper improvement does not itself change this repository policy. |
| master-branch | Upstream uses a configurable development/default-branch placeholder. | Retain master as this repository's configured integration branch; do not replace it with the upstream default. |
| needs-triage-label | No v0.17.0 equivalent for this repository's status:needs-triage Discover exclusion. | Retain the A3 intake-label filter so human reports that have not been rewritten are not claimed as ready work. |
| onboarding-doc-trim | The two placeholder/policy pages remain upstream documentation; the local copies are intentionally excluded because substitution corrupts them. | Retain the exclusion and link to the pinned upstream pages; do not restore self-corrupt local copies during import retirement. |
| signing-ladder | No v0.17.0 equivalent for dotfiles' configured GPG → SSH → unsigned commit fallback policy. | Retain the signing ladder in the root and Copilot guidance, including project-blessed SSH aliases and bounded attempts. |
| vendored-file-header | The upstream script body is equivalent, but the source header describes an absent local build step. | Retain the repository-correct header on scripts/minimize-superseded-markers.mjs; it is outside the imported instruction tree. |
| worktree-guard-wiring-note | v0.17.0's [customization guide](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/docs/customization.md) and [optional host setup](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/docs/onboarding/optional-host-setup.md) describe both shipped hooks and the core.hooksPath step. | Upstream-equivalent; no separate overlay rule is needed. |
| review-triage-usercontent-reconstruction | v0.17.0 requires complete userContentEdits pagination and treats each diff as the full post-edit body in [review triage](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-review-triage.instructions.md). | Upstream-equivalent. |
| blocked-by-human-staleness | No equivalent to this repository's label-strip automation workaround. | Retain the requirement for a maintainer approval actor's explicit blocker-resolution comment; label removal or an unrelated comment does not reset staleness. |
| post-switch-ancestry-reset-guard | v0.17.0's F2 route uses guarded fast-forward and explicitly forbids reset in [pre-merge](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-pre-merge.instructions.md). | Superseded by the safer upstream no-reset route; the local reset-specific guard need not be carried forward. |
| subagent-process-cleanup | v0.17.0 asks a subagent to end its own background processes but does not specify a safe identity mechanism. | Retain the stronger shared-host rule below: terminate only processes started by that agent via recorded PID/process group; never by name or command pattern. |
| session-offset-direct-index | v0.17.0 specifies direct index selection for multi-entry tie bands in [Discover](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-discover.instructions.md). | Upstream-equivalent. |
| instruction-size-limits-not-enforced | Upstream documents instruction size budgets; dotfiles intentionally does not enforce the per-file/bundle limits. | Retain the repository's recorded non-enforcement decision in [policy constants](policy-constants.md); do not imply upstream enforces the local choice. |
| advisory-trigger-pull-request-target-only | The v0.17.0 template does not impose dotfiles' workflow-trigger restriction. | Retain pull_request_target-only advisory polling and its provenance requirements in policy constants and the local workflow. |
| queued-validation-commands | Upstream has no dotfiles Pueue queue wrapper. | Retain the queue wrappers in [IDD config](../.github/idd/config.json) and [Pueue validation guide](pueue-validation-queue.md); full validation remains queued. |

### Clause-level disposition for v0.14 safety corrections

| Local correction | v0.17.0 disposition |
| --- | --- |
| Reject lock takeover after the claim has been released. | Upstream-equivalent: [claim verification](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-claim.instructions.md) rejects a released-claim route. |
| Avoid duplicate claim markers on continuation and forced-handoff activation. | Upstream-equivalent: [claim execution](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-claim.instructions.md) distinguishes continuation from fresh activation. |
| Check authoring holds before and after the first forced-handoff activation. | Upstream-equivalent: [handoff claim verification](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-claim.instructions.md) checks the current hold around nonce verification. |
| Require a verified same-session claim before posting a hold comment on a closed issue. | **Retain**. The v0.17.0 closed-issue route says to post a hold but does not bind that write to this session's verified claim. |
| Stop Discover before selection when parked-issue enumeration is incomplete. | **Retain**. v0.17.0 allows unlisted candidates through when parkedIssuesComplete: false; dotfiles fails closed before ranking. |
| Hold issue-only closure and unknown worktree states. | Upstream-equivalent for the hold/stop route: [Resume](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-resume.instructions.md) stops on issue-only closure and occupied, unreadable, or unknown worktrees. The same-session write gate above remains local. |
| Repeat the stale-takeover worktree gate immediately before writing. | Upstream-equivalent: [Claim](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-claim.instructions.md) rechecks the candidate and [Resume](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-resume.instructions.md) treats occupied/unreadable/unknown worktrees as a stop. |
| Enforce roadmap issue-author approval. | Upstream-equivalent: [A3.5](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-discover.instructions.md) applies the gate to explicit targets and roadmap candidates. |
| Restrict claimless F2 to no-closing-issue or a valid bootstrap PR. | Upstream-equivalent: [Pre-merge](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-pre-merge.instructions.md) allows only those claimless cases. |
| Define lite advisory routes for every outcome and keep AW1's proven-head path distinct from AW3 elapsed-window satisfaction. | Upstream-equivalent: [Lite advisory outcomes](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-advisory-wait-lite.instructions.md) and [lite E1](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md) separate these routes. |
| Apply the scored-floor filter before tie-breaking, then effort/overlap ordering, with session-offset as the final direct pick. | Upstream-equivalent: [Discover selection](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-discover.instructions.md) and the session-offset-direct-index row above. |
| Skip session-offset rotation only when disabled or the band is a singleton. | Upstream-equivalent: [Discover selection](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-discover.instructions.md) preserves the remaining tie-breakers in those cases. |
| Preserve validator status when output is piped. | Upstream-equivalent: [Project commands](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-overview-core.instructions.md) and the lite work/submit files require pipefail or PIPESTATUS[0]. |
| Apply merge-capable actor and resume-condition checks in the full workflow. | Upstream-equivalent: [Merge handoff](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-merge-handoff.instructions.md). |
| Route CI outcomes by required-check state and policy. | Upstream-equivalent: [CI interpretation](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-ci.instructions.md). |
| Make every F4 submodule inspection fail the probe on status, stash, ref, or detached-HEAD errors. | Upstream-equivalent: [F4 cleanup](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-merge.instructions.md) uses a fail-propagating command chain. |
| Lock shared-clone F4 fetch, switch/fast-forward, removal, and local branch deletion. | Upstream-equivalent: [F4 cleanup](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-merge.instructions.md) and the clone-scoped lock contract. |
| Keep the active claim in the digest until every closing issue is confirmed closed. | Upstream-equivalent: [F4 digest order](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/idd-merge.instructions.md) releases only after closure confirmation. |
| Require matching head repository plus inheritable branch for own-PR exceptions. | **Retain**. The local rule binds both repository identity and claim branch; no equivalent conjunction appears in the v0.17.0 instruction contract. |
| Compare asynchronous closing-keyword age to GitHub's server Date, not the local clock. | **Retain**. The v0.17.0 instructions have no equivalent server-Date comparison for this closing-keyword decision. |
| Keep convergence recovery that has not been promoted and is held by the rerun budget on hold; do not bypass per-run budgets with --refresh-latest. | **Retain**. v0.17.0 offers a --refresh-latest recovery route for selected withheld instances; dotfiles' tighter per-run cap remains the policy. |
| Route deferred E1 snapshots through E14 before E15 when advisory coverage is not current, then return to E1 before F1/F2. | Upstream-equivalent: [lite E1](https://github.com/kurone-kito/idd-skill/blob/77befdd4030757464bed7f31c7dfe6d0a404a18b/idd-template/.github/instructions/lite/idd-review-snapshot-lite.instructions.md) says E14 first when both are pending and returns to E1 before F1/F2. |

## Retained shared-host process rule

When a critique or review agent starts background work, it may stop
only processes it started and identified by a recorded PID or process
group. Never stop processes by name, working directory, or command-line
pattern (`pkill`, `killall`, or `pgrep -f ... | xargs kill`). `pgrep -P`
may enumerate children of a recorded PID. The only daemon exception is
the bounded signing procedure's `gpgconf --kill gpg-agent`. This rule
also applies to reviewer prompts used by the installed issue-authoring
companion.

## Scope boundary

This overlay preserves non-equivalent IDD behavior for future
local-import retirement. #679 leaves the linked imported files in place
and does not remove or resync them. Re-evaluate a retained row only
after a new source comparison and an explicit repository policy
decision.
