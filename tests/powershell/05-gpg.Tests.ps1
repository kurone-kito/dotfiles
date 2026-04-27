# Tests for the PowerShell GPG passphrase-caching helper script.
# Exercises: alias creation, gpg availability check, success/failure paths.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '05-gpg.ps1'
}

Describe '05-gpg' {

  BeforeEach {
    $script:OriginalLastExitCode = $global:LASTEXITCODE
    Remove-Item Function:\Invoke-GpgCachePassphrase -ErrorAction SilentlyContinue
    Remove-Item Alias:\gpg-cache -ErrorAction SilentlyContinue
  }

  AfterEach {
    $global:LASTEXITCODE = $script:OriginalLastExitCode
    Remove-Item Function:\Invoke-GpgCachePassphrase -ErrorAction SilentlyContinue
    Remove-Item Alias:\gpg-cache -ErrorAction SilentlyContinue
  }

  It 'creates the gpg-cache alias pointing to Invoke-GpgCachePassphrase' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg' }

    . $script:Subject

    $alias = Get-Alias -Name gpg-cache -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Invoke-GpgCachePassphrase'
  }

  It 'warns and returns early when gpg is not in PATH' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg' }

    . $script:Subject

    $result = Invoke-GpgCachePassphrase 3>&1
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*gpg not found*'
  }

  It 'writes success message when gpg succeeds' {
    function script:gpg {
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }

    . $script:Subject

    $output = (Invoke-GpgCachePassphrase) 6>&1 | Out-String
    $output | Should -BeLike '*cached successfully*'
    $global:LASTEXITCODE | Should -Be 0

    Remove-Item Function:\script:gpg -ErrorAction SilentlyContinue
  }

  It 'writes failure warning when gpg fails' {
    function script:gpg {
      $global:LASTEXITCODE = 1
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }

    . $script:Subject

    $result = Invoke-GpgCachePassphrase 3>&1
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*caching failed*'

    Remove-Item Function:\script:gpg -ErrorAction SilentlyContinue
  }
}
