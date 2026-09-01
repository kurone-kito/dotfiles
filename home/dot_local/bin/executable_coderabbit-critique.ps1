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
    return [pscustomobject]@{ TimedOut = $true; ExitCode = -1; Stdout = ''; Stderr = '' }
  }

  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  return [pscustomobject]@{
    TimedOut = $false
    ExitCode = $proc.ExitCode
    Stdout   = $stdout
    Stderr   = $stderr
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

# Anchors action_required detection to the captured stream's own
# top-level JSON "type" property, rather than an unanchored substring/
# regex scan of the whole stream (#329): an unescaped nested JSON object
# shaped like `"type": "action_required"` elsewhere in a legitimate
# finding (e.g. inside its "message" or an example/documentation field)
# is otherwise indistinguishable from a genuine top-level marker to any
# pattern that does not track JSON's arbitrary nesting depth --
# `coderabbit review --agent`'s serialization is not a pinned contract,
# so the marker's own top-level key is not guaranteed to be the first
# byte of the payload either. `ConvertFrom-Json` parses the stream as
# real JSON and `.type` reads only the direct top-level property of the
# resulting object, so a nested occurrence several levels deep never
# surfaces through it -- no external-tool absence risk here, unlike the
# shell twin's `jq` dependency, since JSON parsing is native to .NET.
# This also preserves #327's whitespace tolerance around the key, the
# colon, and the value for free: JSON whitespace between tokens is
# syntactically insignificant, so a pretty-printed marker parses
# identically to a compact one.
#
# `-ceq` (case-sensitive) throughout, rather than the default
# case-insensitive `-eq`/property-access behavior: jq's `==` and its
# `.type` key lookup on the shell twin are both byte-exact case-sensitive
# (a `"Type":"action_required"` payload's key is simply not `.type` to
# jq), so matching that here keeps the twins in lockstep rather than
# reintroducing the latent case-insensitivity the prior `-match` regex
# (also case-insensitive by default) already carried. This has to cover
# both the property NAME and its VALUE: PowerShell's own `.type` property
# access resolves a differently-cased `Type` key too (confirmed
# empirically), so a plain `$parsed.type -ceq 'action_required'` would
# still diverge from jq on a `{"Type":"action_required"}` payload even
# with a case-sensitive value comparison -- see the property-name lookup
# below.
function global:Test-DotfilesActionRequiredType {
  param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)

  if (-not $Text) {
    return $false
  }
  # A JSON object literal must start with '{' (after insignificant
  # leading whitespace) by grammar -- checked on the raw text, before
  # parsing, because the *parsed* result's .NET type is not a reliable
  # way to tell a top-level object apart from a top-level array here:
  # PowerShell's pipeline silently unwraps a single-element array
  # returned by ConvertFrom-Json into a bare [pscustomobject] on
  # assignment (`$parsed = $Text | ConvertFrom-Json`), so a
  # single-element top-level array like `[{"type":"action_required"}]`
  # would otherwise satisfy an `-is [pscustomobject]` check exactly as
  # though it were a genuine top-level object (confirmed empirically --
  # `jq`'s `type == "object"` guard on the shell twin does not share this
  # gap, since jq reports "array" for a JSON array regardless of element
  # count). Rejecting non-object syntax from the raw text up front closes
  # this gap entirely, independent of any pipeline unwrapping.
  if (-not $Text.TrimStart().StartsWith('{')) {
    return $false
  }
  # `ConvertFrom-Json` throws when a top-level object has two keys that
  # differ only by case (e.g. both "type" and "Type" present) -- a known
  # .NET/PSObject limitation, since PSObject property names are
  # case-insensitive internally and the two keys collide when the object
  # is constructed. `jq`, being case-sensitive with no such collision
  # restriction, has no trouble with the identical payload. This is
  # accepted as a rare, untested edge case (a real coderabbit payload
  # emitting two case-colliding top-level keys would itself be unusual)
  # rather than worth a case-sensitive hand-rolled parser here: the
  # brace-gate above and the property-name lookup below already cover
  # every payload shape this delegate's own tests exercise. The `catch`
  # below still fails closed to "no match" on this collision, consistent
  # with every other parse failure in this function.
  try {
    $parsed = $Text | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $false
  }
  # No further object-vs-scalar check is needed here: the brace-gate
  # above already guarantees that a value which parses successfully
  # without throwing must be a JSON object (that is the only value shape
  # JSON grammar permits to start with '{').
  # `.type` property access is case-insensitive in PowerShell (it would
  # resolve a `Type` key just as readily), so the key name itself is
  # matched case-sensitively by enumerating PSObject.Properties instead
  # of relying on dot-access -- the case-sensitive equivalent of jq's own
  # key lookup on the shell twin.
  $typeProperty = $parsed.PSObject.Properties |
    Where-Object { $_.Name -ceq 'type' } | Select-Object -First 1
  if (-not $typeProperty) {
    return $false
  }
  # The property's VALUE must also be a string before comparing it,
  # separately from the property-NAME lookup above: for an array-shaped
  # value (e.g. `{"type":["action_required"]}`), PowerShell's `-ceq`
  # performs an *element-wise* comparison when its left operand is a
  # collection and returns the (non-empty, therefore truthy) matching
  # subset rather than a single boolean -- so an unguarded
  # `$typeProperty.Value -ceq 'action_required'` would wrongly return a
  # truthy result here (confirmed empirically). `jq`'s `.type` on the
  # shell twin has no equivalent gap: a non-string JSON value serializes
  # to something that can never equal the bare literal `action_required`
  # in the shell's plain string comparison, so this guard is what keeps
  # the twins in lockstep for every non-string `type` value shape (array,
  # number, boolean, or nested object), not just strings.
  if ($typeProperty.Value -isnot [string]) {
    return $false
  }
  return ($typeProperty.Value -ceq 'action_required')
}

