# PowerShell aliases and functions

Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command

$compatAliases = @(
  @{ Name = 'wt'; Target = 'git-wt' }
  @{ Name = 'git-wt'; Target = 'wt' }
  @{ Name = 'batcat'; Target = 'bat' }
  @{ Name = 'bat'; Target = 'batcat' }
)

# Select-Object -First 1: aliases resolve by name so only the first wt
# in PATH matters (unlike 45-worktrunk.ps1 which iterates all candidates
# to find a non-Windows-Terminal wt it can invoke by path).
$__wtCommand = Get-Command wt -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$__wtPath = if ($__wtCommand) {
  if ($__wtCommand.Path) { $__wtCommand.Path } else { $__wtCommand.Source }
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

foreach ($compatAlias in $compatAliases) {
  if (Get-Command $compatAlias.Name -ErrorAction SilentlyContinue) {
    continue
  }

  $targetCommand = Get-Command $compatAlias.Target -ErrorAction SilentlyContinue
  if (-not $targetCommand) {
    continue
  }

  if ($compatAlias.Target -eq 'wt' -and $__wtIsWindowsTerminal) {
    continue
  }

  Set-Alias -Name $compatAlias.Name -Value $compatAlias.Target
}

Remove-Variable compatAliases, compatAlias, targetCommand, __wtCommand, __wtPath, __wtIsWindowsTerminal -ErrorAction SilentlyContinue
