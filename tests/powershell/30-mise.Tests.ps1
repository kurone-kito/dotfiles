# Tests for the PowerShell mise bootstrap script.
# Exercises: PATH-first resolution and Windows fallback discovery.

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

  function Get-TestWingetPackagesRoot {
    Join-Path (
      (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet')
    ) 'Packages'
  }

  function New-TestWingetMisePackage {
    param(
      [Parameter(Mandatory)]
      [string] $PackageName
    )

    $packageRoot = Join-Path (Get-TestWingetPackagesRoot) $PackageName
    $misePath = Join-Path (Join-Path (Join-Path $packageRoot 'mise') 'bin') 'mise.exe'

    New-Item -ItemType Directory -Path (Split-Path $misePath) -Force | Out-Null
    New-Item -ItemType File -Path $misePath -Force | Out-Null

    return $misePath
  }
}

Describe '30-mise' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalTrusted = $env:MISE_TRUSTED_CONFIG_PATHS
    $script:OriginalWarning = $env:MISE_PWSH_CHPWD_WARNING
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $script:OriginalPath = $env:PATH
    $script:MiseCalls = @()
    $script:FallbackPath = $null

    $homeRoot = (New-Item -ItemType Directory -Path 'TestDrive:\home' -Force).FullName
    $localAppDataRoot = (New-Item -ItemType Directory -Path 'TestDrive:\LocalAppData' -Force).FullName

    # Pre-create shims directory — on Windows the script prepends this to PATH
    $script:ShimsDir = Join-Path (Join-Path $localAppDataRoot 'mise') 'shims'
    New-Item -ItemType Directory -Path $script:ShimsDir -Force | Out-Null

    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force
    $env:LOCALAPPDATA = $localAppDataRoot
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:MISE_TRUSTED_CONFIG_PATHS = $script:OriginalTrusted
    $env:MISE_PWSH_CHPWD_WARNING = $script:OriginalWarning
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    $env:PATH = $script:OriginalPath
    Remove-Item Function:\PathMise -ErrorAction SilentlyContinue
    Remove-Item Function:\FallbackMise -ErrorAction SilentlyContinue
    Remove-Item Function:\WingetMise -ErrorAction SilentlyContinue
    Remove-Item Function:\WingetMiseA -ErrorAction SilentlyContinue
    Remove-Item Function:\WingetMiseB -ErrorAction SilentlyContinue
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
    # Windows: shims dir prepended to PATH (not activate)
    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $script:ShimsDir
  }

  It 'uses the official Windows fallback before winget package bins' {
    New-TestMiseConfigs

    $fallbackCommand = New-TestMiseCommand -Name 'FallbackMise'
    $wingetCommand = New-TestMiseCommand -Name 'WingetMise'
    $script:FallbackPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe'
    $script:WingetPath = New-TestWingetMisePackage -PackageName 'jdx.mise_2025.1.0_x64__test'

    New-Item -ItemType Directory -Path (Split-Path $script:FallbackPath) -Force | Out-Null
    New-Item -ItemType File -Path $script:FallbackPath -Force | Out-Null

    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }
    Mock Get-Command { $fallbackCommand } -ParameterFilter {
      $Name -eq $script:FallbackPath
    }
    Mock Get-Command { $wingetCommand } -ParameterFilter {
      $Name -eq $script:WingetPath
    }

    . $script:Subject

    Assert-MockCalled Get-Command -ParameterFilter { $Name -eq 'mise' } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:FallbackPath
    } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:WingetPath
    } -Times 0

    $usedCommands = @(
      $script:MiseCalls |
        Select-Object -ExpandProperty Command |
        Sort-Object -Unique
    )
    $usedCommands | Should -HaveCount 1
    $usedCommands[0] | Should -Be 'FallbackMise'
    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'trust' }).Count |
      Should -Be 2
    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $script:ShimsDir
  }

  It 'uses the winget package-bin executable when other Windows paths are unavailable' {
    New-TestMiseConfigs

    $wingetCommand = New-TestMiseCommand -Name 'WingetMise'
    $script:FallbackPath = Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe'
    $packagesRoot = Get-TestWingetPackagesRoot
    $packageRoot = Join-Path $packagesRoot 'jdx.mise_2025.1.0_x64__test'
    $script:WingetPath = Join-Path (Join-Path (Join-Path $packageRoot 'mise') 'bin') 'mise.exe'

    Mock Get-ChildItem {
      @([pscustomobject]@{ FullName = $packageRoot })
    } -ParameterFilter {
      $LiteralPath -eq $packagesRoot -and
      $Directory
    }
    Mock Resolve-Path {
      [pscustomobject]@{ ProviderPath = $script:WingetPath }
    } -ParameterFilter {
      $LiteralPath -eq $script:WingetPath
    }
    Mock Get-Command {
      if ($Name -eq 'mise') { return $null }
      if ($Name -eq $script:FallbackPath) { return $null }
      if ($Name -eq $script:WingetPath) { return $wingetCommand }
      throw "Unexpected Get-Command lookup: $Name"
    }

    . $script:Subject

    Assert-MockCalled Get-Command -ParameterFilter { $Name -eq 'mise' } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:FallbackPath
    } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:WingetPath
    } -Times 1

    $usedCommands = @(
      $script:MiseCalls |
        Select-Object -ExpandProperty Command |
        Sort-Object -Unique
    )
    $usedCommands | Should -HaveCount 1
    $usedCommands[0] | Should -Be 'WingetMise'
    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'trust' }).Count |
      Should -Be 2
    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $script:ShimsDir
  }

  It 'de-duplicates winget package-bin candidates that resolve to one executable' {
    New-TestMiseConfigs

    $packagesRoot = Get-TestWingetPackagesRoot
    $packageA = Join-Path $packagesRoot 'jdx.mise_2025.1.0_x64__test-a'
    $packageB = Join-Path $packagesRoot 'jdx.mise_2025.1.0_x64__test-b'
    $script:WingetPathA = Join-Path (Join-Path (Join-Path $packageA 'mise') 'bin') 'mise.exe'
    $script:WingetPathB = Join-Path (Join-Path (Join-Path $packageB 'mise') 'bin') 'mise.exe'
    $canonicalWingetPath = 'TestDrive:\canonical\mise.exe'
    $wingetCommandA = New-TestMiseCommand -Name 'WingetMiseA'
    $wingetCommandB = New-TestMiseCommand -Name 'WingetMiseB'

    Mock Get-Command {
      if ($Name -eq 'mise') { return $null }
      if ($Name -eq (Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe')) { return $null }
      if ($Name -eq $script:WingetPathA) { return $wingetCommandA }
      if ($Name -eq $script:WingetPathB) { return $wingetCommandB }
      throw "Unexpected Get-Command lookup: $Name"
    }
    Mock Get-ChildItem {
      @(
        [pscustomobject]@{ FullName = $packageA }
        [pscustomobject]@{ FullName = $packageB }
      )
    } -ParameterFilter {
      $LiteralPath -eq $packagesRoot -and
      $Directory
    }
    Mock Resolve-Path {
      [pscustomobject]@{ ProviderPath = $canonicalWingetPath }
    } -ParameterFilter {
      $LiteralPath -eq $script:WingetPathA
    }
    Mock Resolve-Path {
      [pscustomobject]@{ ProviderPath = $canonicalWingetPath }
    } -ParameterFilter {
      $LiteralPath -eq $script:WingetPathB
    }

    . $script:Subject

    Assert-MockCalled Get-Command -ParameterFilter { $Name -eq 'mise' } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:WingetPathA
    } -Times 1
    Assert-MockCalled Get-Command -ParameterFilter {
      $Name -eq $script:WingetPathB
    } -Times 0

    $usedCommands = @(
      $script:MiseCalls |
        Select-Object -ExpandProperty Command |
        Sort-Object -Unique
    )
    $usedCommands | Should -HaveCount 1
    $usedCommands[0] | Should -Be 'WingetMiseA'
    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'trust' }).Count |
      Should -Be 2
    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $script:ShimsDir
  }

  It 'calls reshim when shims directory does not exist' {
    New-TestMiseConfigs

    # Remove the pre-created shims dir
    Remove-Item -LiteralPath $script:ShimsDir -Recurse -Force

    $pathCommand = New-TestMiseCommand -Name 'PathMise'
    Mock Get-Command { $pathCommand } -ParameterFilter { $Name -eq 'mise' }

    . $script:Subject

    ($script:MiseCalls | Where-Object { $_.Arguments[0] -eq 'reshim' }).Count |
      Should -Be 1
  }
}
