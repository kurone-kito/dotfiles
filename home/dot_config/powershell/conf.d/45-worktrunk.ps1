# Prefer git-wt on Windows; only fall back to wt when it is not Windows Terminal.
# Restrict to Application to match bash/zsh type -P / whence -p semantics
# and prevent function/alias injection into Invoke-Expression.
$__wtCommandInfo = Get-Command wt -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$__wtPath = if ($__wtCommandInfo) {
  if ($__wtCommandInfo.Path) { $__wtCommandInfo.Path } else { $__wtCommandInfo.Source }
} else {
  $null
}
$__wtIsWindowsTerminal = $false
if ($__wtPath) {
  $__wtIsWindowsTerminal = (
    $__wtPath -match '[/\\]WindowsApps[/\\]wt(?:\.exe)?$' -or
    $__wtPath -match '[/\\]Microsoft\.WindowsTerminal[^/\\]*[/\\]wt(?:\.exe)?$'
  )
}

$__gitWtInfo = Get-Command git-wt -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$__wtCmd = if ($__gitWtInfo) {
  if ($__gitWtInfo.Path) { $__gitWtInfo.Path } else { $__gitWtInfo.Source }
} elseif ($__wtCommandInfo -and -not $__wtIsWindowsTerminal) {
  $__wtPath
} else { $null }
if (-not $__wtCmd) {
  Remove-Variable __wtCmd, __gitWtInfo, __wtCommandInfo, __wtPath, __wtIsWindowsTerminal -ErrorAction SilentlyContinue
  return
}

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip only the final trailing zero line before evaluating.
$__wtInit = (& $__wtCmd config shell init powershell 2>$null) | Out-String
if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0) {
  $__wtInit = $__wtInit -replace '(?s)(\r?\n)0\s*$', ''
  if ($__wtInit.Trim()) { Invoke-Expression $__wtInit }
}
Remove-Variable __wtCmd, __gitWtInfo, __wtInit, __wtCommandInfo, __wtPath, __wtIsWindowsTerminal -ErrorAction SilentlyContinue
