---
type: guide
title: Repairing Git Bash under Windows mandatory ASLR
description: Explains how to diagnose and repair Git Bash fork() failures caused by Windows mandatory ASLR, and what the chezmoi apply warning means.
---

# Repairing Git Bash under Windows mandatory ASLR

When Windows' system-wide **mandatory ASLR** (Exploit Protection's
"Force randomization for images") is enabled, Git Bash's `usr\bin`
binaries (`bash.exe` and the rest of the MSYS toolchain) can no longer
`fork()`, while `git.exe` itself keeps working throughout. This guide
explains the symptom, the cause, how to confirm it, and how to repair
it using the helper this repository ships.

## Symptom

Commands run from Git Bash fail with `fork()` errors instead of
completing. A representative failure looks like this (the process IDs,
addresses, and Win32 error codes vary per machine and per run --the
`child_copy` / `dofork` function names and overall shape are the
signal to recognize):

```text
0 [main] bash (19340) child_copy: cygheap read copy failed, 0x0..0x800029A98, done 0, windows pid 19340, Win32 error 299
0 [main] bash 1199 dofork: child -1 - forked process 19340 died unexpectedly, retry 0, exit code 0xC0000142, errno 11
```

Nothing in this output mentions ASLR, mitigations, or Windows security
settings, so it does not point a reader toward the actual cause on its
own.

### Why `git.exe` keeps working

Git for Windows ships two kinds of binaries:

- **MINGW builds** (`git.exe`, and everything under `mingw64\bin`) --
  ordinary Windows-native binaries that support ASLR normally.
- **MSYS builds** (`bash.exe` and the rest of `usr\bin`) -- POSIX
  emulation binaries whose `fork()` is emulated by copying the parent
  process's memory into a child that must map the same DLLs at the
  same addresses. Mandatory ASLR re-randomizes those addresses per
  process, so the copy fails.

Because `git.exe` is a MINGW build, plain `git` commands (including
ones invoked from PowerShell, `cmd.exe`, or an IDE) keep working even
while Git Bash itself is broken -- the machine looks healthy while Git
Bash is not, which makes this failure mode easy to miss.

## Cause

