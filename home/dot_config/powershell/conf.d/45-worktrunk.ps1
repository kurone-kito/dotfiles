# Initialize each worktrunk binary on PATH: git-wt, then wt. A wt that is
# Windows Terminal is never wrapped, so no wt function shadows it.
# Restrict to Application to match bash/zsh type -P / whence -p semantics
# and prevent function/alias injection into Invoke-Expression.
# Iterate all wt matches so a later worktrunk wt is found even when
# Windows Terminal's wt.exe appears first in PATH. That later match is used
# only when git-wt is absent; see the wt subject below.
$__wtPath = $null
$__wtFirstIsWindowsTerminal = $false
$__wtFirst = $true
foreach ($__wtCandidate in @(Get-Command wt -CommandType Application -ErrorAction SilentlyContinue)) {
  $__candidatePath = if ($__wtCandidate.Path) { $__wtCandidate.Path } else { $__wtCandidate.Source }
  $__isWindowsTerminal = ($__candidatePath -match '[/\\]WindowsApps[/\\]wt(?:\.exe)?$' -or
      $__candidatePath -match '[/\\]Microsoft\.WindowsTerminal[^/\\]*[/\\]wt(?:\.exe)?$')
  if ($__wtFirst) {
    $__wtFirstIsWindowsTerminal = $__isWindowsTerminal
    $__wtFirst = $false
  }
  if (-not $__isWindowsTerminal) {
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
$__gitWtPresent = [bool]$__wtResolved -or ($null -ne $__gitWtInfo)
$__gitWtCmd = if ($__wtResolved) {
  $__wtResolved
} elseif ($__gitWtInfo) {
  if ($__gitWtInfo.Path) { $__gitWtInfo.Path } else { $__gitWtInfo.Source }
} else { $null }

# With git-wt absent, wt takes the later-match fallback. With git-wt present, wt
# is initialized only when the first wt match is not Windows Terminal, so a wt
# function does not shadow Windows Terminal.
$__wtCmd = if ($__gitWtPresent -and $__wtFirstIsWindowsTerminal) {
  $null
} else {
  $__wtPath
}

$__wtSubjects = @()
if ($__gitWtCmd) {
  $__wtSubjects += [pscustomobject]@{ Name = 'git-wt'; Cmd = $__gitWtCmd }
}
if ($__wtCmd) {
  $__wtSubjects += [pscustomobject]@{ Name = 'wt'; Cmd = $__wtCmd }
}
if ($__wtSubjects.Count -eq 0) {
  Remove-Variable __wtPath, __wtFirstIsWindowsTerminal, __wtFirst, __wtCandidate, __candidatePath, __isWindowsTerminal, __wtResolved, __gitWtInfo, __gitWtPresent, __gitWtCmd, __wtCmd, __wtSubjects -ErrorAction SilentlyContinue
  return
}

foreach ($__wtSubject in $__wtSubjects) {
  $__wtCmd = $__wtSubject.Cmd

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
      # completion launch that runs during this evaluation. For the git-wt
      # subject, when the variable is unset and git-wt was resolved, point it
      # at that executable for this evaluation only, and restore the unset
      # state afterwards so later git-wt calls are not pinned to it. The wt
      # subject is never pinned to git-wt. A value the user set is left as it is.
      $__wtSetBin = $false
      if ($__wtSubject.Name -eq 'git-wt' -and $null -ne $__wtResolved -and $null -eq $env:WORKTRUNK_BIN) {
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
}
Remove-Variable __wtSubject, __wtSubjects, __wtCmd, __gitWtCmd, __gitWtPresent, __wtResolved, __gitWtInfo, __wtFirst, __wtFirstIsWindowsTerminal, __wtPath, __wtCandidate, __candidatePath, __isWindowsTerminal, __wtInit, __wtExitOk, __wtSetBin, __psi, __proc, __stderrTask -ErrorAction SilentlyContinue
