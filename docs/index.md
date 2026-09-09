---
type: index
title: IDD Documentation Index
description: Is the entry point and topic map for the IDD documentation bundle this repository imports into its own docs/.
---

# IDD Documentation Index

Use this page as the entry point to this documentation bundle. If you
are an agent working in this repository for the first time, start with
[Getting started](getting-started.md) or [Core concepts](concepts.md);
otherwise use the table below to find a page by topic.

Every page in this bundle follows the OKF (Open Knowledge Format)
frontmatter convention this table is generated from — see
[Customizing IDD § Docs Bundle Frontmatter Convention
(OKF)](customization.md#docs-bundle-frontmatter-convention-okf) before
adding a page of your own.

<!-- dotfiles-divergence: onboarding-doc-trim -->
The generated table below omits two upstream pages this repository
does not vendor locally — `onboarding/placeholders.md` and
`onboarding/policy-decisions.md` (self-corrupting once their
placeholder tokens are substituted; see the `onboarding-doc-trim`
[Divergence Register](idd-policy.md#divergence-register) entry) —
every in-bundle reference to either links the pinned upstream copy
instead.

## Reference Map

<!-- audit:generated id=idd-template-docs-index-okf-table -->

<!-- dprint-ignore-start -->
| Type | Page | Description |
| ---- | ---- | ----------- |
| guide | [Customizing IDD](customization.md) | Lists which IDD surfaces adopters can safely customize and points to the authoritative file for each policy. |
| guide | [Getting Started with IDD](getting-started.md) | Walks a new adopter through the shortest safe path from deciding to adopt IDD to running the first Issue-Driven Development loop. |
| guide | [IDD Review Policy Profiles](idd-review-policy-profiles.md) | Names the supported PR review policy profiles and the instruction files an adopter must edit to select one other than the Copilot-advisory default. |
| guide | [Permissions and Threat Model](permissions.md) | Defines the credential profiles, merge-policy boundaries, and threat model an operator must choose before granting IDD agents GitHub access. |
| concept | [Core IDD Concepts](concepts.md) | Introduces the loop-engineering vocabulary and mental model behind the IDD phase instructions before diving into phase-by-phase rules. |
| reference | [IDD — Advisory-Wait Shell Fallback (AW1 / AW2 / AW3-R / AW3-S / AW3-H / F2 detail)](idd-advisory-wait-shell-fallback.md) | Provides the verbatim gh, gh api, jq, and curl commands the advisory-wait and F2 advisory-convergence shell fallbacks use when helper support cannot be trusted. |
| reference | [IDD Autonomy Contract](idd-autonomy-contract.md) | Classifies every externally visible IDD mutation as reversible or irreversible and names the gate or undo path for each. |
| reference | [IDD Comment Minimization](idd-comment-minimization.md) | Defines the live status digest contract and the safe procedure for minimizing completed review feedback and stale operational markers after merge. |
| reference | [IDD — Concept Ownership Matrix](idd-concept-ownership.md) | Answers which actor may touch a given IDD concept at a given phase without re-reading every instruction file. |
| reference | [IDD Resume — Detail Reference](idd-resume-detail.md) | Provides the full narrative detail behind idd-resume.instructions.md's compact routing tables for branches that need careful judgment. |
| reference | [Onboarding Reference — Agent Entry and Verification](onboarding/agent-entry-and-verification.md) | Provides the detailed agent-entry examples and verification checklist referenced by ONBOARDING.md steps 5 and 6. |
| reference | [Onboarding Reference — Issue-Mediated Bootstrap](onboarding/issue-mediated-bootstrap.md) | Documents an opt-in alternate bootstrap path that imports the IDD template through a reviewed issue-branch-PR cycle instead of theirs-flow's direct, unreviewed commit. |
| reference | [Onboarding Reference — Optional Host Setup](onboarding/optional-host-setup.md) | Documents the optional host-level setup steps (worktree guard, idd-doctor CI gate, advisory-convergence CI workflow, vendored-bundle linguist attributes) that ONBOARDING.md now only points to. |
| reference | [Onboarding Reference — Project Tuning](onboarding/project-tuning.md) | The post-hearing judgment calls idd-onboard's CLI does not automate — agent-entry file surgery, non-default profile artifacts, extra trusted marker actors, claim-timing/label-name overrides, the reserved-label guard, the issue-authoring companion install, and command-row retuning. |
| reference | [Template Distribution Maintainer Reference](onboarding/template-distribution.md) | Explains how the template's generated file-distribution lists in ONBOARDING.md stay correct as files are added, removed, or moved. |
| reference | [IDD Policy Constants](policy-constants.md) | Inventories the distributed IDD policy defaults and names which configuration surface owns each one. |
| reference | [IDD Detailed Reference](reference.md) | Maps each operational question to the authoritative phase file or policy page that answers it. |
| workflow | [IDD workflow guide](idd-workflow.md) | Routes each agent to its entry file and the phase file matching its current state. |
| design | [IDD — Design Rationale and Maintainer Notes](idd-design-rationale.md) | Collects maintainer-facing rationale for why IDD phase rules exist as they do, organized by phase file. |
| design | [IDD Helper Script Evaluation](idd-helper-scripts.md) | Records the current adoption decision and trade-offs for IDD's optional helper scripts so future reviews do not re-evaluate them from scratch. |
<!-- dprint-ignore-end -->

<!-- /audit:generated -->

<!-- dotfiles-divergence: local-docs-index -->
This repository also has locally-authored, non-upstream pages that
upstream's index generator has no knowledge of. They are folded into
the table below so this index still covers the full `docs/` bundle.

## Local pages

<!-- dprint-ignore-start -->
| Type | Page | Description |
| ---- | ---- | ----------- |
| guide | [AI tooling strategy](ai-strategy.md) | Explains why this repository prioritizes GitHub Copilot for AI tooling and how its instruction-file layers relate to each other. |
| guide | [Using ghq with multiple accounts](ghq-workflow.md) | Explains how to configure ghq so each GitHub or GitLab account automatically uses the correct SSH key, commit identity, and GPG signing key. |
| guide | [Repairing Git Bash under Windows mandatory ASLR](git-bash-aslr-repair.md) | Explains how to diagnose and repair Git Bash fork() failures caused by Windows mandatory ASLR, and what the chezmoi apply warning means. |
| guide | [Opt-in local development CA setup (mkcert)](mkcert-local-ca.md) | Explains how to opt into registering a local mkcert CA into the Windows certificate trust store during chezmoi apply, and why it stays off by default. |
| guide | [Secret manager setup](secret-manager-setup.md) | Explains how to configure chezmoi to retrieve GPG keys, SSH keys, and SSH host configuration from an external secret manager. |
| guide | [Tool ownership boundary with setup.windows](setup-windows-boundary.md) | Explains which layer — this repository's mise, WinGet/DSC in kurone-kito/setup.windows, or Chocolatey — owns each Windows tool and why. |
| guide | [Deploying sshd_config](sshd-config-setup.md) | Explains how to manually deploy the chezmoi-generated hardened sshd_config to its system location on Linux, macOS, and Windows. |
| guide | [Configuring the systemd-tmpfiles /tmp cleanup age](tmpfiles-cleanup-setup.md) | Explains how to manually deploy the chezmoi-generated tmpfiles.d override that shortens the /tmp cleanup age on Linux, and why deployment stays manual. |
| guide | [VS Code Integrated Terminal](vscode-terminal.md) | Explains how this dotfiles PowerShell profile adapts to VS Code's integrated terminal and lists recommended VS Code settings. |
| guide | [Declaring WinGet package directories in the User PATH](winget-user-path.md) | Explains how to declare a WinGet portable package's real directory so it is registered in the managed User PATH independent of WinGet's symlinks. |
| guide | [Zellij Web Client — Mobile Usage Guide](zellij-web-mobile.md) | Covers known limitations and recommended workarounds for using the Zellij web client from mobile devices. |
| reference | [chezmoi.toml Configuration Reference](chezmoi-toml-reference.md) | Documents every chezmoi.toml configuration path, with each field's type, default, and a link to its deployment guide. |
| reference | [IDD Policy Configuration](idd-policy.md) | Records this repository's confirmed IDD policy decisions alongside their machine-readable mirror in .github/idd/config.json. |
<!-- dprint-ignore-end -->
