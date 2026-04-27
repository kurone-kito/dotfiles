# Prefer git-wt on Windows; only fall back to wt when it is not Windows Terminal.
$__wtCommandInfo = Get-Command wt -ErrorAction SilentlyContinue
$__wtPath = if ($__wtCommandInfo) {
  if ($__wtCommandInfo.Path) { $__wtCommandInfo.Path } else { $__wtCommandInfo.Source }
} else {
  $null
}
$__wtIsWindowsTerminal = $false
if ($__wtPath) {
  $__wtPath = $__wtPath.ToString().Replace('/', '\')
  $__wtIsWindowsTerminal = (
    $__wtPath -match '\\WindowsApps\\wt(?:\.exe)?$' -or
    $__wtPath -match '\\Microsoft\.WindowsTerminal[^\\]*\\wt(?:\.exe)?$'
  )
}

$__wtCmd = if (Get-Command git-wt -ErrorAction SilentlyContinue) { 'git-wt' }
           elseif ($__wtCommandInfo -and -not $__wtIsWindowsTerminal) { 'wt' }
           else { $null }
if (-not $__wtCmd) {
  Remove-Variable __wtCmd, __wtCommandInfo, __wtPath, __wtIsWindowsTerminal -ErrorAction SilentlyContinue
  return
}

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip it before evaluating.
$__wtInit = (& $__wtCmd config shell init powershell 2>$null) | Out-String
$__wtInit = $__wtInit -replace '(?m)^0\s*$', ''
if ($__wtInit.Trim()) { Invoke-Expression $__wtInit }
Remove-Variable __wtCmd, __wtInit, __wtCommandInfo, __wtPath, __wtIsWindowsTerminal -ErrorAction SilentlyContinue
