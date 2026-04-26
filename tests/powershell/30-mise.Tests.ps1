# Tests for the PowerShell mise bootstrap script.
# Exercises: PATH-first resolution and the Windows ~/.local/bin fallback.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '30-mise.ps1'

  function New-TestMiseCommand {
    param(
      [Parameter(Mandatory)]
      [string] $Name
    )

    Set-Item -Path "Function:\$Name" -Value {
      param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Arguments)

      $script:MiseCalls += [pscustomobject]@{
        Command   = $MyInvocation.MyCommand.Name
        Arguments = [string[]]$Arguments
      }

      if ($Arguments[0] -eq 'activate') {
        '$null'
      }
    }

    Microsoft.PowerShell.Core\Get-Command $Name
  }

  function New-TestMiseConfigs {
    $miseDir = Join-Path $HOME '.mise'
    $configDir = Join-Path (Join-Path $HOME '.config') 'mise'

    New-Item -ItemType Directory -Path $miseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $miseDir 'config.toml') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $configDir 'config.toml') -Force | Out-Null
  }
}

Describe '30-mise' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalTrusted = $env:MISE_TRUSTED_CONFIG_PATHS
    $script:OriginalWarning = $env:MISE_PWSH_CHPWD_WARNING
    $script:MiseCalls = @()
    $script:FallbackPath = $null

    Set-Variable -Name HOME -Value 'TestDrive:\home' -Scope Global -Force
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:MISE_TRUSTED_CONFIG_PATHS = $script:OriginalTrusted
    $env:MISE_PWSH_CHPWD_WARNING = $script:OriginalWarning
    Remove-Item Function:\PathMise -ErrorAction SilentlyContinue
    Remove-Item Function:\FallbackMise -ErrorAction SilentlyContinue
  }

  It 'prefers the PATH command before the Windows fallback' {
    New-TestMiseConfigs

    $pathCommand = New-TestMiseCommand -Name 'PathMise'
    $fallbackCommand = New-TestMiseCommand -Name 'FallbackMise'
    $script:FallbackPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe'

    New-Item -ItemType Directory -Path (Split-Path $script:FallbackPath) -Force | Out-Null
    New-Item -ItemType File -Path $script:FallbackPath -Force | Out-Null

    Mock Get-Command { $pathCommand } -ParameterFilter { $Name -eq 'mise' }
    Mock Get-Command { $fallbackCommand } -ParameterFilter {
      $Name -eq $script:FallbackPath
    }

    . $script:Subject

    Assert-MockCalled Get-Command -ParameterFilter { $Name -eq 'mise' } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:FallbackPath
    } -Times 0

    $usedCommands = @(
      $script:MiseCalls |
        Select-Object -ExpandProperty Command |
        Sort-Object -Unique
    )
    $usedCommands | Should -HaveCount 1
    $usedCommands[0] | Should -Be 'PathMise'
    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'trust' }).Count |
      Should -Be 2
    ($script:MiseCalls | Where-Object {
      $_.Arguments[0] -eq 'activate' -and
      $_.Arguments[1] -eq 'pwsh' -and
      $_.Arguments[2] -eq '--quiet'
    }).Count | Should -Be 1
  }

  It 'uses the Windows fallback executable when mise is not on PATH' {
    New-TestMiseConfigs

    $fallbackCommand = New-TestMiseCommand -Name 'FallbackMise'
    $script:FallbackPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe'

    New-Item -ItemType Directory -Path (Split-Path $script:FallbackPath) -Force | Out-Null
    New-Item -ItemType File -Path $script:FallbackPath -Force | Out-Null

    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }
    Mock Get-Command { $fallbackCommand } -ParameterFilter {
      $Name -eq $script:FallbackPath
    }

    . $script:Subject

    Assert-MockCalled Get-Command -ParameterFilter { $Name -eq 'mise' } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:FallbackPath
    } -Times 1

    $usedCommands = @(
      $script:MiseCalls |
        Select-Object -ExpandProperty Command |
        Sort-Object -Unique
    )
    $usedCommands | Should -HaveCount 1
    $usedCommands[0] | Should -Be 'FallbackMise'
    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'trust' }).Count |
      Should -Be 2
    ($script:MiseCalls | Where-Object {
      $_.Arguments[0] -eq 'activate' -and
      $_.Arguments[1] -eq 'pwsh' -and
      $_.Arguments[2] -eq '--quiet'
    }).Count | Should -Be 1
  }
}
