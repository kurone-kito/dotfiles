#!/usr/bin/env pwsh
# Emit CodeRabbit CLI's structured findings for the current branch diff, for
# use as an IDD C1 critiqueLoop.delegate command. Read-only findings adapter
# only: never fixes, commits, or retries -- C2-C6 own that. Fails (non-zero
# exit) whenever the caller should fall through to the per-agent critique
# mechanism instead: coderabbit missing, unauthenticated, or an
# action_required response (rate limit / usage confirmation) that only the
# operator can resolve.
#
# `coderabbit review --agent` does not fail fast when unauthenticated -- it
# hangs waiting on an interactive browser OAuth flow instead of exiting, so
# authentication is checked up front via `coderabbit auth status` (which
# never hangs and always exits 0 regardless of sign-in state -- its text
# output must be parsed instead).
$ErrorActionPreference = 'Stop'

function global:Get-DotfilesCoderabbitCommand {
  return Get-Command coderabbit -ErrorAction SilentlyContinue
}

function global:Test-DotfilesCoderabbitAuthenticated {
  param([Parameter(Mandatory)] $CoderabbitCommand)

  $authOutput = & $CoderabbitCommand.Name auth status 2>&1 | Out-String
  return ($authOutput -notmatch 'signed out')
}

# 300s default: an empirically observed real review of a 5-file diff took
# ~151s end to end (connect, setup, summarize, review); 120s was measured
# to be too short and cut a genuine in-progress review off mid-flight.
function global:Resolve-DotfilesCoderabbitTimeoutSeconds {
  $raw = $env:CODERABBIT_CRITIQUE_TIMEOUT
  $parsed = 0
  if ($raw -and [int]::TryParse($raw, [ref] $parsed) -and $parsed -gt 0) {
    return $parsed
  }
  return 300
}

# A hardcoded default branch name would be wrong for any repository that
# does not use it (this delegate is user-global, not dotfiles-specific).
# Prefer the remote's actual recorded default; fall back to checking common
# candidate names only if that is unset (e.g. `git remote set-head origin
# -a` was never run); return $null (fail closed) rather than guessing wrong.
function global:Resolve-DotfilesCoderabbitBaseBranch {
  if ($env:CODERABBIT_CRITIQUE_BASE) {
    return $env:CODERABBIT_CRITIQUE_BASE
  }

  $gitCommand = Get-Command git -ErrorAction SilentlyContinue
  if (-not $gitCommand) {
    return $null
  }

  try {
    $symref = (& $gitCommand.Name symbolic-ref --short refs/remotes/origin/HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $symref) {
      return ($symref -replace '^origin/', '')
    }
  } catch [System.Exception] {}

  # A first-match loop would silently pick "main" over "master" whenever a
  # repository happens to have both remote-tracking refs (a rename in
  # progress, a stale branch left over, etc.) even if the real default is
  # "master" -- fail closed on that ambiguity instead of guessing.
  $existing = @{}
  foreach ($candidate in @('main', 'master')) {
    try {
      & $gitCommand.Name rev-parse --verify --quiet "origin/$candidate" 2>$null | Out-Null
      $existing[$candidate] = ($LASTEXITCODE -eq 0)
    } catch [System.Exception] {
      $existing[$candidate] = $false
    }
  }
  if ($existing['main'] -and -not $existing['master']) {
    return 'main'
  }
  if ($existing['master'] -and -not $existing['main']) {
    return 'master'
  }

  return $null
}

