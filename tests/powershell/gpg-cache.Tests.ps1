# Tests for the PowerShell gpg-cache script.
# Exercises: gpg detection, tty/agent session updates, signing-key
# discovery, multi-key priming, reloadagent, success, and failure.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_gpg-cache.ps1'
}

Describe 'gpg-cache' {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN
    $script:OriginalLastExitCode = $global:LASTEXITCODE
    $script:OriginalGpgTty = $env:GPG_TTY
    $script:OriginalHome = $HOME
    $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN = '1'
    Set-Variable -Name HOME -Value 'TestDrive:\home' -Scope Global -Force
    # Clean up any leftover profile files from prior tests
    $profileDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'git') 'profiles'
    if (Test-Path $profileDir) {
      Remove-Item $profileDir -Recurse -Force
    }
    Remove-Variable DotfilesAgentArgs -Scope Script -ErrorAction SilentlyContinue
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN = $script:OriginalSkip
    $global:LASTEXITCODE = $script:OriginalLastExitCode
    $env:GPG_TTY = $script:OriginalGpgTty
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force

    foreach ($name in @(
      'Get-DotfilesGpgCommand'
      'Get-DotfilesGpgSigningKeys'
      'Update-DotfilesGpgSession'
      'Invoke-DotfilesGpgCachePassphrase'
      'script:gpg'
      'script:git'
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

  It 'calls gpg-connect-agent reloadagent then updatestartuptty' {
    $script:DotfilesAgentCalls = [System.Collections.Generic.List[string]]::new()
    function script:gpg-connect-agent {
      $script:DotfilesAgentCalls.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg-connect-agent'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }

    Update-DotfilesGpgSession

    $script:DotfilesAgentCalls[0] | Should -Be 'reloadagent /bye'
    $script:DotfilesAgentCalls[1] | Should -Be 'updatestartuptty /bye'
  }

  It 'reads signing key from git config' {
    function script:git {
      if ($args[0] -eq 'config' -and $args[1] -eq 'user.signingkey') {
        'AAAA1111BBBB2222'
        $global:LASTEXITCODE = 0
      }
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git' }

    $keys = Get-DotfilesGpgSigningKeys

    $keys | Should -Contain 'AAAA1111BBBB2222'
  }

  It 'reads signing keys from profile config files' {
    $profileDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'git') 'profiles'
    $null = New-Item -ItemType Directory -Path $profileDir -Force
    Set-Content -Path (Join-Path $profileDir 'work') -Value @"
[user]
  signingkey = "CCCC3333DDDD4444"
"@
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }

    $keys = Get-DotfilesGpgSigningKeys

    $keys | Should -Contain 'CCCC3333DDDD4444'
  }

  It 'deduplicates signing keys from git config and profiles' {
    $profileDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'git') 'profiles'
    $null = New-Item -ItemType Directory -Path $profileDir -Force
    Set-Content -Path (Join-Path $profileDir 'dup') -Value @"
[user]
  signingkey = "AAAA1111BBBB2222"
"@
    function script:git {
      if ($args[0] -eq 'config' -and $args[1] -eq 'user.signingkey') {
        'AAAA1111BBBB2222'
        $global:LASTEXITCODE = 0
      }
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'git' }

    $keys = Get-DotfilesGpgSigningKeys

    $keys.Count | Should -Be 1
  }

  It 'returns empty when no signing keys configured' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }

    $keys = Get-DotfilesGpgSigningKeys

    $keys.Count | Should -Be 0
  }

  It 'primes specific key with --local-user when signing keys found' {
    $script:GpgCallArgs = [System.Collections.Generic.List[string]]::new()
    function script:gpg {
      $script:GpgCallArgs.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-DotfilesGpgSigningKeys { @('AAAA1111') }

    $output = (Invoke-DotfilesGpgCachePassphrase) 6>&1 | Out-String

    $script:GpgCallArgs[0] | Should -BeLike '*--local-user AAAA1111*'
    $output | Should -BeLike '*Prompting GPG passphrase for key AAAA1111*'
    $output | Should -BeLike '*cached successfully*'
  }

  It 'primes multiple keys in sequence' {
    $script:GpgCallArgs = [System.Collections.Generic.List[string]]::new()
    function script:gpg {
      $script:GpgCallArgs.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-DotfilesGpgSigningKeys { @('KEY1', 'KEY2') }

    $output = (Invoke-DotfilesGpgCachePassphrase) 6>&1 | Out-String

    $script:GpgCallArgs.Count | Should -Be 2
    $script:GpgCallArgs[0] | Should -BeLike '*--local-user KEY1*'
    $script:GpgCallArgs[1] | Should -BeLike '*--local-user KEY2*'
  }

  It 'falls back to default key when no signing keys found' {
    $script:GpgCallArgs = [System.Collections.Generic.List[string]]::new()
    function script:gpg {
      $script:GpgCallArgs.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-DotfilesGpgSigningKeys { @() }

    $output = (Invoke-DotfilesGpgCachePassphrase) 6>&1 | Out-String

    $script:GpgCallArgs[0] | Should -Not -BeLike '*--local-user*'
    $output | Should -BeLike '*Prompting GPG passphrase*'
    $output | Should -BeLike '*cached successfully*'
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
    Mock Get-DotfilesGpgSigningKeys { @() }

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
    Mock Get-DotfilesGpgSigningKeys { @() }

    $result = Invoke-DotfilesGpgCachePassphrase 3>&1

    ($result | Where-Object { $_ -is [bool] })[-1] | Should -BeFalse
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*caching failed*'
  }

  It 'returns false when any key in multi-key mode fails' {
    $script:GpgCallCount = 0
    function script:gpg {
      $script:GpgCallCount++
      if ($script:GpgCallCount -eq 1) {
        $global:LASTEXITCODE = 0
      } else {
        $global:LASTEXITCODE = 1
      }
    }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'gpg'; CommandType = 'Function' }
    } -ParameterFilter { $Name -eq 'gpg' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tty' }
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'gpg-connect-agent' }
    Mock Get-DotfilesGpgSigningKeys { @('OK_KEY', 'BAD_KEY') }

    $result = Invoke-DotfilesGpgCachePassphrase 3>&1

    ($result | Where-Object { $_ -is [bool] })[-1] | Should -BeFalse
  }
}