function global:Invoke-DotfilesCoderabbitCritique {
  # Every diagnostic below goes through [Console]::Error.WriteLine, never
  # Write-Warning: under `pwsh -File` non-interactive execution (this
  # script's actual invocation shape), the default host writes the warning
  # stream onto the process's real stdout, not stderr -- confirmed
  # empirically -- which would corrupt a caller (like IDD's C1 critique
  # step) expecting this script's stdout to carry only structured
  # findings/report output. `[Console]::Error` writes directly to the
  # OS-level stderr handle, bypassing that host routing entirely.
  $coderabbitCommand = Get-DotfilesCoderabbitCommand
  if (-not $coderabbitCommand) {
    [Console]::Error.WriteLine('coderabbit not found in PATH')
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  if (-not (Test-DotfilesCoderabbitAuthenticated -CoderabbitCommand $coderabbitCommand)) {
    [Console]::Error.WriteLine('coderabbit is not authenticated (run: coderabbit auth login)')
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  $timeoutSeconds = Resolve-DotfilesCoderabbitTimeoutSeconds
  $baseBranch = Resolve-DotfilesCoderabbitBaseBranch
  if (-not $baseBranch) {
    [Console]::Error.WriteLine('could not determine the default base branch (no origin/HEAD symref, no origin/main or origin/master); set CODERABBIT_CRITIQUE_BASE explicitly')
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  $result = Invoke-DotfilesCoderabbitReviewWithTimeout `
    -CoderabbitCommand $coderabbitCommand -BaseBranch $baseBranch `
    -TimeoutSeconds $timeoutSeconds

  if ($result.TimedOut) {
    [Console]::Error.WriteLine("coderabbit review timed out after ${timeoutSeconds}s")
    return [pscustomobject]@{ Success = $false; Output = '' }
  }
  if ($result.ExitCode -ne 0) {
    [Console]::Error.WriteLine("coderabbit review failed (exit $($result.ExitCode))")
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  # See Test-DotfilesActionRequiredType's own comment for why this is
  # anchored to each stream's top-level JSON "type" property rather than
  # a substring/regex scan. Both streams are checked (not only the one
  # presumed to carry findings) because the emission point is unverified;
  # this keeps today's detection reach even though only Stdout is
  # returned as findings below.
  if ((Test-DotfilesActionRequiredType -Text $result.Stdout) -or
    (Test-DotfilesActionRequiredType -Text $result.Stderr)) {
    [Console]::Error.WriteLine('coderabbit review requires operator action; treating as unavailable')
    return [pscustomobject]@{ Success = $false; Output = '' }
  }

  # Only Stdout becomes findings text -- a progress line or diagnostic on
  # Stderr must never reach C1 as findings, where C3 could score it as a
  # real issue. Stderr is not silently dropped, though: it is forwarded to
  # the delegate's own real stderr here too, mirroring the shell twin's
  # equivalent forward-to-stderr-on-success behavior, via the same
  # [Console]::Error mechanism explained at the top of this function.
  if ($result.Stderr) {
    [Console]::Error.WriteLine($result.Stderr)
  }
  return [pscustomobject]@{ Success = $true; Output = $result.Stdout }
}

if ($env:DOTFILES_TEST_CODERABBIT_CRITIQUE_SKIP_MAIN -ne '1') {
  $result = Invoke-DotfilesCoderabbitCritique
  if ($result.Success) {
    Write-Output $result.Output
    exit 0
  }

  exit 1
}
