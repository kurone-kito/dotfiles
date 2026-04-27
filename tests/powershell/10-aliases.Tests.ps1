# Tests for the PowerShell aliases configuration script.
# Exercises: ll and which alias creation and targets.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '10-aliases.ps1'
}

Describe '10-aliases' {

  BeforeEach {
    $script:OriginalLl = Get-Alias -Name ll -ErrorAction SilentlyContinue
    $script:OriginalWhich = Get-Alias -Name which -ErrorAction SilentlyContinue
    Remove-Item Alias:\ll -ErrorAction SilentlyContinue
    Remove-Item Alias:\which -ErrorAction SilentlyContinue
  }

  AfterEach {
    Remove-Item Alias:\ll -ErrorAction SilentlyContinue
    Remove-Item Alias:\which -ErrorAction SilentlyContinue
    if ($script:OriginalLl) {
      Set-Alias -Name ll -Value $script:OriginalLl.Definition -Scope Global
    }
    if ($script:OriginalWhich) {
      Set-Alias -Name which -Value $script:OriginalWhich.Definition -Scope Global
    }
  }

  It 'creates the ll alias pointing to Get-ChildItem' {
    . $script:Subject

    $alias = Get-Alias -Name ll -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Get-ChildItem'
  }

  It 'creates the which alias pointing to Get-Command' {
    . $script:Subject

    $alias = Get-Alias -Name which -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Get-Command'
  }
}
