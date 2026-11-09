# Prefer git-wt on Windows; only fall back to wt when it is not Windows Terminal.
# Restrict to Application to match bash/zsh type -P / whence -p semantics
# and prevent function/alias injection into Invoke-Expression.
# Iterate all wt matches so a later worktrunk wt is found even when
# Windows Terminal's wt.exe appears first in PATH.
$__wtPath = $null
foreach ($__wtCandidate in @(Get-Command wt -CommandType Application -ErrorAction SilentlyContinue)) {
  $__candidatePath = if ($__wtCandidate.Path) { $__wtCandidate.Path } else { $__wtCandidate.Source }
  if ($__candidatePath -notmatch '[/\\]WindowsApps[/\\]wt(?:\.exe)?$' -and
      $__candidatePath -notmatch '[/\\]Microsoft\.WindowsTerminal[^/\\]*[/\\]wt(?:\.exe)?$') {
    $__wtPath = $__candidatePath
    break
  }
}

# The git-wt that 31-mise-executables.ps1 resolved, when mise reported one, is
# used in place of the lookup. A miss keeps the lookup below.
$__wtResolved = $null
if ($null -ne $__miseExecutables -and $__miseExecutables.ContainsKey('git-wt')) {
  $__wtResolved = $__miseExecutables['git-wt']
}

$__gitWtInfo = Get-Command git-wt -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$__wtCmd = if ($__wtResolved) {
  $__wtResolved
} elseif ($__gitWtInfo) {
  if ($__gitWtInfo.Path) { $__gitWtInfo.Path } else { $__gitWtInfo.Source }
} elseif ($__wtPath) {
  $__wtPath
} else { $null }
if (-not $__wtCmd) {
  Remove-Variable __wtCmd, __wtResolved, __gitWtInfo, __wtPath, __wtCandidate, __candidatePath -ErrorAction SilentlyContinue
  return
}

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip only the final trailing zero line before evaluating.
# Use try/catch to handle non-console environments (e.g. Windows SSH) where
# native command pipelines fail with StandardOutputEncoding errors.
$__wtInit = $null
$__wtExitOk = $false
try {
  $__wtInit = & {
    $ErrorActionPreference = 'Stop'
    (& $__wtCmd config shell init powershell 2>$null) | Out-String
  }
  $__wtExitOk = ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0)
} catch {
  try {
    $__psi = [Diagnostics.ProcessStartInfo]::new($__wtCmd)
    $__psi.Arguments = 'config shell init powershell'
    $__psi.UseShellExecute = $false
    $__psi.RedirectStandardOutput = $true
    $__psi.RedirectStandardError = $true
    $__psi.CreateNoWindow = $true
    $__proc = [Diagnostics.Process]::Start($__psi)
    $__stderrTask = $__proc.StandardError.ReadToEndAsync()
    $__wtInit = $__proc.StandardOutput.ReadToEnd()
    $null = $__stderrTask.GetAwaiter().GetResult()
    $__proc.WaitForExit()
    $__wtExitOk = ($__proc.ExitCode -eq 0)
    Remove-Variable __psi, __proc, __stderrTask -ErrorAction SilentlyContinue
  } catch { }
}
if ($__wtExitOk -and $__wtInit) {
  $__wtInit = $__wtInit -replace '(?s)(\r?\n)0\s*$|^0\s*$', ''
  if ($__wtInit.Trim()) {
    # worktrunk's init reads WORKTRUNK_BIN for its wrapper and for the
    # completion launch that runs during this evaluation. When the variable
    # is unset and git-wt was resolved, point it at that executable for this
    # evaluation only, and restore the unset state afterwards so later git-wt
    # calls are not pinned to it. A value the user set is left as it is.
    $__wtSetBin = $false
    if ($null -ne $__wtResolved -and $null -eq $env:WORKTRUNK_BIN) {
      $env:WORKTRUNK_BIN = $__wtResolved
      $__wtSetBin = $true
    }
    try {
      Invoke-Expression $__wtInit
    } finally {
      if ($__wtSetBin) {
        Remove-Item -LiteralPath Env:WORKTRUNK_BIN -ErrorAction SilentlyContinue
      }
    }
  }
}
Remove-Variable __wtCmd, __wtResolved, __wtSetBin, __gitWtInfo, __wtInit, __wtPath, __wtCandidate, __candidatePath, __wtExitOk, __psi, __proc, __stderrTask -ErrorAction SilentlyContinue