# ProcessStartInfo.ArgumentList was added in .NET Core 2.1+ and does not
# exist on .NET Framework -- Windows PowerShell 5.1's runtime. Build the
# single-string Arguments fallback using the standard CommandLineToArgvW
# escaping algorithm .NET's own ArgumentList uses internally on newer
# runtimes -- doubling embedded quotes (an earlier version of this
# function) is a CSV/SQL-style convention, not how Windows argv parsing
# actually decodes a quoted argument, and does not reliably preserve an
# embedded quote. A git branch name cannot contain a backslash (git
# check-ref-format rejects it) but git does allow an embedded double
# quote, and the explicit CODERABBIT_CRITIQUE_BASE override is
# unconstrained by git's ref-name rules at all, so both the
# quote-escaping and backslash-run-doubling parts of the algorithm are
# required, not just quote-wrapping.
function global:ConvertTo-DotfilesWindowsQuotedArgument {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Argument)

  if ($Argument -eq '') {
    return '""'
  }
  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  $result = [System.Text.StringBuilder]::new()
  [void]$result.Append('"')
  $backslashes = 0
  foreach ($ch in $Argument.ToCharArray()) {
    if ($ch -eq '\') {
      $backslashes++
      continue
    }
    if ($ch -eq '"') {
      [void]$result.Append('\' * (($backslashes * 2) + 1))
      [void]$result.Append('"')
      $backslashes = 0
      continue
    }
    if ($backslashes -gt 0) {
      [void]$result.Append('\' * $backslashes)
      $backslashes = 0
    }
    [void]$result.Append($ch)
  }
  if ($backslashes -gt 0) {
    [void]$result.Append('\' * ($backslashes * 2))
  }
  [void]$result.Append('"')
  return $result.ToString()
}

function global:ConvertTo-DotfilesQuotedArgumentString {
  param([string[]] $ArgumentList = @())

  return ($ArgumentList | ForEach-Object {
      ConvertTo-DotfilesWindowsQuotedArgument -Argument $_
    }) -join ' '
}

# Generic bounded-execution primitive, factored out of
# Invoke-DotfilesCoderabbitReviewWithTimeout so it can be unit-tested with
# an arbitrary real target (e.g. pwsh itself) instead of only via coderabbit
# -- [Diagnostics.Process]::Start() launches a real OS process and bypasses
# PowerShell function-shadowing, unlike the `&` call operator used
# elsewhere in this script.
function global:Start-DotfilesProcessWithTimeout {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [string[]] $ArgumentList = @(),
    [Parameter(Mandatory)] [int] $TimeoutSeconds
  )

  $psi = [Diagnostics.ProcessStartInfo]::new($FilePath)
  if ($psi.PSObject.Properties.Name -contains 'ArgumentList') {
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add($a) }
  } else {
    $psi.Arguments = ConvertTo-DotfilesQuotedArgumentString -ArgumentList $ArgumentList
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  $proc = [Diagnostics.Process]::Start($psi)
  $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
  $stderrTask = $proc.StandardError.ReadToEndAsync()

  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch [System.Exception] {}
    return [pscustomobject]@{ TimedOut = $true; ExitCode = -1; Output = '' }
  }

  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  return [pscustomobject]@{
    TimedOut = $false
    ExitCode = $proc.ExitCode
    Output   = "$stdout$stderr"
  }
}

function global:Invoke-DotfilesCoderabbitReviewWithTimeout {
  param(
    [Parameter(Mandatory)] $CoderabbitCommand,
    [Parameter(Mandatory)] [string] $BaseBranch,
    [Parameter(Mandatory)] [int] $TimeoutSeconds
  )

  return Start-DotfilesProcessWithTimeout -FilePath $CoderabbitCommand.Name `
    -ArgumentList @('review', '--agent', '--base', $BaseBranch) `
    -TimeoutSeconds $TimeoutSeconds
}

function global:Invoke-DotfilesCoderabbitCritique {
  $coderabbitCommand = Get-DotfilesCoderabbitCommand
  if (-not $coderabbitCommand) {
    Write-Warning 'coderabbit not found in PATH'
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  if (-not (Test-DotfilesCoderabbitAuthenticated -CoderabbitCommand $coderabbitCommand)) {
    Write-Warning 'coderabbit is not authenticated (run: coderabbit auth login)'
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  $timeoutSeconds = Resolve-DotfilesCoderabbitTimeoutSeconds
  $baseBranch = Resolve-DotfilesCoderabbitBaseBranch
  if (-not $baseBranch) {
    Write-Warning 'could not determine the default base branch (no origin/HEAD symref, no origin/main or origin/master); set CODERABBIT_CRITIQUE_BASE explicitly'
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  $result = Invoke-DotfilesCoderabbitReviewWithTimeout `
    -CoderabbitCommand $coderabbitCommand -BaseBranch $baseBranch `
    -TimeoutSeconds $timeoutSeconds

  if ($result.TimedOut) {
    Write-Warning "coderabbit review timed out after ${timeoutSeconds}s"
    return [pscustomobject]@{ Success = $false; Output = '' }
  }
  if ($result.ExitCode -ne 0) {
    Write-Warning "coderabbit review failed (exit $($result.ExitCode))"
    return [pscustomobject]@{ Success = $false; Output = '' }
  }
  if ($result.Output -match '"type":"action_required"') {
    Write-Warning 'coderabbit review requires operator action; treating as unavailable'
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  return [pscustomobject]@{ Success = $true; Output = $result.Output }
}

if ($env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN -ne '1') {
  $result = Invoke-DotfilesCoderabbitCritique
  if ($result.Success) {
    Write-Output $result.Output
    exit 0
  }

  exit 1
}
