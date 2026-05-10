# Tests for the PowerShell GPG cache helper wrapper.
# Exercises: alias creation, missing script handling, delegation, and
# gpg-agent config reload at profile load.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '05-gpg.ps1'
}

Describe '05-gpg' {

  BeforeEach {
    $script:OriginalHome = $HOME
    Remove-Item Function:\Invoke-GpgCachePassphrase -ErrorAction SilentlyContinue
    Remove-Item Alias:\gpg-cache -ErrorAction SilentlyContinue
    Set-Variable -Name HOME -Value 'TestDrive:\home' -Scope Global -Force
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    Remove-Item Function:\Invoke-GpgCachePassphrase -ErrorAction SilentlyContinue
    Remove-Item Alias:\gpg-cache -ErrorAction SilentlyContinue
  }

  It 'creates the gpg-cache alias pointing to Invoke-GpgCachePassphrase' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    . $script:Subject

    $alias = Get-Alias -Name gpg-cache -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Invoke-GpgCachePassphrase'
  }

  It 'warns and returns early when the helper script is missing' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    . $script:Subject

    $result = Invoke-GpgCachePassphrase 3>&1
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*gpg-cache script not found*'
  }

  It 'invokes the helper script when it exists' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    $scriptPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'gpg-cache.ps1'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $scriptPath) -Force
    Set-Content -Path $scriptPath -Value "Write-Output 'script-invoked'"

    . $script:Subject

    $output = (Invoke-GpgCachePassphrase) 6>&1 | Out-String
    $output | Should -Match 'script-invoked'
  }

  It 'calls gpg-connect-agent reloadagent at load time' {
    $script:AgentCalls = [System.Collections.Generic.List[string]]::new()
    function script:gpg-connect-agent {
      $script:AgentCalls.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg-connect-agent'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    . $script:Subject

    $script:AgentCalls | Should -Contain 'reloadagent /bye'
  }
}
