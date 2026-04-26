# PowerShell aliases and functions

Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command

$compatAliases = @(
  @{ Name = 'wt'; Target = 'git-wt' }
  @{ Name = 'git-wt'; Target = 'wt' }
  @{ Name = 'batcat'; Target = 'bat' }
  @{ Name = 'bat'; Target = 'batcat' }
)

foreach ($compatAlias in $compatAliases) {
  if (Get-Command $compatAlias.Name -ErrorAction SilentlyContinue) {
    continue
  }

  if (-not (Get-Command $compatAlias.Target -ErrorAction SilentlyContinue)) {
    continue
  }

  Set-Alias -Name $compatAlias.Name -Value $compatAlias.Target
}

Remove-Variable compatAliases, compatAlias -ErrorAction SilentlyContinue
