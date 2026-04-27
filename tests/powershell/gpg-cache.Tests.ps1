# Tests for the PowerShell gpg-cache script.
# Exercises: gpg detection, tty/agent session updates, success, and failure.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_gpg-cache.ps1'
}

Describe 'gpg-cache' {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN
    $script:OriginalLastExitCode = $global:LASTEXITCODE
    $script:OriginalGpgTty = $env:GPG_TTY
    $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN = '1'
    Remove-Variable DotfilesAgentArgs -Scope Script -ErrorAction SilentlyContinue
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN = $script:OriginalSkip
    $global:LASTEXITCODE = $script:OriginalLastExitCode
    $env:GPG_TTY = $script:OriginalGpgTty

    foreach ($name in @(
      'Get-DotfilesGpgCommand'
      'Update-DotfilesGpgSession'
      'Invoke-DotfilesGpgCachePassphrase'
      'script:gpg'
      'script:tty'
      'script:gpg-connect-agent'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'warns and returns false when gpg is not in PATH' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg' }

    $result = Invoke-DotfilesGpgCachePassphrase 3>&1

    ($result | Where-Object { $_ -is [bool] })[-1] | Should -BeFalse
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*gpg not found*'
  }

  It 'updates GPG_TTY when tty succeeds' {
    function script:tty {
      $global:LASTEXITCODE = 0
      '/dev/pts/99'
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'tty'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    Update-DotfilesGpgSession

    $env:GPG_TTY | Should -Be '/dev/pts/99'
  }

  It 'calls gpg-connect-agent updatestartuptty when available' {
    function script:gpg-connect-agent {
      $script:DotfilesAgentArgs = @($args)
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg-connect-agent'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }

    Update-DotfilesGpgSession

    $script:DotfilesAgentArgs | Should -Be @('updatestartuptty', '/bye')
  }

  It 'writes success message when gpg succeeds' {
    function script:gpg {
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    $output = (Invoke-DotfilesGpgCachePassphrase) 6>&1 | Out-String

    $output | Should -BeLike '*Prompting GPG passphrase*'
    $output | Should -BeLike '*cached successfully*'
  }

  It 'writes failure warning when gpg fails' {
    function script:gpg {
      $global:LASTEXITCODE = 1
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }

    $result = Invoke-DotfilesGpgCachePassphrase 3>&1

    ($result | Where-Object { $_ -is [bool] })[-1] | Should -BeFalse
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*caching failed*'
  }
}
