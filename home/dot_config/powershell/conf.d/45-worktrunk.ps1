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

$__gitWtInfo = Get-Command git-wt -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$__wtCmd = if ($__gitWtInfo) {
  if ($__gitWtInfo.Path) { $__gitWtInfo.Path } else { $__gitWtInfo.Source }
} elseif ($__wtPath) {
  $__wtPath
} else { $null }
if (-not $__wtCmd) {
  Remove-Variable __wtCmd, __gitWtInfo, __wtPath, __wtCandidate, __candidatePath -ErrorAction SilentlyContinue
  return
}

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip only the final trailing zero line before evaluating.
$__wtInit = (& $__wtCmd config shell init powershell 2>$null) | Out-String
if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0) {
  $__wtInit = $__wtInit -replace '(?s)(\r?\n)0\s*$|^0\s*$', ''
  if ($__wtInit.Trim()) { Invoke-Expression $__wtInit }
}
Remove-Variable __wtCmd, __gitWtInfo, __wtInit, __wtPath, __wtCandidate, __candidatePath -ErrorAction SilentlyContinue
