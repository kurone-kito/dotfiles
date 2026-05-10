Describe '20-posh-git' {
  BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot `
      '..\..\home\dot_config\powershell\conf.d\20-posh-git.ps1'
  }

  It 'returns early without error when git is not available' {
    Mock Get-Command { $null } -ParameterFilter {
      $Name -eq 'git'
    }
    Mock Get-Module {}
    Mock Import-Module {}

    { . $script:scriptPath } | Should -Not -Throw
    Should -Invoke Import-Module -Times 0
  }

  It 'returns early without error when posh-git module is not installed' {
    Mock Get-Command { [PSCustomObject]@{ Name = 'git' } } -ParameterFilter {
      $Name -eq 'git'
    }
    Mock Get-Module { $null } -ParameterFilter {
      $Name -eq 'posh-git' -and $ListAvailable
    }
    Mock Import-Module {}

    { . $script:scriptPath } | Should -Not -Throw
    Should -Invoke Import-Module -Times 0
  }

  It 'imports posh-git when both git and the module are available' {
    Mock Get-Command { [PSCustomObject]@{ Name = 'git' } } -ParameterFilter {
      $Name -eq 'git'
    }
    Mock Get-Module {
      [PSCustomObject]@{ Name = 'posh-git'; Version = '1.1.0' }
    } -ParameterFilter {
      $Name -eq 'posh-git' -and $ListAvailable
    }
    Mock Import-Module {} -ParameterFilter { $Name -eq 'posh-git' }

    # Provide a stub $GitPromptSettings so the script can set properties
    $global:GitPromptSettings = [PSCustomObject]@{
      EnablePromptStatus = $true
    }

    { . $script:scriptPath } | Should -Not -Throw
    Should -Invoke Import-Module -Times 1 -ParameterFilter {
      $Name -eq 'posh-git'
    }
  }

  It 'disables EnablePromptStatus after importing posh-git' {
    Mock Get-Command { [PSCustomObject]@{ Name = 'git' } } -ParameterFilter {
      $Name -eq 'git'
    }
    Mock Get-Module {
      [PSCustomObject]@{ Name = 'posh-git'; Version = '1.1.0' }
    } -ParameterFilter {
      $Name -eq 'posh-git' -and $ListAvailable
    }
    Mock Import-Module {} -ParameterFilter { $Name -eq 'posh-git' }

    $global:GitPromptSettings = [PSCustomObject]@{
      EnablePromptStatus = $true
    }

    . $script:scriptPath

    $GitPromptSettings.EnablePromptStatus | Should -BeFalse
  }

  AfterAll {
    Remove-Variable -Name GitPromptSettings -Scope Global -ErrorAction SilentlyContinue
  }
}