Git for Windows documents this as an unfixable design constraint of
its bundled MSYS runtime, not a bug introduced by this repository or
by Git for Windows' packaging: see
[Why Git for Windows does not work with Mandatory Address Space Layout Randomization](https://gitforwindows.org/why-git-for-windows-does-not-work-with-mandatory-address-space-layout-randomization.html).
Its own installer offers a "per-image mitigation exemption" option
during setup; this repository's helper reproduces that same repair for
hosts where it was skipped or lost (for example, after a Windows
reinstall).

## Confirming it

Both checks below use PowerShell's `Get-ProcessMitigation` cmdlet
(part of Windows' Exploit Protection surface, no extra install
needed).

**System-wide value** -- confirms whether mandatory ASLR is enabled at
all:

```powershell
Get-ProcessMitigation -System
```

Look at `ASLR.ForceRelocateImages`: `ON` means mandatory ASLR is
enforced machine-wide. This is the value this repository's tooling
never changes -- see [Why the system-wide setting stays
ON](#why-the-system-wide-setting-stays-on) below.

**Per-image value** -- confirms whether Git Bash specifically has an
exemption from that system-wide policy:

```powershell
Get-ProcessMitigation -Name bash.exe
```

Look at `ASLR.ForceRelocateImages` here too: `OFF` means `bash.exe` is
exempted (fork should work); `ON`, or the same value as the
system-wide check, means it is not.

### `OverrideForceRelocateImages` is not the signal to read

The same `ASLR` object also reports an `OverrideForceRelocateImages`
field. **This field stays `False` even after `bash.exe` is correctly
exempted** -- it does not flip to `True` to confirm the exemption
worked. Reading it as a pass/fail signal will misreport an exempted
image as unprotected. `ForceRelocateImages` (`ON` / `OFF`) is the only
field that reflects the actual mitigation state; treat
`OverrideForceRelocateImages` as unrelated to this check.

## Repairing it

Run the repair helper this repository ships, from an **elevated**
PowerShell prompt (per-image mitigation policy lives under `HKLM`'s
Image File Execution Options, which requires administrator rights to
write):

```powershell
# Run as Administrator
& "$HOME\.local\bin\repair-git-bash-aslr.ps1"
```

The script:

1. Verifies the current session has administrator elevation, and stops
   with a clear error if it does not.
2. Checks the system-wide `ForceRelocateImages` value; if mandatory
   ASLR is not enabled at all, it reports that Git Bash needs no
   exemption and exits without changing anything.
3. Resolves the local Git for Windows install root (via the registry
   keys the installer itself writes, or by walking up from `git.exe`
   on `PATH`).
4. Enumerates **every** `*.exe` file under that install's `usr\bin`
   directory -- not only `bash.exe`, but the entire MSYS toolchain
   (`sh.exe`, `ssh.exe`, `perl.exe`, `grep.exe`, and dozens more) -- and
   disables `ForceRelocateImages` for each one that is not already
   exempted.

`bash.exe` is the sentinel image the confirmation commands above (and
the `chezmoi apply` warning below) check, since it is the entry point
most people notice failing first -- but the repair itself covers the
whole `usr\bin` toolchain in one pass, since every MSYS binary in that
directory has the identical `fork()` limitation.

### The `chezmoi apply` warning

This repository also ships a `chezmoi apply`-time check
(`run_after_85-warn-git-bash-aslr.ps1`) that runs on every apply and
prints a warning when it detects that mandatory ASLR is enabled *and*
`bash.exe` has no exemption:

```text
Git Bash (bash.exe) has no per-image exemption from Windows mandatory ASLR (ForceRelocateImages) and every fork() call inside it will fail. Run & "$HOME\.local\bin\repair-git-bash-aslr.ps1" (elevated) to add the exemption.
```

This script only **detects and warns** -- it never modifies any
mitigation setting itself, and it never runs elevated, since chezmoi's
own apply never escalates privileges. Seeing this warning means the
repair helper above has not been run yet (or its exemption was lost,
most commonly by a Windows reinstall); running the helper once,
elevated, silences the warning on the next `chezmoi apply`. The warning
also stays silent (no output) whenever the mitigation query itself
fails or is unavailable, rather than warning on a guess.

## Why the system-wide setting stays ON

This repository's tooling never disables mandatory ASLR at the system
level -- only the per-image exemption for Git's own MSYS binaries.
Weakening a security mitigation machine-wide during an ordinary
`chezmoi apply` would be the wrong trade for the narrow problem being
solved.

## Exemptions match image names, not paths

Windows process mitigation policy is keyed by **image name**, not by
full path. This has two consequences worth knowing:

- Git for Windows' own `bin\bash.exe` is a junction to `usr\bin\bash.exe`,
  so exempting the name `bash.exe` covers both locations without extra
  work.
- Any other process on the machine that happens to share a name with
  an exempted binary (for example, a different `perl.exe` install) is
  exempted too, since the policy has no way to distinguish which
  `bash.exe` or `perl.exe` on disk actually launched. This is not a
  concern for Git for Windows' own layout, but it is worth knowing if
  you audit process mitigation policy on a shared or multi-tool host.

## Exemptions survive Git upgrades, not a Windows reinstall

The per-image exemption is stored in the registry (`HKLM`'s Image File
Execution Options) and keyed by binary name, not tied to a specific
Git for Windows version or install path. Upgrading Git for Windows in
place does not need the helper re-run. **Reinstalling Windows does**
lose it, since that registry hive is part of the OS install, not part
of Git's own files -- a freshly provisioned host needs the repair
helper run once, after Git for Windows is installed.

## See also

- [Git for Windows: Why Git for Windows does not work with Mandatory Address Space Layout Randomization](https://gitforwindows.org/why-git-for-windows-does-not-work-with-mandatory-address-space-layout-randomization.html)
- [docs/setup-windows-boundary.md](setup-windows-boundary.md) --
  records why this repository, not `kurone-kito/setup.windows`, owns
  this exemption
